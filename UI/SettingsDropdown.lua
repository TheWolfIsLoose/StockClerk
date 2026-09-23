--[[
    Stock Clerk - UI/SettingsDropdown.lua
    Compact settings surface attached to the header cog button.

    Toggles:
      - Auto-open at AH (default ON). Pop the shopping list open on
        AH visit.
      - Express-Restock (default OFF). Also kicks the restock loop when
        opening the AH, but only if the shortfall count is > 0.

    Design notes:
      - Renders as a small floating panel anchored to the cog button.
        Not a StaticPopup: too heavy for a settings surface. Not a
        separate window: users shouldn't have to hunt for it.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local Settings = {}
ADDON.SettingsDropdown = Settings

-- (No WHITE_TEX path -- we use SetColorTexture for solid fills. The
-- WoW "White8x8" atlas returns a texture whose own alpha gates the
-- vertex-color alpha to zero on retail Midnight, which is why the first
-- draft of this dropdown rendered as fully transparent.)

local function P()
    return (ADDON.MainFrame and ADDON.MainFrame.Palette) or {
        bg        = { 0.06, 0.06, 0.06, 0.98 },
        bgMedium  = { 0.10, 0.10, 0.10, 1 },
        bgDark    = { 0.04, 0.04, 0.04, 1 },
        bandTint  = { 1, 1, 1, 0.02 },
        border    = { 0, 0, 0, 1 },
        brand     = { 0.60, 1.00, 0.60, 1 },
    }
end

-- ---------------------------------------------------------------------------
-- Build the dropdown (lazy)
-- ---------------------------------------------------------------------------
local function BuildDropdown(anchor)
    -- Full-screen click-catcher behind the panel. Parented to UIParent
    -- at the same strata so it swallows a click anywhere off the panel
    -- and closes it. Without this, the dropdown lingers behind other
    -- UI whenever the user clicks away, forcing them to click the cog
    -- again to dismiss.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    catcher:Hide()

    local f = CreateFrame("Frame", "StockClerkSettingsDropdown", UIParent, "BackdropTemplate")
    -- Sized to fit the two toggles + their hint lines.
    f:SetSize(280, 156)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(10)                       -- above the catcher
    f:SetToplevel(true)
    f:EnableMouse(true)                       -- swallow clicks on the panel
    f:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    f:Hide()

    -- Catcher only fires when the click missed the panel.
    catcher:SetScript("OnClick", function() f:Hide() end)
    f._catcher = catcher

    -- Solid fill + 1px black border, matching MainFrame's chrome vocab.
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(P().bg[1], P().bg[2], P().bg[3], P().bg[4] or 1)

    local function edge(anchorA, anchorB, isHoriz)
        local t = f:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetColorTexture(0, 0, 0, 1)
        if isHoriz then
            t:SetHeight(1)
            t:SetPoint(anchorA, 0, 0)
            t:SetPoint(anchorB, 0, 0)
        else
            t:SetWidth(1)
            t:SetPoint(anchorA, 0, 0)
            t:SetPoint(anchorB, 0, 0)
        end
    end
    edge("TOPLEFT",     "TOPRIGHT",    true)
    edge("BOTTOMLEFT",  "BOTTOMRIGHT", true)
    edge("TOPLEFT",     "BOTTOMLEFT",  false)
    edge("TOPRIGHT",    "BOTTOMRIGHT", false)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cff98FF98Settings|r")

    -- Auto-open at AH toggle (default ON).
    local ahCheck = CreateFrame("CheckButton", "StockClerkAHCheck", f, "UICheckButtonTemplate")
    ahCheck:SetPoint("TOPLEFT", 8, -32)
    ahCheck:SetSize(22, 22)
    _G[ahCheck:GetName() .. "Text"]:SetText("Auto-open at Auction House")
    _G[ahCheck:GetName() .. "Text"]:SetTextColor(0.9, 0.9, 0.9, 1)
    f._ahCheck = ahCheck

    local ahHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ahHint:SetPoint("TOPLEFT", 30, -54)
    ahHint:SetPoint("RIGHT", -8, 0)
    ahHint:SetJustifyH("LEFT")
    ahHint:SetWordWrap(true)
    ahHint:SetText("Pop the shopping list open when you visit the Auction House.")

    -- Express-Restock toggle (default OFF). Internal identifier stays
    -- StockClerkAutoRestockCheck / DB field autoRestock for compatibility.
    local arCheck = CreateFrame("CheckButton", "StockClerkAutoRestockCheck", f, "UICheckButtonTemplate")
    arCheck:SetPoint("TOPLEFT", 8, -84)
    arCheck:SetSize(22, 22)
    _G[arCheck:GetName() .. "Text"]:SetText("Express-Restock on AH open")
    _G[arCheck:GetName() .. "Text"]:SetTextColor(0.9, 0.9, 0.9, 1)
    f._autoRestockCheck = arCheck

    local arHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    arHint:SetPoint("TOPLEFT", 30, -106)
    arHint:SetPoint("RIGHT", -8, 0)
    arHint:SetJustifyH("LEFT")
    arHint:SetWordWrap(true)
    arHint:SetText("Also kick the restock loop when the AH opens (if anything is short).")

    -- --- Wire callbacks ------------------------------------------------
    ahCheck:SetScript("OnClick", function(self)
        ADDON.DB:Settings().autoOpenAtAH = self:GetChecked() and true or false
    end)
    arCheck:SetScript("OnClick", function(self)
        ADDON.DB:Settings().autoRestock = self:GetChecked() and true or false
    end)

    -- Show/Hide handlers pair up the click-catcher with the panel.
    f:SetScript("OnShow", function() catcher:Show() end)
    f:SetScript("OnHide", function() catcher:Hide() end)

    Settings.frame = f
    return f
end

-- ---------------------------------------------------------------------------
-- Public: refresh the widgets from the DB settings.
-- ---------------------------------------------------------------------------
function Settings:Refresh()
    local f = self.frame
    if not f then return end
    local s = ADDON.DB:Settings()
    f._ahCheck:SetChecked(s.autoOpenAtAH and true or false)
    if f._autoRestockCheck then
        f._autoRestockCheck:SetChecked(s.autoRestock and true or false)
    end
end

-- ---------------------------------------------------------------------------
-- Public: toggle the dropdown anchored to the given button.
-- ---------------------------------------------------------------------------
function Settings:Toggle(anchor)
    local f = self.frame or BuildDropdown(anchor)
    if f:IsShown() then
        f:Hide()
    else
        self:Refresh()
        f:Show()
    end
end

function Settings:Hide()
    if self.frame then self.frame:Hide() end
end
