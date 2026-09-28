--[[
    Stock Clerk - RestockLoop.lua
    "Restock at AH" (checkout): walks the short items in list order. For
    each it searches the AH, then marks it over cap and moves on, or shows
    it in the footer with Buy in place of the Restock button. Buying needs
    the player's click (a hardware event), so nothing is ever bought
    silently. After each buy, skip or failure it moves on; closing the AH,
    Escape or the footer's x stops it.

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
-- Running (checkout). The list is the shopping list: each short item gets a
-- mark (queued, current, bought, over cap...) and the footer shows the one
-- being bought, with Buy where the Restock button was.
-- ---------------------------------------------------------------------------
local BUY_LOCK  = 1.5  -- seconds Buy waits when an item looks risky
local DEBOUNCE  = 0.5  -- no Buy within this long of the player's last click
local PRICEY    = 1.25 -- "well above Last Seen": average unit price over 125% of it
local AMBER, GREY = "|cffffa866", "|cff999999"

local function MF() return ADDON.MainFrame end

-- How many items a Restock would try right now. The one shortfall answer for
-- the button, Express-Restock and the footer, so they can't disagree.
function Loop:PreviewShortfallCount()
    local n = 0
    for itemID, entry in pairs(ADDON.DB:GetItems()) do
        if entry.need > self:_EffectiveHave(itemID) then n = n + 1 end
    end
    return n
end

-- "2 of 4 · spent 2,420g"
function Loop:_Progress()
    local s = self.state
    local txt = ("%d of %d"):format(s.index, #s.queue)
    if s.spentCopper > 0 then txt = txt .. " \194\183 spent " .. ADDON.MoneyText(s.spentCopper, "gold") end
    return txt
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
    self.state.active, self.state.queue, self.state.clickAt = true, queue, GetTime()
    MF():ClearMarks()
    for _, it in ipairs(queue) do MF():Mark(it.itemID, "queued", "In this restock") end
    ADDON.Log:Emit("loop_start", nil, { queueSize = #queue, mode = express and "express" or "manual" })
    self:Advance()
end

-- Next item: search, then mark it over cap (and move on) or arm Buy.
function Loop:Advance()
    local s = self.state
    if not s.active then return end
    s.index = s.index + 1
    local item = s.queue[s.index]
    if not item then return self:Stop("done") end

    -- An earlier buy (or run) may have covered it already.
    local have = self:_EffectiveHave(item.itemID)
    local short = item.need - have
    if short <= 0 then
        MF():Mark(item.itemID, nil)
        return self:Advance()
    end
    ADDON.Debug("Loop", ("processing id=%d need=%d have=%d short=%d cap=%s"):format(
        item.itemID, item.need, have, short, tostring(item.maxPrice)))
    Status(("Searching AH: %s (%d/%d in queue)"):format(item.name, s.index, #s.queue))
    MF():Mark(item.itemID, "current", "Checking the AH")
    MF():SetCheckout(GREY .. "Checking " .. item.name .. "...|r", GREY .. self:_Progress() .. "|r")
    -- The search re-stamps Last Seen, so read the previous price first.
    local seen = (ADDON.DB:GetItems()[item.itemID] or {}).lastPrice  -- nil if removed mid-run

    ADDON.AH:BuyUpTo(item.itemID, short, item.maxPrice, function(ok, plan, overCap)
        if not s.active then return end  -- stopped meanwhile
        if not ok then
            if overCap then
                s.skippedCapped = s.skippedCapped + 1
                MF():Mark(item.itemID, "over", "Over your cap: cheapest is " .. ADDON.MoneyText(overCap, "silver"))
                ADDON.Log:Emit("buy_skip", item.itemID, { reason = "over cap" })
            else
                s.stillShort = s.stillShort + 1
                MF():Mark(item.itemID, "failed", "Not bought: " .. plan)
                ADDON.Log:Emit("buy_fail", item.itemID, { reason = plan })
            end
            C_Timer.After(0.15, function() self:Advance() end)
            return
        end
        plan.name = item.name
        -- Anything that makes this buy worth a second look slows Buy down.
        local bd, warn = ADDON.Inventory:GetBreakdown(item.itemID), {}
        if bd.bank > 0 then warn[#warn + 1] = ("%d in your bank"):format(bd.bank) end
        if bd.warband > 0 then warn[#warn + 1] = ("%d in your warband bank"):format(bd.warband) end
        if not item.maxPrice then warn[#warn + 1] = "No cap set" end
        local unit = plan.plannedSpend / plan.planQuantity
        if seen and unit > seen.copper * PRICEY then
            warn[#warn + 1] = ("%d%% above last seen"):format(math.floor((unit / seen.copper - 1) * 100 + 0.5))
        end
        plan.warnings = warn
        self:_Arm(plan)
    end)
end

-- Buy is live once the plan is shown: at once, or after BUY_LOCK when there
-- are warnings, and never within DEBOUNCE of the player's last click (so a
-- double-click on Restock can't buy).
function Loop:_Arm(plan)
    local s = self.state
    s.armedPlan = plan
    s.readyAt = math.max(GetTime() + (#plan.warnings > 0 and BUY_LOCK or 0), s.clickAt + DEBOUNCE)
    Status(("Ready: %d x %s for %s"):format(plan.planQuantity, plan.name, ADDON.MoneyText(plan.plannedSpend)))
    MF():Mark(plan.itemID, "current", "Waiting for you to buy or skip")
    local total = ADDON.MoneyText(plan.plannedSpend, "gold")
    MF():SetCheckout(("%d \195\151 %s"):format(plan.planQuantity, plan.name), #plan.warnings > 0
        and (total .. "  " .. AMBER .. table.concat(plan.warnings, " \194\183 ") .. "|r")
        or  (total .. "  " .. GREY .. self:_Progress() .. "|r"))
    -- Repaint the Buy countdown until it unlocks.
    local ticker
    ticker = C_Timer.NewTicker(0.25, function()
        if s.armedPlan ~= plan or GetTime() >= s.readyAt then ticker:Cancel() end
        MF():RefreshRestockBtn()
    end)
end

-- Seconds until Buy unlocks (0 = ready), or nil when nothing is armed.
function Loop:BuyWait()
    local s = self.state
    if not (s.active and s.armedPlan) or s.buying then return nil end
    return math.max(0, s.readyAt - GetTime())
end

-- The Buy click: the hardware event StartCommoditiesPurchase requires.
-- Consumes the armed plan, so a double click can't buy twice.
function Loop:Fire()
    local s, plan = self.state, self.state.armedPlan
    if self:BuyWait() ~= 0 then return end
    s.armedPlan, s.buying, s.clickAt = nil, true, GetTime()
    ADDON.Log:Emit("buy_attempt", plan.itemID, {
        qty = plan.planQuantity, plannedSpendCopper = plan.plannedSpend, worstUnitCopper = plan.worstUnitPrice,
    })
    Status(("Buying %d x %s..."):format(plan.planQuantity, plan.name))
    MF():Mark(plan.itemID, "current", "Buying")
    MF():SetCheckout(GREY .. ("Buying %d \195\151 %s..."):format(plan.planQuantity, plan.name) .. "|r",
        GREY .. self:_Progress() .. "|r")
    ADDON.AH:ExecutePurchase(plan.itemID, plan.planQuantity, plan.plannedSpend, function(ok, err)
        if not s.active then return end
        s.buying = false
        if ok then
            s.spentCopper, s.touched = s.spentCopper + plan.plannedSpend, s.touched + 1
            self:_RecordPurchase(plan.itemID, plan.planQuantity)  -- first, so the next check counts it
            ADDON.Log:Emit("buy_success", plan.itemID, { qty = plan.planQuantity, spentCopper = plan.plannedSpend })
            Status(("Bought %d %s for %s (via mail)"):format(plan.planQuantity, plan.name, ADDON.MoneyText(plan.plannedSpend)))
            MF():Mark(plan.itemID, "done", ("Bought %d for %s, on its way by mail"):format(
                plan.planQuantity, ADDON.MoneyText(plan.plannedSpend, "gold")))
        else
            s.stillShort = s.stillShort + 1
            ADDON.Log:Emit("buy_fail", plan.itemID, { reason = tostring(err) })
            MF():Mark(plan.itemID, "failed", "Not bought: " .. tostring(err))
        end
        -- A beat for inventory counts to update before the next search.
        C_Timer.After(0.8, function() self:Advance() end)
    end)
end

function Loop:Skip()
    local s, plan = self.state, self.state.armedPlan
    if not (s.active and plan) then return end
    s.armedPlan, s.clickAt = nil, GetTime()
    ADDON.Log:Emit("buy_skip", plan.itemID, { reason = "user skipped" })
    MF():Mark(plan.itemID, "skipped", "Skipped")
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
    -- Items the run never reached lose their marks; results stay until the AH closes.
    for i = s.index, #s.queue do
        local m = MF().marks[s.queue[i].itemID]
        if m and (m.kind == "queued" or m.kind == "current") then MF():Mark(s.queue[i].itemID, nil) end
    end
    MF():SetCheckout(nil)

    -- Receipt: what was spent first, then anything left to act on.
    local head = ({ done = "|cff98FF98Done|r", ["AH closed"] = "AH closed" })[reason] or "Stopped"
    local parts = { s.touched > 0 and ("bought %d for %s"):format(s.touched, ADDON.MoneyText(s.spentCopper, "gold"))
                    or "nothing bought" }
    if s.skippedCapped > 0 then parts[#parts + 1] = s.skippedCapped .. " over cap" end
    if s.stillShort > 0 then parts[#parts + 1] = s.stillShort .. " not bought" end
    Status(head .. ": " .. table.concat(parts, " \194\183 "))
end

function Loop:IsActive()
    return self.state.active
end
