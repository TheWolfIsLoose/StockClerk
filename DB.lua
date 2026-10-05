--[[
    StockClerk - DB.lua
    SavedVariables and the per-character list.

    Two lists with the same entry shape, { need, maxPrice?, sortOrder }:
      "mine"    StockClerkCharDB.items   keep N in this character's bags
      "warband" StockClerkDB.global.warband  keep at least N in the warband bank
    sortOrder is the player's list order, which is also restock priority.
    Every list call takes the list name last; nil means "mine".

    StockClerkCharDB (per character):
      uiPos = { point, x, y, width?, height? }
      ui.stuckOnly   "short items only" filter (old name kept for saved data)
      ui.view        "mine" | "warband": the list the window shows
      shopWarband    offer the warband pass at the AH on this character
      pendingBuys    mail ledger, see RestockLoop
    StockClerkDB.global (account): settings, log, warband list,
      prices[itemID] = { copper, seenAt, source }  Last Seen, shared by every
        character and both lists
      transit[charKey][itemID] = qty  warband buys not yet deposited, so
        other characters don't buy them again (see RestockLoop)
    The `.global` layer is the old AceDB shape, kept so existing data loads as-is.
    New fields go in `defaults`; Initialize fills them in without a migration.
--]]

local addonName = ...
local ADDON     = _G[addonName] or {}
_G[addonName]   = ADDON

local DB = {}
ADDON.DB = DB

DB.defaults = {
    char = {
        items       = {},
        uiPos       = { point = "CENTER", x = 0, y = 0 },
        ui          = { stuckOnly = false, view = "mine" },
        pendingBuys = {},
        shopWarband = true,
    },
    global = {
        warband  = {},
        prices   = {},
        transit  = {},
        settings = {
            autoOpenAtAH    = true,
            autoOpenAtBank  = true,
            autoRestock     = false,      -- Express restock at AH: opt-in, it starts a buying flow
            autoRestockBank = false,      -- Express restock at Bank: opt-in
            lastPriceTTL    = 24 * 3600,  -- Last Seen dims after 24h
        },
    },
}

-- Fill missing keys from defaults, recursively, so new settings reach existing users.
local function ApplyDefaults(saved, defaults)
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            saved[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" and type(saved[k]) == "table" then
            ApplyDefaults(saved[k], v)
        end
    end
    return saved
end

-- Core calls this at ADDON_LOADED.
function DB:Initialize()
    StockClerkDB = StockClerkDB or {}
    StockClerkDB.global = ApplyDefaults(StockClerkDB.global or {}, self.defaults.global)
    self.global = StockClerkDB.global
    StockClerkCharDB = ApplyDefaults(StockClerkCharDB or {}, self.defaults.char)
    self.char = StockClerkCharDB

    -- Saves from before list ordering: stamp the current alphabetical order.
    local items, needsOrder = self.char.items, false
    for _, entry in pairs(items) do
        if not entry.sortOrder then needsOrder = true; break end
    end
    if needsOrder then
        local ids = {}
        for itemID in pairs(items) do ids[#ids + 1] = itemID end
        local function name(id) return C_Item.GetItemInfo(id) or ("item:" .. id) end
        table.sort(ids, function(a, b)
            if name(a) == name(b) then return a < b end
            return name(a) < name(b)
        end)
        for i, itemID in ipairs(ids) do items[itemID].sortOrder = i * 10 end
    end

    -- Ledger hygiene: number keys (a hand-edit can leave strings), and drop
    -- entries older than 30 days (auction mail has expired by then).
    local expiry, ledger = GetServerTime() - 30 * 86400, {}
    for k, v in pairs(self.char.pendingBuys) do
        local id = tonumber(k)
        if id and type(v) == "table" and (v.qty or 0) > 0 and (v.boughtAt or 0) >= expiry then
            ledger[id] = { qty = v.qty, baseHave = v.baseHave or 0, boughtAt = v.boughtAt }
        end
    end
    self.char.pendingBuys = ledger

    -- Last Seen used to live on each character's items: fold it into the
    -- shared table (newest wins).
    local prices = self.global.prices
    for itemID, entry in pairs(items) do
        local lp = entry.lastPrice
        if lp and (not prices[itemID] or prices[itemID].seenAt < lp.seenAt) then prices[itemID] = lp end
        entry.lastPrice = nil
    end
end

-- "Name-Realm", the key for this character's warband transit.
function DB:CharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

function DB:Settings()
    return self.global.settings
end

function DB:GetStuckOnly()
    return self.char.ui.stuckOnly == true
end

function DB:SetStuckOnly(on)
    self.char.ui.stuckOnly = on and true or false
end

-- The raw items table of a list (read-only for callers).
function DB:GetItems(list)
    return list == "warband" and self.global.warband or self.char.items
end

function DB:LastPrice(itemID)
    return self.global.prices[itemID]
end

-- A list in the player's order. Restock order and priority follow it.
function DB:GetSortedItems(list)
    local out = {}
    for itemID, entry in pairs(self:GetItems(list)) do
        out[#out + 1] = {
            itemID    = itemID,
            name      = C_Item.GetItemInfo(itemID) or ("item:" .. itemID),
            need      = entry.need,
            maxPrice  = entry.maxPrice,
            lastPrice = self.global.prices[itemID],
            sortOrder = entry.sortOrder,
        }
    end
    table.sort(out, function(a, b)
        if a.sortOrder ~= b.sortOrder then return a.sortOrder < b.sortOrder end
        return a.itemID < b.itemID
    end)
    return out
end

-- Apply a new full order (10, 20, 30... leaves gaps). Refused unless it
-- names every item on the list.
function DB:ReorderItems(orderedIDs, list)
    local items, seen = self:GetItems(list), {}
    for _, id in ipairs(orderedIDs) do seen[id] = true end
    for id in pairs(items) do
        if not seen[id] then return false end
    end
    for i, id in ipairs(orderedIDs) do
        if items[id] then items[id].sortOrder = i * 10 end
    end
    return true
end

-- Create or update an item. need 0 removes it; maxPrice (copper) changes
-- only when given. New items go last: the order is the player's priority.
function DB:SetItem(itemID, need, maxPrice, list)
    itemID, need = tonumber(itemID), tonumber(need)
    if not itemID or not need or need < 0 then return end
    local items = self:GetItems(list)
    if need == 0 then
        items[itemID] = nil
    elseif items[itemID] then
        items[itemID].need = need
        if maxPrice ~= nil then items[itemID].maxPrice = maxPrice end
    else
        local last = 0
        for _, entry in pairs(items) do last = math.max(last, entry.sortOrder or 0) end
        items[itemID] = { need = need, maxPrice = maxPrice, sortOrder = last + 10 }
    end
end

-- Adds each Data/Consumables.lua item not yet on the list, at target 1;
-- listed items are never touched. Returns how many were added.
function DB:AddCommonConsumables(list)
    local added = 0
    for _, itemID in ipairs(ADDON.CommonConsumables) do
        if not self:GetItems(list)[itemID] then
            self:SetItem(itemID, 1, nil, list)
            added = added + 1
        end
    end
    return added
end

function DB:SetItemMaxPrice(itemID, maxPriceCopper, list)
    local entry = self:GetItems(list)[itemID]
    if entry then entry.maxPrice = maxPriceCopper end
end

-- Last AH unit price ("click" or "loop" search), for items on either list
-- (a search that returns after the item was removed is ignored).
function DB:StampLastPrice(itemID, copperPerUnit, source)
    if copperPerUnit > 0 and (self.char.items[itemID] or self.global.warband[itemID]) then
        self.global.prices[itemID] = { copper = copperPerUnit, seenAt = time(), source = source or "unknown" }
    end
end

function DB:RemoveItem(itemID, list)
    self:GetItems(list)[itemID] = nil
end

function DB:ClearAll()
    wipe(self.char.items)
end
