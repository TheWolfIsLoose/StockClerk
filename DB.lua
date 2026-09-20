--[[
    Stock Clerk - DB.lua
    Owns the AceDB-3.0 database schema and provides read/write helpers
    for the per-character consumable list.

    Schema:
      char.items = {
        [itemID:number] = {
          need        = number,
          maxPrice    = copper,          -- optional; nil = no cap set
          priceSource = string,          -- optional; PT-1 v0.5. Records
                                         -- How the current maxPrice was
                                         -- chosen: "user" (manually typed),
                                         -- "vendor" (reserved -- vendor
                                         -- price plumbing lands in Wave 2),
                                         -- "template" (came in via a saved
                                         -- template import). Purely metadata
                                         -- today; no runtime behavior reads
                                         -- it. Nil is treated as "user".
          addedAt     = timestamp,
          lastPrice   = { copper, seenAt, source },   -- optional; QA-11
          sortOrder   = number,          -- user-arranged list position;
                                         -- Doubles as restock priority
        }
      }
      char.uiPos = { point, x, y }           -- last MainFrame position
      char.autoSpend = {
          copper  = 0,        -- auto-purchase spend since last daily reset
          resetAt = unixtime, -- when the current budget day ends (realm
                              -- Daily reset via C_DateAndTime), not midnight
      }
      global.templates = { [name] = { [itemID] = need, ... } }
      global.settings  = {
        autoOpenAtAH     = bool,       -- default TRUE. Pops SC on AH visit.
        autoRestock      = bool,       -- default FALSE. If TRUE, opening the
                                       -- AH also fires the restock loop when
                                       -- there's a shortfall to work through.
        lastPriceTTL     = number,     -- QA-11 seconds before "Last Seen" dims
      }
      -- AutoPurchase / autoBudgetGold /
      -- defaultMaxCopper deleted. WoW's C_AuctionHouse commodity API
      -- requires a hardware event per transaction, so silent auto-buy
      -- is impossible. Restock is user-driven: one keystroke = one
      -- purchase. Budget guardrail deleted with it -- users are
      -- adults, SC is a tool not a nanny. defaultMaxCopper deleted
      -- because per-row cap is now the only way to skip: no cap =
      -- buy at any price (with a one-shot per-AH-session soft
      -- warning). No global cap fallback.
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
        -- AutoSpend deleted. Was the
        -- daily budget tracker. No budget = no tracker.
        -- (PT-3): per-character UI state. Filter toggle for the
        -- shopping-list view. `stuckOnly = true` means the list hides
        -- every row except items whose most recent observed unit price
        -- exceeds their price cap (i.e. "currently priced out"). Per-
        -- character because different characters carry different lists
        -- and different market pressures, so persisting the filter
        -- globally would be surprising.
        ui = { stuckOnly = false },

        -- Mail-delivery ledger (PT-4). Persisted per-character because
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
        templates = {},
        settings  = {
            autoOpenAtAH     = true,      -- open SC docked to the AH on visit.
                                          -- Design ended up here: users who
                                          -- track a shopping list generally
                                          -- WANT it up when they're at the AH.
            autoRestock      = false,     -- opt-in. When ON + AH open + at
                                          -- Least one row is short, the
                                          -- restock loop auto-starts. Off by
                                          -- default because it commits the
                                          -- user to a purchase flow they
                                          -- didn't explicitly ask for.
            debugSeeded      = false,     -- so /clerk seed only runs once by default
            lastPriceTTL     = 24 * 3600, -- QA-11; 24h before Last Seen dims
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
            -- Shallow copy is fine — nested tables are simple
            if type(v) == "table" then
                _G.StockClerkCharDB[k] = CopyTable(v)
            else
                _G.StockClerkCharDB[k] = v
            end
        end
    end
    self.char = _G.StockClerkCharDB

    -- SortOrder migration (v0.4): pre-priority users have no sortOrder on
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

    -- PT-4: pendingBuys hygiene. Two responsibilities:
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
-- v0.6: shopping-list "stuck above cap" filter toggle (PT-3)
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
            priceSource = entry.priceSource, -- "user"/"vendor"/"template" or nil
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

-- Nudge one item up (delta=-1) or down (delta=+1) a single position.
-- Returns true when the item actually moved.
function DB:MoveItem(itemID, delta)
    local list = self:GetSortedItems()
    local idx
    for i, it in ipairs(list) do
        if it.itemID == itemID then idx = i; break end
    end
    if not idx then return false end
    local target = idx + delta
    if target < 1 or target > #list then return false end
    local ids = {}
    for i, it in ipairs(list) do ids[i] = it.itemID end
    ids[idx], ids[target] = ids[target], ids[idx]
    self:ReorderItems(ids)
    return true
end

-- Create-or-update an item entry. `maxPrice` is copper or nil. `source`
-- (PT-1 priceSource) defaults to "user" when a maxPrice is provided;
-- callers that import from a template or vendor path should pass their
-- tag explicitly.
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

-- Update just the maxPrice for an existing item; no-op if the item isn't
-- tracked. Pass nil to clear the cap. `source` is the PT-1 priceSource
-- tag ("user" / "vendor" / "template"); defaults to "user" when omitted
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
    -- Mode: "merge" (default, keeps existing) or "replace"
    local t = self.db.global.templates[name]
    if not t then return 0 end
    if mode == "replace" then wipe(self.char.items) end
    local count = 0
    for itemID, need in pairs(t) do
        -- Merge: only set if not present; keep user-modified needs
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

-- The entire daily-budget subsystem is
-- gone. NextResetTime / EnsureFreshBucket / GetDailyAutoSpend /
-- GetDailyAutoBudgetLeft / AddDailyAutoSpend / GetDailyResetAt all
-- deleted along with settings.autoBudgetGold and char.autoSpend.
-- Rationale: WoW's commodity API requires a hardware event per
-- transaction, so silent budget-gated auto-buys are impossible.
-- Restock is user-driven now; there is nothing to gate.
