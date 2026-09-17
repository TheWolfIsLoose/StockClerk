--[[
    Stock Clerk - AH.lua
    Thin wrapper around C_AuctionHouse for search + commodity buyout.

    Scope (Wave 1.5 soft-release):
      * Commodities only (potions, flasks, mats, most consumables). Items
        with per-slot bids (BoP/BoE gear) are NOT supported yet; those
        use ItemSearch, not CommoditySearch. Called out in NOTES.md.
      * One search in flight at a time. Any new call cancels the old.
      * Read-only browse -> callback with results. Never spends money on
        its own. The actual buyout is a two-step server handshake
        (StartCommoditiesPurchase -> ConfirmCommoditiesPurchase), so we
        always have a chance to bail if price drifts between search and
        buy.

    Reference:
      Auctionator/Source_ModernAH/Tabs/Buying/Commodity/Mixins/Main.lua
      and Dialogs.lua were the source-of-truth for the API dance.

    Event flow for a search:
      1. C_AuctionHouse.SendSearchQuery(itemKey, sorts, false)
      2. wait for COMMODITY_SEARCH_RESULTS_UPDATED (arg = itemID)
      3. C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)

    Event flow for a buy:
      1. C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
      2. wait for one of:
           COMMODITY_PRICE_UPDATED    - price drifted, server sent new total
           COMMODITY_PRICE_UNAVAILABLE- results went stale, must re-search
           COMMODITY_PURCHASE_SUCCEEDED - already went through (rare)
      3. C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, quantity)
      4. wait for COMMODITY_PURCHASE_SUCCEEDED / _FAILED
--]]

local addonName = ...
local ADDON     = _G[addonName]

local AH = {}
ADDON.AH = AH

-- State for the currently-in-flight operation. Only one at a time.
AH.state = {
    mode        = nil,   -- "search" | "buy" | nil
    itemID      = nil,
    quantity    = nil,   -- for buys
    maxUnitPrice= nil,   -- for buys (copper)
    callback    = nil,   -- function(ok, resultOrErr)
    timeoutTimer= nil,
}

local SORT_UNIT_PRICE_ASC = { { sortOrder = 0, reverseSort = false } }
local SEARCH_TIMEOUT_SEC = 6

local function DebugPrint(...)
    if ADDON.debug then
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
        print("|cff98FF98[SC:AH]|r " .. table.concat(parts, " "))
    end
end

local function ClearState()
    if AH.state.timeoutTimer then
        AH.state.timeoutTimer:Cancel()
        AH.state.timeoutTimer = nil
    end
    AH.state.mode         = nil
    AH.state.itemID       = nil
    AH.state.quantity     = nil
    AH.state.maxUnitPrice = nil
    AH.state.callback     = nil
end

local function Finish(ok, result)
    local cb = AH.state.callback
    ClearState()
    if cb then
        -- Defer one frame so callers can safely start a new operation
        -- from within the callback without re-entering our state mid-clear.
        C_Timer.After(0, function() cb(ok, result) end)
    end
end

-- ---------------------------------------------------------------------------
-- Public: search
-- ---------------------------------------------------------------------------
-- Fires an AH search for a commodity. Callback receives (true, results)
-- where results is a sorted-by-price array of
--   { unitPrice = copper, quantity = N, owners = {...} }
-- Or (false, errorString) on failure/timeout.
function AH:SearchItem(itemID, callback)
    if not itemID then
        if callback then callback(false, "no itemID") end
        return
    end
    if not C_AuctionHouse or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        if callback then callback(false, "AH is not open") end
        return
    end
    if self.state.mode then
        DebugPrint("cancelling in-flight " .. self.state.mode .. " for new search")
        Finish(false, "superseded")
    end

    self.state.mode     = "search"
    self.state.itemID   = itemID
    self.state.callback = callback

    DebugPrint("SendSearchQuery id=" .. itemID)
    local itemKey = C_AuctionHouse.MakeItemKey(itemID)
    C_AuctionHouse.SendSearchQuery(itemKey, SORT_UNIT_PRICE_ASC, false)

    self.state.timeoutTimer = C_Timer.NewTimer(SEARCH_TIMEOUT_SEC, function()
        DebugPrint("search timeout id=" .. itemID)
        Finish(false, "search timeout")
    end)
end

local function GatherResults(itemID)
    local results = {}
    local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
    for i = 1, n do
        local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if info then
            results[#results + 1] = {
                unitPrice = info.unitPrice,
                quantity  = info.quantity,
                owners    = info.owners,
            }
        end
    end
    return results
end

-- ---------------------------------------------------------------------------
-- Public: buy N units at or below maxUnitPrice
-- ---------------------------------------------------------------------------
-- Two-phase: run a search first, then attempt the purchase from cheapest
-- listings. Callback:
--   (true,  {bought = N, spent = copper, unitPrice = highestPaidUnit})
--   (false, errorStringWithContext)
--
-- Buy is capped at whatever's available at or below maxUnitPrice, so the
-- caller may get less than requested. That's still a "success" -- the
-- callback shows exactly how much moved.
function AH:BuyUpTo(itemID, quantity, maxUnitPrice, callback)
    if not itemID or not quantity or quantity <= 0 then
        if callback then callback(false, "bad args") end
        return
    end

    -- Step 1: run a fresh search so we're working from live data.
    self:SearchItem(itemID, function(ok, resultsOrErr)
        if not ok then
            if callback then callback(false, "search failed: " .. tostring(resultsOrErr)) end
            return
        end

        -- Step 2: walk sorted results, accumulate until we hit quantity
        -- or exceed the price cap. Results are unit-price ascending.
        local toBuy = 0
        local plannedSpend = 0
        local worstUnitPrice = 0
        for _, r in ipairs(resultsOrErr) do
            if toBuy >= quantity then break end
            if maxUnitPrice and r.unitPrice > maxUnitPrice then break end
            local take = math.min(r.quantity, quantity - toBuy)
            toBuy = toBuy + take
            plannedSpend = plannedSpend + take * r.unitPrice
            if r.unitPrice > worstUnitPrice then worstUnitPrice = r.unitPrice end
        end

        if toBuy == 0 then
            local cheapest = resultsOrErr[1] and resultsOrErr[1].unitPrice or nil
            if callback then
                callback(false, "no listings under cap"
                    .. (cheapest and (" (cheapest = " .. GetCoinTextureString(cheapest) .. ")") or ""))
            end
            return
        end

        -- Step 3: hand off to the confirm dialog. It'll call ExecutePurchase.
        if callback then
            callback(true, {
                itemID         = itemID,
                planQuantity   = toBuy,
                plannedSpend   = plannedSpend,
                worstUnitPrice = worstUnitPrice,
                shortfall      = quantity - toBuy,
                requestedQty   = quantity,
            })
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Public: actually execute a purchase the user has already confirmed.
-- Assumes SearchItem was called recently enough that the server results
-- are still valid. If they've drifted, COMMODITY_PRICE_UPDATED will fire
-- with a new total and we bail (user has to reconfirm on next loop turn).
-- ---------------------------------------------------------------------------
function AH:ExecutePurchase(itemID, quantity, expectedSpend, callback)
    if self.state.mode then
        DebugPrint("cancelling in-flight " .. self.state.mode .. " for buy")
        Finish(false, "superseded")
    end

    self.state.mode     = "buy"
    self.state.itemID   = itemID
    self.state.quantity = quantity
    self.state.callback = callback

    DebugPrint(("StartCommoditiesPurchase id=%d qty=%d expected=%d"):format(
        itemID, quantity, expectedSpend or 0))
    self.state.expectedSpend = expectedSpend
    C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)

    self.state.timeoutTimer = C_Timer.NewTimer(SEARCH_TIMEOUT_SEC, function()
        DebugPrint("buy timeout id=" .. itemID)
        Finish(false, "buy timeout")
    end)
end

-- ---------------------------------------------------------------------------
-- Event dispatcher (Core.lua forwards events here)
-- ---------------------------------------------------------------------------
function AH:OnCommoditySearchUpdated(itemID)
    if self.state.mode ~= "search" or self.state.itemID ~= itemID then return end
    DebugPrint("search results in for id=" .. itemID)
    local results = GatherResults(itemID)
    Finish(true, results)
end

-- Server tells us the current price/total for the pending StartCommoditiesPurchase.
-- If it matches (or is under) what we expected, auto-confirm. If it went UP,
-- bail out and let the user re-decide.
function AH:OnCommodityPriceUpdated(itemID, newTotal)
    if self.state.mode ~= "buy" or self.state.itemID ~= itemID then return end
    local expected = self.state.expectedSpend or math.huge
    DebugPrint(("price update id=%d new=%d expected=%d"):format(itemID, newTotal or 0, expected))
    if newTotal and newTotal <= expected then
        DebugPrint("price acceptable, confirming")
        C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, self.state.quantity)
    else
        DebugPrint("price increased beyond cap, cancelling")
        C_AuctionHouse.CancelCommoditiesPurchase()
        Finish(false, "price rose above cap during purchase")
    end
end

function AH:OnCommodityPriceUnavailable(itemID)
    if self.state.mode ~= "buy" or self.state.itemID ~= itemID then return end
    DebugPrint("price unavailable id=" .. itemID)
    C_AuctionHouse.CancelCommoditiesPurchase()
    Finish(false, "listings stale, re-search needed")
end

function AH:OnCommodityPurchaseSucceeded(itemID)
    if self.state.mode ~= "buy" or self.state.itemID ~= itemID then return end
    DebugPrint("purchase succeeded id=" .. itemID)
    Finish(true, {
        itemID   = itemID,
        quantity = self.state.quantity,
        spent    = self.state.expectedSpend,
    })
end

function AH:OnCommodityPurchaseFailed(itemID)
    if self.state.mode ~= "buy" or self.state.itemID ~= itemID then return end
    DebugPrint("purchase failed id=" .. itemID)
    Finish(false, "server reported purchase failed")
end

-- When the AH closes mid-flight, abort cleanly.
function AH:OnAuctionHouseClosed()
    if self.state.mode then
        DebugPrint("AH closed mid-" .. self.state.mode .. ", aborting")
        Finish(false, "AH closed")
    end
end
