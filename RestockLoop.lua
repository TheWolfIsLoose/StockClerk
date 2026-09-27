--[[
    Stock Clerk - RestockLoop.lua
    "Restock at AH": walks the short items in list order. For each it
    searches the AH, then either skips quietly (cheapest is above the cap)
    or arms the confirm flyout. Buying needs the player's click (a hardware
    event), so nothing is ever bought silently. After each buy, skip or
    failure it moves on; closing the AH or Escape stops it.

    Mail ledger (char.pendingBuys: itemID -> { qty, baseHave, boughtAt }):
    AH purchases arrive by mail, so bag counts miss them until looted, and
    every Restock press would buy the same items again. "Have" here is
    always _EffectiveHave (bags + ledger). Kept honest by 30-day expiry on
    load, mailbox reconciliation, and decay as bag counts catch up.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local Loop = {}
ADDON.RestockLoop = Loop

local function NewState()
    return { active = false, index = 0, spentCopper = 0, touched = 0, stillShort = 0, skippedCapped = 0 }
end
Loop.state = NewState()

local function Status(msg) ADDON.MainFrame:SetStatus(msg) end
local function Ledger() return ADDON.DB.char.pendingBuys end

-- ---------------------------------------------------------------------------
-- Mail ledger
-- ---------------------------------------------------------------------------
function Loop:_RecordPurchase(itemID, qty)
    local cur = Ledger()[itemID]
    if cur then
        -- Keep the first baseline so decay still works once the first mail is looted.
        cur.qty, cur.boughtAt = cur.qty + qty, GetServerTime()
    else
        Ledger()[itemID] = { qty = qty, baseHave = ADDON.Inventory:GetBreakdown(itemID).bags, boughtAt = GetServerTime() }
    end
end

-- Bags + purchases still in the mail. An entry goes away once bags catch up.
function Loop:_EffectiveHave(itemID)
    local have, p = ADDON.Inventory:GetBreakdown(itemID).bags, Ledger()[itemID]
    if not p then return have end
    local unlooted = p.qty - math.max(0, have - p.baseHave)
    if unlooted <= 0 then
        Ledger()[itemID] = nil
        return have
    end
    return have + unlooted
end

-- Mailbox open: clamp the ledger to what's actually in the mail. Not there =
-- looted or expired: drop. Fewer = partly looted: clamp. More is someone
-- else's mail: leave it.
function Loop:_OnMailInboxUpdate()
    local ledger = Ledger()
    local n = GetInboxNumItems()
    if not next(ledger) or n == 0 then return end  -- 0 can mean "not streamed yet"
    local inMail = {}
    for i = 1, n do
        for j = 1, ATTACHMENTS_MAX_RECEIVE do
            local _, itemID, _, count = GetInboxItem(i, j)
            if itemID and (count or 0) > 0 then inMail[itemID] = (inMail[itemID] or 0) + count end
        end
    end
    for id, p in pairs(ledger) do
        local count = inMail[id] or 0
        if count == 0 then
            ADDON.Debug("Loop", ("reconcile: id=%d cleared (not in mail)"):format(id))
            ledger[id] = nil
        elseif count < p.qty then
            ADDON.Debug("Loop", ("reconcile: id=%d clamped %d -> %d"):format(id, p.qty, count))
            p.qty = count
        end
    end
end

-- ---------------------------------------------------------------------------
-- Running
-- ---------------------------------------------------------------------------

-- How many items a Restock would try right now. The one shortfall answer for
-- the button, Express-Restock and the footer, so they can't disagree.
function Loop:PreviewShortfallCount()
    local n = 0
    for itemID, entry in pairs(ADDON.DB:GetItems()) do
        if entry.need > self:_EffectiveHave(itemID) then n = n + 1 end
    end
    return n
end

function Loop:Start(express)
    if self.state.active then return end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        return Status("|cffff8888Open the auction house first.|r")
    end
    local queue = {}
    for _, it in ipairs(ADDON.DB:GetSortedItems()) do  -- list order is the priority
        if it.need > self:_EffectiveHave(it.itemID) then queue[#queue + 1] = it end
    end
    if #queue == 0 then
        -- The button is greyed when nothing is short, so this is a race.
        return Status("|cfff87171Nothing to restock -- every row is at or above its need.|r")
    end
    self.state = NewState()
    self.state.active, self.state.queue = true, queue
    ADDON.Log:Emit("loop_start", nil, { queueSize = #queue, mode = express and "express" or "manual" })
    self:Advance()
end

-- Next item: search, then quietly skip (over cap) or arm the flyout.
function Loop:Advance()
    local s = self.state
    if not s.active then return end
    s.index = s.index + 1
    local item = s.queue[s.index]
    if not item then return self:Stop("done") end

    Status(("Searching AH: %s (%d/%d in queue)"):format(item.name, s.index, #s.queue))
    -- An earlier buy (or run) may have covered it already.
    local have = self:_EffectiveHave(item.itemID)
    local short = item.need - have
    if short <= 0 then return self:Advance() end
    ADDON.Debug("Loop", ("processing id=%d need=%d have=%d short=%d cap=%s"):format(
        item.itemID, item.need, have, short, tostring(item.maxPrice)))

    ADDON.AH:BuyUpTo(item.itemID, short, item.maxPrice, function(ok, plan)
        if not s.active then return end  -- stopped meanwhile
        if not ok then
            local capOut = plan:find("above your", 1, true) and plan:find("cap", 1, true)
            if capOut then
                s.skippedCapped = s.skippedCapped + 1
                ADDON.Log:Emit("buy_skip", item.itemID, { reason = "cap out (silent)" })
            else
                s.stillShort = s.stillShort + 1
                Status(("|cffff8888%s: %s|r"):format(item.name, plan))
                ADDON.Log:Emit("buy_fail", item.itemID, { reason = plan })
            end
            C_Timer.After(capOut and 0.15 or 1.0, function() self:Advance() end)
            return
        end
        -- Bank and warband counts let the flyout warn before buying what's
        -- already owned elsewhere. Uncapped items arm normally; the flyout
        -- shows an amber "No cap set".
        local bd = ADDON.Inventory:GetBreakdown(item.itemID)
        plan.name, plan.maxPrice = item.name, item.maxPrice
        plan.stashBank, plan.stashWarband = bd.bank, bd.warband
        self:_Arm(plan)
    end)
end

-- Show the confirm flyout. Its Buy click is the hardware event
-- StartCommoditiesPurchase requires, and calls Fire().
function Loop:_Arm(plan)
    self.state.armedPlan = plan
    Status(("Ready: %d x %s for %s -- confirm in the buy flyout"):format(
        plan.planQuantity, plan.name, ADDON.MoneyText(plan.plannedSpend)))
    ADDON.MainFrame:RefreshRestockBtn()
    ADDON.MainFrame:ShowArmedToast(plan, {
        onBuy  = function() self:Fire() end,
        onSkip = function() self:_OnSkip(plan) end,
        onStop = function() self:Stop("user_stop") end,
    })
end

-- The Buy click. Consumes the armed plan; a double click can't buy twice.
function Loop:Fire()
    local s, plan = self.state, self.state.armedPlan
    if not (s.active and plan) or s.buying then return end
    s.armedPlan, s.buying = nil, true
    ADDON.Log:Emit("buy_attempt", plan.itemID, {
        qty = plan.planQuantity, plannedSpendCopper = plan.plannedSpend, worstUnitCopper = plan.worstUnitPrice,
    })
    Status(("Buying %d x %s..."):format(plan.planQuantity, plan.name))
    ADDON.MainFrame:HideToast()
    ADDON.MainFrame:RefreshRestockBtn()
    ADDON.AH:ExecutePurchase(plan.itemID, plan.planQuantity, plan.plannedSpend, function(ok, err)
        if not s.active then return end
        s.buying = false
        if ok then
            s.spentCopper, s.touched = s.spentCopper + plan.plannedSpend, s.touched + 1
            self:_RecordPurchase(plan.itemID, plan.planQuantity)  -- first, so the next check counts it
            ADDON.Log:Emit("buy_success", plan.itemID, { qty = plan.planQuantity, spentCopper = plan.plannedSpend })
            Status(("|cff4ade80Bought %d %s for %s (via mail)|r"):format(
                plan.planQuantity, plan.name, ADDON.MoneyText(plan.plannedSpend)))
        else
            s.stillShort = s.stillShort + 1
            ADDON.Log:Emit("buy_fail", plan.itemID, { reason = tostring(err) })
            Status(("|cffff8888Buy failed for %s: %s|r"):format(plan.name, tostring(err)))
        end
        ADDON.MainFrame:RefreshRestockBtn()
        -- A beat for inventory counts to update before the next search.
        C_Timer.After(0.8, function() self:Advance() end)
    end)
end

function Loop:_OnSkip(plan)
    if not self.state.active then return end
    ADDON.Log:Emit("buy_skip", plan.itemID, { reason = "user skipped" })
    Status(("Skipped %s"):format(plan.name))
    self.state.armedPlan = nil
    ADDON.MainFrame:HideToast()
    C_Timer.After(0.2, function() self:Advance() end)
end

-- reason: "done", "AH closed", "user_esc" or "user_stop" (the log words these).
function Loop:Stop(reason)
    local s = self.state
    if not s.active then return end
    s.active = false  -- pending AH callbacks hold this table; they must see the stop
    self.state = NewState()
    ADDON.Log:Emit("loop_stop", nil, { reason = reason, spentCopper = s.spentCopper, touched = s.touched,
                                        stillShort = s.stillShort, skippedCapped = s.skippedCapped })
    local mf = ADDON.MainFrame
    if mf._toastMode == "armed" then mf:HideToast() end
    mf:RefreshRestockBtn()

    -- End-of-run recap: title in the footer and flyout, detail line in the flyout.
    local mail  = next(Ledger()) and " (mail pending)" or ""
    local skip  = s.skippedCapped > 0 and ("  \194\183  %d skipped over cap"):format(s.skippedCapped) or ""
    local money = ADDON.MoneyText(s.spentCopper)
    local title, sub
    if reason == "done" then
        title = ("|cff4ade80Restock complete|r  \194\183  bought %d for %s"):format(s.touched, money)
        local total = s.touched + s.stillShort + s.skippedCapped
        -- One item: "1/1 resolved" would repeat the title.
        sub = total > 1 and ("%d/%d items resolved%s%s"):format(s.touched, total, skip, mail)
              or mail:gsub("^%s+", "")
    elseif reason == "user_esc" or reason == "user_stop" then
        title = ("Stopped  \194\183  bought %d for %s"):format(s.touched, money)
        sub   = ("%d still short%s%s"):format(s.stillShort, skip, mail)
    elseif reason == "AH closed" then
        title = ("AH closed  \194\183  bought %d for %s"):format(s.touched, money)
        sub   = ("Reopen the AH to continue%s%s"):format(skip, mail)
    else
        title = ("Stopped (%s)"):format(tostring(reason))
        sub   = ("bought %d for %s%s%s"):format(s.touched, money, skip, mail)
    end
    Status(title)
    mf:ShowSummaryToast({ title = title, sub = sub })
end

function Loop:IsActive()
    return self.state.active
end
