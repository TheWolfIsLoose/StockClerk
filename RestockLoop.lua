--[[
    Stock Clerk - RestockLoop.lua
    Walks the shortlist and drives per-item buy prompts.

    Loop lifecycle:
      Start()  - snapshot the current shortfall list, allocate a per-
                 item budget slice (QA-10a two-pass proportional), open
                 the AH search for the first item, hand off to either
                 the buy dialog (manual) or ExecutePurchase (auto).
      Advance()- pop the current item, jump to the next. Called after
                 the user confirms, skips, or a search yields nothing.
      Stop()   - abort, close any open dialog, clear state, log outcome.

    Two run modes (v0.3):
      "manual" - existing v0.2 behavior. Every buy waits for a BuyDialog
                 confirmation. Budget field is ignored.
      "auto"   - QA-10. Sanity checks pass -> ExecutePurchase directly,
                 no per-item confirmation. Requires:
                   * settings.autoPurchase == true
                   * settings.autoBudgetGold not nil
                 Each item MUST have a maxPrice set; uncapped items are
                 skipped and logged (buy_skip, reason "no cap set").

    Budget allocation (QA-10a):
      Two-pass proportional + spillover, per NOTES.md.
      Pass 1: for each short item, budgetSlice = (need-have)*est_unit_price,
              scaled to fit total budget. est_unit_price comes from
              lastPrice (QA-11) with "equal share" fallback for items
              with no recorded lastPrice.
      Pass 2: after each purchase, any budget slack redistributes to
              still-short items biggest-shortfall first (implicit -
              we simply track running budgetLeft and allow subsequent
              items to overflow their initial slice if budget allows).

    Contract:
      * Only runs while the AH is open. If the user closes the AH we
        stop cleanly.
      * Auto never buys uncapped items and never exceeds an item's cap.
      * Auto never spends past the loop's budget.
      * Esc key while a loop is active -> Stop("user_esc").
--]]

local addonName = ...
local ADDON     = _G[addonName]

local Loop = {}
ADDON.RestockLoop = Loop

Loop.state = {
    active         = false,
    mode           = "manual",
    queue          = nil,   -- array of shortfall items to process (copies)
    index          = 0,     -- current position in queue
    lastPlan       = nil,
    budgetCopper   = nil,   -- total budget for this loop, nil = unlimited
    budgetLeft     = nil,   -- copper remaining after prior purchases
    spentCopper    = 0,     -- copper spent in this loop
    touched        = 0,     -- items successfully bought this loop
    stillShort     = 0,     -- items whose need was not met at loop end
}

local function DebugPrint(...)
    if ADDON.debug then
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
        print("|cff98FF98[SC:Loop]|r " .. table.concat(parts, " "))
    end
end

local function Status(msg)
    if ADDON.MainFrame and ADDON.MainFrame.SetStatus then
        ADDON.MainFrame:SetStatus(msg)
    end
end

-- ---------------------------------------------------------------------------
-- Session purchase ledger (itemID -> { qty, baseHave })
--
-- WHY: AH commodity purchases are delivered by MAIL, not straight to bags,
-- so Inventory:GetCount (bags-only) doesn't reflect a successful buy until
-- the user loots their mailbox. Without this ledger the shortfall math
-- (short = need - have) never sees the purchase, and every press of
-- "Restock at AH" re-buys everything it just bought. That was the live
-- user bug: repeated Restock presses kept re-purchasing with no memory
-- of prior success.
--
-- Recording each success as (qty bought, bag count at buy time) lets the
-- shortfall math treat those units as provisionally owned. When the user
-- loots the mail, the bag count rises by qty and effectivePending()
-- decays to zero on its own -- no event watching needed. Session-scoped
-- on purpose: never persisted, so no stale-offset hazard across logouts.
-- ---------------------------------------------------------------------------
Loop.pendingBuys = {}

function Loop:_RecordPurchase(itemID, qty)
    local haveNow = ADDON.Inventory:GetCount(itemID) or 0
    local cur = self.pendingBuys[itemID]
    if cur then
        -- Stack onto the same baseline so decay still works after the
        -- mail from the FIRST purchase is looted.
        cur.qty = cur.qty + qty
    else
        self.pendingBuys[itemID] = { qty = qty, baseHave = haveNow }
    end
end

-- Bag count + outstanding (mailed-but-unlooted) purchases from this
-- session. Decays automatically as the bag count catches up.
function Loop:_EffectiveHave(itemID)
    local have = ADDON.Inventory:GetCount(itemID) or 0
    local p = self.pendingBuys[itemID]
    if not p then return have end
    local unlooted = math.max(0, p.qty - math.max(0, have - p.baseHave))
    if unlooted <= 0 then
        self.pendingBuys[itemID] = nil -- fully absorbed, stop tracking
        return have
    end
    return have + unlooted
end

-- ---------------------------------------------------------------------------
-- Build the shortfall queue. Sorted by biggest shortfall first so
-- raid-critical stuff comes up before nice-to-haves. Each entry carries
-- lastPrice for the budget allocator.
-- ---------------------------------------------------------------------------
local function BuildQueue()
    local q = {}
    for _, it in ipairs(ADDON.DB:GetSortedItems()) do
        -- _EffectiveHave, not raw bag count: items we successfully bought
        -- earlier this session are sitting in the mailbox and must count
        -- toward the shortfall or we buy them again on the next press.
        local have = Loop:_EffectiveHave(it.itemID)
        local short = it.need - have
        if short > 0 then
            q[#q + 1] = {
                itemID    = it.itemID,
                name      = it.name,
                need      = it.need,
                have      = have,
                short     = short,
                maxPrice  = it.maxPrice,   -- copper, nil = unset
                lastPrice = it.lastPrice,  -- { copper, seenAt, source } or nil
            }
        end
    end
    table.sort(q, function(a, b) return a.short > b.short end)
    return q
end

-- ---------------------------------------------------------------------------
-- QA-10a: two-pass proportional budget allocator.
--
--   Pass 1: estimate demand-value = short * est_unit for each item.
--           est_unit prefers lastPrice.copper; falls back to a
--           per-item "equal share" placeholder when no price is known.
--           Scale each slice so the sum fits under `budgetCopper`.
--
--   Pass 2 (spillover) is implicit -- we don't reduce budgetLeft when
--   an item comes in under its slice; the next items simply see more
--   headroom. When an item exceeds its slice we still allow it as
--   long as budgetLeft covers it, because the whole point of a
--   proportional plan is guidance, not a hard per-item cap. The hard
--   cap is the ITEM's maxPrice, enforced by AH:BuyUpTo directly.
--
-- Mutates q in place: adds `budgetSlice` (copper) to each entry.
-- Returns the total planned spend so the caller can log it.
-- ---------------------------------------------------------------------------
local function AllocateBudget(q, budgetCopper)
    if not budgetCopper or budgetCopper <= 0 then
        for _, it in ipairs(q) do it.budgetSlice = math.huge end
        return 0
    end

    -- Compute raw demand values. Items without lastPrice get a placeholder
    -- of 1 gold per unit so they still get a proportional slice; the real
    -- cap enforcement lives in AH:BuyUpTo via item.maxPrice.
    local totalDemand = 0
    for _, it in ipairs(q) do
        local est = (it.lastPrice and it.lastPrice.copper) or 10000
        it._rawDemand = it.short * est
        totalDemand = totalDemand + it._rawDemand
    end

    if totalDemand == 0 then
        -- Degenerate case: give everyone equal share.
        local per = math.floor(budgetCopper / math.max(1, #q))
        for _, it in ipairs(q) do it.budgetSlice = per end
        return budgetCopper
    end

    -- Scale each demand to fit the budget. If total demand fits under
    -- budget, no scaling needed (slice = raw demand).
    local scale = math.min(1, budgetCopper / totalDemand)
    local allocated = 0
    for _, it in ipairs(q) do
        it.budgetSlice = math.floor(it._rawDemand * scale)
        allocated = allocated + it.budgetSlice
    end
    return allocated
end

-- ---------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------
function Loop:Start()
    if self.state.active then
        DebugPrint("already active, ignoring Start")
        return
    end
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        Status("|cffff8888Open the auction house first.|r")
        return
    end

    local q = BuildQueue()
    if #q == 0 then
        Status("|cff4ade80Nothing to restock -- all items at or above target.|r")
        return
    end

    -- Determine run mode from settings.
    local s = ADDON.DB:Settings()
    local mode = "manual"
    local budgetCopper = nil
    if s.autoPurchase and s.autoBudgetGold and s.autoBudgetGold > 0 then
        mode = "auto"
        budgetCopper = s.autoBudgetGold * 10000
        AllocateBudget(q, budgetCopper)
    end

    self.state.active       = true
    self.state.mode         = mode
    self.state.queue        = q
    self.state.index        = 0
    self.state.budgetCopper = budgetCopper
    self.state.budgetLeft   = budgetCopper
    self.state.spentCopper  = 0
    self.state.touched      = 0
    self.state.stillShort   = 0

    DebugPrint(("started mode=%s items=%d budget=%s"):format(
        mode, #q, tostring(budgetCopper)))

    -- QA-13: log the loop start with mode + budget context.
    if ADDON.Log then
        ADDON.Log:Emit("loop_start", nil, {
            queueSize    = #q,
            mode         = mode,
            budgetCopper = budgetCopper,
        })
    end

    self:Advance()
end

-- ---------------------------------------------------------------------------
-- Advance to next item
-- ---------------------------------------------------------------------------
function Loop:Advance()
    if not self.state.active then return end
    self.state.index = self.state.index + 1
    local item = self.state.queue[self.state.index]
    if not item then
        DebugPrint("queue exhausted, stopping")
        self:Stop("done")
        return
    end

    Status(("Searching AH: %s (%d/%d in queue)"):format(
        item.name, self.state.index, #self.state.queue))

    -- Re-derive short in case we bought some in a prior loop iteration
    -- and the count has updated. _EffectiveHave folds in this session's
    -- mailed-but-unlooted purchases so successive loop iterations and
    -- successive whole loops don't re-buy what already succeeded.
    local have = Loop:_EffectiveHave(item.itemID)
    local short = item.need - have
    if short <= 0 then
        DebugPrint(("skip id=%d, already restocked (%d/%d)"):format(item.itemID, have, item.need))
        self:Advance()
        return
    end

    -- Auto-mode fast-fail: no cap set means the item is not eligible
    -- for auto-purchase. Log the skip and move on.
    if self.state.mode == "auto" and not item.maxPrice then
        DebugPrint(("auto skip id=%d, no cap set"):format(item.itemID))
        if ADDON.Log then
            ADDON.Log:Emit("buy_skip", item.itemID, { reason = "no cap set" })
        end
        self.state.stillShort = self.state.stillShort + 1
        self:Advance()
        return
    end

    -- Auto-mode budget fast-fail: no budget left at all means nothing
    -- more can happen this loop. Stop cleanly.
    if self.state.mode == "auto" and self.state.budgetLeft and self.state.budgetLeft <= 0 then
        DebugPrint("auto stop: budget exhausted")
        -- Count this and every remaining item as stillShort for the
        -- loop-stop summary.
        self.state.stillShort = self.state.stillShort + (#self.state.queue - self.state.index + 1)
        self:Stop("budget exhausted")
        return
    end

    DebugPrint(("processing id=%d need=%d have=%d short=%d cap=%s"):format(
        item.itemID, item.need, have, short, tostring(item.maxPrice)))

    ADDON.AH:BuyUpTo(item.itemID, short, item.maxPrice, function(ok, plan)
        if not self.state.active then return end -- user stopped mid-flight
        if not ok then
            DebugPrint("search/plan failed: " .. tostring(plan))
            Status(("|cffff8888%s: %s|r"):format(item.name, tostring(plan)))
            if ADDON.Log then
                ADDON.Log:Emit("buy_fail", item.itemID, { reason = tostring(plan) })
            end
            self.state.stillShort = self.state.stillShort + 1
            -- On failure we still auto-advance -- one bad item shouldn't
            -- stall the queue.
            C_Timer.After(1.0, function() if self.state.active then self:Advance() end end)
            return
        end

        self.state.lastPlan = plan
        plan.name = item.name
        plan.have = have
        plan.need = item.need
        plan.maxPrice = item.maxPrice

        -- ------ Auto-mode sanity checks (QA-10) --------------------------
        if self.state.mode == "auto" then
            -- Qty sanity: refuse anything more than 3x need, per NOTES.md.
            if plan.planQuantity > 3 * item.need then
                DebugPrint(("auto refuse id=%d qty=%d >3x need=%d"):format(
                    item.itemID, plan.planQuantity, item.need))
                if ADDON.Log then
                    ADDON.Log:Emit("auto_refuse", item.itemID, {
                        reason              = "qty sanity (>3x need)",
                        qty                 = plan.planQuantity,
                        plannedSpendCopper  = plan.plannedSpend,
                    })
                end
                self.state.stillShort = self.state.stillShort + 1
                C_Timer.After(0.2, function() if self.state.active then self:Advance() end end)
                return
            end

            -- Budget: refuse if this plan exceeds remaining budget.
            if self.state.budgetLeft and plan.plannedSpend > self.state.budgetLeft then
                DebugPrint(("auto refuse id=%d spend=%d > left=%d"):format(
                    item.itemID, plan.plannedSpend, self.state.budgetLeft))
                if ADDON.Log then
                    ADDON.Log:Emit("auto_refuse", item.itemID, {
                        reason             = "over budget",
                        qty                = plan.planQuantity,
                        plannedSpendCopper = plan.plannedSpend,
                    })
                end
                self.state.stillShort = self.state.stillShort + 1
                C_Timer.After(0.2, function() if self.state.active then self:Advance() end end)
                return
            end

            -- All checks passed: execute directly, no user confirmation.
            if ADDON.Log then
                ADDON.Log:Emit("buy_attempt", item.itemID, {
                    qty                = plan.planQuantity,
                    plannedSpendCopper = plan.plannedSpend,
                    worstUnitCopper    = plan.worstUnitPrice,
                })
            end
            self:_OnConfirm(plan)
            return
        end

        -- ------ Manual mode: hand off to BuyDialog (unchanged) -----------
        ADDON.BuyDialog:Show(plan, {
            onConfirm = function()
                if ADDON.Log then
                    ADDON.Log:Emit("buy_attempt", item.itemID, {
                        qty                = plan.planQuantity,
                        plannedSpendCopper = plan.plannedSpend,
                        worstUnitCopper    = plan.worstUnitPrice,
                    })
                end
                self:_OnConfirm(plan)
            end,
            onSkip    = function() self:_OnSkip(plan) end,
            onStop    = function() self:Stop("user_stop") end,
        })
    end)
end

-- ---------------------------------------------------------------------------
-- Confirmation path (shared by manual + auto)
-- ---------------------------------------------------------------------------
function Loop:_OnConfirm(plan)
    if not self.state.active then return end
    DebugPrint(("confirming buy id=%d qty=%d spend=%d"):format(
        plan.itemID, plan.planQuantity, plan.plannedSpend))
    Status(("Buying %d x %s..."):format(plan.planQuantity, plan.name))
    ADDON.AH:ExecutePurchase(plan.itemID, plan.planQuantity, plan.plannedSpend, function(ok, result)
        if not self.state.active then return end
        if ok then
            local spent = plan.plannedSpend or 0
            self.state.spentCopper = self.state.spentCopper + spent
            self.state.touched     = self.state.touched + 1
            if self.state.budgetLeft then
                self.state.budgetLeft = math.max(0, self.state.budgetLeft - spent)
            end
            -- Record in the session ledger BEFORE logging/status so the
            -- very next shortfall computation (next Advance, or the next
            -- manual Restock press) sees these units as provisionally
            -- owned. Items arrive by mail; bags-only counts won't show
            -- them until the user loots, and the ledger decays away as
            -- soon as they do.
            self:_RecordPurchase(plan.itemID, plan.planQuantity)
            if ADDON.Log then
                ADDON.Log:Emit("buy_success", plan.itemID, {
                    qty         = plan.planQuantity,
                    spentCopper = spent,
                })
            end
            Status(("|cff4ade80Bought %d %s for %s (via mail)|r"):format(
                plan.planQuantity, plan.name, GetCoinTextureString(spent)))
        else
            if ADDON.Log then
                ADDON.Log:Emit("buy_fail", plan.itemID, { reason = tostring(result) })
            end
            self.state.stillShort = self.state.stillShort + 1
            Status(("|cffff8888Buy failed for %s: %s|r"):format(plan.name, tostring(result)))
        end
        -- Auto-advance regardless of outcome. Give the game a beat to
        -- refresh inventory counts before the next search.
        C_Timer.After(0.8, function() if self.state.active then self:Advance() end end)
    end)
end

function Loop:_OnSkip(plan)
    if not self.state.active then return end
    DebugPrint("user skipped id=" .. plan.itemID)
    if ADDON.Log then
        ADDON.Log:Emit("buy_skip", plan.itemID, { reason = "user skipped" })
    end
    Status(("Skipped %s"):format(plan.name))
    C_Timer.After(0.2, function() if self.state.active then self:Advance() end end)
end

-- ---------------------------------------------------------------------------
-- Stop
--
-- `reason` is a short machine-y string that becomes payload.reason on
-- the loop_stop log entry. Callers use:
--   "done"              - queue exhausted normally
--   "budget exhausted"  - auto mode ran out of budget mid-queue
--   "AH closed"         - AH window closed while active
--   "user_esc"          - user pressed Escape while active
--   "user_stop"         - user clicked Stop in the manual buy dialog
-- ---------------------------------------------------------------------------
function Loop:Stop(reason)
    if not self.state.active then return end
    reason = reason or "unspecified"
    DebugPrint("stopping loop: " .. reason)

    -- Snapshot for the log emit; state is cleared below.
    local spent      = self.state.spentCopper or 0
    local touched    = self.state.touched     or 0
    local stillShort = self.state.stillShort  or 0
    if ADDON.Log then
        ADDON.Log:Emit("loop_stop", nil, {
            reason      = reason,
            spentCopper = spent,
            touched     = touched,
            stillShort  = stillShort,
        })
    end

    self.state.active       = false
    self.state.queue        = nil
    self.state.index        = 0
    self.state.lastPlan     = nil
    self.state.budgetCopper = nil
    self.state.budgetLeft   = nil
    self.state.spentCopper  = 0
    self.state.touched      = 0
    self.state.stillShort   = 0
    if ADDON.BuyDialog and ADDON.BuyDialog.Hide then
        ADDON.BuyDialog:Hide()
    end

    -- One human-readable statusbar summary. Kept short; the sidecar
    -- has the full breakdown.
    local msg
    if reason == "done" then
        msg = ("|cff4ade80Loop done. Bought %d, spent %s.|r"):format(
            touched, GetCoinTextureString(spent))
    elseif reason == "budget exhausted" then
        msg = ("|cffffaa00Budget exhausted. Bought %d, %d still short.|r"):format(
            touched, stillShort)
    elseif reason == "user_esc" then
        msg = ("Loop stopped (Escape). Bought %d, spent %s."):format(
            touched, GetCoinTextureString(spent))
    else
        msg = ("Loop stopped (%s)."):format(reason)
    end
    Status(msg)
end

function Loop:IsActive()
    return self.state.active == true
end
