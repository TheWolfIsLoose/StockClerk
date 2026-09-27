--[[
    Stock Clerk - UI/LogPopup.lua

    `/clerk log`: the support report (Log:Report) in a copyable text box,
    pre-selected so Ctrl+C works at once. A snapshot taken when it opens;
    it doesn't refresh live, so a selection survives while copying.
]]

local addonName = ...
local ADDON     = _G[addonName]

local LogPopup = {}
ADDON.LogPopup = LogPopup

local Palette = ADDON.MainFrame.Palette

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
    bg:SetColorTexture(Palette.panelBg[1], Palette.panelBg[2], Palette.panelBg[3], Palette.panelBg[4] or 1)

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
    local title = f:CreateFontString(nil, "OVERLAY", "StockClerkFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cff98FF98Stock|r|cffffffffClerk|r log")

    local hint = f:CreateFontString(nil, "OVERLAY", "StockClerkFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, -28)
    hint:SetText("|cff888888Everything is selected: press Ctrl+C and paste it into your bug report.|r")

    -- Close X button, upper right
    local closeX = CreateFrame("Button", nil, f)
    closeX:SetSize(28, 22)
    closeX:SetPoint("TOPRIGHT", -6, -6)
    local xText = closeX:CreateFontString(nil, "OVERLAY", "StockClerkFontNormalLarge")
    xText:SetPoint("CENTER")
    xText:SetText("X")
    xText:SetTextColor(0.85, 0.85, 0.85, 1)
    closeX:SetScript("OnEnter", function() xText:SetTextColor(1.0, 0.6, 0.6, 1) end)
    closeX:SetScript("OnLeave", function() xText:SetTextColor(0.85, 0.85, 0.85, 1) end)
    closeX:SetScript("OnClick", function() f:Hide() end)

    -- ScrollFrame containing the multi-line EditBox
    local scrollBg = f:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetColorTexture(Palette.bgDark[1], Palette.bgDark[2], Palette.bgDark[3], 1)
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
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(80, 22)
    ADDON.MainFrame.StyleButton(closeBtn)
    closeBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local clearBtn = CreateFrame("Button", nil, f)
    clearBtn:SetSize(80, 22)
    ADDON.MainFrame.StyleButton(clearBtn)
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
    f._edit:SetText(ADDON.Log:Report())
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
