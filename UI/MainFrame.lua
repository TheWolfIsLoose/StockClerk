--[[
    Stock Clerk - UI/MainFrame.lua

    Native Blizzard UI. Built on PortraitFrameTemplate (the same chrome
    Bags / Collections / Character use) and the modern ScrollBox +
    ScrollView + DataProvider system introduced in Dragonflight.

    Design system (kept in one place at the top so the theme can be
    tweaked without hunting through the file):

        ROW_HEIGHT           row height in pixels
        Palette.rowBgOdd     dim base row (odd index)
        Palette.rowBgEven    slightly brighter base row (even index)
        Palette.rowBgShort   red tint overlay when have < need
        Palette.rowBgOk      subtle green tint overlay when satisfied
        Palette.hover        white overlay on mouseover
        Palette.pillOkBg / pillOkText   green "ok" pill
        Palette.pillShortBg / pillShortText  red "-N" pill

    Row shape:

        [icon] [name (item link)]                   have / need   [ ok / -N ]   [🗑]
                                                                                (trash only on hover)

    Interactions:
        - Click the "need" number     -> inline EditBox appears in place, Enter saves.
        - Hover row                   -> trash icon fades in, row highlights.
        - Click trash icon            -> removes item from DB, refreshes list.
        - Hover name / icon           -> Blizzard item tooltip.
        - Middle click name           -> chat link.

    The window is registered with UISpecialFrames so Escape closes it,
    exactly like Bags. Frame position is persisted per-character in
    ADDON.DB.char.uiPos.
--]]

local addonName = ...
local ADDON     = _G[addonName]
local L         = _G[addonName .. "_L"]

local MF = {}
ADDON.MainFrame = MF

-- ---------------------------------------------------------------------------
-- Theme
-- ---------------------------------------------------------------------------
local ROW_HEIGHT = 32
local Palette = {
    rowBgOdd      = { 0.00, 0.00, 0.00, 0.35 },
    rowBgEven     = { 1.00, 1.00, 1.00, 0.03 },
    rowBgShort    = { 0.60, 0.10, 0.10, 0.30 },
    rowBgOk       = { 0.10, 0.35, 0.15, 0.18 },
    hover         = { 1.00, 1.00, 1.00, 0.08 },
    pillOkBg      = { 0.12, 0.36, 0.20, 0.85 },
    pillOkText    = "|cff4ade80ok|r",
    pillShortBg   = { 0.36, 0.12, 0.12, 0.85 },
    -- pillShortText is built dynamically from the delta
    fontHeader    = { 1.00, 0.82, 0.00 },  -- Blizzard gold
    fontMuted     = { 0.65, 0.65, 0.65 },
}

local WHITE_TEX = "Interface\\Buttons\\WHITE8x8"
local TRASH_TEX = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"   -- red X, native asset
local QUESTION_ICON = 134400

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function ApplyBackdrop(frame, r, g, b, a)
    if not frame._bg then
        frame._bg = frame:CreateTexture(nil, "BACKGROUND")
        frame._bg:SetAllPoints(true)
        frame._bg:SetTexture(WHITE_TEX)
    end
    frame._bg:SetVertexColor(r, g, b, a)
    frame._bg:Show()
end

local function ApplyOverlay(frame, r, g, b, a)
    if not frame._overlay then
        frame._overlay = frame:CreateTexture(nil, "ARTWORK")
        frame._overlay:SetAllPoints(true)
        frame._overlay:SetTexture(WHITE_TEX)
    end
    frame._overlay:SetVertexColor(r, g, b, a)
    frame._overlay:Show()
end

local function HideOverlay(frame)
    if frame._overlay then frame._overlay:Hide() end
end

local function ShowItemTooltip(anchor, itemID)
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)

    -- Append our own storage breakdown so the user sees where the item
    -- lives across bags / bank / reagent / warband. Only lines with a
    -- non-zero count are shown, so a common-case tooltip only picks up
    -- one extra line at most.
    if ADDON.Inventory and ADDON.Inventory.GetBreakdown then
        local bd = ADDON.Inventory:GetBreakdown(itemID)
        if bd.total > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffffd200Stock Clerk|r", 1, 1, 1)
            if bd.bags    > 0 then GameTooltip:AddDoubleLine("  Bags",         tostring(bd.bags),    0.8, 0.8, 0.8, 1, 1, 1) end
            if bd.bank    > 0 then GameTooltip:AddDoubleLine("  Personal bank",tostring(bd.bank),    0.8, 0.8, 0.8, 1, 1, 1) end
            if bd.reagent > 0 then GameTooltip:AddDoubleLine("  Reagent bank", tostring(bd.reagent), 0.8, 0.8, 0.8, 1, 1, 1) end
            if bd.warband > 0 then GameTooltip:AddDoubleLine("  Warband bank", tostring(bd.warband), 0.8, 0.8, 0.8, 1, 1, 1) end
            GameTooltip:AddDoubleLine("  Total", tostring(bd.total), 1, 0.82, 0, 1, 0.82, 0)
        end
    end

    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Row template setup
--
-- Each row is a Button (so we get OnClick / OnEnter / OnLeave for free).
-- We build the child widgets once inside :Init() and reuse them as the
-- ScrollView recycles the frame across scrolls / refreshes.
-- ---------------------------------------------------------------------------
local function BuildRow(row)
    row:SetHeight(ROW_HEIGHT)

    -- Backdrop textures created lazily by ApplyBackdrop/ApplyOverlay.

    -- Icon
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim default 5% border

    -- Name
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -180, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Count "27 / 20"
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.count:SetPoint("RIGHT", row, "RIGHT", -140, 0)
    row.count:SetJustifyH("RIGHT")

    -- Inline EditBox (hidden until target number clicked)
    row.editBg = row:CreateTexture(nil, "BACKGROUND")
    row.editBg:SetTexture(WHITE_TEX)
    row.editBg:SetVertexColor(0, 0, 0, 0.6)
    row.editBg:Hide()

    row.edit = CreateFrame("EditBox", nil, row)
    row.edit:SetFontObject("GameFontHighlight")
    row.edit:SetAutoFocus(false)
    row.edit:SetNumeric(true)
    row.edit:SetMaxLetters(5)
    row.edit:SetJustifyH("CENTER")
    row.edit:SetSize(48, 20)
    row.edit:SetPoint("RIGHT", row, "RIGHT", -140, 0)
    row.editBg:SetPoint("TOPLEFT", row.edit, "TOPLEFT", -4, 2)
    row.editBg:SetPoint("BOTTOMRIGHT", row.edit, "BOTTOMRIGHT", 4, -2)
    row.edit:Hide()

    -- Status pill (ok / -N)
    row.pill = CreateFrame("Frame", nil, row)
    row.pill:SetSize(52, 20)
    row.pill:SetPoint("RIGHT", row, "RIGHT", -46, 0)
    row.pill.bg = row.pill:CreateTexture(nil, "BACKGROUND")
    row.pill.bg:SetAllPoints(true)
    row.pill.bg:SetTexture(WHITE_TEX)
    row.pill.text = row.pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.pill.text:SetPoint("CENTER")

    -- Trash button (visible on hover only).
    --
    -- Tooltip / trash-visibility model:
    --   * Both `row:OnEnter/OnLeave` and `trash:OnEnter/OnLeave` route
    --     to shared helpers (RowEnter / RowLeave). Whichever the mouse is
    --     over, the row is "hovered" and the trash + tooltip are up.
    --   * On leave, we defer one frame and check both frames' IsMouseOver.
    --     If neither is hovered, we tear the tooltip down. This survives
    --     slow exits through the GameTooltip frame (which is NOT part of
    --     the row's mouse-over region), which previously caused a stuck
    --     tooltip because trash:OnEnter had re-shown it with no matching
    --     hide path.
    row.trash = CreateFrame("Button", nil, row)
    row.trash:SetSize(18, 18)
    row.trash:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.trash:SetFrameLevel(row:GetFrameLevel() + 5)
    row.trash:SetNormalTexture(TRASH_TEX)
    row.trash:SetHighlightTexture(TRASH_TEX)
    local ht = row.trash:GetHighlightTexture()
    if ht then ht:SetBlendMode("ADD") end
    row.trash:Hide()
    row.trash:RegisterForClicks("LeftButtonUp")

    local function RowEnter(r)
        ApplyOverlay(r, unpack(Palette.hover))
        if r._itemID then ShowItemTooltip(r, r._itemID) end
        r.trash:Show()
    end

    local function RowLeave(r)
        -- Defer one frame so IsMouseOver reflects the settled state after
        -- WoW has processed all pending Enter/Leave dispatches. Then hide
        -- iff the pointer is truly off both the row and the trash button.
        C_Timer.After(0, function()
            if r:IsMouseOver() or r.trash:IsMouseOver() then
                return -- still hovering some part of the row cluster
            end
            HideOverlay(r)
            GameTooltip:Hide()
            r.trash:Hide()
        end)
    end

    row:SetScript("OnEnter",  function(self) RowEnter(self) end)
    row:SetScript("OnLeave",  function(self) RowLeave(self) end)
    row.trash:SetScript("OnEnter", function(self) RowEnter(self:GetParent()) end)
    row.trash:SetScript("OnLeave", function(self) RowLeave(self:GetParent()) end)
    row:SetScript("OnClick", function(self, mouseButton)
        -- Shift + Left Click -> paste item link into the active chat edit,
        -- matching the standard Blizzard bag/inventory behavior.
        if mouseButton == "LeftButton" and IsShiftKeyDown() and self._itemLink then
            local edit = ChatEdit_ChooseBoxForSend()
            ChatEdit_ActivateChat(edit)
            edit:Insert(self._itemLink)
            return
        end
        -- Plain Left Click while AH is open -> browse this item at the AH.
        -- Callback logs to the status bar; doesn't buy anything.
        if mouseButton == "LeftButton" and self._itemID
           and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
            local id = self._itemID
            MF:SetStatus(("Searching AH for %s..."):format(self.name:GetText() or ("item:" .. id)))
            ADDON.AH:SearchItem(id, function(ok, results)
                if not ok then
                    MF:SetStatus("|cffff8888AH search failed: " .. tostring(results) .. "|r")
                    return
                end
                local cheapest = results[1] and results[1].unitPrice
                if cheapest then
                    MF:SetStatus(("Cheapest: %s / unit (%d listings)"):format(
                        GetCoinTextureString(cheapest), #results))
                else
                    MF:SetStatus("No auctions found")
                end
            end)
        end
    end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Click the count -> inline edit target.
    -- FontStrings don't reliably take clicks; use an overlay Button instead.
    row.editHit = CreateFrame("Button", nil, row)
    row.editHit:SetPoint("TOPLEFT", row.count, "TOPLEFT", -20, 4)
    row.editHit:SetPoint("BOTTOMRIGHT", row.count, "BOTTOMRIGHT", 4, -4)
    row.editHit:SetScript("OnEnter", function(self)
        self:GetParent():GetScript("OnEnter")(self:GetParent())
        GameTooltip:Hide()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Click to edit target", 1, 1, 1)
        GameTooltip:Show()
    end)
    row.editHit:SetScript("OnLeave", function(self)
        self:GetParent():GetScript("OnLeave")(self:GetParent())
    end)
    row.editHit:SetScript("OnClick", function(self)
        local r = self:GetParent()
        r.edit:SetText(tostring(r._need or 20))
        r.edit:Show()
        r.editBg:Show()
        r.count:Hide()
        r.pill:Hide()
        r.edit:SetFocus()
        r.edit:HighlightText()
    end)

    row.edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:Hide()
        self:GetParent().editBg:Hide()
        self:GetParent().count:Show()
        self:GetParent().pill:Show()
    end)
    row.edit:SetScript("OnEnterPressed", function(self)
        local r = self:GetParent()
        local newNeed = tonumber(self:GetText())
        if newNeed and newNeed > 0 and r._itemID then
            ADDON.DB:SetItem(r._itemID, newNeed)
            r._need = newNeed
        end
        self:ClearFocus()
        self:Hide()
        r.editBg:Hide()
        r.count:Show()
        r.pill:Show()
        MF:Refresh()
    end)
end

-- ---------------------------------------------------------------------------
-- Row initializer (called by ScrollView for each visible row)
-- ---------------------------------------------------------------------------
local function InitializeRow(row, data)
    if not row._built then
        BuildRow(row)
        row._built = true
    end

    row._itemID   = data.itemID
    row._need     = data.need
    row._maxPrice = data.maxPrice

    local name, link, quality, _, _, _, _, _, _, tex = C_Item.GetItemInfo(data.itemID)
    local icon = tex or select(5, C_Item.GetItemInfoInstant(data.itemID)) or QUESTION_ICON
    row.icon:SetTexture(icon)
    row._itemLink = link
    if link then
        row.name:SetText(link)
    else
        -- Async resolve for cold items; fall back to stored name.
        row.name:SetText(data.name or ("item:" .. data.itemID))
        ADDON.ItemResolver:Resolve(data.itemID, function(id, nm, ln)
            if row._itemID == id and ln then
                row.name:SetText(ln)
                row._itemLink = ln
            end
        end)
    end

    -- The row's main count is BAGS ONLY — what the character can actually
    -- use right now. Non-bag storage (bank/reagent/warband) is folded into
    -- a dim `(+N elsewhere)` annotation appended to the count line so the
    -- user always sees where the rest of their stockpile lives without
    -- the primary metric being invariant to bag<->bank moves.
    local bd     = ADDON.Inventory:GetBreakdown(data.itemID)
    local have   = bd.bags
    local stashed = bd.bank + bd.reagent + bd.warband

    row._have      = have
    row._breakdown = bd

    local countText
    if stashed > 0 then
        countText = ("%d / %d  |cff888888(+%d)|r"):format(have, data.need, stashed)
    else
        countText = ("%d / %d"):format(have, data.need)
    end
    if data.maxPrice then
        countText = countText .. ("  |cff888888\226\137\164 %dg|r"):format(math.floor(data.maxPrice / 10000))
    end
    row.count:SetText(countText)

    if ADDON.debug then
        print(("|cff98FF98[SC:debug]|r InitializeRow: id=%d bags=%d stashed=%d need=%d"):format(
            data.itemID, have, stashed, data.need))
    end

    local short = data.need - have
    if short > 0 then
        row.pill.bg:SetVertexColor(unpack(Palette.pillShortBg))
        row.pill.text:SetText(("|cfff87171-%d|r"):format(short))
    else
        row.pill.bg:SetVertexColor(unpack(Palette.pillOkBg))
        row.pill.text:SetText(Palette.pillOkText)
    end

    -- Row background: alternate stripe, plus red / green wash by status.
    local baseR, baseG, baseB, baseA
    if data._index % 2 == 1 then
        baseR, baseG, baseB, baseA = unpack(Palette.rowBgOdd)
    else
        -- Composite: base odd + even highlight blended
        baseR, baseG, baseB, baseA = 0.05, 0.05, 0.05, 0.35
    end
    ApplyBackdrop(row, baseR, baseG, baseB, baseA)

    -- Status wash goes in the ARTWORK overlay slot; hover replaces it.
    if short > 0 then
        row._statusWash = Palette.rowBgShort
    else
        row._statusWash = Palette.rowBgOk
    end
    ApplyOverlay(row, unpack(row._statusWash))

    -- Trash click wire. Read from row._itemID rather than closing over
    -- `data`, so a recycled row can't accidentally delete a stale item.
    row.trash:SetScript("OnClick", function(self)
        local r = self:GetParent()
        local id = r and r._itemID
        if id then
            ADDON.DB:RemoveItem(id)
            ADDON.Inventory:Invalidate()
            MF:Refresh()
        end
    end)

    -- Hide inline edit if it was left showing during a refresh
    row.edit:Hide()
    row.editBg:Hide()
    row.count:Show()
    row.pill:Show()
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------
function MF:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "StockClerkFrame", UIParent, "PortraitFrameTemplate")
    f:SetSize(620, 480)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)

    -- Body background. PortraitFrameTemplate in current builds only provides
    -- the border chrome; the inner panel is transparent, so we paint an
    -- opaque dark backdrop over the frame area (inset to leave the border).
    local body = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    body:SetTexture(WHITE_TEX)
    body:SetVertexColor(0.06, 0.06, 0.08, 0.94)
    body:SetPoint("TOPLEFT", 8, -22)
    body:SetPoint("BOTTOMRIGHT", -8, 8)

    -- Title + portrait
    f:SetTitle(L.MAIN_TITLE or "Stock Clerk")
    if f.SetPortraitToAsset then
        f:SetPortraitToAsset("Interface\\ICONS\\INV_Misc_Book_11")
    end

    -- Drag by title bar
    if f.TitleContainer then
        f.TitleContainer:EnableMouse(true)
        f.TitleContainer:RegisterForDrag("LeftButton")
        f.TitleContainer:SetScript("OnDragStart", function() f:StartMoving() end)
        f.TitleContainer:SetScript("OnDragStop",  function()
            f:StopMovingOrSizing()
            local point, _, _, x, y = f:GetPoint()
            ADDON.DB.char.uiPos = { point = point, x = x, y = y }
        end)
    end

    -- Position
    local pos = ADDON.DB.char.uiPos
    if pos and pos.point then
        f:ClearAllPoints()
        f:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER")
    end

    -- Escape closes it, like Bags
    tinsert(UISpecialFrames, "StockClerkFrame")

    -- ---- Toolbar ------------------------------------------------------
    local toolbar = CreateFrame("Frame", nil, f)
    toolbar:SetHeight(52)
    toolbar:SetPoint("TOPLEFT", 12, -32)
    toolbar:SetPoint("TOPRIGHT", -12, -32)

    local addLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", 4, -4)
    addLabel:SetText(L.PROMPT_ADD_ITEM or "Enter item name or itemID")
    addLabel:SetTextColor(unpack(Palette.fontHeader))

    local addBox = CreateFrame("EditBox", nil, toolbar, "InputBoxTemplate")
    addBox:SetSize(300, 22)
    addBox:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 6, -4)
    addBox:SetAutoFocus(false)

    local countLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("TOPLEFT", addBox, "TOPRIGHT", 18, 12)
    countLabel:SetText(L.PROMPT_ADD_COUNT or "Target")
    countLabel:SetTextColor(unpack(Palette.fontHeader))

    local countBox = CreateFrame("EditBox", nil, toolbar, "InputBoxTemplate")
    countBox:SetSize(50, 22)
    countBox:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", 6, -4)
    countBox:SetAutoFocus(false)
    countBox:SetNumeric(true)
    countBox:SetMaxLetters(5)
    countBox:SetText("20")

    -- Per-item max price (gold). Copper units in DB; multiply by 10000 on
    -- write. Blank/0 means "no cap".
    local priceLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceLabel:SetPoint("TOPLEFT", countBox, "TOPRIGHT", 12, 12)
    priceLabel:SetText("Max g/unit")
    priceLabel:SetTextColor(unpack(Palette.fontHeader))

    local priceBox = CreateFrame("EditBox", nil, toolbar, "InputBoxTemplate")
    priceBox:SetSize(60, 22)
    priceBox:SetPoint("TOPLEFT", priceLabel, "BOTTOMLEFT", 6, -4)
    priceBox:SetAutoFocus(false)
    priceBox:SetNumeric(true)
    priceBox:SetMaxLetters(7)
    priceBox:SetText("")

    local addBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    addBtn:SetSize(100, 24)
    addBtn:SetPoint("LEFT", priceBox, "RIGHT", 12, 0)
    addBtn:SetText(L.BTN_ADD_ITEM or "Add Item")

    local function DoAdd()
        local input = addBox:GetText()
        if not input or input == "" then return end
        local need = tonumber(countBox:GetText()) or 20
        local priceGold = tonumber(priceBox:GetText())
        local maxPriceCopper = (priceGold and priceGold > 0) and (priceGold * 10000) or nil
        ADDON.ItemResolver:Resolve(input, function(itemID, name, _)
            if not itemID then
                MF:SetStatus("|cffff8888" .. tostring(name) .. "|r")
                return
            end
            ADDON.DB:SetItem(itemID, need, maxPriceCopper)
            ADDON.Inventory:Invalidate()
            addBox:SetText("")
            priceBox:SetText("")
            local pMsg = maxPriceCopper and (", cap %dg"):format(priceGold) or ""
            MF:SetStatus(("Added %s (need %d%s)"):format(name, need, pMsg))
            MF:Refresh()
        end)
    end
    addBtn:SetScript("OnClick", DoAdd)
    addBox:SetScript("OnEnterPressed", function() DoAdd() addBox:ClearFocus() end)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    countBox:SetScript("OnEnterPressed", function() DoAdd() addBox:ClearFocus() end)
    countBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    priceBox:SetScript("OnEnterPressed", function() DoAdd() addBox:ClearFocus() end)
    priceBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Separator under toolbar
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(WHITE_TEX)
    sep:SetVertexColor(1, 0.82, 0, 0.35)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -4)
    sep:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -4)

    -- One-line hint under the separator so the user isn't guessing the
    -- interaction model. Keep it terse; the tooltip carries the rest.
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 4, -4)
    hint:SetPoint("TOPRIGHT", sep, "BOTTOMRIGHT", -4, -4)
    hint:SetJustifyH("LEFT")
    hint:SetText("|cff888888Shift+Click a row to link \194\183 Click 'x' to remove \194\183 Click the target to edit \194\183 Restock at AH to buy|r")

    -- ---- Status bar (bottom) -----------------------------------------
    local statusBar = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusBar:SetPoint("BOTTOMLEFT", 14, 12)
    statusBar:SetPoint("BOTTOMRIGHT", -14, 12)
    statusBar:SetJustifyH("LEFT")
    self.statusBar = statusBar

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", -14, 8)
    closeBtn:SetText(L.BTN_CLOSE or "Close")
    closeBtn:SetScript("OnClick", function() MF:Hide() end)

    -- Restock at AH. Enabled only while the AH frame is shown. Text
    -- toggles between "Restock at AH" and "Stop" based on loop state.
    local restockBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    restockBtn:SetSize(140, 22)
    restockBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    restockBtn:SetText("Restock at AH")
    restockBtn:SetScript("OnClick", function()
        if ADDON.RestockLoop:IsActive() then
            ADDON.RestockLoop:Stop("Restock loop stopped.")
        else
            ADDON.RestockLoop:Start()
        end
    end)
    self.restockBtn = restockBtn

    -- Refresh the button state whenever the frame is shown (RefreshRestockBtn
    -- is also called from Refresh() when the shortlist changes).
    f:HookScript("OnShow", function() MF:RefreshRestockBtn() end)

    -- ---- ScrollBox (list of rows) ------------------------------------
    local listHolder = CreateFrame("Frame", nil, f)
    listHolder:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -4, -6)
    listHolder:SetPoint("BOTTOMRIGHT", closeBtn, "TOPRIGHT", 0, 8)

    local scrollBox = CreateFrame("Frame", nil, listHolder, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT")
    scrollBox:SetPoint("BOTTOMRIGHT", -18, 0)

    local scrollBar = CreateFrame("EventFrame", nil, listHolder, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT",     scrollBox, "TOPRIGHT",    2, 0)
    scrollBar:SetPoint("BOTTOMLEFT",  scrollBox, "BOTTOMRIGHT", 2, 0)

    -- Order matters: current builds validate that the element factory is
    -- set before a DataProvider is attached, otherwise SetDataProvider
    -- errors out with "elementFactory was nil". Configure the view first,
    -- initialize with the scroll bar, then hand off the DataProvider.
    local scrollView = CreateScrollBoxListLinearView()
    scrollView:SetElementInitializer("Button", InitializeRow)
    scrollView:SetElementExtent(ROW_HEIGHT)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, scrollView)

    local dataProvider = CreateDataProvider()
    scrollView:SetDataProvider(dataProvider)

    self.frame        = f
    self.scrollBox    = scrollBox
    self.scrollView   = scrollView
    self.dataProvider = dataProvider

    -- Empty-state text (hidden by default)
    self.emptyText = listHolder:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    self.emptyText:SetPoint("CENTER")
    self.emptyText:SetText(L.EMPTY_LIST or "No items tracked. Add one above.")
    self.emptyText:Hide()

    return f
end

-- ---------------------------------------------------------------------------
-- Refresh: rebuild the DataProvider from ADDON.DB.
-- Follows the Auctionator pattern of replacing the DataProvider each
-- refresh (see Source/Components/ResultsListing/Mixins/ResultsListing.lua).
-- Flushing + re-inserting can leave the ScrollView reusing frames without
-- re-invoking the row initializer, which causes stale counts.
-- ---------------------------------------------------------------------------
function MF:Refresh()
    if not self.frame or not self.scrollBox then return end

    if ADDON.debug then
        print("|cff98FF98[SC:debug]|r MainFrame:Refresh() called (frame shown: " .. tostring(self.frame:IsShown()) .. ")")
    end

    local items = ADDON.DB:GetSortedItems()

    if #items == 0 then
        -- Empty provider still needs to be swapped in so any prior rows
        -- are cleared out.
        local emptyProvider = CreateDataProvider()
        self.scrollBox:SetDataProvider(emptyProvider, ScrollBoxConstants.RetainScrollPosition)
        self.dataProvider = emptyProvider
        self.emptyText:Show()
        self:SetStatus("0 items tracked")
        return
    end
    self.emptyText:Hide()

    local newProvider = CreateDataProvider()
    local shortCount = 0
    for i, it in ipairs(items) do
        -- GetCount returns bags-only, matching what the row displays.
        -- Shortfall is thus "my bags are below target", not "my total
        -- across everything is below target" — aligned with the metric
        -- shown to the user.
        local have = ADDON.Inventory:GetCount(it.itemID) or 0
        if have < it.need then shortCount = shortCount + 1 end
        newProvider:Insert({
            itemID   = it.itemID,
            name     = it.name,
            need     = it.need,
            maxPrice = it.maxPrice,
            _index   = i,
        })
    end

    -- Swap the provider. Passing RetainScrollPosition keeps the user's
    -- scroll offset stable across refreshes so restocking updates don't
    -- yank the list back to the top.
    self.scrollBox:SetDataProvider(newProvider, ScrollBoxConstants.RetainScrollPosition)
    self.dataProvider = newProvider

    if shortCount > 0 then
        self:SetStatus(("|cffffd200%d items tracked|r  |cff888888|||r  |cfff87171%d short|r"):format(#items, shortCount))
    else
        self:SetStatus(("|cffffd200%d items tracked|r  |cff888888|||r  |cff4ade80all stocked|r"):format(#items))
    end

    self:RefreshRestockBtn(shortCount)
end

-- Enable the Restock button only when the AH is open AND we have at least
-- one shortfall item to restock. The loop itself handles empty queues and
-- caps -- this is just first-line UX so the button doesn't look clickable
-- when it can't do anything.
function MF:RefreshRestockBtn(shortCount)
    if not self.restockBtn then return end
    if shortCount == nil then
        shortCount = 0
        for _, it in ipairs(ADDON.DB:GetSortedItems()) do
            local have = ADDON.Inventory:GetCount(it.itemID) or 0
            if have < it.need then shortCount = shortCount + 1 end
        end
    end
    local ahOpen = AuctionHouseFrame and AuctionHouseFrame:IsShown()
    local looping = ADDON.RestockLoop and ADDON.RestockLoop:IsActive()
    if looping then
        self.restockBtn:SetText("Stop restock")
        self.restockBtn:Enable()
    else
        self.restockBtn:SetText("Restock at AH")
        if ahOpen and shortCount > 0 then
            self.restockBtn:Enable()
        else
            self.restockBtn:Disable()
        end
    end
end

function MF:SetStatus(text)
    if self.statusBar then self.statusBar:SetText(text or "") end
end

-- ---------------------------------------------------------------------------
-- Show / Hide
-- ---------------------------------------------------------------------------
-- Show accepts an optional `fromAH` argument. Only overwrite openedByAH
-- when the caller explicitly tells us where the show came from -- calling
-- Show() with no arg (e.g. from a slash command or a Refresh after add)
-- must not clobber a flag Core.lua just set on our behalf.
function MF:Show(fromAH)
    self:Build()
    if fromAH ~= nil then
        self.openedByAH = fromAH and true or false
    end
    self.frame:Show()
    self:Refresh()
end

function MF:Hide()
    if self.frame then self.frame:Hide() end
end

function MF:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show(false)
    end
end
