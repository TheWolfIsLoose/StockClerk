--[[
    Stock Clerk - Log.lua
    Account-wide activity log for user-visible auditing.

    Ring buffer of ~500 entries persisted in StockClerkDB.global.log.
    Every entry carries a timestamp, a kind, and a kind-specific payload
    table. The log is intended for two things:

      1) Human review in the LogPopup window (see UI/LogPopup.lua).
      2) Debug reproduction of "wait, what did the addon just do?"
         moments after an auto-purchase.

    Entry shape:
      { ts       = unix_seconds,
        kind     = "add" | "remove" | "target_change" | "cap_change"
                  | "ah_search" | "buy_attempt" | "buy_success"
                  | "buy_fail" | "buy_skip"
                  | "loop_start" | "loop_stop"
                  | "auto_toggle" | "auto_refuse",
        itemID   = optional itemID this entry pertains to,
        char     = character name at time of log entry,
        realm    = realm name at time of log entry,
        payload  = { ... free-form, per-kind ... } }

    We keep the char/realm on every entry so an account-wide sidecar
    can attribute events to the alt that made them without needing a
    per-character shard of the log.

    ============================================================
    ADD A NEW KIND
    ============================================================
    1) Add its name to VALID_KINDS below (keeps typos out).
    2) Pick payload fields; keep them small and JSON-y (numbers,
       strings, booleans). Nested tables are fine but the log window
       renders them shallow, so keep it flat where possible.
    3) Add a formatter case in UI/LogPopup.lua's formatter.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local Log = {}
ADDON.Log = Log

-- Hard cap on entries retained. Old entries are evicted FIFO once the
-- buffer is full. 500 is roughly a month of moderately active play
-- (~15 auto-restock loops of ~30 events each).
Log.MAX_ENTRIES = 500

-- Every kind the addon can emit. Emit() rejects unknown kinds outright
-- so a typo in a callsite becomes an immediate error rather than a
-- silently un-filterable entry in the sidecar.
local VALID_KINDS = {
    add            = true,   -- payload: { need, cap? }
    remove         = true,   -- payload: {} (name is in itemID cache)
    target_change  = true,   -- payload: { from, to }
    cap_change     = true,   -- payload: { fromCopper, toCopper }  (nil = unset)
    ah_search      = true,   -- payload: { unitPriceCopper, listings }  (unit = cheapest)
    buy_attempt    = true,   -- payload: { qty, plannedSpendCopper, worstUnitCopper }
    buy_success    = true,   -- payload: { qty, spentCopper }
    buy_fail       = true,   -- payload: { reason }
    buy_skip       = true,   -- payload: { reason }   -- "no cap" / "already at target" / etc
    loop_start     = true,   -- payload: { queueSize, mode = "manual"|"auto", budgetCopper? }
    loop_stop      = true,   -- payload: { reason, spentCopper, touched, stillShort }
    auto_toggle    = true,   -- payload: { on }
    auto_refuse    = true,   -- payload: { reason, qty?, plannedSpendCopper? }
    -- "status" is a passthrough of MF:SetStatus's human-readable footer
    -- message so the sidecar mirrors the same feedback stream the footer
    -- shows. Payload is just { text = string } already coloured/formatted
    -- by the caller; the log renderer prints it verbatim.
    status         = true,   -- payload: { text }
    -- v0.6.1 keyboard-capture watchdog. Emitted by KeyboardWatchdog.lua
    -- when it detects a suspicious state (hidden focused editbox,
    -- long-lived propagate=false, EnableKeyboard(true) on a hidden
    -- frame). Gives the tester a smoking-gun line to share in
    -- `/clerk log` dumps if the input-capture bug recurs.
    kbd_stuck      = true,   -- payload: { reason, detail? }
}

-- ---------------------------------------------------------------------------
-- Internal: get / create the backing table on StockClerkDB.global.log.
-- ---------------------------------------------------------------------------
local function GetBuffer()
    -- DB.lua wires AceDB and exposes .db; global.log is created lazily on
    -- first write rather than seeded in defaults so we don't force a table
    -- allocation on install for users who never open the log.
    local g = ADDON.DB and ADDON.DB.db and ADDON.DB.db.global
    if not g then return nil end
    if not g.log then g.log = {} end
    return g.log
end

-- ---------------------------------------------------------------------------
-- Public: emit a log entry.
--
--   Log:Emit("buy_success", 212283, { qty = 20, spentCopper = 800000 })
--
-- itemID may be nil for entries that aren't item-scoped (loop_start,
-- auto_toggle, etc.). payload may be nil.
-- ---------------------------------------------------------------------------
function Log:Emit(kind, itemID, payload)
    if not VALID_KINDS[kind] then
        -- Loud enough for the developer, quiet enough to not spam users
        -- if a live install somehow sees this. Silently succeeding on an
        -- unknown kind would be worse.
        if ADDON.debug then
            print("|cffff8888[SC:Log]|r unknown kind: " .. tostring(kind))
        end
        return
    end
    local buf = GetBuffer()
    if not buf then return end

    buf[#buf + 1] = {
        ts      = time(),
        kind    = kind,
        itemID  = itemID,
        char    = UnitName("player"),
        realm   = GetRealmName(),
        payload = payload or {},
    }

    -- Evict oldest entries once we exceed the cap. table.remove(t, 1) is
    -- O(n) but n = 500 max and this fires only after a hard threshold, so
    -- the amortised cost is negligible.
    while #buf > self.MAX_ENTRIES do
        table.remove(buf, 1)
    end

    -- Live LogPopup refresh, if the popup is currently open. (v0.6
    -- LogFrame surface was retired in v0.8; LogPopup replaced it in v0.7.)
    if ADDON.LogPopup and ADDON.LogPopup.frame and ADDON.LogPopup.frame:IsShown()
            and ADDON.LogPopup.Refresh then
        ADDON.LogPopup:Refresh()
    end
end

-- ---------------------------------------------------------------------------
-- Public: read the log. Returns a REVERSED array (newest first) suitable
-- for straight-through display. Filter is an optional table:
--   { kinds = { "buy_success", "buy_fail", ... },  -- OR-set of kinds
--     itemID = 212283,                              -- exact-match filter
--     since  = unix_ts }                            -- >= this timestamp
-- ---------------------------------------------------------------------------
function Log:Query(filter)
    local buf = GetBuffer()
    if not buf then return {} end

    filter = filter or {}
    local kindSet = nil
    if filter.kinds then
        kindSet = {}
        for _, k in ipairs(filter.kinds) do kindSet[k] = true end
    end

    local out = {}
    for i = #buf, 1, -1 do
        local e = buf[i]
        local ok = true
        if kindSet  and not kindSet[e.kind]        then ok = false end
        if filter.itemID and e.itemID ~= filter.itemID then ok = false end
        if filter.since  and e.ts     <  filter.since  then ok = false end
        if ok then out[#out + 1] = e end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Public: aggregations for the sidecar header ("Spent Xg on N purchases").
-- Returns a single table so callers can pluck what they need without
-- iterating the log a second time.
-- ---------------------------------------------------------------------------
function Log:Aggregate(since)
    local buf = GetBuffer()
    local agg = {
        purchases     = 0,
        spentCopper   = 0,
        byItemSpent   = {},   -- [itemID] = copper
        byItemQty     = {},   -- [itemID] = units
    }
    if not buf then return agg end

    for i = 1, #buf do
        local e = buf[i]
        if not since or e.ts >= since then
            if e.kind == "buy_success" then
                agg.purchases   = agg.purchases + 1
                local spent = e.payload.spentCopper or 0
                local qty   = e.payload.qty         or 0
                agg.spentCopper = agg.spentCopper + spent
                if e.itemID then
                    agg.byItemSpent[e.itemID] = (agg.byItemSpent[e.itemID] or 0) + spent
                    agg.byItemQty[e.itemID]   = (agg.byItemQty[e.itemID]   or 0) + qty
                end
            end
        end
    end
    return agg
end

-- ---------------------------------------------------------------------------
-- Public: clear the log entirely. Only wired to a /clerk log clear command;
-- there is intentionally no UI button (deleting audit trail should require
-- the user to type the command).
-- ---------------------------------------------------------------------------
function Log:Clear()
    local buf = GetBuffer()
    if buf then wipe(buf) end
    if ADDON.LogPopup and ADDON.LogPopup.frame and ADDON.LogPopup.frame:IsShown()
            and ADDON.LogPopup.Refresh then
        ADDON.LogPopup:Refresh()
    end
end
