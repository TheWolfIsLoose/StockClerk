--[[
    Stock Clerk - AH.lua
    Commodity search and buyout on C_AuctionHouse. One operation at a time;
    a new one supersedes the old. Never spends gold on its own: a buy is
    StartCommoditiesPurchase (after the player's Buy click) and is confirmed
    only if the server's price hasn't risen past what was shown.

    Search: SendSearchQuery -> COMMODITY_SEARCH_RESULTS_UPDATED -> read results.
    Buy:    StartCommoditiesPurchase -> COMMODITY_PRICE_UPDATED (confirm or
            cancel) -> COMMODITY_PURCHASE_SUCCEEDED / _FAILED.
    Commodities only (potions, flasks, mats); gear uses a different API.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local AH = { state = {} }  -- state: mode ("search"|"buy"), itemID, callback, timer, ...
ADDON.AH = AH

local SORT_UNIT_PRICE_ASC = { { sortOrder = 0, reverseSort = false } }
local TIMEOUT = 6  -- seconds for the server to answer any step

-- End the current operation; the callback runs next frame so it can start
-- a new one without re-entering this state.
local function Finish(ok, result)
    local s = AH.state
    if s.timer then s.timer:Cancel() end
    local cb = s.callback
    wipe(s)
    if cb then C_Timer.After(0, function() cb(ok, result) end) end
end

local function Begin(mode, itemID, callback, timeoutMsg, onTimeout)
    if AH.state.mode then
        ADDON.Debug("AH", "cancelling in-flight " .. AH.state.mode)
        Finish(false, "superseded")
    end
    AH.state.mode, AH.state.itemID, AH.state.callback = mode, itemID, callback
    AH.state.timer = C_Timer.NewTimer(TIMEOUT, function()
        ADDON.Debug("AH", timeoutMsg .. " id=" .. itemID)
        if onTimeout then onTimeout() end
        Finish(false, timeoutMsg)
    end)
end

-- callback(true, results) with results cheapest first: { { unitPrice, quantity }, ... },
-- or callback(false, reason). priceSource ("click" | "loop") tags the Last Seen stamp.
function AH:SearchItem(itemID, callback, priceSource)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        return callback(false, "AH is not open")
    end
    Begin("search", itemID, callback, "search timeout")
    self.state.priceSource = priceSource
    ADDON.Debug("AH", "SendSearchQuery id=" .. itemID)
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(itemID), SORT_UNIT_PRICE_ASC, false)
end

-- Plan a buy of up to `quantity` at or below maxUnitPrice (nil = no cap) from a
-- fresh search. callback(true, plan) or callback(false, reason, overCapCheapest):
-- the third value is set only when every listing is above the cap. The plan
-- may cover less than asked for if cheap listings run out.
function AH:BuyUpTo(itemID, quantity, maxUnitPrice, callback)
    self:SearchItem(itemID, function(ok, results)
        if not ok then return callback(false, "search failed: " .. tostring(results)) end
        local toBuy, spend, worst = 0, 0, 0
        for _, r in ipairs(results) do
            if toBuy >= quantity or (maxUnitPrice and r.unitPrice > maxUnitPrice) then break end
            local take = math.min(r.quantity, quantity - toBuy)
            toBuy, spend, worst = toBuy + take, spend + take * r.unitPrice, math.max(worst, r.unitPrice)
        end
        if toBuy > 0 then
            return callback(true, { itemID = itemID, planQuantity = toBuy, plannedSpend = spend, worstUnitPrice = worst })
        end
        local cheapest = results[1] and results[1].unitPrice
        if not cheapest then return callback(false, "no auctions listed") end
        if maxUnitPrice then
            return callback(false, ("cheapest %s is above your %dg cap"):format(
                ADDON.MoneyText(cheapest), math.floor(maxUnitPrice / 10000)), cheapest)
        end
        callback(false, "cheapest " .. ADDON.MoneyText(cheapest) .. " but no quantity available")
    end, "loop")
end

-- Buy a plan the player just confirmed. expectedSpend is the ceiling: a
-- higher server total cancels instead of confirming.
function AH:ExecutePurchase(itemID, quantity, expectedSpend, callback)
    Begin("buy", itemID, callback, "buy timeout",
        -- Cancel server-side so the next buy isn't blocked by an orphaned start.
        function() pcall(C_AuctionHouse.CancelCommoditiesPurchase) end)
    self.state.quantity, self.state.expectedSpend = quantity, expectedSpend
    ADDON.Debug("AH", ("StartCommoditiesPurchase id=%d qty=%d expected=%d"):format(itemID, quantity, expectedSpend or 0))
    C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
end

-- ---------------------------------------------------------------------------
-- Events (forwarded by Core). Other addons' searches don't match our state.
-- ---------------------------------------------------------------------------
function AH:OnCommoditySearchUpdated(itemID)
    local s = self.state
    if s.mode ~= "search" or s.itemID ~= itemID then return end
    local results = {}
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0 do
        local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if info then results[#results + 1] = { unitPrice = info.unitPrice, quantity = info.quantity } end
    end
    -- Free Last Seen data: stamp the cheapest price and repaint the column.
    local cheapest = results[1] and results[1].unitPrice
    if cheapest then
        ADDON.DB:StampLastPrice(itemID, cheapest, s.priceSource)
        ADDON.MainFrame:Refresh()
    end
    ADDON.Log:Emit("ah_search", itemID, { unitPriceCopper = cheapest, listings = #results })
    Finish(true, results)
end

-- (unitPrice, totalPrice) for the pending buy; no itemID in the payload, but
-- only one buy is ever in flight.
function AH:OnCommodityPriceUpdated(unitPrice, totalPrice)
    local s = self.state
    if s.mode ~= "buy" then return end
    ADDON.Debug("AH", ("price update id=%d unit=%d total=%d expected=%d"):format(
        s.itemID, unitPrice or 0, totalPrice or 0, s.expectedSpend or 0))
    if not (totalPrice and totalPrice <= (s.expectedSpend or math.huge)) then
        C_AuctionHouse.CancelCommoditiesPurchase()
        return Finish(false, "price rose above cap during purchase")
    end
    C_AuctionHouse.ConfirmCommoditiesPurchase(s.itemID, s.quantity)
    s.timer:Cancel()  -- fresh timeout for the confirm ack
    s.timer = C_Timer.NewTimer(TIMEOUT, function()
        C_AuctionHouse.CancelCommoditiesPurchase()
        Finish(false, "purchase confirm timed out")
    end)
end

function AH:OnCommodityPriceUnavailable()
    if self.state.mode ~= "buy" then return end
    C_AuctionHouse.CancelCommoditiesPurchase()
    Finish(false, "listings stale, re-search needed")
end

function AH:OnCommodityPurchaseSucceeded()
    if self.state.mode == "buy" then Finish(true) end
end

function AH:OnCommodityPurchaseFailed()
    if self.state.mode == "buy" then Finish(false, "server reported purchase failed") end
end

function AH:OnAuctionHouseClosed()
    if self.state.mode then Finish(false, "AH closed") end
end
