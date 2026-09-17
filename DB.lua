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
                                         -- how the current maxPrice was
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
                                         -- doubles as restock priority
        }
      }
      char.uiPos = { point, x, y }           -- last MainFrame position
      char.autoSpend = {
          copper  = 0,        -- auto-purchase spend since last daily reset
          resetAt = unixtime, -- when the current budget day ends (realm
                              -- daily reset via C_DateAndTime), not midnight
      }
      global.templates = { [name] = { [itemID] = need, ... } }
      global.settings  = {
        autoOpenAtAH     = bool,
        autoPurchase     = bool,      -- QA-10 opt-in auto-purchase master switch
        autoBudgetGold   = number|nil, -- daily auto-buy budget (gold); manual
                                       -- buys are never budget-gated
        lastPriceTTL     = number,     -- QA-11 seconds before "Last Seen" dims
        defaultMaxCopper = number|nil, -- PT-1 v0.5 Batch 2 (global default cap).
                                       -- When set, auto-mode treats items
                                       -- without their own maxPrice as
                                       -- having this cap. Nil = no default,
                                       -- and uncapped items are still
                                       -- skipped by auto (v0.4 contract).
                                       -- Never applied to manual mode --
                                       -- manual is full user discretion.
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
        -- Daily (realm-reset-aligned) auto-buy spend tracker. resetAt is
        -- established lazily because C_DateAndTime isn't guaranteed at
        -- PLAYER_LOGIN for every client build.
        autoSpend = { copper = 0, resetAt = nil },
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
            autoOpenAtAH     = true,
            debugSeeded      = false,     -- so /clerk seed only runs once by default
            autoPurchase     = false,     -- QA-10; user must opt in explicitly
            autoBudgetGold   = nil,       -- QA-10a; required to be set before auto runs
            lastPriceTTL     = 24 * 3600, -- QA-11; 24h before Last Seen dims
            defaultMaxCopper = nil,       -- PT-1 v0.5 Batch 2; nil preserves
                                          -- the v0.4 "uncapped => auto skip" contract
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

    -- sortOrder migration (v0.4): pre-priority users have no sortOrder on
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

-- PT-1: parse a user-entered price string into copper.
-- Accepts (in order of specificity):
--   "12g50s"       -> 12*10000 + 50*100      copper
--   "12g"          -> 12*10000               copper
--   "50s"          -> 50*100                 copper
--   "5c"           -> 5                      copper
--   "12g 50s 5c"   -> 12*10000 + 50*100 + 5  copper (whitespace tolerated)
--   "12.5g"        -> 12*10000 + 5000        copper (fractional gold)
--   "12"           -> 12*10000               copper (bare number = gold
--                                             for backward compatibility
--                                             with the pre-v0.5 editor)
--   ""             -> nil                    (blank = clear cap)
--   invalid text   -> nil                    (caller decides what to do)
-- Returns (copper, ok). `ok` is false on parse failure so callers can
-- distinguish "cleared" (nil, true) from "bad input" (nil, false).
function DB.ParsePriceString(str)
    if type(str) ~= "string" then return nil, false end
    local trimmed = str:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return nil, true end
    local lower = trimmed:lower()

    -- Any g/s/c suffix present? If so, use the token parser.
    if lower:find("[gsc]") then
        local copper = 0
        local seenAny = false
        -- Match all (number, unit) pairs. Number may be integer or decimal.
        for numStr, unit in lower:gmatch("([%d%.]+)%s*([gsc])") do
            local n = tonumber(numStr)
            if not n or n < 0 then return nil, false end
            if unit == "g" then
                copper = copper + math.floor(n * 10000 + 0.5)
            elseif unit == "s" then
                copper = copper + math.floor(n * 100 + 0.5)
            else -- "c"
                copper = copper + math.floor(n + 0.5)
            end
            seenAny = true
        end
        if not seenAny then return nil, false end
        -- Any leftover non-token junk = bad input. Rebuild the parsed
        -- string and compare to the sanitized original to detect it.
        local sanitized = lower:gsub("%s+", "")
        local consumed = ""
        for numStr, unit in lower:gmatch("([%d%.]+)%s*([gsc])") do
            consumed = consumed .. numStr .. unit
        end
        if sanitized ~= consumed then return nil, false end
        return copper, true
    end

    -- No suffix: bare number, interpret as GOLD for backward compat with
    -- pre-v0.5 UIs that only ever accepted whole gold.
    local n = tonumber(trimmed)
    if not n or n < 0 then return nil, false end
    return math.floor(n * 10000 + 0.5), true
end

-- PT-1: format copper as a short g/s/c string. Skips zero components and
-- collapses so 12g0s0c prints as "12g", 0g50s0c as "50s", etc. Returns
-- "0c" for exactly zero copper. Nil in returns nil out ("no cap").
function DB.FormatCopperShort(copper)
    if copper == nil then return nil end
    copper = math.floor(copper + 0.5)
    if copper <= 0 then return "0c" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
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

-- ---------------------------------------------------------------------------
-- Daily auto-buy budget (realm-reset aligned)
--
-- The budget day ends at the REALM daily reset, not local midnight:
-- C_DateAndTime.GetSecondsUntilDailyReset() returns seconds until the
-- player's own realm reset (retail API since Shadowlands), so NA gets
-- 7am Pacific, EU gets their morning reset, etc., with zero hardcoding.
-- If the API is ever unavailable we degrade to "24h from first spend"
-- rather than losing the budget feature outright.
--
-- Semantics (user decision, 2026-09-17): the budget tracks and gates
-- AUTO-BUYS ONLY. Manual buys are full user discretion -- they neither
-- count toward the daily total nor are blocked by it. Budgets exist
-- as guardrails against the autopilot inadvertently spending a pile
-- of gold; a human-confirmed click needs no such guardrail.
--
-- Corollary: the daily readout reads "auto spend today", NOT "total
-- gold out the door". Deliberate split, not an accounting bug.
-- ---------------------------------------------------------------------------

-- Internal: unix timestamp of the next daily reset.
local function NextResetTime()
    local now = GetServerTime()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        local secs = C_DateAndTime.GetSecondsUntilDailyReset()
        if secs and secs > 0 then
            return now + secs
        end
    end
    -- Degraded path: 24h rolling window from now. Used only when the
    -- realm-reset API is missing (unexpected client/API change).
    return now + 86400
end

-- Normalize the persisted bucket: zero it out when the reset has passed.
local function EnsureFreshBucket(spend)
    if spend.resetAt == nil then
        spend.resetAt = NextResetTime()
    end
    if GetServerTime() >= spend.resetAt then
        spend.copper  = 0
        spend.resetAt = NextResetTime()
    end
    return spend
end

-- Auto-buy spend so far today, in copper, reset-aware. Manual buys
-- are excluded by design (see semantics above).
function DB:GetDailyAutoSpend()
    if not self.char then return 0 end
    return EnsureFreshBucket(self.char.autoSpend).copper
end

-- Remaining daily AUTO-BUY budget in copper (settings.autoBudgetGold
-- is gold). Returns nil when no budget is configured (unlimited).
function DB:GetDailyAutoBudgetLeft()
    local s = self:Settings()
    if not s.autoBudgetGold or s.autoBudgetGold <= 0 then return nil end
    local left = math.floor(s.autoBudgetGold * 10000) - self:GetDailyAutoSpend()
    return math.max(0, left)
end

-- Record a successful AUTO purchase against today's budget. Callers:
-- the loop's auto confirm path ONLY -- manual buys must never touch
-- this (user decision: manual spend is outside the budget ledger).
function DB:AddDailyAutoSpend(copper)
    if not self.char then return end
    copper = tonumber(copper) or 0
    if copper <= 0 then return end
    local spend = EnsureFreshBucket(self.char.autoSpend)
    spend.copper = spend.copper + copper
end

-- Seconds until the current budget day ends; for UI readout.
function DB:GetDailyResetAt()
    if not self.char then return nil end
    return EnsureFreshBucket(self.char.autoSpend).resetAt
end
