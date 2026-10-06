--[[
    StockClerk - BankRestock.lua
    At a banker, two runs over the same planner and executor:
      pull     "Restock from bank": exactly enough of each short item from
               the character bank, then the warband bank, into bags.
      deposit  every listed item above this character's own target (or all
               of it, for an item only on the warband list) from bags into
               the warband bank: surplus lives where every character can
               reach it. Button-only, never automatic.

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
local BAGS = { 0, 1, 2, 3, 4 }  -- pull targets: backpack + bags; the reagent bag can't hold these
local DEPOSIT_BAGS = { 0, 1, 2, 3, 4, 5 }  -- deposit sources: mats can sit in the reagent bag

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

-- Which banks this visit can reach: the warband bank portal opens only the
-- warband bank. kind: "Character" or "Account".
local function usable(kind)
    return not C_Bank.CanUseBank or C_Bank.CanUseBank(Enum.BankType[kind])
end

-- Short items with at least one copy in a bank this visit can reach.
function BR:PullableCount()
    local n = 0
    for _, s in ipairs(self:Shortfalls()) do
        local bd = ADDON.Inventory:GetBreakdown(s.itemID)
        if (usable("Character") and bd.bank or 0) + (usable("Account") and bd.warband or 0) > 0 then n = n + 1 end
    end
    return n
end

-- Surplus in bags (not mail: it can't be deposited yet), personal list
-- first, then items only on the warband list: { {itemID, short = surplus} }.
function BR:Surpluses()
    local out, mine = {}, ADDON.DB:GetItems()
    local function add(itemID, keep)
        local extra = C_Item.GetItemCount(itemID) - keep
        if extra > 0 then out[#out + 1] = { itemID = itemID, short = extra } end
    end
    for _, it in ipairs(ADDON.DB:GetSortedItems()) do add(it.itemID, it.need) end
    for _, it in ipairs(ADDON.DB:GetSortedItems("warband")) do
        if not mine[it.itemID] then add(it.itemID, 0) end
    end
    return out
end

-- Bag stacks that can go in the warband bank (soulbound etc. can't).
local function allowed(bag, slot)
    if not (C_Bank.IsItemAllowedInBankType and ItemLocation) then return true end  -- the move itself will say no
    local ok, yes = pcall(C_Bank.IsItemAllowedInBankType, Enum.BankType.Account,
        ItemLocation:CreateFromBagAndSlot(bag, slot))
    return ok and yes
end

-- Surplus items split into depositable and refused (nothing in bags the
-- warband bank will take).
function BR:DepositPlan()
    local want, refused = {}, {}
    for _, s in ipairs(self:Surpluses()) do want[s.itemID] = s end
    local sources, ok = {}, {}
    for _, bagID in ipairs(DEPOSIT_BAGS) do
        for slot = 1, C_Container.GetContainerNumSlots(bagID) do
            local i = C_Container.GetContainerItemInfo(bagID, slot)
            if i and want[i.itemID] and not i.isLocked and allowed(bagID, slot) then
                sources[#sources + 1] = { bag = bagID, slot = slot, itemID = i.itemID, count = i.stackCount }
                ok[i.itemID] = true
            end
        end
    end
    local list = {}
    for _, s in ipairs(self:Surpluses()) do
        if ok[s.itemID] then list[#list + 1] = s else refused[#refused + 1] = s.itemID end
    end
    return list, sources, refused
end

function BR:DepositableCount()
    return #(self:DepositPlan())
end

local function warbandTabs()
    return C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account) or {}
end

local function slotsOf(bagIDs)
    local out = {}
    for _, bagID in ipairs(bagIDs) do
        for slot = 1, C_Container.GetContainerNumSlots(bagID) do
            local i = C_Container.GetContainerItemInfo(bagID, slot)
            if not (i and i.isLocked) then  -- a slot mid-move can't take a drop
                out[#out + 1] = { bag = bagID, slot = slot, itemID = i and i.itemID, count = i and i.stackCount or 0 }
            end
        end
    end
    return out
end

local function scan()
    local sources, bags = {}, {}
    for _, kind in ipairs({ "Character", "Account" }) do
        for _, bagID in ipairs(usable(kind) and C_Bank.FetchPurchasedBankTabIDs(Enum.BankType[kind]) or {}) do
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
            for _, b in ipairs(slotsOf({ bagID })) do bags[#bags + 1] = b end
        end
    end
    return sources, bags
end

-- ---------------------------------------------------------------------------
-- Executor
-- ---------------------------------------------------------------------------
function BR:IsActive() return self.active end

-- dir: "pull" (default) or "deposit".
function BR:Start(express, dir)
    if self.active then return end
    local mf = ADDON.MainFrame
    if not ADDON.bankOpen then mf:SetStatus("Open the bank first."); return end
    if InCombatLockdown() then mf:SetStatus("|cffff8888Can't use the bank in combat.|r"); return end
    if GetCursorInfo() then mf:SetStatus("|cffff8888Put down the item on your cursor first.|r"); return end
    self.dir = dir or "pull"
    self.active, self.moved, self.tabs, self.run = true, {}, {}, (self.run or 0) + 1
    self.mode = express and "express" or "manual"
    -- A pull serves your own list, so show it. A deposit can cover items on
    -- either list: the view stays, and its marks are warband blue.
    if self.dir == "pull" then mf:SetView("mine") end
    mf:ClearMarks()
    self:_Step(self.run)
end

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function plural(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end

-- Finish (or abort with `reason`) and report in the footer.
function BR:Stop(reason)
    if not self.active then return end
    self.active = false
    if GetCursorInfo() then ClearCursor() end
    local mf, deposit = ADDON.MainFrame, self.dir == "deposit"
    local verb = deposit and "Deposited %d to the warband bank" or "Pulled %d from your bank"
    for itemID, m in pairs(mf.marks) do  -- stopped mid-move: that row isn't "current" any more
        local n = self.moved[itemID]
        if m.kind == "current" then mf:Mark(itemID, n and "done", n and verb:format(n), deposit) end
    end
    for itemID, qty in pairs(self.moved) do  -- one log entry per item moved
        if deposit then ADDON.Log:Emit("bank_deposit", itemID, { qty = qty, tab = self.tabs[itemID] })
        else ADDON.Log:Emit("bank_pull", itemID, { qty = qty }) end
    end
    local items = count(self.moved)
    ADDON.Log:Emit("bank_run", nil, { items = items, reason = reason, mode = self.mode, dir = self.dir })
    ADDON.Inventory:Invalidate()
    ADDON.RestockLoop:Sweep()  -- deposited warband buys leave transit now, not at the next bag event
    mf:SetCheckout(nil)
    return mf:SetStatus(deposit and self:_DepositReceipt(items, reason) or self:_PullReceipt(items, reason))
end

function BR:_PullReceipt(items, reason)
    local msg = items == 0 and "Nothing pulled from the bank." or ("Pulled %s from the bank."):format(plural(items, "item"))
    if reason == "not enough bag space" and items == 0 then
        msg = "|cffff8888Not enough bag space.|r"
    elseif reason then
        msg = msg .. " |cffff8888Stopped: " .. reason .. ".|r"
    end
    local stillShort = #self:Shortfalls()
    if stillShort > 0 and reason ~= "not enough bag space" then  -- they're in the bank, not the AH
        msg = msg .. (" %d still short, restock at the AH."):format(stillShort)
    end
    local d = self:DepositableCount()
    if d > 0 and not reason then msg = msg .. (" |cff5AA9FFWarband: deposit %s.|r"):format(plural(d, "item")) end
    return msg
end

-- "Done: deposited 3 to the warband · 1 can't go in the warband · 2 more waiting in your mail"
function BR:_DepositReceipt(items, reason)
    local head = ({ [false] = "|cff5AA9FFDone|r", ["warband bank is full"] = "|cffff8888Warband bank is full|r" })[reason or false]
        or ("Stopped (" .. reason .. ")")
    local parts = { items > 0 and ("deposited %s to the warband"):format(plural(items, "item")) or "nothing deposited" }
    local _, _, refused = self:DepositPlan()
    local mf = ADDON.MainFrame
    for _, id in ipairs(refused) do
        mf:Mark(id, "failed", "Can't go in the warband bank (soulbound or otherwise restricted)")
        ADDON.Log:Emit("deposit_skip", id, { reason = "refused" })
    end
    if #refused > 0 then parts[#parts + 1] = ("%d can't go in the warband"):format(#refused) end
    local mail, mine = 0, ADDON.DB:GetItems()  -- surplus still in the mail: deposited on a later visit
    for id in pairs(ADDON.DB.char.pendingBuys) do
        local keep = mine[id] and mine[id].need or 0
        if (mine[id] or ADDON.DB:GetItems("warband")[id])
           and ADDON.RestockLoop:Surplus(id) > math.max(0, C_Item.GetItemCount(id) - keep) then
            mail = mail + 1
        end
    end
    if mail > 0 then parts[#parts + 1] = plural(mail, "more item") .. " waiting in your mail" end
    return head .. ": " .. table.concat(parts, " \194\183 ")
end

-- The next move for this run: { move, name } or nil plus why nothing moves.
function BR:_NextMove()
    if self.dir == "deposit" then
        local list, sources = self:DepositPlan()
        if #list == 0 then return nil end
        local m = BR.PlanPulls(list, sources, slotsOf(warbandTabs()), maxStack)[1]
        return m, not m and "warband bank is full" or nil
    end
    local sources, bags = scan()
    local m = BR.PlanPulls(self:Shortfalls(), sources, bags, maxStack)[1]
    -- Nothing left to move: either done or bags are full.
    return m, not m and #self:Shortfalls() > 0 and self:PullableCount() > 0 and "not enough bag space" or nil
end

function BR:_Step(run)
    if not self.active or run ~= self.run then return end
    if not ADDON.bankOpen then return self:Stop("bank closed") end
    if InCombatLockdown() then return self:Stop("entered combat") end

    -- Counts must be live: the inventory cache only refreshes 0.25s after
    -- bag events, and a stale count would move the same item twice.
    ADDON.Inventory:Invalidate()
    local m, why = self:_NextMove()
    if not m then return self:Stop(why) end

    -- Same pattern as the AH checkout: the row being filled is current, and
    -- ticks once something has landed.
    local deposit = self.dir == "deposit"
    local mf, name = ADDON.MainFrame, C_Item.GetItemNameByID(m.itemID) or ("item " .. m.itemID)
    local verb = deposit and "Deposited %d to the warband bank" or "Pulled %d from your bank"
    mf:Mark(m.itemID, "current", deposit and "Moving to your warband bank" or "Moving from your bank", deposit)
    local done = count(self.moved)
    mf:SetCheckout((deposit and "Depositing %d \195\151 %s" or "Pulling %d \195\151 %s"):format(m.count, name),
        ("|cff8c8c8c%s %s so far|r"):format(plural(done, "item"), deposit and "deposited" or "pulled"))

    -- A pull has landed when the bag count rises (only on the server's
    -- confirmation). A deposit's bag count drops the moment the client drops
    -- the stack, so it waits for the warband slot itself: new count, unlocked.
    local before = C_Item.GetItemCount(m.itemID)
    local target = C_Container.GetContainerItemInfo(m.toBag, m.toSlot)
    local targetWant = (target and target.stackCount or 0) + m.count
    if m.whole then
        C_Container.PickupContainerItem(m.fromBag, m.fromSlot)
    else
        C_Container.SplitContainerItem(m.fromBag, m.fromSlot, m.count)
    end
    if GetCursorInfo() then C_Container.PickupContainerItem(m.toBag, m.toSlot) end

    local t0 = GetTime()
    local function wait()
        if not self.active or run ~= self.run then return end
        local landed
        if deposit then
            local t = C_Container.GetContainerItemInfo(m.toBag, m.toSlot)
            landed = t and t.stackCount >= targetWant and not t.isLocked
        else
            landed = C_Item.GetItemCount(m.itemID) >= before + m.count
        end
        if landed and not GetCursorInfo() then
            self.moved[m.itemID] = (self.moved[m.itemID] or 0) + m.count
            if deposit then  -- "tab 2": its place among the warband tabs
                for i, id in ipairs(warbandTabs()) do if id == m.toBag then self.tabs[m.itemID] = i end end
            end
            mf:Mark(m.itemID, "done", verb:format(self.moved[m.itemID]), deposit)
            return self:_Step(run)
        end
        if GetTime() - t0 > MOVE_TIMEOUT then return self:Stop("a move didn't finish") end
        C_Timer.After(0.05, wait)
    end
    C_Timer.After(0.05, wait)
end
