--[[
    StockClerk - UI/Minimap.lua
    Minimap icon: click toggles the window, drag moves it around the rim.
    Settings: minimapIcon (shown), minimapAngle (degrees, 0 = east).
    ponytail: positions on a round minimap only; embed LibDBIcon if players
    with square minimaps or button-collector addons ask for it.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local Icon = {}
ADDON.Minimap = Icon

local function Place(b, angle)
    local r, a = Minimap:GetWidth() / 2 + 5, math.rad(angle)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function Build()
    local b = CreateFrame("Button", "StockClerkMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\StockClerk\\icon.png")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(50, 50)
    ring:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function()
        local mf = ADDON.MainFrame
        if mf.frame and mf.frame:IsShown() then mf:Hide() else mf:Show() end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("StockClerk", 1, 1, 1)
        GameTooltip:AddLine("Click to open or close. Drag to move.", 0.74, 0.74, 0.74, true)
        GameTooltip:AddLine("Hide this icon in StockClerk's settings.", 0.74, 0.74, 0.74, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            local angle = math.deg(math.atan2(py / s - my, px / s - mx))
            ADDON.DB:Settings().minimapAngle = angle
            Place(self, angle)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    Icon.button = b
    return b
end

-- Show or hide per the setting (Core at login, the settings checkbox on click).
function Icon:Refresh()
    local settings = ADDON.DB:Settings()
    if not settings.minimapIcon then
        if self.button then self.button:Hide() end
        return
    end
    local b = self.button or Build()
    Place(b, settings.minimapAngle)
    b:Show()
end
