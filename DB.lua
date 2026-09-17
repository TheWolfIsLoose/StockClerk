--[[
    Stock Clerk - DB.lua
    Owns the AceDB-3.0 database schema and provides read/write helpers
    for the per-character consumable list.

    Schema:
      char.items = {
        [itemID:number] = {
          need      = number,
          maxPrice  = copper,          -- optional; nil = no cap set
          addedAt   = timestamp,
          lastPrice = { copper, seenAt, source },   -- optional; QA-11
        }
      }
      char.uiPos = { point, x, y }           -- last MainFrame position
      global.templates = { [name] = { [itemID] = need, ... } }
      global.settings  = {
        autoOpenAtAH   = bool,
        autoPurchase   = bool,      -- QA-10 opt-in auto-purchase master switch
        autoBudgetGold = number|nil, -- QA-10a per-loop budget cap (gold)
        lastPriceTTL   = number,     -- QA-11 seconds before "Last Seen" dims
      }
      global.log      = array of entries (see Log.lua)

    We keep the on-disk shape stable across versions; any new field lives
    inside `defaults` so AceDB fills it in on load without a migration.
--]]

local addonName = ...
local ADDON     = _G[addonName] or {}
_G[addonName]   = ADDON

local DB = {}
ADDON.DB = DB

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------
DB.defaults = {
    char = {
        items = {},
        uiPos = { point = "CENTER", x = 0, y = 0 },
    },
    global = {
        templates = {},
        settings  = {
            autoOpenAtAH   = true,
            debugSeeded    = false,     -- so /clerk seed only runs once by default
            autoPurchase   = false,     -- QA-10; user must opt in explicitly
            autoBudgetGold = nil,       -- QA-10a; required to be set before auto runs
            lastPriceTTL   = 24 * 3600, -- QA-11; 24h before Last Seen dims
        },
    },
}

-- ---------------------------------------------------------------------------
-- Init (called from Core.lua on OnInitialize)
-- ---------------------------------------------------------------------------
function DB:Initialize()
    -- AceDB-3.0 wraps the two SavedVariables tables declared in the TOC.
    -- It handles per-character scoping automatically via the `char` profile.
    self.db = LibStub("AceDB-3.0"):New("StockClerkDB", self.defaults, true)

    -- AceDB only manages the "global" SV; the PerCharacter SV needs manual
    -- initialization. We mirror the char defaults into StockClerkCharDB.
    _G.StockClerkCharDB = _G.StockClerkCharDB or {}
    for k, v in pairs(self.defaults.char) do
        if _G.StockClerkCharDB[k] == nil then
            -- shallow copy is fine — nested tables are simple
            if type(v) == "table" then
                _G.StockClerkCharDB[k] = CopyTable(v)
            else
                _G.StockClerkCharDB[k] = v
            end
        end
    end
    self.char = _G.StockClerkCharDB
end

-- ---------------------------------------------------------------------------
-- List CRUD (operates on the current character's list)
-- ---------------------------------------------------------------------------

-- Returns the raw items table; callers should NOT mutate keys/values directly.
function DB:GetItems()
    return self.char.items
end

-- Returns a numerically sorted array copy suitable for iterating in UI order.
-- Sort: alphabetical by (cached) item name if available, else by itemID.
function DB:GetSortedItems()
    local list = {}
    for itemID, entry in pairs(self.char.items) do
        local name = C_Item.GetItemInfo(itemID) or ("item:" .. itemID)
        list[#list + 1] = {
            itemID    = itemID,
            need      = entry.need,
            name      = name,
            maxPrice  = entry.maxPrice,  -- copper, may be nil ("no cap set")
            lastPrice = entry.lastPrice, -- { copper, seenAt, source } or nil
        }
    end
    table.sort(list, function(a, b)
        if a.name == b.name then return a.itemID < b.itemID end
        return a.name < b.name
    end)
    return list
end

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
            self.char.items[itemID] = {
                need     = need,
                maxPrice = maxPrice, -- copper; nil means "unlimited" / not set
                addedAt  = time(),
            }
        end
    end
end

-- Update just the maxPrice for an existing item; no-op if the item isn't
-- tracked. Pass nil to clear the cap.
function DB:SetItemMaxPrice(itemID, maxPriceCopper)
    itemID = tonumber(itemID)
    if not itemID then return end
    local entry = self.char.items[itemID]
    if not entry then return end
    entry.maxPrice = maxPriceCopper
end

-- QA-11: stamp the most-recent observed unit price for an item. Sources:
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
-- Templates (account-wide named lists we can apply to any character)
-- ---------------------------------------------------------------------------
function DB:ApplyTemplate(name, mode)
    -- mode: "merge" (default, keeps existing) or "replace"
    local t = self.db.global.templates[name]
    if not t then return 0 end
    if mode == "replace" then wipe(self.char.items) end
    local count = 0
    for itemID, need in pairs(t) do
        -- merge: only set if not present; keep user-modified needs
        if mode == "replace" or self.char.items[itemID] == nil then
            self:SetItem(itemID, need)
            count = count + 1
        end
    end
    return count
end

function DB:SaveTemplate(name)
    local t = {}
    for itemID, entry in pairs(self.char.items) do
        t[itemID] = entry.need
    end
    self.db.global.templates[name] = t
end

-- ---------------------------------------------------------------------------
-- Settings passthrough
-- ---------------------------------------------------------------------------
function DB:Settings()
    return self.db.global.settings
end
