--[[
    Stock Clerk - RestockLoop.lua
    Walks the shortlist and arms per-item purchases for user firing.

    Armed model:
      WoW's C_AuctionHouse commodity API requires a hardware event
      to advance (StartCommoditiesPurchase is user-input-gated), so
      silent auto-buys are impossible. The loop searches the AH for
      the top-of-queue item, then STOPS in an "armed" state. The
      restock button on the main frame lights up as a big Buy button
      -- "Buy 5 x Flask of Alchemical Chaos - 250g" -- and one click
      fires the purchase in the same hardware-event context. The
      loop auto-advances to the next item and re-arms.

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

    Repeat-press safety (mail-delivery gate):
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
}

local function Status(msg)
    if ADDON.MainFrame and ADDON.MainFrame.SetStatus then
        ADDON.MainFrame:SetStatus(msg)
    end
end

-- ---------------------------------------------------------------------------
-- Purchase ledger (char.pendingBuys: itemID -> { qty, baseHave, boughtAt })
-- AH commodity buys arrive by mail, so bag counts miss them until looted;
-- without the ledger every Restock press would buy the same items again.
-- "Have" in the loop is always _EffectiveHave (bags + ledger). Persisted,
-- since mail can sit for days. Kept honest by: 30-day expiry on load
-- (auction mail expires at 30 days), mailbox reconciliation, and the ledger
-- decaying as bag counts catch up.
-- ---------------------------------------------------------------------------

function Loop:_Ledger()
    return ADDON.DB and ADDON.DB.char and ADDON.DB.char.pendingBuys or nil
end

function Loop:_RecordPurchase(itemID, qty)
    local ledger = self:_Ledger()
    if not ledger then return end
    local haveNow = ADDON.Inventory:GetBreakdown(itemID).bags
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
    local have   = ADDON.Inventory:GetBreakdown(itemID).bags
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

-- Mailbox open: clamp the ledger to what's actually in the mail. Not in the
-- mail = looted or expired: drop. Fewer in the mail = partly looted: clamp.
-- More in the mail is someone else's mail: leave it.
function Loop:_OnMailInboxUpdate()
    local ledger = self:_Ledger()
    if not ledger or not next(ledger) then return end
    -- 0 can mean "not streamed yet"; the next MAIL_INBOX_UPDATE has the list.
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
            ADDON.Debug("Loop", ("reconcile: id=%d cleared (not in mail)"):format(id))
            ledger[id] = nil
        elseif inMail < p.qty then
            ADDON.Debug("Loop", ("reconcile: id=%d clamped %d -> %d"):format(id, p.qty, inMail))
            p.qty = inMail
        end
    end
end

-- ---------------------------------------------------------------------------
-- Queue in list order: the arranged list is the priority.
-- ---------------------------------------------------------------------------
local function BuildQueue()
    local q = {}
    for _, it in ipairs(ADDON.DB:GetSortedItems()) do
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
-- How many items would BuildQueue take right now? The one shortfall answer
-- for the button, Express-Restock and the footer, so they can't disagree.
-- Traces only items whose shortfall changed since the last call.
Loop._previewLast = Loop._previewLast or {}
function Loop:PreviewShortfallCount()
    local n = 0
    if not ADDON.DB then return 0 end
    local seen = {}
    -- Order doesn't matter for a count, so walk the raw table rather than
    -- GetSortedItems (which sorts and resolves every item name).
    for itemID, entry in pairs(ADDON.DB:GetItems()) do
        local have  = self:_EffectiveHave(itemID)
        local short = entry.need - have
        if short > 0 then
            n = n + 1
            if ADDON.debug and self._previewLast[itemID] ~= short then
                ADDON.Debug("Loop", ("preview: id=%d need=%d effHave=%d short=%d"):format(
                    itemID, entry.need, have, short))
            end
            seen[itemID] = short
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

function Loop:Start(express)
    if self.state.active then
        ADDON.Debug("Loop", "already active, ignoring Start")
        return
    end
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        Status("|cffff8888Open the auction house first.|r")
        return
    end

    local q = BuildQueue()
    if #q == 0 then
        -- Red: the button is greyed when nothing is short, so getting here
        -- means the caller raced the inventory.
        Status("|cfff87171Nothing to restock -- every row is at or above its need.|r")
        return
    end

    self.state.active       = true
    self.state.queue        = q
    self.state.index        = 0
    self.state.spentCopper  = 0
    self.state.touched      = 0
    self.state.stillShort   = 0

    ADDON.Debug("Loop", ("started items=%d"):format(#q))

    if ADDON.Log then
        ADDON.Log:Emit("loop_start", nil, { queueSize = #q, mode = express and "express" or "manual" })
    end

    self:Advance()
end

function Loop:Advance()
    if not self.state.active then return end
    self.state.index = self.state.index + 1
    local item = self.state.queue[self.state.index]
    if not item then
        ADDON.Debug("Loop", "queue exhausted, stopping")
        self:Stop("done")
        return
    end

    Status(("Searching AH: %s (%d/%d in queue)"):format(
        item.name, self.state.index, #self.state.queue))

    -- Re-check: an earlier step (or run) may have covered it already.
    local have = Loop:_EffectiveHave(item.itemID)
    local short = item.need - have
    if short <= 0 then
        ADDON.Debug("Loop", ("skip id=%d, already restocked (%d/%d)"):format(item.itemID, have, item.need))
        self:Advance()
        return
    end

    -- ARMED-MODEL: search + arm, don't dialog.
    ADDON.Debug("Loop", ("processing id=%d need=%d have=%d short=%d cap=%s"):format(
        item.itemID, item.need, have, short, tostring(item.maxPrice)))

    ADDON.AH:BuyUpTo(item.itemID, short, item.maxPrice, function(ok, plan)
        if not self.state.active then return end -- user stopped mid-flight
        if not ok then
            -- Cheapest above the cap is a quiet skip; anything else is a
            -- real failure, logged and shown.
            local reason = tostring(plan)
            local isCapOut = reason:find("above your") and reason:find("cap")
            if isCapOut then
                ADDON.Debug("Loop", "cap-out silent skip: " .. reason)
                self.state.skippedCapped = self.state.skippedCapped + 1
                if ADDON.Log then
                    ADDON.Log:Emit("buy_skip", item.itemID, { reason = "cap out (silent)" })
                end
            else
                ADDON.Debug("Loop", "search/plan failed: " .. reason)
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

        -- Attach bank/warband counts so the flyout can warn before buying
        -- something already owned elsewhere.
        local bd = ADDON.Inventory and ADDON.Inventory.GetBreakdown
                    and ADDON.Inventory:GetBreakdown(item.itemID)
        if bd then
            plan.stashBank    = bd.bank or 0
            plan.stashWarband = bd.warband or 0
            plan.hasStash     = (plan.stashBank + plan.stashWarband) > 0
        else
            plan.stashBank    = 0
            plan.stashWarband = 0
            plan.hasStash     = false
        end

        -- Uncapped items arm normally; the flyout's amber "No cap set" is the warning.
        self:_Arm(plan)
    end)
end

-- ---------------------------------------------------------------------------
-- Arm: show the confirm flyout. Its Buy click (a hardware event, which
-- StartCommoditiesPurchase requires) calls Fire().
-- ---------------------------------------------------------------------------
function Loop:_Arm(plan)
    self.state.armed     = true
    self.state.armedPlan = plan
    ADDON.Debug("Loop", ("armed id=%d qty=%d spend=%d"):format(
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

-- Fire: must run from the Buy click (hardware event). Consumes the armed plan.
function Loop:Fire()
    if not self.state.active then return end
    if not self.state.armed then
        ADDON.Debug("Loop", "Fire called but not armed, ignoring")
        return
    end
    if self.state.buying then
        ADDON.Debug("Loop", "Fire called mid-buy, ignoring (guards double-click)")
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

function Loop:_OnConfirm(plan)
    if not self.state.active then return end
    ADDON.Debug("Loop", ("confirming buy id=%d qty=%d spend=%d"):format(
        plan.itemID, plan.planQuantity, plan.plannedSpend))
    Status(("Buying %d x %s..."):format(plan.planQuantity, plan.name))
    ADDON.AH:ExecutePurchase(plan.itemID, plan.planQuantity, plan.plannedSpend, function(ok, result)
        if not self.state.active then return end
        self.state.buying = false
        if ok then
            local spent = plan.plannedSpend or 0
            self.state.spentCopper = self.state.spentCopper + spent
            self.state.touched     = self.state.touched + 1
            -- Ledger first, so the next shortfall check already counts
            -- these mailed units.
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
    ADDON.Debug("Loop", "user skipped id=" .. plan.itemID)
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
-- Stop(reason): "done", "AH closed", "user_esc", "user_stop" (the log
-- turns these into plain words).
-- ---------------------------------------------------------------------------
function Loop:Stop(reason)
    if not self.state.active then return end
    reason = reason or "unspecified"
    ADDON.Debug("Loop", "stopping loop: " .. reason)

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
    if ADDON.MainFrame then
        -- Hide any armed toast on stop; the summary toast below replaces it.
        if ADDON.MainFrame._toastMode == "armed" and ADDON.MainFrame.HideToast then
            ADDON.MainFrame:HideToast()
        end
        if ADDON.MainFrame.RefreshRestockBtn then
            ADDON.MainFrame:RefreshRestockBtn()
        end
    end

    -- Bought items still in the mail: remind the player to loot it.
    local mailNudge = ""
    local ledger = self:_Ledger()
    if ledger and next(ledger) then
        mailNudge = " (mail pending)"
    end

    -- End-of-run recap in the flyout; a shorter version goes to the footer.
    local title, sub
    local skipTxt = ""
    if skippedCapped > 0 then
        skipTxt = (("  \194\183  %d skipped over cap"):format(skippedCapped))
    end
    -- One item: the "1/1 resolved" sub line would repeat the title.
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
        sub   = ("%d still short%s%s"):format(stillShort, skipTxt, mailNudge)
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
