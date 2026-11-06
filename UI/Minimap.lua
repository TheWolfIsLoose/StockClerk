--[[
    StockClerk - UI/Minimap.lua
    Minimap icon through LibDBIcon, so it follows square minimaps
    (GetMinimapShape) and minimap-button collector addons.
    Settings: minimapIcon (shown), minimap (LibDBIcon's db: position, hide).
--]]

local addonName = ...
local ADDON     = _G[addonName]

local Icon = {}
ADDON.Minimap = Icon

local DBIcon = LibStub("LibDBIcon-1.0")

local launcher = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
    type = "launcher",
    icon = "Interface\\AddOns\\StockClerk\\icon.png",
    OnClick = function()
        local mf = ADDON.MainFrame
        if mf.frame and mf.frame:IsShown() then mf:Hide() else mf:Show() end
    end,
    OnTooltipShow = function(tt)
        tt:SetText("StockClerk", 1, 1, 1)
        tt:AddLine("Click to open or close. Drag to move.", 0.74, 0.74, 0.74, true)
        tt:AddLine("Hide this icon in StockClerk's settings.", 0.74, 0.74, 0.74, true)
    end,
})

-- Show or hide per the setting (Core at login, the settings checkbox on click).
function Icon:Refresh()
    local settings = ADDON.DB:Settings()
    settings.minimap.hide = not settings.minimapIcon
    if DBIcon:IsRegistered(addonName) then
        DBIcon:Refresh(addonName, settings.minimap)
    else
        DBIcon:Register(addonName, launcher, settings.minimap)
    end
end
