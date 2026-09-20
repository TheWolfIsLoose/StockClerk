--[[
    Stock Clerk - RestockLoop.lua
    Walks the shortlist and arms per-item purchases for user firing.

    v0.7.0-alpha6 AUTO-BUY-NUKE + Phase B ARMED-MODEL:
      The "auto" run mode is gone. WoW's C_AuctionHouse commodity API
      requires a hardware event to advance (StartCommoditiesPurchase
      is user-input-gated), so silent auto-buys were always impossible.

      What replaces it: an ARMED model. The loop searches the AH for
      the top-of-queue item, then STOPS in an "armed" state. The
      restock button on the main frame lights up as a big buy button
      -- "Buy 5 x Flask of Alchemical Chaos - 250g" -- and one click
      fires the purchase in the same hardware-event context. The loop
      auto-advances to the next item and re-arms.

      Capped-out rows (cheapest listing above the user's cap) are
      auto-skipped silently -- the loop advances without ever arming.

      Uncapped rows arm normally with the armed-flyout's amber
      'No cap set' badge on its sub line. That badge IS the soft
      warning -- the user sees they're about to buy at market
      price before pressing Buy. No per-session ack needed.

    Loop lifecycle:
      Start()  - snapshot the current shortfall list IN USER-ARRANGED
                 LIST ORDER (the list is the priority), advance to
                 the first item.
      Advance()- move to the next queue item, run its search, then
                 either auto-skip (cap out) or ARM.
      Fire()   - user pressed the buy button on an armed item. Runs
                 ExecutePurchase, then auto-advances on completion.
      Stop()   - abort, clear armed state, log outcome.

    Repeat-press safety (v0.5 mail-delivery gate, preserved):
      pendingBuys is PERSISTED on char.pendingBuys. Every successful
      purchase increments the ledger; _EffectiveHave folds mailed-
      but-unlooted purchases into the "have" number so BuildQueue
      correctly returns short=0 for a row already bought this AH
      session. Reconciles against actual mail contents when the
      user opens their mailbox (MAIL_INBOX_UPDATE). This is the
      guardrail that protects users from running several buy loops
      without ever leaving the AH -- an early testing loophole that
      let them repeatedly buy items they were in a deficit of because
      they hadn't fetched their mail. It stays.

    Contract:
      * Only runs while the AH is open. Closing the AH stops cleanly.
      * User confirms every buy via the armed-flyout's Buy button
        (hardware click required by StartCommoditiesPurchase).
      * Escape while active -> Stop("user_esc").
--]]

local addonName = ...
local ADDON     = _G[addonName]

local Loop = {}
ADDON.RestockLoop = Loop

Loop.state = {
    active         = false,
    queue          = nil,   -- array of shortfall items to process (copies)
    index          = 0,     -- current position in queue
    armed          = false, -- an item is ready to buy; MainFrame paints buy button
    armedPlan      = nil,   -- plan object (itemID, planQuantity, plannedSpend, ...)
    buying         = false, -- ExecutePurchase in flight; guards double-fires
    lastPlan       = nil,
    spentCopper    = 0,     -- copper spent in this loop
    touched        = 0,     -- items successfully bought this loop
    stillShort     = 0,     -- items whose need was not met at loop end
    skippedCapped  = 0,     -- rows silently skipped for cap-out
    -- (uncappedAcked removed in v0.7.0 sweep: soft warning now lives in
    -- the armed-flyout's amber 'No cap set' badge, no per-session ack needed)
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
-- v0.4). Two reasons: (1) the ledger closes the repeat-press gate, and
-- if a user buys then logs out, the gate must remain closed on next
-- login until on-hand confirmation; (2) mailbox reconciliation needs the
-- ledger to survive across sessions because auction mail sits in the
-- inbox for up to 30 days.
--
-- v0.7.0-alpha6 note: the ledger is used by ALL restock passes now
-- (manual-only mode). "Have" always means _EffectiveHave, never raw
-- bag count -- this is what stops a user from rebuying the same
-- items on the second, third, fourth press of the buy bind before
-- their mail arrives.
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
-- list IS the priority: top of the list gets restocked first. No
-- re-sorting here -- biggest-shortfall-first would contradict the
-- user's explicit arrangement.
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

-- ---------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------
-- Public preview: how many items would BuildQueue enqueue right now?
-- Uses _EffectiveHave (bags + unlooted purchase ledger) so callers
-- outside RestockLoop don't have to reimplement the same math and
-- risk drifting from BuildQueue's real behavior. Used by
-- Core.lua's auto-restock trigger so "would the loop find work?" is
-- a SINGLE decision point, not two independent shortfall calcs.
-- Called many times per frame from Refresh, button state, and Core's
-- auto-restock trigger. To keep debug logs signal-heavy we memoize the
-- last per-item shortfall snapshot and only log entries whose short
-- number CHANGED since the previous call. Under normal steady-state
-- browsing the log stays silent; when something actually moves (bag
-- update, purchase, mail loot), the log records the delta once.
Loop._previewLast = Loop._previewLast or {}
function Loop:PreviewShortfallCount()
    local n = 0
    if not ADDON.DB then return 0 end
    local seen = {}
    for _, it in ipairs(ADDON.DB:GetSortedItems()) do
        local have  = self:_EffectiveHave(it.itemID)
        local short = it.need - have
        if short > 0 then
            n = n + 1
            if ADDON.debug and self._previewLast[it.itemID] ~= short then
                DebugPrint(("preview: id=%d name=%s need=%d effHave=%d short=%d"):format(
                    it.itemID, tostring(it.name), it.need, have, short))
            end
            seen[it.itemID] = short
        end
    end
    -- Drop stale memo entries so items that transitioned short -> stocked
    -- log their next transition back to short.
    for id in pairs(self._previewLast) do
        if not seen[id] then self._previewLast[id] = nil end
    end
    for id, short in pairs(seen) do self._previewLast[id] = short end
    return n
end

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
        -- Red, not mint: this is an unexpected refusal, not a success.
        -- Under normal flow the button is greyed when there's nothing
        -- to do, so hitting Start with an empty queue means the caller
        -- (slash command / autoRestock race) is out of sync with the
        -- current inventory state.
        Status("|cfff87171Nothing to restock -- every row is at or above its need.|r")
        return
    end

    self.state.active       = true
    self.state.queue        = q
    self.state.index        = 0
    self.state.spentCopper  = 0
    self.state.touched      = 0
    self.state.stillShort   = 0

    DebugPrint(("started items=%d"):format(#q))

    if ADDON.Log then
        ADDON.Log:Emit("loop_start", nil, { queueSize = #q })
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

    -- Phase B ARMED-MODEL: search + arm, don't dialog.
    DebugPrint(("processing id=%d need=%d have=%d short=%d cap=%s"):format(
        item.itemID, item.need, have, short, tostring(item.maxPrice)))

    ADDON.AH:BuyUpTo(item.itemID, short, item.maxPrice, function(ok, plan)
        if not self.state.active then return end -- user stopped mid-flight
        if not ok then
            -- Distinguish cap-out (silent skip) from real failure. AH.lua's
            -- BuyUpTo returns "cheapest ... is above your Ng cap" for the
            -- cap-out case; treat that as a benign, silent skip -- the
            -- whole point of the reshape is that capped-out rows don't
            -- bother the user. Everything else is logged and status-noted.
            local reason = tostring(plan)
            local isCapOut = reason:find("above your") and reason:find("cap")
            if isCapOut then
                DebugPrint("cap-out silent skip: " .. reason)
                self.state.skippedCapped = self.state.skippedCapped + 1
                if ADDON.Log then
                    ADDON.Log:Emit("buy_skip", item.itemID, { reason = "cap out (silent)" })
                end
            else
                DebugPrint("search/plan failed: " .. reason)
                Status(("|cffff8888%s: %s|r"):format(item.name, reason))
                if ADDON.Log then
                    ADDON.Log:Emit("buy_fail", item.itemID, { reason = reason })
                end
                self.state.stillShort = self.state.stillShort + 1
            end
            C_Timer.After(isCapOut and 0.15 or 1.0, function()
                if self.state.active then self:Advance() end
            end)
            return
        end

        self.state.lastPlan = plan
        plan.name = item.name
        plan.have = have
        plan.need = item.need
        plan.maxPrice = item.maxPrice
        plan.capSource = "item"

        -- Uncapped items arm normally: the armed-flyout already flags
        -- 'No cap set' in amber on the sub line, which IS the soft warning
        -- for buying at market price. Previously we short-circuited to a
        -- StaticPopup modal via BuyDialog on the first uncapped row of an
        -- AH session, but that was a legacy Phase-A pattern that fought
        -- the flyout instead of leveraging it (multi-source-of-truth for
        -- the same 'confirm this buy' decision). Consolidated to the
        -- flyout in v0.7.0 release sweep.
        self:_Arm(plan)
    end)
end

-- ---------------------------------------------------------------------------
-- Arm the loop on a plan. Post-feedback rework: the confirm/skip UI lives
-- in MainFrame's ConfirmToast flyout above the restock button, NOT on the
-- restock button itself. The toast has a 3s arm delay on its Buy button
-- so accidental clicks are impossible during arm.
-- Fire() is invoked from the toast's Buy OnClick -- that click is the
-- hardware event that lets StartCommoditiesPurchase go through.
-- ---------------------------------------------------------------------------
function Loop:_Arm(plan)
    self.state.armed     = true
    self.state.armedPlan = plan
    DebugPrint(("armed id=%d qty=%d spend=%d"):format(
        plan.itemID, plan.planQuantity, plan.plannedSpend))
    Status(("Ready: %d x %s for %s -- confirm in the buy flyout"):format(
        plan.planQuantity, plan.name, ADDON.MoneyText(plan.plannedSpend)))
    if ADDON.MainFrame then
        if ADDON.MainFrame.RefreshRestockBtn then
            ADDON.MainFrame:RefreshRestockBtn()
        end
        if ADDON.MainFrame.ShowArmedToast then
            ADDON.MainFrame:ShowArmedToast(plan, {
                onBuy  = function() self:Fire() end,
                onSkip = function() self:_OnSkip(plan) end,
                onStop = function() self:Stop("user_stop") end,
            })
        end
    end
end

-- ---------------------------------------------------------------------------
-- Fire: user clicked the armed Buy button on the toast. MUST be called
-- from a hardware-event context (the toast Buy OnClick). Consumes armed
-- state, kicks ExecutePurchase.
-- ---------------------------------------------------------------------------
function Loop:Fire()
    if not self.state.active then return end
    if not self.state.armed then
        DebugPrint("Fire called but not armed, ignoring")
        return
    end
    if self.state.buying then
        DebugPrint("Fire called mid-buy, ignoring (guards double-click)")
        return
    end
    local plan = self.state.armedPlan
    if not plan then return end

    self.state.armed  = false
    self.state.buying = true

    if ADDON.Log then
        ADDON.Log:Emit("buy_attempt", plan.itemID, {
            qty                = plan.planQuantity,
            plannedSpendCopper = plan.plannedSpend,
            worstUnitCopper    = plan.worstUnitPrice,
        })
    end
    self:_OnConfirm(plan)
    if ADDON.MainFrame then
        if ADDON.MainFrame.HideToast then ADDON.MainFrame:HideToast() end
        if ADDON.MainFrame.RefreshRestockBtn then
            ADDON.MainFrame:RefreshRestockBtn()
        end
    end
end

-- Test-only convenience for the armed-plan getter. MainFrame uses this to
-- paint the button label.
function Loop:GetArmedPlan()
    if self.state.armed then return self.state.armedPlan end
    return nil
end

-- ---------------------------------------------------------------------------
-- Confirmation path
-- ---------------------------------------------------------------------------
function Loop:_OnConfirm(plan)
    if not self.state.active then return end
    DebugPrint(("confirming buy id=%d qty=%d spend=%d"):format(
        plan.itemID, plan.planQuantity, plan.plannedSpend))
    Status(("Buying %d x %s..."):format(plan.planQuantity, plan.name))
    ADDON.AH:ExecutePurchase(plan.itemID, plan.planQuantity, plan.plannedSpend, function(ok, result)
        if not self.state.active then return end
        self.state.buying = false
        if ok then
            local spent = plan.plannedSpend or 0
            self.state.spentCopper = self.state.spentCopper + spent
            self.state.touched     = self.state.touched + 1
            -- Record in the ledger BEFORE logging/status so the very
            -- next shortfall computation (next Advance, or the next
            -- Restock press) sees these units as provisionally owned.
            -- Items arrive by mail; bags-only counts won't show them
            -- until the user loots, and the ledger decays away as
            -- soon as they do. This is the repeat-press safeguard.
            self:_RecordPurchase(plan.itemID, plan.planQuantity)
            if ADDON.Log then
                ADDON.Log:Emit("buy_success", plan.itemID, {
                    qty         = plan.planQuantity,
                    spentCopper = spent,
                })
            end
            Status(("|cff4ade80Bought %d %s for %s (via mail)|r"):format(
                plan.planQuantity, plan.name, ADDON.MoneyText(spent)))
        else
            if ADDON.Log then
                ADDON.Log:Emit("buy_fail", plan.itemID, { reason = tostring(result) })
            end
            self.state.stillShort = self.state.stillShort + 1
            Status(("|cffff8888Buy failed for %s: %s|r"):format(plan.name, tostring(result)))
        end
        if ADDON.MainFrame and ADDON.MainFrame.RefreshRestockBtn then
            ADDON.MainFrame:RefreshRestockBtn()
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
    -- Clear armed state so the next Advance re-searches and re-arms cleanly.
    self.state.armed     = false
    self.state.armedPlan = nil
    if ADDON.MainFrame and ADDON.MainFrame.HideToast then
        ADDON.MainFrame:HideToast()
    end
    C_Timer.After(0.2, function() if self.state.active then self:Advance() end end)
end

-- ---------------------------------------------------------------------------
-- Stop
--
-- `reason` is a short machine-y string that becomes payload.reason on
-- the loop_stop log entry. Callers use:
--   "done"       - queue exhausted normally
--   "AH closed"  - AH window closed while active
--   "user_esc"   - user pressed Escape while active
--   "user_stop"  - user clicked Stop in the manual buy dialog
-- ---------------------------------------------------------------------------
function Loop:Stop(reason)
    if not self.state.active then return end
    reason = reason or "unspecified"
    DebugPrint("stopping loop: " .. reason)

    -- Snapshot for the log emit; state is cleared below.
    local spent         = self.state.spentCopper   or 0
    local touched       = self.state.touched       or 0
    local stillShort    = self.state.stillShort    or 0
    local skippedCapped = self.state.skippedCapped or 0
    if ADDON.Log then
        ADDON.Log:Emit("loop_stop", nil, {
            reason        = reason,
            spentCopper   = spent,
            touched       = touched,
            stillShort    = stillShort,
            skippedCapped = skippedCapped,
        })
    end

    self.state.active        = false
    self.state.queue         = nil
    self.state.index         = 0
    self.state.armed         = false
    self.state.armedPlan     = nil
    self.state.buying        = false
    self.state.lastPlan      = nil
    self.state.spentCopper   = 0
    self.state.touched       = 0
    self.state.stillShort    = 0
    self.state.skippedCapped = 0
    -- (uncappedAcked field removed in v0.7.0 sweep -- see state init above)
    -- reset by Core.lua on AUCTION_HOUSE_CLOSED. A user starting a new
    -- restock pass in the same AH visit shouldn't re-see the warning.
    -- (BuyDialog removed in v0.7.0 sweep; nothing to hide here)
    if ADDON.MainFrame then
        -- Hide any armed toast on stop; the summary toast below replaces it.
        if ADDON.MainFrame._toastMode == "armed" and ADDON.MainFrame.HideToast then
            ADDON.MainFrame:HideToast()
        end
        if ADDON.MainFrame.RefreshRestockBtn then
            ADDON.MainFrame:RefreshRestockBtn()
        end
    end

    -- If the ledger is non-empty at loop end, nudge the user to loot
    -- their mail -- this is the "you already bought these, next
    -- press won't re-buy them because we're tracking mail-in-flight"
    -- transparency message.
    local mailNudge = ""
    local ledger = self:_Ledger()
    if ledger and next(ledger) then
        mailNudge = " (mail pending)"
    end

    -- Post-feedback session-summary toast. The confirm flyout repurposes
    -- for the recap: two lines + [Close]. Status line gets a shorter
    -- version so the activity log still records the outcome.
    local title, sub
    local skipTxt = ""
    if skippedCapped > 0 then
        skipTxt = (("  \194\183  %d skipped over cap"):format(skippedCapped))
    end
    -- Total items the loop touched at ALL (bought + still-short + capped-skip).
    -- When totalItems == 1, the sub line ('1/1 items resolved') is redundant
    -- with the title -- suppress it. Multi-item loops keep the recap.
    local totalItems = touched + stillShort + skippedCapped
    local moneyText  = ADDON.MoneyText(spent)

    if reason == "done" then
        title = ("|cff4ade80Restock complete|r  \194\183  bought %d for %s"):format(touched, moneyText)
        if totalItems > 1 then
            sub = ("%d/%d items resolved%s%s"):format(touched, totalItems, skipTxt, mailNudge)
        else
            -- Single item: keep only the mail-pending nudge if present.
            sub = (mailNudge ~= "") and mailNudge:gsub("^%s+", "") or ""
        end
    elseif reason == "user_esc" or reason == "user_stop" then
        title = ("Stopped  \194\183  bought %d for %s"):format(touched, moneyText)
        sub   = ("Loop halted with %d left%s%s"):format(stillShort, skipTxt, mailNudge)
    elseif reason == "AH closed" then
        title = ("AH closed  \194\183  bought %d for %s"):format(touched, moneyText)
        sub   = ("Reopen the AH to continue%s%s"):format(skipTxt, mailNudge)
    else
        title = ("Stopped (%s)"):format(reason)
        sub   = ("bought %d for %s%s%s"):format(touched, moneyText, skipTxt, mailNudge)
    end
    Status(title)
    if ADDON.MainFrame and ADDON.MainFrame.ShowSummaryToast then
        ADDON.MainFrame:ShowSummaryToast({ title = title, sub = sub })
    end
end

function Loop:IsActive()
    return self.state.active == true
end

function Loop:IsArmed()
    return self.state.active and self.state.armed == true
end

function Loop:IsBuying()
    return self.state.buying == true
end

-- (ResetSessionFlags removed in v0.7.0 sweep -- the uncappedAcked flag
-- it managed is gone. If new AH-session flags ever need per-visit
-- resets, reintroduce here.)
