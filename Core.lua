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
    -- Retail 11.2 (Ghosts of K'aresh) removed the reagent bank; personal
    -- banks are now tabs like the warband bank. Modern events:
    --   BAG_UPDATE_DELAYED                    - normal bag changes
    --   PLAYERBANKSLOTS_CHANGED               - character bank slot change
    --   PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED - warband bank slot change
    --   BANK_TABS_CHANGED                     - tab settings / purchase
    --   BANKFRAME_OPENED                      - force refresh on open
    self:RegisterBucketEvent(
        { "BAG_UPDATE_DELAYED",
          "PLAYERBANKSLOTS_CHANGED",
          "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",
          "BANK_TABS_CHANGED",
          "BANKFRAME_OPENED" },
        0.25,
        "OnInventoryChanged"
    )

    -- Auction House auto-open.
    --
    -- Retail 10.0+ consolidated frame show/hide events into the Player
    -- Interaction Manager. Auctionator's Source_Mainline path uses this
    -- rather than AUCTION_HOUSE_SHOW, and it fires more reliably. We
    -- listen for BOTH events for maximum coverage across client builds:
    --   PLAYER_INTERACTION_MANAGER_FRAME_SHOW (arg1 == Auctioneer)
    --   AUCTION_HOUSE_SHOW (fallback / legacy)
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "OnInteractionShow")
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "OnInteractionHide")
    self:RegisterEvent("AUCTION_HOUSE_SHOW",   "OnAuctionHouseShow")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", "OnAuctionHouseClosed")

    -- AH commodity search + buy events for the restock loop. AH.lua
    -- filters by in-flight itemID/mode so misfires on other addons'
    -- searches are harmless no-ops.
    self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", "OnCommoditySearchUpdated")
    self:RegisterEvent("COMMODITY_PRICE_UPDATED",          "OnCommodityPriceUpdated")
    self:RegisterEvent("COMMODITY_PRICE_UNAVAILABLE",      "OnCommodityPriceUnavailable")
    self:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED",     "OnCommodityPurchaseSucceeded")
    self:RegisterEvent("COMMODITY_PURCHASE_FAILED",        "OnCommodityPurchaseFailed")

    -- PT-4 mail-delivery gate: MAIL_INBOX_UPDATE fires when the mailbox
    -- opens and each time the inbox refreshes. RestockLoop reconciles
    -- its persisted pendingBuys ledger against actual mail contents,
    -- which is how the auto-pass gate opens after cross-session buys.
    self:RegisterEvent("MAIL_INBOX_UPDATE",                "OnMailInboxUpdate")
end

-- ---------------------------------------------------------------------------
-- Event handlers (thin — delegate to modules)
-- ---------------------------------------------------------------------------
function StockClerk:OnInventoryChanged()
    if ADDON.debug then
        print("|cff98FF98[SC:debug]|r bucket fired → Inventory:OnInventoryChanged")
    end
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

function StockClerk:OnInteractionShow(_, interactionType)
    if interactionType == Enum.PlayerInteractionType.Auctioneer then
        self:OnAuctionHouseShow()
    end
end

function StockClerk:OnInteractionHide(_, interactionType)
    if interactionType == Enum.PlayerInteractionType.Auctioneer then
        self:OnAuctionHouseClosed()
    end
end

-- ---- AH commodity events (forward to ADDON.AH state machine) --------
function StockClerk:OnCommoditySearchUpdated(_, itemID)
    if ADDON.AH then ADDON.AH:OnCommoditySearchUpdated(itemID) end
end

-- COMMODITY_PRICE_UPDATED fires with (unitPrice, totalPrice) -- NO itemID.
-- (Auctionator's Tabs/Buying/Commodity/Mixins/Main.lua confirms this:
--  `self:CheckPurchase(eventData, ...)` where eventData=unitPrice.)
-- We know which itemID we're waiting on from AH.state, so we just pass
-- the price data through.
function StockClerk:OnCommodityPriceUpdated(_, newUnitPrice, newTotalPrice)
    if ADDON.AH then ADDON.AH:OnCommodityPriceUpdated(newUnitPrice, newTotalPrice) end
end

-- These three don't carry a reliable itemID payload; AH.lua filters by
-- the currently in-flight operation.
function StockClerk:OnCommodityPriceUnavailable()
    if ADDON.AH then ADDON.AH:OnCommodityPriceUnavailable() end
end

function StockClerk:OnCommodityPurchaseSucceeded()
    if ADDON.AH then ADDON.AH:OnCommodityPurchaseSucceeded() end
end

function StockClerk:OnCommodityPurchaseFailed()
    if ADDON.AH then ADDON.AH:OnCommodityPurchaseFailed() end
end

function StockClerk:OnMailInboxUpdate()
    if ADDON.RestockLoop and ADDON.RestockLoop._OnMailInboxUpdate then
        ADDON.RestockLoop:_OnMailInboxUpdate()
    end
end

function StockClerk:OnAuctionHouseShow()
    if not ADDON.DB:Settings().autoOpenAtAH then return end

    -- The AH UI is load-on-demand; force it in so AuctionHouseFrame exists.
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
        C_AddOns.LoadAddOn("Blizzard_AuctionHouseUI")
    end

    if ADDON.MainFrame then
        ADDON.MainFrame.openedByAH = true
        ADDON.MainFrame:Show()
    end
end

function StockClerk:OnAuctionHouseClosed()
    -- Abort any in-flight AH operation before hiding UI.
    if ADDON.AH        then ADDON.AH:OnAuctionHouseClosed() end
    if ADDON.RestockLoop and ADDON.RestockLoop.IsActive and ADDON.RestockLoop:IsActive() then
        ADDON.RestockLoop:Stop("AH closed, restock loop stopped.")
    end

    -- Close on AH close only when WE opened it. If the user has since
    -- interacted with the window, leave it alone.
    if ADDON.MainFrame and ADDON.MainFrame.openedByAH then
        ADDON.MainFrame.openedByAH = false
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

    -- QA-13: `/clerk log` toggles the activity log sidecar. Also accepts
    -- `/clerk log clear` as a quick shortcut for the header "Clear" button.
    if cmd == "log" then
        local sub = (rest or ""):match("^(%S+)") or ""
        if sub:lower() == "clear" then
            if ADDON.Log and ADDON.Log.Clear then
                ADDON.Log:Clear()
                self:Print("Activity log cleared.")
                if ADDON.LogFrame and ADDON.LogFrame:IsShown() then
                    ADDON.LogFrame:Refresh()
                end
            end
        else
            if ADDON.LogFrame and ADDON.LogFrame.Toggle then
                ADDON.LogFrame:Toggle()
            end
        end
        return
    end

    -- QA-10: `/clerk auto` prints current auto-purchase state.
    -- `/clerk auto on` routes through the SAME click-to-confirm popup
    -- the settings checkbox uses (SettingsDropdown:RequestAutoEnable) --
    -- the confirmation is a hard requirement, not a GUI nicety, and the
    -- slash path previously bypassed it (code-review finding 5).
    -- `/clerk auto off` remains a one-step power-user shortcut.
    if cmd == "auto" then
        local sub = (rest or ""):match("^(%S+)") or ""
        local s = ADDON.DB:Settings()
        sub = sub:lower()
        if sub == "on" then
            if ADDON.SettingsDropdown and ADDON.SettingsDropdown.RequestAutoEnable then
                ADDON.SettingsDropdown:RequestAutoEnable()
            end
            return
        elseif sub == "off" then
            s.autoPurchase = false
            if ADDON.Log then ADDON.Log:Emit("auto_toggle", nil, { on = false }) end
            self:Print("Auto-purchase: |cffff8888OFF|r")
        else
            local budget = s.autoBudgetGold and (s.autoBudgetGold .. "g") or "not set"
            local defCapText = "none"
            if s.defaultMaxCopper and s.defaultMaxCopper > 0 then
                defCapText = (ADDON.DB.FormatCopperShort and ADDON.DB.FormatCopperShort(s.defaultMaxCopper))
                    or (("%dg"):format(math.floor(s.defaultMaxCopper / 10000)))
            end
            self:Print(("Auto-purchase: %s  \194\183  budget: %s  \194\183  default cap: %s"):format(
                s.autoPurchase and "|cff4ade80ON|r" or "|cffff8888OFF|r", budget, defCapText))
        end
        if ADDON.SettingsDropdown and ADDON.SettingsDropdown.Refresh then
            ADDON.SettingsDropdown:Refresh()
        end
        if ADDON.MainFrame and ADDON.MainFrame.Refresh then
            ADDON.MainFrame:Refresh()
        end
        return
    end

    if cmd == "help" or cmd == "?" then
        self:Print(L.HELP_TITLE)
        self:Print(L.HELP_OPEN)
        self:Print(L.HELP_SHORT)
        self:Print(L.HELP_SEED)
        self:Print(L.HELP_RESET)
        self:Print(L.HELP_DUMP)
        self:Print(L.HELP_BUDGET)
        self:Print(L.HELP_PENDING)
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
            local bd = ADDON.Inventory:GetBreakdown(it.itemID)
            local stashed = bd.bank + bd.reagent + bd.warband
            if stashed > 0 then
                self:Print(("  [%d] %s — %d / %d  (+%d elsewhere)"):format(
                    it.itemID, it.name, bd.bags, it.need, stashed))
            else
                self:Print(("  [%d] %s — %d / %d"):format(
                    it.itemID, it.name, bd.bags, it.need))
            end
        end
        return
    end

    if cmd == "debug" then
        ADDON.debug = not ADDON.debug
        self:Print("Debug: " .. (ADDON.debug and "ON" or "OFF"))
        return
    end

    -- v0.4: budget inspection + a test-only reset. The reset zeroes
    -- the current auto-spend bucket and slams resetAt to right now so
    -- the next successful auto buy starts a fresh day. Intended for
    -- verifying the reset-aware ledger without waiting for realm
    -- reset; harmless in normal use.
    if cmd == "budget" then
        local sub = (rest or ""):match("^(%S+)") or ""
        sub = sub:lower()
        local s = ADDON.DB:Settings()
        if sub == "reset" then
            if ADDON.DB.char and ADDON.DB.char.autoSpend then
                ADDON.DB.char.autoSpend.copper  = 0
                ADDON.DB.char.autoSpend.resetAt = nil
            end
            self:Print("|cff98FF98Budget reset.|r Daily auto-spend zeroed and reset clock rearmed.")
            if ADDON.SettingsDropdown and ADDON.SettingsDropdown.Refresh then
                ADDON.SettingsDropdown:Refresh()
            end
            return
        end
        -- No arg: print current status.
        local spentG  = math.floor((ADDON.DB:GetDailyAutoSpend() or 0) / 10000)
        local budgetG = s.autoBudgetGold
        local leftG   = ADDON.DB:GetDailyAutoBudgetLeft()
        leftG = leftG and math.floor(leftG / 10000) or nil
        local resetAt = ADDON.DB.GetDailyResetAt and ADDON.DB:GetDailyResetAt() or nil
        local resetTxt = "never (no auto spend yet)"
        if resetAt then
            local secs = math.max(0, resetAt - GetServerTime())
            resetTxt = ("%.1fh"):format(secs / 3600)
        end
        if budgetG then
            self:Print(("Daily auto budget: |cff98FF98%dg|r spent %dg (%dg left) · resets in %s"):format(
                budgetG, spentG, leftG or 0, resetTxt))
        else
            self:Print(("Daily auto budget: |cffff8888not set|r · %dg spent today · resets in %s"):format(
                spentG, resetTxt))
        end
        return
    end

    -- PT-4: mail-delivery ledger inspection + test-only wipe. Parallels
    -- /clerk budget: prints what's currently pending on-hand confirmation,
    -- and `clear` empties it (bypasses the auto-pass gate for testing).
    if cmd == "pending" then
        local sub = (rest or ""):match("^(%S+)") or ""
        sub = sub:lower()
        local ledger = ADDON.DB and ADDON.DB.char and ADDON.DB.char.pendingBuys or {}
        if sub == "clear" then
            if ADDON.DB and ADDON.DB.char then
                ADDON.DB.char.pendingBuys = {}
            end
            self:Print("|cff98FF98Pending ledger cleared.|r Auto-pass gate open.")
            return
        end
        -- No arg: print current pending items.
        if not next(ledger) then
            self:Print("|cff4ade80Nothing pending.|r Auto-pass gate open.")
            return
        end
        local now = GetServerTime and GetServerTime() or time()
        local rows = {}
        for id, p in pairs(ledger) do
            local nm = C_Item.GetItemInfo(id) or ("item:" .. id)
            local ageH = (p.boughtAt and ((now - p.boughtAt) / 3600)) or 0
            rows[#rows + 1] = ("%s x%d (%.1fh ago)"):format(nm, p.qty, ageH)
        end
        table.sort(rows)
        self:Print("|cffff8888Pending delivery:|r " .. table.concat(rows, ", "))
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
