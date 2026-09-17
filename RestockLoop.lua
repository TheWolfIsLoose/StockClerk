--[[
    Stock Clerk - RestockLoop.lua
    Walks the shortlist and drives per-item buy prompts.

    Loop lifecycle:
      Start()  - snapshot the current shortfall list IN USER-ARRANGED
                 LIST ORDER (the list is the priority), draw the auto
                 mode's allowance from the daily budget, open the AH
                 search for the first item, hand off to either the buy
                 dialog (manual) or ExecutePurchase (auto).
      Advance()- pop the current item, jump to the next. Called after
                 the user confirms, skips, or a search yields nothing.
      Stop()   - abort, close any open dialog, clear state, log outcome.

    Two run modes:
      "manual" - every buy waits for a BuyDialog confirmation. Budget is
                 neither enforced nor tracked here: manual buys are full
                 user discretion (user decision 2026-09-17 -- budgets
                 guard against inadvertent autopilot spend only).
      "auto"   - sanity checks pass -> ExecutePurchase directly, no
                 per-item confirmation. Requires:
                   * settings.autoPurchase == true
                   * settings.autoBudgetGold not nil
                 Each item MUST have a maxPrice set; uncapped items are
                 skipped and logged (buy_skip, reason "no cap set").

    Budget semantics (v0.4):
      The budget is a DAILY allowance aligned to the realm daily reset
      (C_DateAndTime.GetSecondsUntilDailyReset), persisted in
      char.autoSpend -- see DB.lua. The loop draws from
      DB:GetDailyAutoBudgetLeft(), not a fresh per-run amount: pressing
      Restock twice in one day spends from the same allowance.
      Priority is the list's own order (sortOrder): the queue walks the
      shopping list top-down and the daily allowance runs out wherever
      it runs out. The old two-pass proportional allocator
      (AllocateBudget / budgetSlice) was deleted -- it computed slices
      nothing consumed, and tacit list-order priority replaced it.

    Repeat-press safety (v0.5 mail-delivery gate):
      pendingBuys is now PERSISTED on char.pendingBuys (not session-
      scoped as it was in v0.4). Once auto has bought anything, the
      next auto pass is BLOCKED until the ledger is empty. The ledger
      empties by either:
        (a) bag-count catch-up via _EffectiveHave -- items landing in
            bags absorb ledger qty, or
        (b) mailbox reconciliation via _OnMailInboxUpdate -- opening a
            mailbox with pending items lets us cross-check against
            actual mail contents and clamp or delete accordingly.
      Manual mode is NOT gated (standing rule: manual is full user
      discretion). Gate exists to force a natural on-hand confirmation
      checkpoint on the AUTO path only.

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
-- Purchase ledger (itemID -> { qty, baseHave, boughtAt })
--
-- WHY: AH commodity purchases are delivered by MAIL, not straight to bags,
-- so Inventory:GetCount (bags-only) doesn't reflect a successful buy until
-- the user loots their mailbox. Without this ledger the shortfall math
-- (short = need - have) never sees the purchase, and every press of
-- "Restock at AH" re-buys everything it just bought.
--
-- v0.5 change (PT-4): PERSISTED on char.pendingBuys (was session-only in
-- v0.4). Two reasons: (1) the ledger closes the auto-pass gate, and if a
-- user buys then logs out, the gate must remain closed on next login
-- until on-hand confirmation; (2) mailbox reconciliation needs the
-- ledger to survive across sessions because auction mail sits in the
-- inbox for up to 30 days.
--
-- Stale-offset hazard is bounded by:
--   * 30-day GC in DB:Initialize -- entries older than 30 days are
--     dropped on load (auction mail expires server-side at 30 days).
--   * MAIL_INBOX_UPDATE reconciliation -- opening the mailbox clamps
--     ledger entries to actual mail contents. Missing entries deleted.
--   * Bag-count decay in _EffectiveHave -- unchanged from v0.4.
-- ---------------------------------------------------------------------------

-- Accessor: resolves to the persisted store. DB init runs before any
-- Loop method fires (Core.lua orders it that way), so the nil branch
-- is defensive against load-order regressions only.
function Loop:_Ledger()
    return ADDON.DB and ADDON.DB.char and ADDON.DB.char.pendingBuys or nil
end

function Loop:_RecordPurchase(itemID, qty)
    local ledger = self:_Ledger()
    if not ledger then return end
    local haveNow = ADDON.Inventory:GetCount(itemID) or 0
    local now     = GetServerTime and GetServerTime() or time()
    local cur     = ledger[itemID]
    if cur then
        -- Stack onto the same baseline so decay still works after the
        -- mail from the FIRST purchase is looted.
        cur.qty      = cur.qty + qty
        cur.boughtAt = now
    else
        ledger[itemID] = { qty = qty, baseHave = haveNow, boughtAt = now }
    end
end

-- Bag count + outstanding (mailed-but-unlooted) purchases. Decays
-- automatically as the bag count catches up.
function Loop:_EffectiveHave(itemID)
    local have   = ADDON.Inventory:GetCount(itemID) or 0
    local ledger = self:_Ledger()
    if not ledger then return have end
    local p = ledger[itemID]
    if not p then return have end
    local unlooted = math.max(0, p.qty - math.max(0, have - p.baseHave))
    if unlooted <= 0 then
        ledger[itemID] = nil -- fully absorbed, stop tracking
        return have
    end
    return have + unlooted
end

-- MAIL_INBOX_UPDATE reconciliation. When the mailbox is open the
-- server has streamed inbox contents to the client; walk the inbox
-- and clamp the ledger to reality.
--
-- Cases handled:
--   * Ledger entry NOT in mailbox = looted (bag decay already
--     zeroed it) OR expired server-side OR never existed. Drop it.
--   * Ledger entry qty > mailbox qty = partially looted. Clamp.
--   * Ledger entry qty <= mailbox qty = expected quantity still
--     present, no change.
--
-- We do NOT delete or shrink entries whose mail count exceeds ledger
-- qty -- surplus is from unrelated mail (gifts, sold-auctions, etc).
function Loop:_OnMailInboxUpdate()
    local ledger = self:_Ledger()
    if not ledger or not next(ledger) then return end
    -- GetInboxNumItems can return 0 before the server has streamed
    -- items; a subsequent MAIL_INBOX_UPDATE will fire with the real
    -- list, so bail on empty rather than deleting the ledger.
    local n = GetInboxNumItems()
    if not n or n == 0 then return end
    local seen = {}
    for i = 1, n do
        local attCount = ATTACHMENTS_MAX_RECEIVE or 16
        for j = 1, attCount do
            local _, itemID, _, count = GetInboxItem(i, j)
            if itemID and count and count > 0 then
                seen[itemID] = (seen[itemID] or 0) + count
            end
        end
    end
    for id, p in pairs(ledger) do
        local inMail = seen[id] or 0
        if inMail == 0 then
            DebugPrint(("reconcile: id=%d cleared (not in mail)"):format(id))
            ledger[id] = nil
        elseif inMail < p.qty then
            DebugPrint(("reconcile: id=%d clamped %d -> %d"):format(id, p.qty, inMail))
            p.qty = inMail
        end
    end
end

-- ---------------------------------------------------------------------------
-- Build the shortfall queue in LIST ORDER. The user-arranged shopping
-- list IS the priority (tacit): top of the list gets restocked first,
-- and when the daily budget runs out the bottom of the list waits for
-- tomorrow. No re-sorting here -- the old biggest-shortfall-first
-- ordering would contradict the user's explicit arrangement.
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
    return q
end

-- DELETED: AllocateBudget. The two-pass proportional allocator computed
-- a per-item budgetSlice that nothing ever consumed (flagged in the
-- v0.2.0..HEAD code review) and its model -- divide the pot up front --
-- was replaced by: daily running-total budget + list-order priority.

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

    -- Determine run mode from settings. Auto draws from the DAILY
    -- allowance: remaining = configured budget minus auto spend since the
    -- last realm daily reset. Manual runs have no budget plumbing at all.
    local s = ADDON.DB:Settings()
    local mode = "manual"
    local budgetCopper = nil
    if s.autoPurchase and s.autoBudgetGold and s.autoBudgetGold > 0 then
        mode = "auto"
        budgetCopper = s.autoBudgetGold * 10000
    end

    -- PT-4 mail-delivery gate. Auto passes are blocked while any
    -- purchase from a prior pass is still awaiting on-hand
    -- confirmation. We nudge _EffectiveHave on each ledger entry
    -- first so passive bag-count decay runs -- items already looted
    -- to bags drop out on the spot. Whatever remains is genuinely
    -- outstanding. Manual mode is not gated.
    if mode == "auto" then
        local ledger = self:_Ledger()
        if ledger then
            for id in pairs(ledger) do self:_EffectiveHave(id) end
            if next(ledger) then
                local pieces = {}
                for id, p in pairs(ledger) do
                    local nm = C_Item.GetItemInfo(id) or ("item:" .. id)
                    pieces[#pieces + 1] = ("%s x%d"):format(nm, p.qty)
                end
                table.sort(pieces)
                Status(("|cffff8888Auto blocked -- awaiting mail delivery: %s. Loot mail to continue.|r")
                    :format(table.concat(pieces, ", ")))
                DebugPrint("gate closed: pending=" .. table.concat(pieces, ", "))
                if ADDON.Log then
                    ADDON.Log:Emit("loop_gate_blocked", nil, { pending = pieces })
                end
                return
            end
        end
    end

    local dailyLeft = (mode == "auto") and ADDON.DB:GetDailyAutoBudgetLeft() or nil

    self.state.active       = true
    self.state.mode         = mode
    self.state.queue        = q
    self.state.index        = 0
    self.state.budgetCopper = budgetCopper
    self.state.budgetLeft   = dailyLeft   -- auto only; nil = unlimited
    self.state.spentCopper  = 0
    self.state.touched      = 0
    self.state.stillShort   = 0

    DebugPrint(("started mode=%s items=%d dailyLeft=%s"):format(
        mode, #q, tostring(dailyLeft)))

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

    -- Auto-mode budget fast-fail: no DAILY budget left means nothing
    -- more can happen before the next realm daily reset. Stop cleanly.
    if self.state.mode == "auto" and self.state.budgetLeft and self.state.budgetLeft <= 0 then
        DebugPrint("auto stop: daily budget exhausted")
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

            -- Budget: refuse if this plan exceeds remaining DAILY
            -- budget (auto only; manual never reaches this branch).
            if self.state.budgetLeft and plan.plannedSpend > self.state.budgetLeft then
                DebugPrint(("auto refuse id=%d spend=%d > left=%d"):format(
                    item.itemID, plan.plannedSpend, self.state.budgetLeft))
                if ADDON.Log then
                    ADDON.Log:Emit("auto_refuse", item.itemID, {
                        reason             = "over daily budget",
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
            -- Persist against the DAILY allowance. AUTO ONLY: manual buys
            -- are outside the budget ledger entirely (see DB.lua
            -- semantics block).
            if self.state.mode == "auto" then
                ADDON.DB:AddDailyAutoSpend(spent)
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
    -- has the full breakdown. Auto runs append the daily allowance
    -- readout (the number the user actually cares about now) plus,
    -- if the ledger is non-empty at loop end, a mail-check nudge --
    -- the next auto pass will be gated until those items arrive.
    local daily = ""
    if self.state.mode == "auto" and ADDON.DB and ADDON.DB.GetDailyAutoBudgetLeft then
        local left = ADDON.DB:GetDailyAutoBudgetLeft()
        if left then
            daily = (" %s left today."):format(GetCoinTextureString(left))
        end
    end
    local mailNudge = ""
    if self.state.mode == "auto" then
        local ledger = self:_Ledger()
        if ledger and next(ledger) then
            mailNudge = " |cffff8888Check mail before next auto pass.|r"
        end
    end
    local msg
    if reason == "done" then
        msg = ("|cff4ade80Loop done. Bought %d, spent %s.%s|r%s"):format(
            touched, GetCoinTextureString(spent), daily, mailNudge)
    elseif reason == "budget exhausted" then
        msg = ("|cffffaa00Daily budget exhausted. Bought %d, %d still short until reset.|r%s"):format(
            touched, stillShort, mailNudge)
    elseif reason == "user_esc" then
        msg = ("Loop stopped (Escape). Bought %d, spent %s.%s%s"):format(
            touched, GetCoinTextureString(spent), daily, mailNudge)
    else
        msg = ("Loop stopped (%s).%s"):format(reason, mailNudge)
    end
    Status(msg)
end

function Loop:IsActive()
    return self.state.active == true
end
