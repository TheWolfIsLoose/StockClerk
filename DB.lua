--[[
    Stock Clerk - DB.lua
    Owns the SavedVariables schema and provides read/write helpers
    for the per-character consumable list.

    Schema:
      char.items = {
        [itemID:number] = {
          need        = number,
          maxPrice    = copper,          -- optional; nil = no cap set
          addedAt     = timestamp,
          lastPrice   = { copper, seenAt, source },   -- optional
          sortOrder   = number,          -- user-arranged list position;
                                         -- Doubles as restock priority
        }
      }
      char.uiPos = { point, x, y }           -- last MainFrame position
      global.settings  = {
        autoOpenAtAH     = bool,       -- default TRUE. Pops SC on AH visit.
        autoOpenAtBank   = bool,       -- default TRUE. Pops SC at a banker.
        autoRestock      = bool,       -- default FALSE. If TRUE, opening the
                                       -- AH also fires the restock loop when
                                       -- there's a shortfall to work through.
        autoRestockBank  = bool,       -- default FALSE. Same at a banker:
                                       -- pull short items from the bank.
        lastPriceTTL     = number,     -- seconds before "Last Seen" dims
      }
      global.log      = array of entries (see Log.lua)

    We keep the on-disk shape stable across versions; any new field lives
    inside `defaults` so Initialize fills it in on load without a migration.
--]]

local addonName = ...
local ADDON     = _G[addonName] or {}
_G[addonName]   = ADDON

-- Debug print, gated on `/clerk debug`. Shows as [SC:<tag>].
-- Trace step, recorded into the log only while /clerk debug is on.
function ADDON.Debug(tag, ...)
    if not ADDON.debug or not ADDON.Log then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    ADDON.Log:Emit("trace", nil, { tag = tag, text = table.concat(parts, " ") })
end

local DB = {}
ADDON.DB = DB

DB.defaults = {
    char = {
        items = {},
        uiPos = { point = "CENTER", x = 0, y = 0 },
        -- Filter state, per character (lists differ per character).
        -- stuckOnly = "short items only" (old name kept for saved data).
        ui = { stuckOnly = false },

        -- Mail ledger (RestockLoop): itemID -> { qty, baseHave, boughtAt }.
        -- Per character: auction mail goes to the buyer.
        pendingBuys = {},
    },
    global = {
        settings  = {
            autoOpenAtAH     = true,
            autoOpenAtBank   = true,
            autoRestock      = false,     -- Express-Restock at AH: opt-in, it starts a buying flow
            autoRestockBank  = false,     -- Express-Restock at Bank: opt-in
            lastPriceTTL     = 24 * 3600, -- Last Seen dims after 24h
        },
    },
}

-- ---------------------------------------------------------------------------
-- Init (Core.lua, ADDON_LOADED). Missing keys are filled from defaults,
-- recursively, so new settings reach existing users.
-- ---------------------------------------------------------------------------
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

function DB:Initialize()
    -- StockClerkDB (account-wide) keeps settings + log under `.global`,
    -- the layout AceDB used before v1.1.2, so existing data loads as-is.
    StockClerkDB = StockClerkDB or {}
    StockClerkDB.global = ApplyDefaults(StockClerkDB.global or {}, self.defaults.global)
    self.global = StockClerkDB.global
    StockClerkCharDB = ApplyDefaults(StockClerkCharDB or {}, self.defaults.char)
    self.char = StockClerkCharDB

    -- Saves from before list ordering: stamp the current alphabetical order.
    local needsOrder = false
    for _, entry in pairs(self.char.items) do
        if entry.sortOrder == nil then needsOrder = true; break end
    end
    if needsOrder then
        local alpha = {}
        for itemID in pairs(self.char.items) do alpha[#alpha + 1] = itemID end
        table.sort(alpha, function(a, b)
            local na = C_Item.GetItemInfo(a) or ("item:" .. a)
            local nb = C_Item.GetItemInfo(b) or ("item:" .. b)
            if na == nb then return a < b end
            return na < nb
        end)
        for i, itemID in ipairs(alpha) do
            self.char.items[itemID].sortOrder = i * 10
        end
    end

    -- Ledger hygiene: number keys (a hand-edit can leave strings), and drop
    -- entries older than 30 days (the mail has expired).
    self.char.pendingBuys = self.char.pendingBuys or {}
    local now      = GetServerTime and GetServerTime() or time()
    local expiry   = now - (30 * 86400)
    local normal   = {}
    for k, v in pairs(self.char.pendingBuys) do
        local id = tonumber(k)
        if id and type(v) == "table" and v.qty and v.qty > 0
           and v.boughtAt and v.boughtAt >= expiry then
            normal[id] = { qty = v.qty, baseHave = v.baseHave or 0, boughtAt = v.boughtAt }
        end
    end
    self.char.pendingBuys = normal

    self.char.ui = self.char.ui or { stuckOnly = false }
    if self.char.ui.stuckOnly == nil then self.char.ui.stuckOnly = false end
end

-- "Short items only" filter, per character (stored as char.ui.stuckOnly).
function DB:GetStuckOnly()
    if not self.char or not self.char.ui then return false end
    return self.char.ui.stuckOnly == true
end

function DB:SetStuckOnly(on)
    if not self.char then return end
    self.char.ui = self.char.ui or { stuckOnly = false }
    self.char.ui.stuckOnly = on and true or false
end

-- Returns the raw items table; callers should NOT mutate keys/values directly.
function DB:GetItems()
    return self.char.items
end

-- The list in the player's order (sortOrder). Restock order and priority
-- follow it. Items without sortOrder sort last, by name.
function DB:GetSortedItems()
    local list = {}
    for itemID, entry in pairs(self.char.items) do
        local name = C_Item.GetItemInfo(itemID) or ("item:" .. itemID)
        list[#list + 1] = {
            itemID      = itemID,
            need        = entry.need,
            name        = name,
            maxPrice    = entry.maxPrice,    -- copper, may be nil ("no cap set")
            lastPrice   = entry.lastPrice,   -- { copper, seenAt, source } or nil
            sortOrder   = entry.sortOrder,
        }
    end
    table.sort(list, function(a, b)
        local sa, sb = a.sortOrder, b.sortOrder
        if sa and sb then
            if sa ~= sb then return sa < sb end
        elseif sa or sb then
            return sa ~= nil -- ordered items before unordered
        end
        if a.name == b.name then return a.itemID < b.itemID end
        return a.name < b.name
    end)
    return list
end

-- Rewrite list order wholesale: orderedIDs is the full new sequence.
-- Restamps sortOrder as 10,20,30,... so future inserts have gaps.
function DB:ReorderItems(orderedIDs)
    -- Never trust a partial/garbage sequence from the UI: only apply if
    -- the set of IDs matches the set of tracked itemIDs exactly.
    local seen = {}
    for _, id in ipairs(orderedIDs) do seen[id] = true end
    for id in pairs(self.char.items) do
        if not seen[id] then return false end
    end
    for i, id in ipairs(orderedIDs) do
        local entry = self.char.items[id]
        if entry then entry.sortOrder = i * 10 end
    end
    return true
end

-- Create-or-update an item entry. `maxPrice` is copper or nil.
function DB:SetItem(itemID, need, maxPrice)
    if not itemID or need == nil then return end
    itemID = tonumber(itemID)
    need   = tonumber(need)
    if not itemID or not need or need < 0 then return end
    if need == 0 then
        self.char.items[itemID] = nil
    else
        local existing = self.char.items[itemID]
        if existing then
            existing.need = need
            if maxPrice ~= nil then existing.maxPrice = maxPrice end
        else
            -- New items go last: the order is the player's priority.
            local maxOrder = 0
            for _, entry in pairs(self.char.items) do
                if entry.sortOrder and entry.sortOrder > maxOrder then
                    maxOrder = entry.sortOrder
                end
            end
            self.char.items[itemID] = {
                need        = need,
                maxPrice    = maxPrice, -- copper; nil means "unlimited" / not set
                addedAt     = time(),
                sortOrder   = maxOrder + 10,
            }
        end
    end
end

-- "Add common consumables": adds every Data/Consumables.lua item that isn't
-- tracked yet, with target 1. Tracked items are never touched. Returns the
-- number added.
function DB:AddCommonConsumables()
    local added = 0
    for _, itemID in ipairs(ADDON.CommonConsumables or {}) do
        if not self.char.items[itemID] then
            self:SetItem(itemID, 1)
            added = added + 1
        end
    end
    return added
end

-- Set (or clear, with nil) the cap of a tracked item.
function DB:SetItemMaxPrice(itemID, maxPriceCopper)
    local entry = self.char.items[tonumber(itemID)]
    if entry then entry.maxPrice = maxPriceCopper end
end

-- Remember the last AH unit price (source "click" or "loop"). No-op for
-- untracked items (a late search callback after removal).
function DB:StampLastPrice(itemID, copperPerUnit, source)
    itemID = tonumber(itemID)
    if not itemID or not copperPerUnit or copperPerUnit <= 0 then return end
    local entry = self.char.items[itemID]
    if not entry then return end
    entry.lastPrice = {
        copper = copperPerUnit,
        seenAt = time(),
        source = source or "unknown",
    }
end

function DB:RemoveItem(itemID)
    itemID = tonumber(itemID)
    if itemID then
        self.char.items[itemID] = nil
    end
end

function DB:ClearAll()
    wipe(self.char.items)
end

function DB:Settings()
    return self.global.settings
end
