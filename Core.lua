--[[
    Stock Clerk - Core.lua
    Entry point: one event frame routes game events to the modules, plus the
    /clerk slash command. Modules attach to ADDON.<Name>; no libraries.
--]]

local addonName = ...
local ADDON     = _G[addonName]

-- Copper as "12g 34s 56c" (letters, not coin icons, so reskinned coin art
-- doesn't matter). precision "silver" drops copper; "gold" is whole gold with
-- thousands commas ("7,424g") from 1g up. Zero is "0g".
function ADDON.MoneyText(copper, precision)
    copper = tonumber(copper) or 0
    if copper <= 0 then return "0g" end
    if precision == "gold" and copper >= 10000 then
        return (tostring(math.floor(copper / 10000)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) .. "g"
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 and precision ~= "silver" then parts[#parts + 1] = c .. "c" end
    return #parts > 0 and table.concat(parts, " ") or "0g"
end

-- "1.2.0-beta4" for a release; "dev 7c13266" for a git checkout synced by
-- Dev\update.bat (the packager fills the .toc version, update.bat Build.lua).
function ADDON.VersionText()
    local v = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
    if v:sub(1, 1) ~= "@" then return v end
    return ADDON.build and ("dev " .. ADDON.build) or "dev"
end

function ADDON:Print(msg)
    print("|cff98ff98Stock Clerk|r: " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Events. Handler errors go to the log (so a pasted /clerk log shows them),
-- then on to the normal error handler (BugSack etc.) unchanged.
-- ponytail: only event-driven code is covered; errors raised directly in a
-- button's OnClick skip the log. Wrap those entry points too if reports show gaps.
-- ---------------------------------------------------------------------------
local function LogError(err)
    if ADDON.DB.global then
        local stack = debugstack(2, 3, 0):gsub("\n", " | "):sub(1, 400)
        ADDON.Log:Emit("error", nil, { msg = tostring(err), stack = stack })
    end
    geterrorhandler()(err)
end

local handlers = {}
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local args, n = { ... }, select("#", ...)
    xpcall(function() handlers[event](unpack(args, 1, n)) end, LogError)
end)
local function On(event, fn)
    handlers[event] = fn
    eventFrame:RegisterEvent(event)
end

-- SavedVariables are ready at our ADDON_LOADED; item and bag APIs at PLAYER_LOGIN.
On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    eventFrame:UnregisterEvent("ADDON_LOADED")
    ADDON.DB:Initialize()

    -- One log line per version change, so a report shows when an update landed.
    local g, version = ADDON.DB.global, ADDON.VersionText()
    if g.lastVersion ~= version then
        ADDON.Log:Emit("version", nil, { from = g.lastVersion, to = version })
        g.lastVersion = version
    end

    SLASH_STOCKCLERK1, SLASH_STOCKCLERK2, SLASH_STOCKCLERK3 = "/clerk", "/sc", "/stock"
    SlashCmdList.STOCKCLERK = function(msg) ADDON:OnSlashCommand(msg) end
    ADDON:Print((version:match("^%d") and "v" or "") .. version .. " loaded. Type |cff98ff98/clerk|r to open.")
end)

On("PLAYER_LOGIN", function()
    On("GET_ITEM_INFO_RECEIVED", function(itemID, success)
        ADDON.ItemResolver:OnItemInfoReceived(itemID, success)
        -- Fires for every item any addon asks about (thousands in an AH scan):
        -- repaint only for ours, and only while the window shows.
        local mf = ADDON.MainFrame
        local DB = ADDON.DB
        if (DB:GetItems()[itemID] or DB:GetItems("warband")[itemID]) and mf.frame and mf.frame:IsShown() then mf:Refresh() end
    end)

    -- Bag and bank changes, collapsed into one inventory refresh per 0.25s.
    local pending = false
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED",
                             "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "BANK_TABS_CHANGED", "BANKFRAME_OPENED" }) do
        On(event, function()
            if pending then return end
            pending = true
            C_Timer.After(0.25, function()
                pending = false
                ADDON.Inventory:OnInventoryChanged()
            end)
        end)
    end

    -- Every NPC window (AH, bank) opens and closes through the Player
    -- Interaction Manager; Auctionator uses the same events.
    local Type = Enum.PlayerInteractionType
    On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(t)
        if t == Type.Auctioneer then ADDON:OnAuctionHouseShow() elseif t == Type.Banker then ADDON:OnBankShow() end
    end)
    On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(t)
        if t == Type.Auctioneer then ADDON:OnAuctionHouseClosed() elseif t == Type.Banker then ADDON:OnBankClosed() end
    end)

    -- AH search and buy events go to AH.lua's method of the same name.
    for event, method in pairs({
        COMMODITY_SEARCH_RESULTS_UPDATED = "OnCommoditySearchUpdated",
        COMMODITY_PRICE_UPDATED          = "OnCommodityPriceUpdated",
        COMMODITY_PRICE_UNAVAILABLE      = "OnCommodityPriceUnavailable",
        COMMODITY_PURCHASE_SUCCEEDED     = "OnCommodityPurchaseSucceeded",
        COMMODITY_PURCHASE_FAILED        = "OnCommodityPurchaseFailed",
    }) do
        On(event, function(...) ADDON.AH[method](ADDON.AH, ...) end)
    end

    On("MAIL_INBOX_UPDATE", function() ADDON.RestockLoop:_OnMailInboxUpdate() end)
end)

-- ---------------------------------------------------------------------------
-- Auction House and bank. The window auto-opens when the setting is on, and
-- closes with the NPC only if it was opened that way. It docks to the AH;
-- at the bank it floats where the player left it (bag addons replace the
-- bank window). ADDON.bankOpen is the "at a banker" flag.
-- ---------------------------------------------------------------------------
function ADDON:OnAuctionHouseShow()
    local mf, settings = self.MainFrame, self.DB:Settings()
    mf:RefreshRestockBtn()
    if settings.autoOpenAtAH then
        C_AddOns.LoadAddOn("Blizzard_AuctionHouseUI")  -- load-on-demand; AuctionHouseFrame must exist
        mf.openedByAH = true
        mf:Show()  -- docks
    elseif mf.frame and mf.frame:IsShown() then
        mf:DockToAHIfOpen()
    end
    -- Express restock: start buying once the AH frame settles, if anything is short.
    if settings.autoRestock then
        C_Timer.After(0.3, function()
            local loop = self.RestockLoop
            if AuctionHouseFrame and AuctionHouseFrame:IsShown() and not loop:IsActive()
               and loop:PreviewShortfallCount() > 0 then
                loop:Start(true)
            end
        end)
    end
end

function ADDON:OnAuctionHouseClosed()
    self.AH:OnAuctionHouseClosed()
    self.RestockLoop:Stop("AH closed")
    self.RestockLoop.lastLane = nil  -- the next visit starts with your own list
    local mf = self.MainFrame
    mf:ClearMarks()  -- a restock's row marks last until you leave the AH
    mf:RefreshRestockBtn()
    mf:Undock()  -- before hiding, so a later open comes up where the player left it
    if mf.openedByAH then
        mf.openedByAH = false
        mf:Hide()
    end
end

function ADDON:OnBankShow()
    self.bankOpen = true
    local mf = self.MainFrame
    if self.DB:Settings().autoOpenAtBank and not (mf.frame and mf.frame:IsShown()) then
        mf.openedByBank = true
        mf:Show()
    end
    mf:RefreshRestockBtn()
    local n = self.BankRestock:PullableCount()
    if n > 0 and self.DB:Settings().autoRestockBank then
        -- Express restock at Bank, once the bank frame settles; the pull reports itself.
        C_Timer.After(0.3, function()
            if self.bankOpen then self.BankRestock:Start(true) end
        end)
    elseif n > 0 then
        mf:SetStatus(("%d short item%s can come from your bank."):format(n, n == 1 and "" or "s"), true)
    else
        local d = self.BankRestock:DepositableCount()
        if d > 0 then mf:SetStatus(("|cff5AA9FFWarband: deposit %d item%s.|r"):format(d, d == 1 and "" or "s"), true) end
    end
end

function ADDON:OnBankClosed()
    self.bankOpen = false
    self.BankRestock:Stop("bank closed")
    local mf = self.MainFrame
    mf:ClearMarks()
    mf:RefreshRestockBtn()
    if mf.openedByBank then
        mf.openedByBank = false
        mf:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- /clerk
-- ---------------------------------------------------------------------------
local HELP = {
    "|cff98ff98Stock Clerk|r commands:",
    "  /clerk  |cff8c8c8c— open the main window (also /sc, /stock)|r",
    "  /clerk <item ID or link> |cff8c8c8c— add an item with target 1|r",
    "  /clerk log [clear] |cff8c8c8c— open the log to copy into a bug report, or clear it|r",
    "  /clerk debug |cff8c8c8c— record detailed steps into the log until /reload|r",
    "  /clerk reset |cffff8888— wipe this character's list|r",
}

function ADDON:OnSlashCommand(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "" or cmd == "open" or cmd == "show" then
        self.MainFrame:Show()
    elseif cmd == "close" or cmd == "hide" then
        self.MainFrame:Hide()
    elseif cmd == "log" then
        if rest:lower() == "clear" then
            self.Log:Clear()
            self.Sidecar:OnActivity()
            self:Print("Activity log cleared.")
        else
            self.LogPopup:Toggle()
        end
    elseif cmd == "help" or cmd == "?" then
        for _, line in ipairs(HELP) do self:Print(line) end
    elseif cmd == "reset" then
        self.DB:ClearAll()
        self.MainFrame:Refresh()
        self:Print("This character's list has been cleared.")
    elseif cmd == "debug" then
        -- Trace steps go into the log until toggled off or /reload (never saved).
        self.debug = not self.debug
        if self.debug then
            self.Debug("debug", "detailed recording started")
            self:Print("Detailed recording |cff98ff98on|r until you /reload. Repeat the problem, then type /clerk log.")
        else
            self:Print("Detailed recording off.")
        end
    else
        -- Anything else is an item to add.
        self.ItemResolver:Resolve(msg, function(itemID, name)
            if not itemID then return self:Print("Couldn't add that: " .. tostring(name)) end
            self.DB:SetItem(itemID, 1)
            self:Print(("Added %s (id %d) with target 1. Change it in the window."):format(name, itemID))
            self.MainFrame:Refresh()
        end)
    end
end
