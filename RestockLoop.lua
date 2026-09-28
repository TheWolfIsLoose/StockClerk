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

    Two lanes, one per list. "mine" buys to this character's targets.
    "warband" (offered after it, unless the character opted out) buys to
    the warband list's floors, counting WarbandHave: warband bank + this
    character's surplus (bags and mail above its own target, which the bank
    deposits) + other characters' warband buys not yet deposited (transit).
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
local function Transit()
    local t, key = ADDON.DB.global.transit, ADDON.DB:CharKey()
    t[key] = t[key] or {}
    return t[key]
end

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

-- This character's surplus of an item: bags + mail above its own target
-- (0 when it isn't on this character's list).
function Loop:Surplus(itemID)
    local mine = ADDON.DB:GetItems()[itemID]
    return math.max(0, self:_EffectiveHave(itemID) - (mine and mine.need or 0))
end

-- Toward a warband floor: in the warband bank, this character's surplus (on
-- its way there), and other characters' undeposited warband buys.
function Loop:WarbandHave(itemID)
    local n, me = ADDON.Inventory:GetBreakdown(itemID).warband + self:Surplus(itemID), ADDON.DB:CharKey()
    for key, items in pairs(ADDON.DB.global.transit) do
        if key ~= me then n = n + (items[itemID] or 0) end
    end
    return n
end

-- Inventory changed: settle the ledger for every item in it (items only on
-- the warband list aren't checked by anything else), and clamp this
-- character's transit to its surplus (spent, deposited or never looted).
function Loop:Sweep()
    for id in pairs(Ledger()) do self:_EffectiveHave(id) end
    local transit = ADDON.DB.global.transit[ADDON.DB:CharKey()] or {}  -- don't create one just to read it
    for id, qty in pairs(transit) do
        local left = math.min(qty, self:Surplus(id))
        transit[id] = left > 0 and left or nil
    end
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

-- How many of an item a lane is short.
function Loop:Short(lane, itemID, need)
    return need - (lane == "warband" and self:WarbandHave(itemID) or self:_EffectiveHave(itemID))
end

-- How many items a Restock of `lane` would try right now. The one shortfall
-- answer for the button, Express-Restock and the footer, so they can't disagree.
function Loop:PreviewShortfallCount(lane)
    local n = 0
    for itemID, entry in pairs(ADDON.DB:GetItems(lane)) do
        if self:Short(lane, itemID, entry.need) > 0 then n = n + 1 end
    end
    return n
end

-- Whether the warband pass is offered here: this character hasn't opted
-- out, and something on the warband list is short.
function Loop:WarbandOffered()
    return ADDON.DB.char.shopWarband and self:PreviewShortfallCount("warband") > 0
end

-- The lane the Restock button offers at the AH: whichever has something short
-- and didn't run last this visit, your own first. So a skipped or over-cap
-- item never blocks the warband pass, and after it your own list comes back
-- (a cap may have been raised). nil: nothing short. The AH closing resets it.
function Loop:NextLane()
    local mine, warband = self:PreviewShortfallCount() > 0, self:WarbandOffered()
    if mine and warband then return self.lastLane == "mine" and "warband" or "mine" end
    return mine and "mine" or warband and "warband" or nil
end

-- "2 of 4 · spent 2,420g"
function Loop:_Progress()
    local s = self.state
    local txt = ("%d of %d"):format(s.index, #s.queue)
    if s.spentCopper > 0 then txt = txt .. " \194\183 spent " .. ADDON.MoneyText(s.spentCopper, "gold") end
    return txt
end

-- lane: "mine" (default) or "warband".
function Loop:Start(express, lane)
    if self.state.active then return end
    lane = lane or "mine"
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        return Status("|cffff8888Open the auction house first.|r")
    end
    local queue = {}
    for _, it in ipairs(ADDON.DB:GetSortedItems(lane)) do  -- list order is the priority
        if self:Short(lane, it.itemID, it.need) > 0 then queue[#queue + 1] = it end
    end
    if #queue == 0 then
        -- The button is greyed when nothing is short, so this is a race.
        return Status("|cfff87171Nothing to restock -- every row is at or above its need.|r")
    end
    self.state = NewState()
    self.state.active, self.state.queue, self.state.clickAt, self.state.lane = true, queue, GetTime(), lane
    MF():SetView(lane)  -- the run ticks off the list it's buying for
    MF():ClearMarks()
    for _, it in ipairs(queue) do MF():Mark(it.itemID, "queued", "In this restock") end
    ADDON.Log:Emit("loop_start", nil, { queueSize = #queue, mode = express and "express" or "manual", lane = lane })
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
    local short = self:Short(s.lane, item.itemID, item.need)
    if short <= 0 then
        MF():Mark(item.itemID, nil)
        return self:Advance()
    end
    ADDON.Debug("Loop", ("processing %s id=%d need=%d short=%d cap=%s"):format(
        s.lane, item.itemID, item.need, short, tostring(item.maxPrice)))
    Status(("Searching AH: %s (%d/%d in queue)"):format(item.name, s.index, #s.queue))
    MF():Mark(item.itemID, "current", "Checking the AH")
    MF():SetCheckout(GREY .. "Checking " .. item.name .. "...|r", GREY .. self:_Progress() .. "|r")
    -- The search re-stamps Last Seen, so read the previous price first.
    local seen = ADDON.DB:LastPrice(item.itemID)

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
        -- (Buying for the warband, its stock is already counted.)
        if bd.warband > 0 and s.lane == "mine" then warn[#warn + 1] = ("%d in your warband bank"):format(bd.warband) end
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
            if s.lane == "warband" then  -- other characters count it until it's deposited
                local t = Transit()
                t[plan.itemID] = (t[plan.itemID] or 0) + plan.planQuantity
            end
            ADDON.Log:Emit("buy_success", plan.itemID, { qty = plan.planQuantity, spentCopper = plan.plannedSpend,
                                                         lane = s.lane })
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
    self.lastLane = reason ~= "AH closed" and s.lane or nil  -- a new AH visit starts with your own list
    ADDON.Log:Emit("loop_stop", nil, { reason = reason, spentCopper = s.spentCopper, touched = s.touched,
                                        stillShort = s.stillShort, skippedCapped = s.skippedCapped, lane = s.lane })
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
    -- After your own shopping, point at the warband pass (the button offers it).
    if reason ~= "AH closed" and s.lane == "mine" and self:WarbandOffered() then
        parts[#parts + 1] = ("|cff5AA9FFwarband: %d short|r"):format(self:PreviewShortfallCount("warband"))
    end
    Status(head .. ": " .. table.concat(parts, " \194\183 "))
end

function Loop:IsActive()
    return self.state.active
end
