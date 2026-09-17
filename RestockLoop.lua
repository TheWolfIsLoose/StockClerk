--[[
    Stock Clerk - RestockLoop.lua
    Walks the shortlist and drives per-item buy prompts.

    Loop lifecycle:
      Start()  - snapshot the current shortfall list, sort by neediness,
                 open the AH search for the first item, then hand off to
                 the buy dialog.
      Advance()- pop the current item, jump to the next. Called after
                 the user confirms, skips, or a search yields nothing.
      Stop()   - abort, close any open dialog, clear state.

    Contract:
      * Only runs while the AH is open. If the user closes the AH we
        stop cleanly.
      * Never buys without a user confirmation for that specific item
        (the BuyDialog is the gate). "Auto-advance" means we skip to
        the next item automatically AFTER a decision; it does not
        skip the decision itself.
      * Uses each item's saved maxPrice as the cap. Items without a
        cap are shown but the dialog warns.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local Loop = {}
ADDON.RestockLoop = Loop

Loop.state = {
    active    = false,
    queue     = nil,   -- array of shortfall items to process (copies)
    index     = 0,     -- current position in queue
    lastPlan  = nil,   -- BuyUpTo result for the current item
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

-- Build the queue of items that are BELOW target, sorted by biggest
-- shortfall first so raid-critical stuff comes up before nice-to-haves.
local function BuildQueue()
    local q = {}
    for _, it in ipairs(ADDON.DB:GetSortedItems()) do
        local have = ADDON.Inventory:GetCount(it.itemID) or 0
        local short = it.need - have
        if short > 0 then
            q[#q + 1] = {
                itemID   = it.itemID,
                name     = it.name,
                need     = it.need,
                have     = have,
                short    = short,
                maxPrice = it.maxPrice,
            }
        end
    end
    table.sort(q, function(a, b) return a.short > b.short end)
    return q
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
        Status("|cff4ade80Nothing to restock -- all items at or above target.|r")
        return
    end

    self.state.active = true
    self.state.queue  = q
    self.state.index  = 0
    DebugPrint("started with " .. #q .. " items to process")
    self:Advance()
end

function Loop:Advance()
    if not self.state.active then return end
    self.state.index = self.state.index + 1
    local item = self.state.queue[self.state.index]
    if not item then
        DebugPrint("queue exhausted, stopping")
        self:Stop("|cff4ade80Restock loop done.|r")
        return
    end

    Status(("Searching AH: %s (%d/%d in queue)"):format(
        item.name, self.state.index, #self.state.queue))

    -- Re-derive short in case we bought some in a prior loop iteration
    -- and the count has updated.
    local have = ADDON.Inventory:GetCount(item.itemID) or 0
    local short = item.need - have
    if short <= 0 then
        DebugPrint(("skip id=%d, already restocked (%d/%d)"):format(item.itemID, have, item.need))
        self:Advance()
        return
    end

    DebugPrint(("processing id=%d need=%d have=%d short=%d cap=%s"):format(
        item.itemID, item.need, have, short, tostring(item.maxPrice)))

    ADDON.AH:BuyUpTo(item.itemID, short, item.maxPrice, function(ok, plan)
        if not self.state.active then return end -- user stopped mid-flight
        if not ok then
            DebugPrint("search/plan failed: " .. tostring(plan))
            Status(("|cffff8888%s: %s|r"):format(item.name, tostring(plan)))
            -- On failure we still auto-advance -- one bad item shouldn't
            -- stall the queue. User can restart if they want to retry.
            C_Timer.After(1.0, function() if self.state.active then self:Advance() end end)
            return
        end

        self.state.lastPlan = plan
        plan.name = item.name
        plan.have = have
        plan.need = item.need
        plan.maxPrice = item.maxPrice
        ADDON.BuyDialog:Show(plan, {
            onConfirm = function() self:_OnConfirm(plan) end,
            onSkip    = function() self:_OnSkip(plan) end,
            onStop    = function() self:Stop("Loop stopped.") end,
        })
    end)
end

function Loop:_OnConfirm(plan)
    if not self.state.active then return end
    DebugPrint(("confirming buy id=%d qty=%d spend=%d"):format(
        plan.itemID, plan.planQuantity, plan.plannedSpend))
    Status(("Buying %d x %s..."):format(plan.planQuantity, plan.name))
    ADDON.AH:ExecutePurchase(plan.itemID, plan.planQuantity, plan.plannedSpend, function(ok, result)
        if not self.state.active then return end
        if ok then
            Status(("|cff4ade80Bought %d %s for %s|r"):format(
                plan.planQuantity, plan.name, GetCoinTextureString(plan.plannedSpend)))
        else
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
    Status(("Skipped %s"):format(plan.name))
    C_Timer.After(0.2, function() if self.state.active then self:Advance() end end)
end

function Loop:Stop(msg)
    if not self.state.active then return end
    DebugPrint("stopping loop")
    self.state.active   = false
    self.state.queue    = nil
    self.state.index    = 0
    self.state.lastPlan = nil
    if ADDON.BuyDialog and ADDON.BuyDialog.Hide then
        ADDON.BuyDialog:Hide()
    end
    if msg then Status(msg) end
end

function Loop:IsActive()
    return self.state.active == true
end
