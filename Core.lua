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

    -- Restore the floating position if we docked to the AH. Do this
    -- BEFORE the Hide() below so if the user re-opens the main frame
    -- later it comes up where they left it, not glued to a hidden AH.
    if ADDON.MainFrame and ADDON.MainFrame._docked then
        local f = ADDON.MainFrame.frame
        local pre = ADDON.MainFrame._preDockPos
        if f and pre and pre.point then
            f:ClearAllPoints()
            f:SetPoint(pre.point, UIParent, pre.point, pre.x or 0, pre.y or 0)
        elseif f then
            -- Fall back to the saved uiPos if we lost the pre-dock snapshot
            -- (shouldn't happen, but a re-anchor beats an orphaned frame).
            local pos = ADDON.DB.char.uiPos
            f:ClearAllPoints()
            if pos and pos.point then
                f:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
            else
                f:SetPoint("CENTER")
            end
        end
        ADDON.MainFrame._docked = false
        ADDON.MainFrame._preDockPos = nil
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

    -- QA-13: `/clerk log` opens the log popup (v0.7). `/clerk log clear`
    -- is a quick shortcut for the popup's Clear Log button.
    -- LogPopup is the sole log surface as of v0.8; the retired LogFrame
    -- fallback was removed (its file was deleted from the TOC).
    if cmd == "log" then
        local sub = (rest or ""):match("^(%S+)") or ""
        if sub:lower() == "clear" then
            if ADDON.Log and ADDON.Log.Clear then
                ADDON.Log:Clear()
                self:Print("Activity log cleared.")
                if ADDON.LogPopup and ADDON.LogPopup.Refresh and ADDON.LogPopup.frame
                        and ADDON.LogPopup.frame:IsShown() then
                    ADDON.LogPopup:Refresh()
                end
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

    -- `/clerk auto` slash command removed.
    -- Was the entry point for enabling/disabling silent auto-buys, which
    -- WoW's commodity API prohibits. Restock is user-driven via the
    -- toolbar Restock button (Phase B will add a keybind).


    if cmd == "help" or cmd == "?" then
        self:Print(L.HELP_TITLE)
        self:Print(L.HELP_OPEN)
        self:Print(L.HELP_SHORT)
        self:Print(L.HELP_SEED)
        self:Print(L.HELP_RESET)
        self:Print(L.HELP_DUMP)
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

    -- `/clerk budget` removed along with
    -- the daily-auto-budget subsystem. Was daily-spend inspection +
    -- test-only reset; no analogue needed since restock is now
    -- user-driven and the user's gold is their own accounting.


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
