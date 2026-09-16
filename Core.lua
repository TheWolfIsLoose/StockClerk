--[[
    Stock Clerk - Core.lua
    Addon entry point. Creates the AceAddon object, registers slash
    commands, and routes game events to the appropriate module.

    Load order (from TOC): Locale -> DB -> ItemResolver -> Inventory -> Core.
    Modules attach themselves to ADDON.<Name>; Core wires them together
    here without any module needing to know about the others.
--]]

local addonName = ...
local ADDON     = _G[addonName]
local L         = _G[addonName .. "_L"]

-- Create the AceAddon object with the mixins we need.
-- AceConsole gives us self:RegisterChatCommand and self:Print.
-- AceEvent gives us self:RegisterEvent.
-- AceBucket lets us collapse noisy events (BAG_UPDATE fires per-bag).
local StockClerk = LibStub("AceAddon-3.0"):NewAddon(
    ADDON, addonName, "AceConsole-3.0", "AceEvent-3.0", "AceBucket-3.0"
)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function StockClerk:OnInitialize()
    -- Databases first — anything else may want to read from them.
    ADDON.DB:Initialize()

    -- Slash commands. All three route to the same handler.
    self:RegisterChatCommand("clerk", "OnSlashCommand")
    self:RegisterChatCommand("sc",    "OnSlashCommand")
    self:RegisterChatCommand("stock", "OnSlashCommand")

    self:Print(L.ADDON_NAME .. " loaded. Type |cffffff00/clerk|r to open.")
end

function StockClerk:OnEnable()
    -- Item cache resolution — bounces through ItemResolver:OnItemInfoReceived.
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemInfoReceived")

    -- Inventory invalidation. AceBucket collapses bursts into one call.
    self:RegisterBucketEvent(
        { "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED",
          "PLAYERREAGENTBANKSLOTS_CHANGED" },
        0.25,
        "OnInventoryChanged"
    )

    -- Auction House auto-open. AUCTION_HOUSE_SHOW fires when the AH UI opens.
    self:RegisterEvent("AUCTION_HOUSE_SHOW",  "OnAuctionHouseShow")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", "OnAuctionHouseClosed")
end

-- ---------------------------------------------------------------------------
-- Event handlers (thin — delegate to modules)
-- ---------------------------------------------------------------------------
function StockClerk:OnInventoryChanged()
    ADDON.Inventory:OnInventoryChanged()
end

function StockClerk:OnItemInfoReceived(_, itemID, success)
    ADDON.ItemResolver:OnItemInfoReceived(itemID, success)
    -- A newly-cached item may have appeared in our list; refresh the UI
    -- if the window is currently open (frame is non-nil while shown).
    if ADDON.MainFrame and ADDON.MainFrame.frame then
        ADDON.MainFrame:Refresh()
    end
end

function StockClerk:OnAuctionHouseShow()
    if not ADDON.DB:Settings().autoOpenAtAH then return end
    if ADDON.MainFrame then ADDON.MainFrame:Show() end
end

function StockClerk:OnAuctionHouseClosed()
    -- Optional: close on AH close so we don't leave a floating window.
    -- If the user has interacted with it since AH opened, leave it alone.
    if ADDON.MainFrame and ADDON.MainFrame.openedByAH then
        ADDON.MainFrame:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Slash command router
-- ---------------------------------------------------------------------------
function StockClerk:OnSlashCommand(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$") -- trim
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "" or cmd == "open" or cmd == "show" then
        if ADDON.MainFrame then ADDON.MainFrame:Show() end
        return
    end

    if cmd == "close" or cmd == "hide" then
        if ADDON.MainFrame then ADDON.MainFrame:Hide() end
        return
    end

    if cmd == "help" or cmd == "?" then
        self:Print(L.HELP_TITLE)
        self:Print(L.HELP_OPEN)
        self:Print(L.HELP_SHORT)
        self:Print(L.HELP_SEED)
        self:Print(L.HELP_RESET)
        self:Print(L.HELP_DUMP)
        return
    end

    if cmd == "reset" then
        ADDON.DB:ClearAll()
        ADDON.Inventory:Invalidate()
        if ADDON.MainFrame then ADDON.MainFrame:Refresh() end
        self:Print("This character's list has been cleared.")
        return
    end

    if cmd == "dump" then
        local sorted = ADDON.DB:GetSortedItems()
        if #sorted == 0 then
            self:Print("List is empty.")
            return
        end
        self:Print(("Tracking %d items:"):format(#sorted))
        for _, it in ipairs(sorted) do
            local have = ADDON.Inventory:GetCount(it.itemID)
            self:Print(("  [%d] %s — %d / %d"):format(
                it.itemID, it.name, have, it.need))
        end
        return
    end

    if cmd == "seed" then
        if ADDON.RecommendedLists and ADDON.RecommendedLists.Apply then
            local added, categories = ADDON.RecommendedLists:Apply()
            self:Print(L.SEED_APPLIED:format(added, categories))
            if ADDON.MainFrame then ADDON.MainFrame:Refresh() end
        else
            self:Print("Recommended lists module not loaded (release build strips it).")
        end
        return
    end

    -- Fallback: assume the argument is an item to add.
    if cmd ~= "" then
        local input = msg
        ADDON.ItemResolver:Resolve(input, function(itemID, name, _)
            if not itemID then
                self:Print("Couldn't resolve: " .. tostring(name)) -- name holds err msg on fail
                return
            end
            ADDON.DB:SetItem(itemID, 20) -- sensible default
            self:Print(("Added %s (id %d) with target 20. Edit in the UI to change."):format(name, itemID))
            if ADDON.MainFrame then ADDON.MainFrame:Refresh() end
        end)
        return
    end
end
