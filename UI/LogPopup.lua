--[[
    Stock Clerk - UI/LogPopup.lua
    `/clerk log`: the support report (Log:Report) in a copyable text box,
    pre-selected so Ctrl+C works at once. A snapshot taken on open; it
    doesn't refresh live, so a selection survives while copying.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local LogPopup = {}
ADDON.LogPopup = LogPopup

local MF = ADDON.MainFrame

local function Build()
    MF.ApplyFontFace()
    local f = CreateFrame("Frame", "StockClerkLogPopup", UIParent)
    f:SetSize(500, 400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "StockClerkLogPopup")  -- Escape closes it
    MF.ApplyFill(f, MF.Palette.panelBg)
    MF.AddBlackBorder(f)

    local title = f:CreateFontString(nil, "OVERLAY", "StockClerkFont")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cff98FF98Stock|rClerk log")
    local hint = f:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    hint:SetPoint("TOPLEFT", 12, -28)
    hint:SetText("|cff888888Everything is selected: press Ctrl+C and paste it into your bug report.|r")
    MF.HeaderIcon(f, MF.CLOSE_GLYPH, "Close", function() f:Hide() end):SetPoint("TOPRIGHT", -4, -4)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(unpack(MF.Palette.bgDark))
    bg:SetPoint("TOPLEFT", 8, -50)
    bg:SetPoint("BOTTOMRIGHT", -8, 38)
    local scroll = CreateFrame("ScrollFrame", "StockClerkLogPopupScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -52)
    scroll:SetPoint("BOTTOMRIGHT", -28, 40)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontSmall")
    edit:SetWidth(scroll:GetWidth() - 4)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)

    local clear = CreateFrame("Button", nil, f)
    clear:SetSize(80, 22)
    clear:SetPoint("BOTTOMRIGHT", -8, 8)
    MF.StyleButton(clear)
    clear:SetText("Clear log")

    -- Newest entries at the top, all selected.
    local function Fill()
        edit:SetText(ADDON.Log:Report())
        scroll:SetVerticalScroll(0)
        edit:SetFocus()
        edit:HighlightText()
    end
    clear:SetScript("OnClick", function()
        ADDON.Log:Clear()
        ADDON.Sidecar:OnActivity()
        Fill()
    end)
    f:SetScript("OnShow", Fill)

    LogPopup.frame = f
    return f
end

function LogPopup:Show()
    (self.frame or Build()):Show()
end

function LogPopup:Toggle()
    local f = self.frame or Build()
    f:SetShown(not f:IsShown())
end
