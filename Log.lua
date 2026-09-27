--[[
    Stock Clerk - Log.lua
    Account-wide activity log: what happened, in plain words, for players
    (side panel feed) and for support (/clerk log, copied into a report).

    Ring buffer of MAX_ENTRIES in StockClerkDB.global.log. Entry shape:
      { ts, kind, itemID?, char, realm, payload = { per-kind fields } }

    Every kind has a level:
      activity  what a player cares about; shown in the side panel feed
      detail    what support needs (AH searches, settings, updates...)
      trace     step-by-step internals, recorded only while /clerk debug
                is on (it resets on /reload)

    Add a kind: give it a LEVEL and a FORMAT entry below.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local Log = {}
ADDON.Log = Log

-- Trace step: recorded into the log only while /clerk debug is on.
function ADDON.Debug(tag, ...)
    if not ADDON.debug then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    Log:Emit("trace", nil, { tag = tag, text = table.concat(parts, " ") })
end

Log.MAX_ENTRIES = 1000

Log.LEVEL = {
    add = "activity", remove = "activity", target_change = "activity", cap_change = "activity",
    buy_success = "activity", buy_fail = "activity", buy_skip = "activity", auto_refuse = "activity",
    bank_pull = "activity", loop_stop = "activity", error = "activity",
    ah_search = "detail", buy_attempt = "detail", loop_start = "detail", status = "detail",
    bank_run = "detail", setting = "detail", version = "detail", auto_toggle = "detail",
    trace = "trace",
}

local function Buffer()
    local g = ADDON.DB.global
    g.log = g.log or {}
    return g.log
end

-- Log:Emit("buy_success", 212283, { qty = 20, spentCopper = 800000 })
function Log:Emit(kind, itemID, payload)
    if not self.LEVEL[kind] then
        if ADDON.debug then print("|cffff8888[SC:Log]|r unknown kind: " .. tostring(kind)) end
        return
    end
    local buf = Buffer()
    buf[#buf + 1] = {
        ts = time(), kind = kind, itemID = itemID,
        char = UnitName("player"), realm = GetRealmName(),
        payload = payload or {},
    }
    -- ponytail: table.remove(t, 1) shifts the whole buffer; fine at 1000 entries.
    while #buf > self.MAX_ENTRIES do table.remove(buf, 1) end
    if self.LEVEL[kind] == "activity" then ADDON.Sidecar:OnActivity() end
end

-- Newest-first copy of the buffer.
function Log:Query()
    local buf, out = Buffer(), {}
    for i = #buf, 1, -1 do out[#out + 1] = buf[i] end
    return out
end

function Log:Clear()
    wipe(Buffer())
end

-- ---------------------------------------------------------------------------
-- Formatting (one wording for the feed, the log window and reports)
-- ---------------------------------------------------------------------------

-- "4,255g" for 100g+, "12g 34s" below that (cheap items would read "0g").
local function Money(copper)
    copper = math.floor(copper or 0)
    local g, s = math.floor(copper / 10000), math.floor(copper / 100) % 100
    if g >= 100 then
        local txt = tostring(g):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        return txt .. "g"
    end
    if g > 0 then return s > 0 and ("%dg %ds"):format(g, s) or (g .. "g") end
    return s .. "s"
end
Log.Money = Money

local function Plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local SETTING_LABELS = {
    autoOpenAtAH = "Auto-open at Auction House", autoOpenAtBank = "Auto-open at Bank",
    autoRestock = "Express-Restock at Auction House", autoRestockBank = "Express-Restock at Bank",
}

local STOP_REASONS = {
    done = "Restock finished", user_stop = "Restock stopped by you", user_esc = "Restock stopped by you",
    ["AH closed"] = "Restock stopped: AH closed",
}

-- FORMAT[kind](p, item) -> sentence. `item` is the item's name (or id).
local FORMAT = {
    add           = function(p, item) return ("Added %s (target %s)"):format(item, p.need or "?") end,
    remove        = function(p, item) return ("Removed %s"):format(item) end,
    target_change = function(p, item) return ("%s: target %s to %s"):format(item, p.from or "?", p.to or "?") end,
    cap_change    = function(p, item)
        if not p.toCopper then return ("%s: cap removed"):format(item) end
        if not p.fromCopper then return ("%s: cap set to %s"):format(item, Money(p.toCopper)) end
        return ("%s: cap %s to %s"):format(item, Money(p.fromCopper), Money(p.toCopper))
    end,
    buy_success   = function(p, item) return ("Bought %s %s for %s"):format(p.qty or "?", item, Money(p.spentCopper)) end,
    buy_fail      = function(p, item) return ("Couldn't buy %s: %s"):format(item, Plain(p.reason or "unknown reason")) end,
    buy_skip      = function(p, item)
        if p.reason == "cap out (silent)" then return ("Skipped %s: cheapest price is above your cap"):format(item) end
        if p.reason == "user skipped" then return ("Skipped %s (you chose Skip)"):format(item) end
        return ("Skipped %s: %s"):format(item, Plain(p.reason or "?"))
    end,
    auto_refuse   = function(p) return "Express-Restock didn't start: " .. Plain(p.reason or "?") end,
    bank_pull     = function(p, item) return ("Pulled %s %s from your bank"):format(p.qty or "?", item) end,
    loop_stop     = function(p)
        local txt = STOP_REASONS[p.reason] or ("Restock stopped: " .. Plain(p.reason or "?"))
        local bought = (p.touched or 0) > 0 and ("bought %d item%s for %s"):format(p.touched,
            p.touched == 1 and "" or "s", Money(p.spentCopper)) or "nothing bought"
        txt = txt .. ", " .. bought
        if (p.stillShort or 0) > 0 then txt = txt .. (", %d still short"):format(p.stillShort) end
        if (p.skippedCapped or 0) > 0 then txt = txt .. (", %d above cap"):format(p.skippedCapped) end
        return txt
    end,
    error         = function(p) return "Something went wrong: " .. Plain(p.msg or "?") end,
    ah_search     = function(p, item)
        return ("AH price for %s: %s each, %s listings"):format(item,
            p.unitPriceCopper and Money(p.unitPriceCopper) or "none", p.listings or 0)
    end,
    buy_attempt   = function(p, item)
        return ("Buying %s %s, up to %s"):format(p.qty or "?", item, Money(p.plannedSpendCopper))
    end,
    loop_start    = function(p)
        return ("Restock started (%s, %s items to check)"):format(p.mode or "manual", p.queueSize or "?")
    end,
    status        = function(p) return "Footer: " .. Plain(p.text) end,
    bank_run      = function(p)
        local txt = ("Bank restock (%s): pulled %d item%s"):format(p.mode or "manual", p.items or 0,
            p.items == 1 and "" or "s")
        return p.reason and (txt .. ", stopped: " .. p.reason) or txt
    end,
    setting       = function(p)
        return ("Setting: %s %s"):format(SETTING_LABELS[p.key] or tostring(p.key), p.on and "on" or "off")
    end,
    version       = function(p)
        if not p.from then return "StockClerk " .. tostring(p.to) .. " installed" end
        return ("StockClerk updated from %s to %s"):format(p.from, tostring(p.to))
    end,
    auto_toggle   = function(p) return "Auto-restock " .. (p.on and "on" or "off") end,
    trace         = function(p) return ("[%s] %s"):format(p.tag or "?", Plain(p.text)) end,
}

-- Log:Format(entry, full, color) -> one line, no timestamp.
-- full adds item IDs (support needs them; names can be ambiguous);
-- color tints the item name by quality (display only: codes copy as junk).
-- Item name and quality from the cache, else the name saved with the entry.
local function ItemInfo(itemID, savedName)
    local name, _, quality = C_Item.GetItemInfo(itemID)
    if type(name) ~= "string" then return savedName or ("item " .. itemID), nil end
    return name, quality
end

function Log:Format(e, full, color)
    local item
    if e.itemID then
        local name, quality = ItemInfo(e.itemID, e.payload and e.payload.name)
        -- [Name] like chat links: marks the name even when it's white (Common).
        item = "[" .. name .. "]"
        if full then item = ("%s (#%d)"):format(item, e.itemID) end
        if color and type(quality) == "number" then
            local r, g, b = C_Item.GetItemQualityColor(quality)
            if r then item = ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, item) end
        end
    end
    local fmt = FORMAT[e.kind]
    return fmt and fmt(e.payload or {}, item or "?") or tostring(e.kind)
end

-- ---------------------------------------------------------------------------
-- Support report: environment header + every entry, plain text.
-- ---------------------------------------------------------------------------

-- Addons worth knowing about when something misbehaves (bags, AH, UI suites).
local WATCHED_ADDONS = {
    "Auctionator", "TradeSkillMaster", "Journalator", "Baganator", "Syndicator", "Bagnon",
    "AdiBags", "ArkInventory", "BetterBags", "ElvUI", "EllesmereUI", "EllesmereUIBags",
    "atrocityUI", "atrocityEssentials", "LibSharedMedia-3.0",
}

function Log:Report()
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
    if version:sub(1, 1) == "@" then version = "dev (git checkout)" end
    local wowVersion, build = GetBuildInfo()

    local s = ADDON.DB:Settings()
    local settings = {}
    for _, key in ipairs({ "autoOpenAtAH", "autoOpenAtBank", "autoRestock", "autoRestockBank" }) do
        settings[#settings + 1] = SETTING_LABELS[key] .. " " .. (s[key] and "on" or "off")
    end

    local list = ADDON.DB:GetSortedItems()
    local short = #ADDON.BankRestock:Shortfalls()

    local count, loaded = 0, {}
    for i = 1, C_AddOns.GetNumAddOns() do
        if C_AddOns.IsAddOnLoaded(i) then count = count + 1 end
    end
    for _, name in ipairs(WATCHED_ADDONS) do
        if C_AddOns.IsAddOnLoaded(name) then loaded[#loaded + 1] = name end
    end

    local lines = {
        "StockClerk report, " .. date("%Y-%m-%d %H:%M"),
        ("StockClerk %s | WoW %s (build %s) | %s"):format(version, tostring(wowVersion), tostring(build),
            GetLocale()),
        ("Character: %s-%s | list: %d items, %d short"):format(UnitName("player"), GetRealmName(), #list, short),
        "Settings: " .. table.concat(settings, ", "),
        ("Addons loaded: %d. Relevant: %s"):format(count, #loaded > 0 and table.concat(loaded, ", ") or "none"),
        "Detailed recording (/clerk debug): " .. (ADDON.debug and "ON" or "off"),
    }

    -- The list as it stands, and purchases still waiting in the mail (they
    -- count as owned until looted).
    local rows = {}
    for _, it in ipairs(list) do
        local bd = ADDON.Inventory:GetBreakdown(it.itemID)
        rows[#rows + 1] = ("%s (#%d) %d/%d%s"):format((ItemInfo(it.itemID)), it.itemID, bd.bags, it.need,
            it.maxPrice and (" cap " .. Money(it.maxPrice)) or "")
    end
    lines[#lines + 1] = "List (bags/target): " .. (#rows > 0 and table.concat(rows, "; ") or "empty")
    local mail = {}
    for id, p in pairs(ADDON.DB.char.pendingBuys) do
        mail[#mail + 1] = ("%s (#%d) x%d"):format((ItemInfo(id)), id, p.qty)
    end
    lines[#lines + 1] = "Waiting in the mail: " .. (#mail > 0 and table.concat(mail, "; ") or "nothing")
    lines[#lines + 1] = "Lines marked . are details, > are recorded steps. Newest first."

    -- A date line per day; bracketed times keep the column even.
    local PREFIX = { activity = "  ", detail = ". ", trace = "> " }
    local me, day = UnitName("player"), nil
    for _, e in ipairs(self:Query()) do
        local d = date("%a %Y-%m-%d", e.ts or 0)
        if d ~= day then
            day = d
            lines[#lines + 1] = ""
            lines[#lines + 1] = "-- " .. d .. " --"
        end
        local who = (e.char and e.char ~= me) and (" (" .. e.char .. ")") or ""
        local extra = (e.kind == "error" and e.payload.stack) and ("\n             " .. e.payload.stack) or ""
        lines[#lines + 1] = ("[%s] %s%s%s%s"):format(date("%H:%M:%S", e.ts or 0),
            PREFIX[self.LEVEL[e.kind]] or "  ", self:Format(e, true), who, extra)
    end
    return table.concat(lines, "\n")
end
