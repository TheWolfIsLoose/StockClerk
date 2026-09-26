--[[
    Stock Clerk - BankRestock.lua
    "Restock from Bank" (v1.2): at a banker, move exactly enough of each
    short item from the character bank, then the warband bank, into bags.

    PlanPulls is pure (no WoW calls) so Dev/smoke.lua can test the stack
    math. The executor re-plans from live bag/bank state before every move
    and does ONE move at a time: the 12.1 bank probe showed a second move
    issued before the first lands fails on the item lock, and a move takes
    ~0.3-0.6s to land (first one up to ~1.7s).
--]]

local addonName = ...
local ADDON     = _G[addonName]

local BR = {}
ADDON.BankRestock = BR

local MOVE_TIMEOUT = 3   -- seconds for one move to land
local BAGS = { 0, 1, 2, 3, 4 }  -- backpack + bags; the reagent bag can't hold these

-- ---------------------------------------------------------------------------
-- Planner (pure).
--   shortfalls: { {itemID=, short=}, ... } in list (priority) order
--   sources:    { {bag=, slot=, itemID=, count=}, ... } char bank first, then warband
--   bags:       { {bag=, slot=, itemID=nil|id, count=}, ... } every usable bag slot
--   maxStack:   function(itemID) -> max stack size
-- Returns moves { {itemID, fromBag, fromSlot, count, toBag, toSlot, whole}, ... }
-- and the number of items still short afterwards. Inputs are not modified.
-- Every move fits its target exactly (no remainder left on the cursor):
-- top up existing stacks of the item first, then use empty slots.
-- ---------------------------------------------------------------------------
function BR.PlanPulls(shortfalls, sources, bags, maxStack)
    local src, bag = {}, {}
    for i, s in ipairs(sources) do src[i] = { bag = s.bag, slot = s.slot, itemID = s.itemID, count = s.count } end
    for i, b in ipairs(bags)    do bag[i] = { bag = b.bag, slot = b.slot, itemID = b.itemID, count = b.count or 0 } end

    local moves, stillShort = {}, 0
    for _, want in ipairs(shortfalls) do
        local id, need, max = want.itemID, want.short, maxStack(want.itemID)
        for _, s in ipairs(src) do
            if need <= 0 then break end
            if s.itemID == id then
                while need > 0 and s.count > 0 do
                    -- Target: a stack of this item with room, else an empty slot.
                    local t, room
                    for _, b in ipairs(bag) do
                        if b.itemID == id and b.count < max then t, room = b, max - b.count; break end
                    end
                    if not t then
                        for _, b in ipairs(bag) do
                            if not b.itemID then t, room = b, max; break end
                        end
                    end
                    if not t then break end      -- bags full
                    local n = math.min(need, s.count, room)
                    moves[#moves + 1] = { itemID = id, fromBag = s.bag, fromSlot = s.slot, count = n,
                                          toBag = t.bag, toSlot = t.slot, whole = (n == s.count) }
                    s.count, need = s.count - n, need - n
                    t.itemID, t.count = id, t.count + n
                end
            end
        end
        if need > 0 then stillShort = stillShort + 1 end
    end
    return moves, stillShort
end

-- ---------------------------------------------------------------------------
-- Live state
-- ---------------------------------------------------------------------------
local function maxStack(itemID)
    return C_Item.GetItemMaxStackSizeByID(itemID) or 1
end

-- Short items in list order, using the same "have" as the AH loop (bags +
-- purchases still in the mail), so mailed items aren't pulled twice.
function BR:Shortfalls()
    local out = {}
    for _, it in ipairs(ADDON.DB:GetSortedItems()) do
        local short = it.need - ADDON.RestockLoop:_EffectiveHave(it.itemID)
        if short > 0 then out[#out + 1] = { itemID = it.itemID, short = short } end
    end
    return out
end

-- Short items with at least one copy in the bank or warband bank.
function BR:PullableCount()
    local n = 0
    for _, s in ipairs(self:Shortfalls()) do
        local bd = ADDON.Inventory:GetBreakdown(s.itemID)
        if bd.bank + bd.warband > 0 then n = n + 1 end
    end
    return n
end

local function scan()
    local sources, bags = {}, {}
    for _, kind in ipairs({ "Character", "Account" }) do
        for _, bagID in ipairs(C_Bank.FetchPurchasedBankTabIDs(Enum.BankType[kind]) or {}) do
            for slot = 1, C_Container.GetContainerNumSlots(bagID) do
                local i = C_Container.GetContainerItemInfo(bagID, slot)
                if i and i.itemID and not i.isLocked then
                    sources[#sources + 1] = { bag = bagID, slot = slot, itemID = i.itemID, count = i.stackCount }
                end
            end
        end
    end
    for _, bagID in ipairs(BAGS) do
        local _, family = C_Container.GetContainerNumFreeSlots(bagID)
        if family == 0 then  -- skip profession bags
            for slot = 1, C_Container.GetContainerNumSlots(bagID) do
                local i = C_Container.GetContainerItemInfo(bagID, slot)
                bags[#bags + 1] = { bag = bagID, slot = slot, itemID = i and i.itemID, count = i and i.stackCount or 0 }
            end
        end
    end
    return sources, bags
end

-- ---------------------------------------------------------------------------
-- Executor
-- ---------------------------------------------------------------------------
function BR:IsActive() return self.active == true end

local function refreshUI()
    local mf = ADDON.MainFrame
    if mf and mf.RefreshRestockBtn then mf:RefreshRestockBtn() end
end

function BR:Start()
    if self.active then return end
    local mf = ADDON.MainFrame
    if not ADDON.bankOpen then mf:SetStatus("Open the bank first."); return end
    if InCombatLockdown() then mf:SetStatus("|cffff8888Can't restock from the bank in combat.|r"); return end
    if GetCursorInfo() then mf:SetStatus("|cffff8888Put down the item on your cursor first.|r"); return end
    self.active, self.pulled, self.run = true, {}, (self.run or 0) + 1
    refreshUI()
    self:_Step(self.run)
end

-- Finish (or abort with `reason`) and report in the footer.
function BR:Stop(reason)
    if not self.active then return end
    self.active = false
    if GetCursorInfo() then ClearCursor() end
    local items = 0
    for itemID, qty in pairs(self.pulled) do  -- one log entry per item pulled
        items = items + 1
        ADDON.Log:Emit("bank_pull", itemID, { qty = qty })
    end
    ADDON.Inventory:Invalidate()
    local stillShort = #self:Shortfalls()
    local msg = items == 0 and "Nothing pulled from the bank."
        or ("Pulled %d item%s from the bank."):format(items, items == 1 and "" or "s")
    if reason then msg = msg .. " |cffff8888Stopped: " .. reason .. "|r" end
    if stillShort > 0 then
        msg = msg .. (" %d still short, restock at the AH."):format(stillShort)
    end
    ADDON.MainFrame:SetStatus(msg)
    refreshUI()
end

function BR:_Step(run)
    if not self.active or run ~= self.run then return end
    if not ADDON.bankOpen then return self:Stop("bank closed") end
    if InCombatLockdown() then return self:Stop("entered combat") end

    -- Counts must be live: the inventory cache only refreshes 0.25s after
    -- bag events, and a stale "have" would pull the same item twice.
    ADDON.Inventory:Invalidate()
    local sources, bags = scan()
    local moves = BR.PlanPulls(self:Shortfalls(), sources, bags, maxStack)
    local m = moves[1]
    if not m then
        -- Nothing left to move: either done or bags are full.
        local left = #self:Shortfalls() > 0 and self:PullableCount() > 0
        return self:Stop(left and "bags are full" or nil)
    end

    local before = C_Item.GetItemCount(m.itemID)
    if m.whole then
        C_Container.PickupContainerItem(m.fromBag, m.fromSlot)
    else
        C_Container.SplitContainerItem(m.fromBag, m.fromSlot, m.count)
    end
    if GetCursorInfo() then C_Container.PickupContainerItem(m.toBag, m.toSlot) end

    local t0 = GetTime()
    local function wait()
        if not self.active or run ~= self.run then return end
        if C_Item.GetItemCount(m.itemID) >= before + m.count and not GetCursorInfo() then
            self.pulled[m.itemID] = (self.pulled[m.itemID] or 0) + m.count
            return self:_Step(run)
        end
        if GetTime() - t0 > MOVE_TIMEOUT then return self:Stop("a move didn't finish") end
        C_Timer.After(0.05, wait)
    end
    C_Timer.After(0.05, wait)
end
