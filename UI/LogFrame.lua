--[[
    Stock Clerk - UI/LogFrame.lua
    Sidecar activity-log window.

    Docks to the RIGHT of MainFrame (user-locked; not draggable). Height
    always matches MainFrame's height so the two frames read as one
    composed unit. Width is fixed at 340 -- wide enough for a
    timestamp + kind pill + one line of payload without wrapping.

    Layout mirrors MainFrame's structure so the two windows feel like
    siblings:
      header    - "Activity" title + × close
      aggBar    - single-line "N purchases | Spent Xg | Top: NAME"
      filters   - four chips: All / Purchases / Session / (per-item stub)
      list      - ScrollFrame of formatted entries, newest first
      footer    - "N entries" hint + "/clerk log clear" reminder

    Uses the same Palette hooked off ADDON.MainFrame so any color
    tuning propagates automatically. If MainFrame hasn't loaded yet
    (shouldn't happen -- TOC load order guarantees it), fall back to
    hardcoded palette values.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local LogFrame = {}
ADDON.LogFrame = LogFrame

-- Fixed sidecar width. Not resizable independently of MainFrame; the
-- entire purpose is to be a dockable companion.
local SIDECAR_WIDTH = 340
local HEADER_HEIGHT = 32
local AGG_HEIGHT    = 36
local FILTER_HEIGHT = 26
local FOOTER_HEIGHT = 24
local ENTRY_HEIGHT  = 32   -- one entry takes up roughly two text lines
local BORDER_SIZE   = 1

-- Match MainFrame's palette (approximated here so this file compiles
-- standalone; real values come from ADDON.MainFrame.Palette at runtime).
local function P()
    return (ADDON.MainFrame and ADDON.MainFrame.Palette) or {
        bg        = { 0.06, 0.06, 0.06, 0.96 },
        bgMedium  = { 0.10, 0.10, 0.10, 1 },
        bgDark    = { 0.04, 0.04, 0.04, 1 },
        bandTint  = { 1, 1, 1, 0.02 },
        border    = { 0, 0, 0, 1 },
        brand     = { 0.60, 1.00, 0.60, 1 },
    }
end

local WHITE_TEX = "Interface\\Buildings\\White8x8"

-- ---------------------------------------------------------------------------
-- Filter state (module-level; single sidecar instance)
-- ---------------------------------------------------------------------------
LogFrame.filter = {
    mode  = "all",   -- "all" | "purchases" | "session"
    since = nil,     -- session start timestamp; set on module init
}

-- ---------------------------------------------------------------------------
-- Formatting helpers
-- ---------------------------------------------------------------------------
local function FormatRelTime(ts)
    local delta = time() - ts
    if delta <  60   then return delta .. "s ago" end
    if delta <  3600 then return math.floor(delta/60)   .. "m ago" end
    if delta <  86400 then return math.floor(delta/3600) .. "h ago" end
    return math.floor(delta/86400) .. "d ago"
end

local function CoinText(copper)
    if not copper or copper == 0 then return "0g" end
    if copper >= 10000 then
        return ("%dg"):format(math.floor(copper / 10000))
    else
        return GetCoinTextureString(copper)
    end
end

local function ItemName(itemID)
    if not itemID then return "" end
    return C_Item.GetItemInfo(itemID) or ("item:" .. itemID)
end

-- Per-kind formatter. Returns two strings:
--   line1: pill text + short summary (e.g. "BUY  20x Healing Potion")
--   line2: dim detail line          (e.g. "spent 12g50s -- 2h ago on Alt")
local function FormatEntry(e)
    local pill, summary, detail
    local p = e.payload or {}

    if e.kind == "buy_success" then
        pill    = "|cff4ade80BUY|r"
        summary = ("%dx %s"):format(p.qty or 0, ItemName(e.itemID))
        detail  = ("spent %s"):format(CoinText(p.spentCopper))
    elseif e.kind == "buy_fail" then
        pill    = "|cffe5624aFAIL|r"
        summary = ItemName(e.itemID)
        detail  = tostring(p.reason or "?")
    elseif e.kind == "buy_attempt" then
        pill    = "|cffffd200TRY|r"
        summary = ("%dx %s"):format(p.qty or 0, ItemName(e.itemID))
        detail  = ("plan %s @ worst %s/u"):format(
            CoinText(p.plannedSpendCopper), CoinText(p.worstUnitCopper))
    elseif e.kind == "buy_skip" then
        pill    = "|cff888888SKIP|r"
        summary = ItemName(e.itemID)
        detail  = tostring(p.reason or "?")
    elseif e.kind == "auto_refuse" then
        pill    = "|cffffaa00STOP|r"
        summary = ItemName(e.itemID) .. " -- auto refused"
        detail  = tostring(p.reason or "?")
    elseif e.kind == "auto_toggle" then
        pill    = p.on and "|cff98FF98AUTO|r" or "|cff888888AUTO|r"
        summary = p.on and "auto-purchase enabled" or "auto-purchase disabled"
        detail  = ""
    elseif e.kind == "loop_start" then
        pill    = "|cff98FF98LOOP|r"
        summary = ("started (%s)"):format(p.mode or "?")
        detail  = ("%d items, budget %s"):format(
            p.queueSize or 0,
            p.budgetCopper and CoinText(p.budgetCopper) or "unlimited")
    elseif e.kind == "loop_stop" then
        pill    = "|cff888888LOOP|r"
        summary = ("stopped: %s"):format(p.reason or "?")
        detail  = ("spent %s, %d bought, %d still short"):format(
            CoinText(p.spentCopper), p.touched or 0, p.stillShort or 0)
    elseif e.kind == "ah_search" then
        pill    = "|cff6b7280SRCH|r"
        summary = ItemName(e.itemID)
        detail  = p.unitPriceCopper
            and ("cheapest %s/u (%d listings)"):format(
                CoinText(p.unitPriceCopper), p.listings or 0)
            or "no listings"
    elseif e.kind == "add" then
        pill    = "|cff98FF98ADD|r"
        summary = ItemName(e.itemID)
        detail  = ("need %d, cap %s"):format(
            p.need or 0,
            p.cap and CoinText(p.cap) or "none")
    elseif e.kind == "remove" then
        pill    = "|cffe5624aDEL|r"
        summary = ItemName(e.itemID)
        detail  = ""
    elseif e.kind == "target_change" then
        pill    = "|cffffd200EDIT|r"
        summary = ItemName(e.itemID)
        detail  = ("need %s -> %s"):format(tostring(p.from), tostring(p.to))
    elseif e.kind == "cap_change" then
        pill    = "|cffffd200EDIT|r"
        summary = ItemName(e.itemID)
        detail  = ("cap %s -> %s"):format(
            p.fromCopper and CoinText(p.fromCopper) or "none",
            p.toCopper   and CoinText(p.toCopper)   or "none")
    else
        pill    = "|cff888888?|r"
        summary = tostring(e.kind)
        detail  = ""
    end

    -- Character/realm suffix on detail line, only when it's not the
    -- current character (keeps single-char use quiet).
    if e.char and e.char ~= UnitName("player") then
        detail = detail .. (" |cff555555· on %s|r"):format(e.char)
    end

    return pill, summary, detail
end

-- ---------------------------------------------------------------------------
-- Build the frame (lazy; first Show creates it)
-- ---------------------------------------------------------------------------
local function ApplyFill(frame, rgba)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetTexture(WHITE_TEX)
    t:SetAllPoints(frame)
    t:SetVertexColor(unpack(rgba))
    frame._bg = t
    return t
end

local function ApplyBand(frame, rgba)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    t:SetTexture(WHITE_TEX)
    t:SetAllPoints(frame)
    t:SetVertexColor(unpack(rgba))
    return t
end

local function AddBottomSep(frame)
    local sep = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    sep:SetTexture(WHITE_TEX)
    sep:SetColorTexture(0, 0, 0, 1)
    sep:SetHeight(BORDER_SIZE)
    sep:SetPoint("BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", 0, 0)
    return sep
end

local function BuildFrame()
    local mf = ADDON.MainFrame and ADDON.MainFrame.frame
    if not mf then return nil end

    local f = CreateFrame("Frame", "StockClerkLogFrame", mf, "BackdropTemplate")
    f:SetFrameStrata(mf:GetFrameStrata())
    f:SetFrameLevel(mf:GetFrameLevel())
    f:SetWidth(SIDECAR_WIDTH)

    -- Dock: LEFT edge glued to MainFrame's RIGHT edge, top/bottom flush.
    -- No inset; the 1px black border on each frame provides the visual seam.
    f:SetPoint("TOPLEFT",     mf, "TOPRIGHT",     0, 0)
    f:SetPoint("BOTTOMLEFT",  mf, "BOTTOMRIGHT",  0, 0)

    -- One solid dark fill (matches MainFrame body).
    ApplyFill(f, P().bg)

    -- 1px hairline black border ringing the sidecar. Matches MainFrame's
    -- flat aesthetic; the black line on both frames creates the visible
    -- seam between them.
    local function edge(anchorA, anchorB, isHoriz)
        local t = f:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetTexture(WHITE_TEX)
        t:SetColorTexture(0, 0, 0, 1)
        if isHoriz then
            t:SetHeight(BORDER_SIZE)
            t:SetPoint(anchorA, 0, 0)
            t:SetPoint(anchorB, 0, 0)
        else
            t:SetWidth(BORDER_SIZE)
            t:SetPoint(anchorA, 0, 0)
            t:SetPoint(anchorB, 0, 0)
        end
    end
    edge("TOPLEFT",    "TOPRIGHT",    true)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPRIGHT",   "BOTTOMRIGHT", false)

    -- ---- Header --------------------------------------------------------
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT",  0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    ApplyBand(header, P().bandTint)
    AddBottomSep(header)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", 12, 0)
    title:SetText("|cff98FF98Activity|r")

    local closeX = CreateFrame("Button", nil, header)
    closeX:SetSize(28, 22)
    closeX:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    local xText = closeX:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    xText:SetPoint("CENTER")
    xText:SetText("×")
    xText:SetTextColor(0.85, 0.85, 0.85, 1)
    closeX:SetScript("OnEnter", function()
        xText:SetTextColor(P().brand[1], P().brand[2], P().brand[3], 1)
    end)
    closeX:SetScript("OnLeave", function()
        xText:SetTextColor(0.85, 0.85, 0.85, 1)
    end)
    closeX:SetScript("OnClick", function() LogFrame:Hide() end)

    -- ---- Aggregation bar ----------------------------------------------
    local aggBar = CreateFrame("Frame", nil, f)
    aggBar:SetHeight(AGG_HEIGHT)
    aggBar:SetPoint("TOPLEFT",  header, "BOTTOMLEFT",  0, 0)
    aggBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    ApplyBand(aggBar, P().bandTint)
    AddBottomSep(aggBar)

    local aggText = aggBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    aggText:SetPoint("LEFT",  12, 0)
    aggText:SetPoint("RIGHT", -12, 0)
    aggText:SetJustifyH("LEFT")
    aggText:SetWordWrap(false)
    f._aggText = aggText

    -- ---- Filter chips --------------------------------------------------
    local filters = CreateFrame("Frame", nil, f)
    filters:SetHeight(FILTER_HEIGHT)
    filters:SetPoint("TOPLEFT",  aggBar, "BOTTOMLEFT",  0, 0)
    filters:SetPoint("TOPRIGHT", aggBar, "BOTTOMRIGHT", 0, 0)
    AddBottomSep(filters)

    local chips = {}
    local function MakeChip(label, mode, xOffset)
        local c = CreateFrame("Button", nil, filters)
        c:SetSize(72, 18)
        c:SetPoint("LEFT", filters, "LEFT", xOffset, 0)
        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(WHITE_TEX)
        bg:SetAllPoints()
        bg:SetVertexColor(P().bgMedium[1], P().bgMedium[2], P().bgMedium[3], 0.6)
        c._bg = bg
        local txt = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("CENTER")
        txt:SetText(label)
        c._text = txt
        c._mode = mode
        c:SetScript("OnClick", function()
            LogFrame.filter.mode = mode
            LogFrame:Refresh()
        end)
        chips[#chips+1] = c
        return c
    end
    MakeChip("All",       "all",       10)
    MakeChip("Purchases", "purchases", 88)
    MakeChip("Session",   "session",  166)
    f._chips = chips

    -- ---- Footer --------------------------------------------------------
    local footer = CreateFrame("Frame", nil, f)
    footer:SetHeight(FOOTER_HEIGHT)
    footer:SetPoint("BOTTOMLEFT",  0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    ApplyBand(footer, P().bandTint)
    local footerTop = footer:CreateTexture(nil, "OVERLAY", nil, 6)
    footerTop:SetTexture(WHITE_TEX)
    footerTop:SetColorTexture(0, 0, 0, 1)
    footerTop:SetHeight(BORDER_SIZE)
    footerTop:SetPoint("TOPLEFT",  0, 0)
    footerTop:SetPoint("TOPRIGHT", 0, 0)

    local footerText = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerText:SetPoint("LEFT",  10, 0)
    footerText:SetPoint("RIGHT", -10, 0)
    footerText:SetJustifyH("LEFT")
    footerText:SetText("/clerk log clear  wipes this list")
    f._footerText = footerText

    -- ---- Scroll body ---------------------------------------------------
    -- Simple ScrollFrame + child frame instead of ScrollBox to keep the
    -- module small; entry count caps at 500 so this is well within the
    -- comfortable range for a plain scrollframe.
    local scrollHolder = CreateFrame("Frame", nil, f)
    scrollHolder:SetPoint("TOPLEFT",     filters, "BOTTOMLEFT",  0, 0)
    scrollHolder:SetPoint("BOTTOMRIGHT", footer,  "TOPRIGHT",    0, 0)

    local scroll = CreateFrame("ScrollFrame", "StockClerkLogScroll", scrollHolder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)   -- size set on refresh
    scroll:SetScrollChild(content)
    f._scroll  = scroll
    f._content = content
    f._entryPool = {}       -- reusable row frames

    LogFrame.frame = f
    return f
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------
local function AcquireEntryRow(f, idx)
    local pool = f._entryPool
    local r = pool[idx]
    if r then return r end

    r = CreateFrame("Frame", nil, f._content)
    r:SetHeight(ENTRY_HEIGHT)
    r:SetPoint("LEFT",  0, 0)
    r:SetPoint("RIGHT", 0, 0)

    r.timeText = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.timeText:SetPoint("TOPLEFT", 4, -2)
    r.timeText:SetWidth(60)
    r.timeText:SetJustifyH("LEFT")

    r.pill = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.pill:SetPoint("TOPLEFT", r.timeText, "TOPRIGHT", 4, 0)
    r.pill:SetWidth(50)
    r.pill:SetJustifyH("LEFT")

    r.summary = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.summary:SetPoint("TOPLEFT", r.pill, "TOPRIGHT", 4, 0)
    r.summary:SetPoint("RIGHT", -4, 0)
    r.summary:SetJustifyH("LEFT")
    r.summary:SetWordWrap(false)

    r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.detail:SetPoint("TOPLEFT", r.pill, "BOTTOMLEFT", 0, -1)
    r.detail:SetPoint("RIGHT", -4, 0)
    r.detail:SetJustifyH("LEFT")
    r.detail:SetWordWrap(false)

    pool[idx] = r
    return r
end

function LogFrame:Refresh()
    local f = self.frame
    if not f then return end

    -- Update chip visuals to reflect current mode.
    for _, c in ipairs(f._chips) do
        if c._mode == self.filter.mode then
            c._bg:SetVertexColor(P().brand[1] * 0.5, P().brand[2] * 0.5, P().brand[3] * 0.5, 0.9)
            c._text:SetTextColor(P().brand[1], P().brand[2], P().brand[3], 1)
        else
            c._bg:SetVertexColor(P().bgMedium[1], P().bgMedium[2], P().bgMedium[3], 0.6)
            c._text:SetTextColor(0.85, 0.85, 0.85, 1)
        end
    end

    -- Build filter for Log:Query.
    local q = {}
    if self.filter.mode == "purchases" then
        q.kinds = { "buy_success", "buy_fail", "buy_attempt", "buy_skip", "auto_refuse" }
    elseif self.filter.mode == "session" then
        q.since = self.filter.since or 0
    end
    local entries = ADDON.Log:Query(q)

    -- Aggregation for the top bar (respects "session" filter so header
    -- reads "This session" totals when session mode is active).
    local aggSince = (self.filter.mode == "session") and self.filter.since or nil
    local agg = ADDON.Log:Aggregate(aggSince)

    -- Top-spent item (by copper) for the "Top: NAME" callout.
    local topID, topSpent = nil, 0
    for id, spent in pairs(agg.byItemSpent) do
        if spent > topSpent then topID, topSpent = id, spent end
    end
    local topName = topID and ItemName(topID) or ""
    local aggLine = ("|cff98FF98%d|r buys · spent |cffffffff%s|r"):format(
        agg.purchases, CoinText(agg.spentCopper))
    if topID then
        aggLine = aggLine .. ("  ·  top: %s (%s)"):format(topName, CoinText(topSpent))
    end
    f._aggText:SetText(aggLine)
    f._footerText:SetText(("%d entries · /clerk log clear to wipe"):format(#entries))

    -- Draw entries (newest first). Hide any pool rows we don't need.
    for i, e in ipairs(entries) do
        local r = AcquireEntryRow(f, i)
        r:SetPoint("TOPLEFT",  0, -((i - 1) * ENTRY_HEIGHT))
        r:SetPoint("TOPRIGHT", 0, -((i - 1) * ENTRY_HEIGHT))
        local pill, summary, detail = FormatEntry(e)
        r.timeText:SetText(FormatRelTime(e.ts))
        r.pill:SetText(pill)
        r.summary:SetText(summary)
        r.detail:SetText(detail)
        r:Show()
    end
    for i = #entries + 1, #f._entryPool do
        f._entryPool[i]:Hide()
    end
    f._content:SetHeight(math.max(1, #entries * ENTRY_HEIGHT))
end

-- ---------------------------------------------------------------------------
-- Public: show / hide / toggle
-- ---------------------------------------------------------------------------
function LogFrame:Show()
    -- Session-start baseline the first time we ever show. Every "Session"
    -- filter query uses this as its `since`.
    if not self.filter.since then
        self.filter.since = time()
    end
    local f = self.frame or BuildFrame()
    if not f then return end
    f:Show()
    self:Refresh()
end

function LogFrame:Hide()
    if self.frame then self.frame:Hide() end
end

function LogFrame:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function LogFrame:IsShown()
    return self.frame and self.frame:IsShown()
end
