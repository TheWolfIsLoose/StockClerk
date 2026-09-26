--[[
    Stock Clerk - DB.lua
    Owns the SavedVariables schema and provides read/write helpers
    for the per-character consumable list.

    Schema:
      char.items = {
        [itemID:number] = {
          need        = number,
          maxPrice    = copper,          -- optional; nil = no cap set
          priceSource = string,          -- optional; PT-1 v0.5. Records
                                         -- How the current maxPrice was
                                         -- chosen: "user" (manually typed),
                                         -- "vendor" (reserved). Purely
                                         -- metadata; nothing reads it.
                                         -- Nil is treated as "user".
          addedAt     = timestamp,
          lastPrice   = { copper, seenAt, source },   -- optional; QA-11
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
        lastPriceTTL     = number,     -- QA-11 seconds before "Last Seen" dims
      }
      global.log      = array of entries (see Log.lua)

    We keep the on-disk shape stable across versions; any new field lives
    inside `defaults` so Initialize fills it in on load without a migration.
--]]

local addonName = ...
local ADDON     = _G[addonName] or {}
_G[addonName]   = ADDON

-- Debug print, gated on `/clerk debug`. Shows as [SC:<tag>].
function ADDON.Debug(tag, ...)
    if not ADDON.debug then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    print("|cff98FF98[SC:" .. tag .. "]|r " .. table.concat(parts, " "))
end

local DB = {}
ADDON.DB = DB

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------
DB.defaults = {
    char = {
        items = {},
        uiPos = { point = "CENTER", x = 0, y = 0 },
        -- AutoSpend deleted. Was the
        -- daily budget tracker. No budget = no tracker.
        -- Per-character UI state. Filter toggle for the
        -- shopping-list view. `stuckOnly = true` means the list shows
        -- only items you're short on (bags below target). Per-
        -- character because different characters carry different lists
        -- and different market pressures, so persisting the filter
        -- globally would be surprising.
        ui = { stuckOnly = false },

        -- Mail-delivery ledger. Persisted per-character because
        -- auction mail is delivered to the buying character, not the
        -- warband. Keys are itemID (as number, keyed by lua so beware
        -- SavedVariables stringifies these on write -- see the load
        -- migration in Initialize). Entries look like:
        --   { qty = N, baseHave = M, boughtAt = serverTimeSeconds }
        -- The ledger empties when either (a) the bag count catches up
        -- to baseHave + qty in Loop:_EffectiveHave, or (b) an inbox
        -- reconciliation observes that the mail no longer holds those
        -- items. Gate on Loop:Start refuses auto passes while non-empty.
        pendingBuys = {},
    },
    global = {
        settings  = {
            autoOpenAtAH     = true,      -- open SC docked to the AH on visit.
            autoOpenAtBank   = true,      -- same at a banker (v1.2).
                                          -- Design ended up here: users who
                                          -- track a shopping list generally
                                          -- WANT it up when they're at the AH.
            autoRestock      = false,     -- opt-in. When ON + AH open + at
                                          -- Least one row is short, the
                                          -- restock loop auto-starts. Off by
                                          -- default because it commits the
                                          -- user to a purchase flow they
                                          -- didn't explicitly ask for.
            lastPriceTTL     = 24 * 3600, -- QA-11; 24h before Last Seen dims
        },
    },
}

-- ---------------------------------------------------------------------------
-- Init (called from Core.lua on OnInitialize)
-- ---------------------------------------------------------------------------
-- Fill missing keys from defaults, recursing into tables the saved data
-- already has so new settings appear for existing users.
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

    -- SortOrder migration: pre-priority users have no sortOrder on
    -- any item. Stamp everyone in the current alphabetical readout so the
    -- upgrade never visibly reshuffles an existing list.
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

    -- pendingBuys hygiene. Two responsibilities:
    --   1. Normalize keys back to numbers. SavedVariables preserves
    --      the lua type of table keys inside a table serialized as-is,
    --      but a defaults-migration path or a hand-edit can leave
    --      stringified keys around. We accept both and normalize to
    --      number so downstream code (GetInboxItem returns numeric
    --      itemIDs) doesn't miss matches.
    --   2. Garbage-collect entries older than 30 days. Auction house
    --      mail expires server-side at 30 days; a ledger entry with
    --      boughtAt older than that is guaranteed stale (the mail is
    --      gone whether we reconciled or not).
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

    -- UI defaults hygiene: old saves predate `ui`, so backfill it
    -- without disturbing anything else on disk. This is the same shape
    -- the defaults table declares; keep them in sync if a new UI flag
    -- is added later.
    self.char.ui = self.char.ui or { stuckOnly = false }
    if self.char.ui.stuckOnly == nil then self.char.ui.stuckOnly = false end
end

-- ---------------------------------------------------------------------------
-- Shopping-list "short items only" filter toggle (named stuckOnly for
-- saved-data compatibility; it meant "stuck above cap" before v1.2)
--
-- Persisted per-character on char.ui.stuckOnly. Getter/setter live here
-- so MainFrame doesn't touch the raw table shape.
-- ---------------------------------------------------------------------------
function DB:GetStuckOnly()
    if not self.char or not self.char.ui then return false end
    return self.char.ui.stuckOnly == true
end

function DB:SetStuckOnly(on)
    if not self.char then return end
    self.char.ui = self.char.ui or { stuckOnly = false }
    self.char.ui.stuckOnly = on and true or false
end

-- ---------------------------------------------------------------------------
-- List CRUD (operates on the current character's list)
-- ---------------------------------------------------------------------------

-- Returns the raw items table; callers should NOT mutate keys/values directly.
function DB:GetItems()
    return self.char.items
end

-- Returns an array copy in USER-ARRANGED order (sortOrder ascending).
-- This is the ordering contract of the whole addon: the shopping list,
-- the restock loop's queue order, and implicit buy priority all read
-- the same sequence ("tacit priority" -- the list IS the priority).
-- Items lacking sortOrder (shouldn't happen post-migration, but SetItem
-- races during seed) sort to the end by name.
function DB:GetSortedItems()
    local list = {}
    for itemID, entry in pairs(self.char.items) do
        local name = C_Item.GetItemInfo(itemID) or ("item:" .. itemID)
        list[#list + 1] = {
            itemID      = itemID,
            need        = entry.need,
            name        = name,
            maxPrice    = entry.maxPrice,    -- copper, may be nil ("no cap set")
            priceSource = entry.priceSource, -- "user"/"vendor" or nil
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

-- Create-or-update an item entry. `maxPrice` is copper or nil. `source`
-- (priceSource) defaults to "user" when a maxPrice is provided;
-- callers from a vendor path should pass their tag explicitly.
function DB:SetItem(itemID, need, maxPrice, source)
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
            if maxPrice ~= nil then
                existing.maxPrice    = maxPrice
                existing.priceSource = source or "user"
            end
        else
            -- New items go to the END of the user's arranged list: the
            -- list is priority order, so silently inserting a newcomer
            -- anywhere else would imply a priority the user never chose.
            local maxOrder = 0
            for _, entry in pairs(self.char.items) do
                if entry.sortOrder and entry.sortOrder > maxOrder then
                    maxOrder = entry.sortOrder
                end
            end
            self.char.items[itemID] = {
                need        = need,
                maxPrice    = maxPrice, -- copper; nil means "unlimited" / not set
                priceSource = maxPrice and (source or "user") or nil,
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

-- Update just the maxPrice for an existing item; no-op if the item isn't
-- tracked. Pass nil to clear the cap. `source` is the priceSource
-- tag ("user" / "vendor"); defaults to "user" when omitted
-- because every UI-driven call site is a user edit. Passing nil for
-- maxPriceCopper clears the source tag too -- an unset cap has no source.
function DB:SetItemMaxPrice(itemID, maxPriceCopper, source)
    itemID = tonumber(itemID)
    if not itemID then return end
    local entry = self.char.items[itemID]
    if not entry then return end
    entry.maxPrice = maxPriceCopper
    if maxPriceCopper == nil then
        entry.priceSource = nil
    else
        entry.priceSource = source or "user"
    end
end

-- Stamp the most-recent observed unit price for an item. Sources:
--   "click"  - piggybacked on a left-click AH search from the row list
--   "loop"   - piggybacked on the restock loop's per-item search
--   "manual" - user-initiated re-price (reserved for future)
-- Silently no-ops if the item isn't currently tracked (a stale search
-- callback firing after remove shouldn't create a phantom entry).
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

-- ---------------------------------------------------------------------------
-- Settings passthrough
-- ---------------------------------------------------------------------------
function DB:Settings()
    return self.global.settings
end
