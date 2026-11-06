--[[
    StockClerk - AES.lua
    atrocityEssentials (AES) carries StockClerk's restocking as its own
    Restocking. An AES build with it, switched on, does StockClerk's whole
    job: StockClerk steps aside (no windows, no automatic steps) and offers,
    at login, to turn itself off. Only reads AES's state.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local AES = {}
ADDON.AES = AES

-- An AES whose Restocking carries StockClerk's (it says so with
-- `mergedRestock`), switched on.
function AES.Merged()
    local ae = _G.atrocityEssentials
    if type(ae) ~= "table" or not ae.GetModule then return false end
    local ok, m = pcall(ae.GetModule, ae, "Restocking", true)
    local db = ok and type(m) == "table" and m.mergedRestock ~= nil and type(m.db) == "table" and m.db
    return db and db.Enabled == true or false
end

StaticPopupDialogs.STOCKCLERK_MERGED = {
    text = "atrocityEssentials' Restocking now does everything StockClerk does, and it's on.\n\nTurn StockClerk off? (The game reloads.)",
    button1 = "Turn Off StockClerk",
    button2 = "Not Now",
    OnAccept = function()
        ADDON.Log:Emit("setting", nil, { key = "turned off for AES Restocking", on = true })
        C_AddOns.DisableAddOn(addonName)
        C_UI.Reload()
    end,
    OnCancel = function() ADDON.Log:Emit("setting", nil, { key = "turned off for AES Restocking", on = false }) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function AES.Notice()
    ADDON:Print("atrocityEssentials' Restocking is on, so StockClerk is staying out of its way. Your lists are under |cffffffff/aes restock|r.")
end

-- At login: say so and offer to turn StockClerk off (every login until it is).
function AES.StepAside()
    C_Timer.After(3, function()
        AES.Notice()
        StaticPopup_Show("STOCKCLERK_MERGED")
    end)
end
