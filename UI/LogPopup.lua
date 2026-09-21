--[[
    Stock Clerk - UI/LogPopup.lua

    v0.7: replaces UI/LogFrame.lua. Instead of a full mini-app with filters
    and a live tail, this is a simple copy-friendly dump popup summoned by
    `/clerk log`. Design goals:

    * 500x400 popup, one big multi-line EditBox showing every log entry
    * EditBox pre-selects all text on show so Ctrl+C copies immediately
    * Escape closes; a Close button in the corner as a fallback
    * Entries prefixed with tag glyphs ([BUY]/[CAP]/[AUTO-BLOCK]/etc) so
      the copy-paste output is greppable for support conversations

    Two-tier model with the Sidecar's Recent Activity feed:
    * Sidecar shows a live, curated preview (~30 entries, action-focused)
    * This popup shows the FULL log (up to Log.MAX_ENTRIES, currently 500)
      for the user who wants everything

    LogFrame.lua was the v0.6 log surface. LogPopup replaced it in v0.7
    (kept alongside for one release to give any external callers a grace
    period) and LogFrame.lua was deleted in v0.8.
]]

local addonName = ...
local ADDON     = _G[addonName]

local LogPopup = {}
ADDON.LogPopup = LogPopup

local function P()
    return (ADDON.MainFrame and ADDON.MainFrame.Palette) or {
        bg       = { 0.06, 0.06, 0.06, 0.98 },
        bgDark   = { 0.04, 0.04, 0.04, 1 },
        border   = { 0, 0, 0, 1 },
        brand    = { 0.60, 1.00, 0.60, 1 },
    }
end

-- -------------------------------------------------------------------------
-- Tag glyph per kind. Uppercase-in-brackets for greppability. Kept in one
-- table so extending the log with a new kind is a one-line change here.
-- -------------------------------------------------------------------------
local TAGS = {
    buy_success   = "[BUY]",
    buy_fail      = "[BUY-FAIL]",
    buy_skip      = "[BUY-SKIP]",
    buy_attempt   = "[BUY-TRY]",
    cap_change    = "[CAP]",
    target_change = "[TARGET]",
    add           = "[ADD]",
    remove        = "[REMOVE]",
    ah_search     = "[SEARCH]",
    loop_start    = "[LOOP-START]",
    loop_stop     = "[LOOP-STOP]",
    auto_toggle   = "[AUTO]",
    auto_refuse   = "[AUTO-BLOCK]",
    status        = "[STATUS]",
    kbd_stuck     = "[KBD]",
}

-- -------------------------------------------------------------------------
-- One-line renderer. Compact but human-readable. Item names resolved via
-- GetItemInfo, with itemID fallback if the client hasn't cached the name
-- yet. Gold values shown as whole gold (matches the addon-wide preference
-- for legibility over precision when the last few silver don't matter).
-- -------------------------------------------------------------------------
local function FormatLine(entry)
    local tag = TAGS[entry.kind] or ("[" .. (entry.kind or "?"):upper() .. "]")
    local when = date("%Y-%m-%d %H:%M:%S", entry.ts or time())
    local pay = entry.payload or {}

    local who = ""
    if entry.itemID then
        local name = GetItemInfo(entry.itemID)
        who = " " .. (name or ("item:" .. entry.itemID))
    end

    local extra = ""
    if entry.kind == "buy_success" then
        extra = (" qty=%d spent=%dg"):format(pay.qty or 0, math.floor((pay.spentCopper or 0)/10000))
    elseif entry.kind == "buy_fail" or entry.kind == "buy_skip" then
        extra = " reason=" .. tostring(pay.reason or "?")
    elseif entry.kind == "buy_attempt" then
        extra = (" qty=%d planned=%dg"):format(pay.qty or 0, math.floor((pay.plannedSpendCopper or 0)/10000))
    elseif entry.kind == "cap_change" then
        local from = pay.fromCopper and (math.floor(pay.fromCopper/10000) .. "g") or "unset"
        local to   = pay.toCopper   and (math.floor(pay.toCopper/10000)   .. "g") or "unset"
        extra = (" %s -> %s"):format(from, to)
    elseif entry.kind == "target_change" then
        extra = (" %s -> %s"):format(tostring(pay.from), tostring(pay.to))
    elseif entry.kind == "add" then
        extra = " need=" .. tostring(pay.need or 0)
    elseif entry.kind == "loop_start" then
        extra = (" mode=%s queue=%d"):format(pay.mode or "?", pay.queueSize or 0)
    elseif entry.kind == "loop_stop" then
        extra = (" reason=%s spent=%dg touched=%d short=%d"):format(
            pay.reason or "?",
            math.floor((pay.spentCopper or 0)/10000),
            pay.touched or 0,
            pay.stillShort or 0)
    elseif entry.kind == "auto_toggle" then
        extra = " on=" .. tostring(pay.on)
    elseif entry.kind == "auto_refuse" then
        extra = " reason=" .. tostring(pay.reason or "?")
    elseif entry.kind == "ah_search" then
        local u = pay.unitPriceCopper and (math.floor(pay.unitPriceCopper/10000) .. "g") or "?"
        extra = (" unit=%s listings=%d"):format(u, pay.listings or 0)
    elseif entry.kind == "status" then
        -- Strip WoW color codes from status text so the dump stays plain
        -- (color codes copy as raw |cffXXXXXX...|r markers into the
        -- clipboard which is ugly when pasting into a bug report).
        local text = tostring(pay.text or "")
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        extra = " " .. text
    elseif entry.kind == "kbd_stuck" then
        -- Keyboard-capture watchdog (v0.6.1). Reason is the key field for
        -- diagnosis; detail is a fuller human-readable sentence.
        extra = " reason=" .. tostring(pay.reason or "unknown")
        if pay.detail then
            extra = extra .. " -- " .. tostring(pay.detail)
        end
    end

    return ("%s %s%s%s"):format(when, tag, who, extra)
end

-- -------------------------------------------------------------------------
-- Build the popup lazily. UIParent-parented, DIALOG strata so it floats
-- above the sidecar and main frame; movable via title-bar drag.
-- -------------------------------------------------------------------------
local function Build()
    local f = CreateFrame("Frame", "StockClerkLogPopup", UIParent, "BackdropTemplate")
    f:SetSize(500, 400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(30)
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    -- Register the popup with Blizzard's
    -- UISpecialFrames so Escape closes it even when no editbox has focus.
    -- The existing edit:OnEscapePressed only fires when the read-only
    -- transcript editbox has keyboard focus, which is not the common case
    -- for `/clerk log` (opened to read, not to edit) -- so Escape
    -- previously fell through and the log window ignored it, breaking the
    -- consistent Escape-closes-my-window pattern set by the settings
    -- window and main frame.
    tinsert(UISpecialFrames, "StockClerkLogPopup")

    -- Bg + black frame edges
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(P().bg[1], P().bg[2], P().bg[3], P().bg[4] or 1)

    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local t = f:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetColorTexture(0, 0, 0, 1)
        if side == "top" then
            t:SetHeight(1); t:SetPoint("TOPLEFT", 0, 0); t:SetPoint("TOPRIGHT", 0, 0)
        elseif side == "bottom" then
            t:SetHeight(1); t:SetPoint("BOTTOMLEFT", 0, 0); t:SetPoint("BOTTOMRIGHT", 0, 0)
        elseif side == "left" then
            t:SetWidth(1); t:SetPoint("TOPLEFT", 0, 0); t:SetPoint("BOTTOMLEFT", 0, 0)
        else
            t:SetWidth(1); t:SetPoint("TOPRIGHT", 0, 0); t:SetPoint("BOTTOMRIGHT", 0, 0)
        end
    end

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cff98FF98Stock Clerk - Activity Log|r")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, -28)
    hint:SetText("|cff6a6a6aText below is pre-selected. Press Ctrl+C to copy. Esc to close.|r")

    -- Close X button, upper right
    local closeX = CreateFrame("Button", nil, f)
    closeX:SetSize(28, 22)
    closeX:SetPoint("TOPRIGHT", -6, -6)
    local xText = closeX:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    xText:SetPoint("CENTER")
    xText:SetText("X")
    xText:SetTextColor(0.85, 0.85, 0.85, 1)
    closeX:SetScript("OnEnter", function() xText:SetTextColor(1.0, 0.6, 0.6, 1) end)
    closeX:SetScript("OnLeave", function() xText:SetTextColor(0.85, 0.85, 0.85, 1) end)
    closeX:SetScript("OnClick", function() f:Hide() end)

    -- ScrollFrame containing the multi-line EditBox
    local scrollBg = f:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetColorTexture(P().bgDark[1], P().bgDark[2], P().bgDark[3], 1)
    scrollBg:SetPoint("TOPLEFT", 8, -50)
    scrollBg:SetPoint("BOTTOMRIGHT", -8, 38)

    local scroll = CreateFrame("ScrollFrame", "StockClerkLogPopupScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -52)
    scroll:SetPoint("BOTTOMRIGHT", -28, 40)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontSmall")
    edit:SetWidth(scroll:GetWidth() - 4)
    edit:SetJustifyH("LEFT")
    -- Route Enter into a newline (default EditBox behavior for MultiLine
    -- is already correct). Escape clears focus and hides the popup.
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        f:Hide()
    end)
    scroll:SetScrollChild(edit)
    f._edit = edit
    f._scroll = scroll

    -- Bottom-right buttons: Clear, Close.
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    clearBtn:SetText("Clear Log")
    clearBtn:SetScript("OnClick", function()
        if ADDON.Log and ADDON.Log.Clear then
            ADDON.Log:Clear()
            LogPopup:Refresh()
        end
    end)

    -- OnShow: build the text and pre-select everything so Ctrl+C works
    -- immediately without the user having to click into the box first.
    f:SetScript("OnShow", function()
        LogPopup:Refresh()
        edit:SetFocus()
        edit:HighlightText()
    end)

    LogPopup.frame = f
    return f
end

-- -------------------------------------------------------------------------
-- Public: rebuild the text from the current log buffer, newest-first.
-- -------------------------------------------------------------------------
function LogPopup:Refresh()
    local f = self.frame
    if not f then return end

    local entries = {}
    if ADDON.Log and ADDON.Log.Query then
        entries = ADDON.Log:Query()  -- newest-first
    end

    if #entries == 0 then
        f._edit:SetText("(log is empty)")
        return
    end

    local lines = {}
    for i = 1, #entries do
        lines[i] = FormatLine(entries[i])
    end
    f._edit:SetText(table.concat(lines, "\n"))
    -- Reset scroll to top so the user sees the newest entry immediately.
    f._scroll:SetVerticalScroll(0)
end

-- -------------------------------------------------------------------------
-- Public: show / hide / toggle.
-- -------------------------------------------------------------------------
function LogPopup:Show()
    local f = self.frame or Build()
    f:Show()
end

function LogPopup:Hide()
    if self.frame then self.frame:Hide() end
end

function LogPopup:Toggle()
    local f = self.frame or Build()
    if f:IsShown() then f:Hide() else f:Show() end
end

-- -------------------------------------------------------------------------
-- Hook Log:Emit so a live popup refreshes when new entries land. Chained
-- after Sidecar's hook so both surfaces stay current; each hook checks
-- IsShown before doing any work, so a hidden popup costs nothing per
-- emit beyond a single frame:IsShown call.
-- -------------------------------------------------------------------------
do
    if ADDON.Log and ADDON.Log.Emit and not ADDON.Log._logpopup_hook then
        local origEmit = ADDON.Log.Emit
        ADDON.Log.Emit = function(self, kind, itemID, payload)
            origEmit(self, kind, itemID, payload)
            if LogPopup.frame and LogPopup.frame:IsShown() then
                if not LogPopup._refreshing then
                    LogPopup._refreshing = true
                    pcall(LogPopup.Refresh, LogPopup)
                    LogPopup._refreshing = false
                end
            end
        end
        ADDON.Log._logpopup_hook = true
    end
end
