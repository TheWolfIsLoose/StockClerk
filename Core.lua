--[[
    Stock Clerk - Core.lua
    Addon entry point. Registers slash commands and routes game events
    to the appropriate module. No libraries: one event frame + SlashCmdList.

    Load order (from TOC): Locale -> DB -> ItemResolver -> Inventory -> Core.
    Modules attach themselves to ADDON.<Name>; Core wires them together
    here without any module needing to know about the others.
--]]

local addonName = ...
local ADDON     = _G[addonName]
local L         = _G[addonName .. "_L"]

-- ---------------------------------------------------------------------------
-- ADDON-wide money helper. Renders copper as compact "#g #s #c" text using
-- letter suffixes instead of Blizzard's coin-icon textures, so users who
-- swap those textures out with alternative art still see consistent price
-- rendering inside SC. Lives in Core (early in load order) so every module
-- can call ADDON.MoneyText(copper) without a nil-guard.
--
-- precision:
--   "gold"   -> rounds to whole gold, e.g. "1219g"
--   "silver" -> shows silver when non-zero, drops copper, e.g. "1219g 80s"
--   "copper" -> full precision, e.g. "1219g 80s 66c" (default)
-- Zero always returns "0g"; sub-gold amounts drop the leading 0g so
-- "12s 34c" doesn't read as "0g 12s 34c".
-- ---------------------------------------------------------------------------
function ADDON.MoneyText(copper, precision)
    copper = tonumber(copper) or 0
    if copper <= 0 then return "0g" end
    precision = precision or "copper"
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if precision == "gold" then
        return ("%dg"):format(g)
    end
    local parts = {}
    if g > 0 then parts[#parts + 1] = ("%dg"):format(g) end
    if s > 0 then parts[#parts + 1] = ("%ds"):format(s) end
    if precision == "copper" and c > 0 then
        parts[#parts + 1] = ("%dc"):format(c)
    end
    if #parts == 0 then return "0g" end
    return table.concat(parts, " ")
end

local StockClerk = ADDON

function ADDON:Print(msg)
    print("|cff33ff99StockClerk|r: " .. tostring(msg))
end

-- One frame dispatches every game event to its handler: fn(...) gets the
-- event payload (the event name itself is dropped).
local handlers = {}
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)
local function On(event, fn)
    handlers[event] = fn
    eventFrame:RegisterEvent(event)
end

-- ---------------------------------------------------------------------------
-- Lifecycle: SavedVariables are ready at our ADDON_LOADED; the world (and
-- item/bag APIs) at PLAYER_LOGIN.
-- ---------------------------------------------------------------------------
On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    eventFrame:UnregisterEvent("ADDON_LOADED")
    ADDON.DB:Initialize()

    SLASH_STOCKCLERK1, SLASH_STOCKCLERK2, SLASH_STOCKCLERK3 = "/clerk", "/sc", "/stock"
    SlashCmdList.STOCKCLERK = function(msg) StockClerk:OnSlashCommand(msg) end

    StockClerk:Print(L.ADDON_NAME .. " loaded. Type |cffffff00/clerk|r to open.")
end)

On("PLAYER_LOGIN", function()
    -- Item cache resolution -- bounces through ItemResolver:OnItemInfoReceived.
    On("GET_ITEM_INFO_RECEIVED", function(...) StockClerk:OnItemInfoReceived(...) end)

    -- Inventory invalidation, debounced 0.25s so bursts collapse into one call.
    -- Retail 11.2 (Ghosts of K'aresh) removed the reagent bank; personal
    -- banks are now tabs like the warband bank. Modern events:
    --   BAG_UPDATE_DELAYED                    - normal bag changes
    --   PLAYERBANKSLOTS_CHANGED               - character bank slot change
    --   PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED - warband bank slot change
    --   BANK_TABS_CHANGED                     - tab settings / purchase
    --   BANKFRAME_OPENED                      - force refresh on open
    local invPending = false
    local function flushInventory()
        invPending = false
        ADDON.Debug("debug", "inventory debounce fired")
        ADDON.Inventory:OnInventoryChanged()
    end
    for _, event in ipairs({
        "BAG_UPDATE_DELAYED",
        "PLAYERBANKSLOTS_CHANGED",
        "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",
        "BANK_TABS_CHANGED",
        "BANKFRAME_OPENED",
    }) do
        On(event, function()
            if invPending then return end
            invPending = true
            C_Timer.After(0.25, flushInventory)
        end)
    end

    -- Auction House auto-open.
    --
    -- Retail 10.0+ consolidated frame show/hide events into the Player
    -- Interaction Manager. Auctionator's Source_Mainline path uses this
    -- rather than AUCTION_HOUSE_SHOW, and it fires more reliably. We
    -- listen for BOTH events for maximum coverage across client builds:
    --   PLAYER_INTERACTION_MANAGER_FRAME_SHOW (arg1 == Auctioneer)
    --   AUCTION_HOUSE_SHOW (fallback / legacy)
    On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(t) StockClerk:OnInteractionShow(t) end)
    On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(t) StockClerk:OnInteractionHide(t) end)
    On("AUCTION_HOUSE_SHOW",   function() StockClerk:OnAuctionHouseShow() end)
    On("AUCTION_HOUSE_CLOSED", function() StockClerk:OnAuctionHouseClosed() end)

    -- AH commodity search + buy events go straight to AH.lua's handler of
    -- the same name (event payload passed through). AH.lua filters by
    -- in-flight itemID/mode, so other addons' searches are harmless no-ops.
    -- COMMODITY_PRICE_UPDATED carries (unitPrice, totalPrice), no itemID.
    for event, method in pairs({
        COMMODITY_SEARCH_RESULTS_UPDATED = "OnCommoditySearchUpdated",
        COMMODITY_PRICE_UPDATED          = "OnCommodityPriceUpdated",
        COMMODITY_PRICE_UNAVAILABLE      = "OnCommodityPriceUnavailable",
        COMMODITY_PURCHASE_SUCCEEDED     = "OnCommodityPurchaseSucceeded",
        COMMODITY_PURCHASE_FAILED        = "OnCommodityPurchaseFailed",
    }) do
        On(event, function(...) ADDON.AH[method](ADDON.AH, ...) end)
    end

    -- Mail-delivery gate: RestockLoop reconciles its persisted
    -- pendingBuys ledger against actual mail contents on each inbox refresh.
    On("MAIL_INBOX_UPDATE", function() ADDON.RestockLoop:_OnMailInboxUpdate() end)
end)

-- ---------------------------------------------------------------------------
-- Event handlers (thin — delegate to modules)
-- ---------------------------------------------------------------------------
function StockClerk:OnItemInfoReceived(itemID, success)
    ADDON.ItemResolver:OnItemInfoReceived(itemID, success)
    -- This event fires for every item any addon asks about (thousands
    -- during an AH scan). Repaint only when it's one of ours and the
    -- window is showing; MF:Show() refreshes on open anyway.
    local mf = ADDON.MainFrame
    if ADDON.DB:GetItems()[itemID] and mf.frame and mf.frame:IsShown() then
        mf:Refresh()
    end
end

-- Banker (8) is what the 12.1 bank probe saw for both the character and
-- warband bank.
function StockClerk:OnInteractionShow(interactionType)
    if interactionType == Enum.PlayerInteractionType.Auctioneer then
        self:OnAuctionHouseShow()
    elseif interactionType == Enum.PlayerInteractionType.Banker then
        self:OnBankShow()
    end
end

function StockClerk:OnInteractionHide(interactionType)
    if interactionType == Enum.PlayerInteractionType.Auctioneer then
        self:OnAuctionHouseClosed()
    elseif interactionType == Enum.PlayerInteractionType.Banker then
        self:OnBankClosed()
    end
end

function StockClerk:OnAuctionHouseShow()
    -- Refresh the restock button state -- ahOpen is now true, so the
    -- button should paint enabled if there's a shortfall. Independent
    -- of the auto-open setting (button state matters even when SC is
    -- already open on the user's schedule).
    if ADDON.MainFrame and ADDON.MainFrame.RefreshRestockBtn then
        ADDON.MainFrame:RefreshRestockBtn()
    end

    -- Auto-open the SC main frame if the user opted in.
    if ADDON.DB:Settings().autoOpenAtAH then
        -- The AH UI is load-on-demand; force it in so AuctionHouseFrame exists.
        if not C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
            C_AddOns.LoadAddOn("Blizzard_AuctionHouseUI")
        end
        if ADDON.MainFrame then
            ADDON.MainFrame.openedByAH = true
            ADDON.MainFrame:Show()
            if ADDON.MainFrame.DockToAHIfOpen then
                ADDON.MainFrame:DockToAHIfOpen()
            end
        end
    else
        -- SC didn't auto-open, but if the user opened it manually already,
        -- dock it now so it snaps to the AH edge the same as auto-open does.
        if ADDON.MainFrame and ADDON.MainFrame.frame
           and ADDON.MainFrame.frame:IsShown()
           and ADDON.MainFrame.DockToAHIfOpen then
            ADDON.MainFrame:DockToAHIfOpen()
        end
    end

    -- Auto-restock: opt-in trigger for the restock loop on AH open. Fires
    -- only when there's a shortfall to work through -- opening the AH with
    -- everything stocked shouldn't kick off an empty loop that immediately
    -- terminates. Small delay lets the AH frame settle before the search
    -- query goes out.
    if ADDON.DB:Settings().autoRestock then
        C_Timer.After(0.3, function()
            if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
            if not ADDON.RestockLoop then return end
            if ADDON.RestockLoop:IsActive() then return end
            -- Use Loop:PreviewShortfallCount so this decision uses the SAME
            -- shortfall math as Loop:BuildQueue -- _EffectiveHave, which
            -- counts bags + unlooted purchase ledger. Two different calcs
            -- previously drifted (Core used raw bags, Loop used effective),
            -- which is how the phantom-restock bug crept in: Core said
            -- "1 short" from stale ledger, Loop's BuildQueue found the
            -- same 1 short, and it fired despite the user having looted
            -- the mail. Same math both sides = same verdict.
            local shortCount = ADDON.RestockLoop:PreviewShortfallCount()
            if shortCount > 0 then
                ADDON.RestockLoop:Start()
            end
        end)
    end
end

function StockClerk:OnAuctionHouseClosed()
    -- Abort any in-flight AH operation before hiding UI.
    if ADDON.AH        then ADDON.AH:OnAuctionHouseClosed() end
    if ADDON.RestockLoop and ADDON.RestockLoop.IsActive and ADDON.RestockLoop:IsActive() then
        ADDON.RestockLoop:Stop("AH closed")
    end
    if ADDON.MainFrame and ADDON.MainFrame.RefreshRestockBtn then
        ADDON.MainFrame:RefreshRestockBtn()
    end

    -- Undock BEFORE hiding so a later reopen comes up where the user left
    -- it; close only when WE opened it.
    local mf = ADDON.MainFrame
    if mf then
        mf:Undock()
        if mf.openedByAH then
            mf.openedByAH = false
            mf:Hide()
        end
    end
end

-- Bank: same auto-open/dock/close pattern as the AH. ADDON.bankOpen is
-- the source of truth for "at a banker" (Restock from Bank, v1.2).
function StockClerk:OnBankShow()
    ADDON.bankOpen = true
    local mf = ADDON.MainFrame
    if not mf then return end
    if ADDON.DB:Settings().autoOpenAtBank and not (mf.frame and mf.frame:IsShown()) then
        mf.openedByBank = true
        mf:Show()
    end
    -- BankFrame shows in the same event burst; dock on the next frame.
    C_Timer.After(0, function() mf:DockTo(_G.BankFrame) end)
end

function StockClerk:OnBankClosed()
    ADDON.bankOpen = false
    local mf = ADDON.MainFrame
    if not mf then return end
    mf:Undock()
    if mf.openedByBank then
        mf.openedByBank = false
        mf:Hide()
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

    -- `/clerk log` opens the log popup; `/clerk log clear` empties the log.
    if cmd == "log" then
        local sub = (rest or ""):match("^(%S+)") or ""
        if sub:lower() == "clear" then
            if ADDON.Log and ADDON.Log.Clear then
                ADDON.Log:Clear()
                self:Print("Activity log cleared.")
                if ADDON.Sidecar and ADDON.Sidecar:IsShown() then
                    ADDON.Sidecar:Refresh()
                end
            end
        else
            if ADDON.LogPopup and ADDON.LogPopup.Toggle then
                ADDON.LogPopup:Toggle()
            end
        end
        return
    end

    if cmd == "help" or cmd == "?" then
        for _, key in ipairs({ "HELP_TITLE", "HELP_OPEN", "HELP_SHORT", "HELP_ADD", "HELP_LOG",
                               "HELP_PENDING", "HELP_DUMP", "HELP_RESET", "HELP_DEBUG" }) do
            self:Print(L[key])
        end
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
            local stashed = bd.bank + bd.warband
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

    -- Mail-delivery ledger inspection; `clear` empties it (bypasses the
    -- auto-pass gate for testing).
    if cmd == "pending" then
        local sub = (rest or ""):match("^(%S+)") or ""
        sub = sub:lower()
        local ledger = ADDON.DB and ADDON.DB.char and ADDON.DB.char.pendingBuys or {}
        if sub == "clear" then
            if ADDON.DB and ADDON.DB.char then
                ADDON.DB.char.pendingBuys = {}
            end
            self:Print("|cff98FF98Pending ledger cleared.|r Mail-in-flight tracking reset.")
            return
        end
        -- No arg: print current pending items.
        if not next(ledger) then
            self:Print("|cff4ade80Nothing pending.|r Mail-in-flight ledger is empty.")
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

    -- Fallback: assume the argument is an item to add.
    if cmd ~= "" then
        local input = msg
        ADDON.ItemResolver:Resolve(input, function(itemID, name, _)
            if not itemID then
                self:Print("Couldn't resolve: " .. tostring(name)) -- name holds err msg on fail
                return
            end
            -- Default target 1 (matches the toolbar Add-cluster default).
            ADDON.DB:SetItem(itemID, 1)
            self:Print(("Added %s (id %d) with target 1. Edit in the UI to change."):format(name, itemID))
            if ADDON.MainFrame then ADDON.MainFrame:Refresh() end
        end)
        return
    end
end
