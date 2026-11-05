--[[
    StockClerk - AES/Adapter.lua
    When atrocityEssentials (AES) is loaded, StockClerk folds into it: its
    settings and lists become a "StockClerk" tab on AES's Utilities page,
    and the on-screen window becomes AES/Panel.lua in AES's look. Without
    AES, nothing here runs and StockClerk is its usual self.

    Everything AES-specific goes through this file and Panel.lua. AES has no
    public plugin API; we use what its options addon itself reaches through
    atrocityEssentials.NS. If any piece we rely on is missing (a new AES
    build moved it), StockClerk says so once and falls back to its own
    window, so a break never looks like an AES error.

    AES loads first (OptionalDeps), so it's settled when this file runs.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local A = {}
ADDON.AESMode = A

local AE  -- atrocityEssentials.NS
-- Utilities, not Automation: Automation hides all its tabs while its own
-- master switch is off, which would hide ours too.
local PAGE, TAB, BUILDER = "Utilities", "stockclerk", "SC_AESTab"

-- What we use from AES at load; the options window is checked when it loads.
local function Usable()
    local addon = _G.atrocityEssentials
    local ns = type(addon) == "table" and addon.NS
    if not (ns and ns.Theme and ns.Skins and ns.ApplyThemeFont and ns.WithOptions
            and ns.CreatePrompt and ns.PaintPulseBorder and ns.StopPulseBorder) then return end
    return ns
end

-- Back to our own window for the rest of the session.
function A:Fallback(why)
    if not ADDON.aesMode then return end
    ADDON.aesMode = false
    ADDON.UI = ADDON.MainFrame
    if ADDON.AESPanel.frame then ADDON.AESPanel.frame:Hide() end
    ADDON.Log:Emit("error", nil, { msg = "AES mode off: " .. tostring(why) })
    ADDON:Print("Couldn't fit into this version of atrocityEssentials, so StockClerk is using its own window. Type |cffffffff/clerk|r to open it.")
end

function A:OpenSettings()
    AE:WithOptions(function()
        local G = AE.GUIFrame
        G.tabbedPageState = G.tabbedPageState or {}
        G.tabbedPageState[PAGE] = TAB
        G:OpenPage(PAGE)
    end)
end

-- ===========================================================================
-- The tab
-- ===========================================================================
local G, Theme  -- AE.GUIFrame, AE.Theme (set in Register)
local ROW_H = 24
local floor = math.floor

local function Settings() return ADDON.DB:Settings() end

-- Repaint after a change, once per frame, only while our tab is on screen,
-- and never under a box being typed in (a rebuild would take the cursor).
local repaintQueued = false
local function Repaint()
    if repaintQueued then return end
    repaintQueued = true
    C_Timer.After(0, function()
        repaintQueued = false
        local state = G.tabbedPageState
        if G:IsShown() and G.selectedSidebarItem == PAGE and state and state[PAGE] == TAB
           and not GetCurrentKeyBoardFocus() then
            G:RefreshContent()
        end
    end)
end
A.Repaint = function() if G then Repaint() end end

local function Text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    AE:ApplyThemeFont(fs, size or "small")
    local c = color or Theme.textSecondary
    fs:SetTextColor(c[1], c[2], c[3], 1)
    fs:SetWordWrap(false)
    return fs
end

-- A small number box in AES's edit-box look. Commits on Enter or focus loss;
-- Escape puts the old value back.
local function NumberBox(parent, width, value, onCommit, tooltip)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, 20)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    box:SetBackdropColor(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], Theme.bgMedium[4])
    box:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    box:SetTextInsets(5, 5, 0, 0)
    box:SetJustifyH("RIGHT")
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(7)
    AE:ApplyThemeFont(box, "small")
    box:SetTextColor(1, 1, 1, 1)
    box:SetText(value or "")
    local committed = value or ""
    local function Commit(self)
        local text = self:GetText()
        if text ~= committed then
            committed = text
            onCommit(tonumber(text))
        end
    end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", function(self) Commit(self); Repaint() end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(committed); self:ClearFocus() end)
    box:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    box:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        GameTooltip:Hide()
    end)
    return box
end

local function SmallButton(parent, size, skin, ...)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local S = AE.Skins
    if S and S[skin] then pcall(S[skin], b, ...) end
    return b
end

-- Column layout, right to left from the row's right edge.
local COL = { remove = 18, seen = 70, cap = 62, target = 46, have = 54, gap = 8 }

local function HeaderRow(content)
    local row = G:CreateRow(content, 16)
    local x = -(COL.remove + COL.gap)
    local function Head(label, width)
        local fs = Text(row, "small", Theme.textMuted)
        fs:SetPoint("RIGHT", row, "RIGHT", x, 0)
        fs:SetWidth(width)
        fs:SetJustifyH("RIGHT")
        fs:SetText(label)
        x = x - width - COL.gap
    end
    Head("Last Seen", COL.seen)
    Head("Cap (g)", COL.cap)
    Head("Target", COL.target)
    Head("Have", COL.have)
    local item = Text(row, "small", Theme.textMuted)
    item:SetPoint("LEFT", row, "LEFT", 40, 0)
    item:SetText("Item")
    return row
end

-- One list item: up/down (list order is restock order), icon and name,
-- what you have, Target and Cap boxes, Last Seen, remove.
local function ItemRow(content, list, it, index, count, ids)
    local DB, row = ADDON.DB, G:CreateRow(content, ROW_H)

    local up = SmallButton(row, 14, "ArrowButton", "up", 10)
    up:SetPoint("LEFT", row, "LEFT", 0, 0)
    local down = SmallButton(row, 14, "ArrowButton", "down", 10)
    down:SetPoint("LEFT", up, "RIGHT", 2, 0)
    local function Move(delta)
        local j = index + delta
        if j < 1 or j > count then return end
        ids[index], ids[j] = ids[j], ids[index]
        DB:ReorderItems(ids, list)
        Repaint()
    end
    up:SetScript("OnClick", function() Move(-1) end)
    down:SetScript("OnClick", function() Move(1) end)
    up:SetEnabled(index > 1)
    down:SetEnabled(index < count)
    up:SetAlpha(index > 1 and 1 or 0.3)
    down:SetAlpha(index < count and 1 or 0.3)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", down, "RIGHT", 8, 0)
    icon:SetTexture(C_Item.GetItemIconByID(it.itemID) or 134400)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local remove = SmallButton(row, COL.remove, "CloseButton", 11)
    remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    remove:SetScript("OnClick", function() DB:SetItem(it.itemID, 0, nil, list); Repaint() end)

    local x = -(COL.remove + COL.gap)
    local seen = Text(row, "small")
    seen:SetPoint("RIGHT", row, "RIGHT", x, 0)
    seen:SetWidth(COL.seen)
    seen:SetJustifyH("RIGHT")
    local lp = it.lastPrice
    if lp then
        seen:SetText(ADDON.MoneyText(lp.copper, "silver"))
        local c = time() - (lp.seenAt or 0) > Settings().lastPriceTTL and Theme.textMuted or Theme.textSecondary
        seen:SetTextColor(c[1], c[2], c[3], 1)
    else
        seen:SetText("\226\128\148")
        seen:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    end
    x = x - COL.seen - COL.gap

    local cap = NumberBox(row, COL.cap, it.maxPrice and tostring(floor(it.maxPrice / 10000)) or "", function(gold)
        DB:SetItemMaxPrice(it.itemID, (gold and gold > 0) and gold * 10000 or nil, list)
    end, "The most you'll pay for one, in whole gold. Empty: no cap.")
    cap:SetPoint("RIGHT", row, "RIGHT", x, 0)
    x = x - COL.cap - COL.gap

    local target = NumberBox(row, COL.target, tostring(it.need), function(n)
        if n and n > 0 then DB:SetItem(it.itemID, n, nil, list) end
    end)
    target:SetPoint("RIGHT", row, "RIGHT", x, 0)
    x = x - COL.target - COL.gap

    local bd = ADDON.Inventory:GetBreakdown(it.itemID)
    local have = list == "warband" and ADDON.RestockLoop:WarbandHave(it.itemID) or bd.bags
    local haveFS = Text(row, "small", have < it.need and Theme.error or Theme.textSecondary)
    haveFS:SetPoint("RIGHT", row, "RIGHT", x, 0)
    haveFS:SetWidth(COL.have)
    haveFS:SetJustifyH("RIGHT")
    haveFS:SetText(have)
    x = x - COL.have - COL.gap

    -- The name takes what's left; hover for the item tooltip.
    local nameBtn = CreateFrame("Button", nil, row)
    nameBtn:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    nameBtn:SetPoint("RIGHT", row, "RIGHT", x, 0)
    nameBtn:SetHeight(ROW_H)
    local name = Text(nameBtn, "small", Theme.textSecondary)
    name:SetPoint("LEFT")
    name:SetPoint("RIGHT")
    name:SetJustifyH("LEFT")
    local itemName, link, quality = C_Item.GetItemInfo(it.itemID)
    name:SetText(itemName or it.name)
    if quality then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then name:SetTextColor(r, g, b, 1) end
    end
    nameBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(it.itemID)
        if list ~= "warband" and (bd.bank > 0 or bd.warband > 0) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("In your bank", bd.bank, 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("In the warband bank", bd.warband, 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    nameBtn:SetScript("OnLeave", GameTooltip_Hide)
    nameBtn:SetScript("OnClick", function()
        if link and IsModifiedClick("CHATLINK") then
            local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
            if insert then insert(link) end
        end
    end)
    return row
end

-- Item ID box that also takes an item dropped on it (from the bags).
local function AddRow(card, list)
    local row = G:CreateRow(card.content, Theme.rowHeight)
    local idBox = G:CreateEditBox(row, "Item ID (or drop an item here)", "", nil)
    local countBox = G:CreateEditBox(row, "Target", "1", nil)
    countBox.editBox:SetNumeric(true)

    local function Add()
        local text = idBox:GetValue()
        if text == "" then return end
        local need = tonumber(countBox:GetValue()) or 1
        ADDON.ItemResolver:Resolve(text, function(itemID, name)
            if not itemID then return ADDON:Print("Couldn't add that: " .. tostring(name)) end
            ADDON.DB:SetItem(itemID, math.max(1, need), nil, list)
            idBox:SetValue("")
            Repaint()
        end)
    end
    local function TakeCursorItem()
        local kind, itemID = GetCursorInfo()
        if kind == "item" and itemID then
            ClearCursor()
            idBox:SetValue(tostring(itemID))
            idBox.editBox:ClearFocus()
        end
    end
    idBox.editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Add() end)
    idBox.editBox:SetScript("OnEditFocusLost", nil)
    idBox.editBox:SetScript("OnReceiveDrag", TakeCursorItem)
    idBox.editBox:HookScript("OnMouseUp", TakeCursorItem)
    idBox.container:SetScript("OnReceiveDrag", TakeCursorItem)
    idBox.container:HookScript("OnMouseUp", TakeCursorItem)
    countBox.editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Add() end)
    countBox.editBox:SetScript("OnEditFocusLost", nil)

    local addBtn = G:CreateButton(row, "Add", { width = 80, height = 24, callback = Add })
    row:AddWidget(idBox, 0.55)
    row:AddWidget(countBox, 0.2)
    row:AddWidget(addBtn, 0.25, nil, 0, -14)
    card:AddRow(row, Theme.rowHeight)
end

-- Per list: is the bulk-add box open (until reload).
local bulkOpen = {}

-- Bulk add: one item per line, "itemID [target] [cap in gold]".
local function ParseBulk(text)
    local out, bad = {}, 0
    for raw in ((text or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local line = raw:match("^%s*(.-)%s*$")
        if line ~= "" then
            local id, need, cap, extra = line:match("^(%S+)%s*(%S*)%s*(%S*)%s*(.-)$")
            id = tonumber(id) or tonumber((id or ""):match("item:(%d+)"))
            need = need == "" and 1 or tonumber(need)
            cap = cap == "" and 0 or tonumber(cap)
            if extra == "" and id and need and need >= 1 and need % 1 == 0 and cap and cap >= 0 and cap % 1 == 0 then
                out[#out + 1] = { itemID = id, need = need, cap = cap > 0 and cap * 10000 or nil }
            else
                bad = bad + 1
            end
        end
    end
    return out, bad
end
A.ParseBulk = ParseBulk  -- for the smoke test

local function BulkAdd(card, list)
    card:AddLabel(G:Note("Paste or type one item per line: its item ID, then the target, then a cap in gold (optional), e.g. |cffffffff241288 20 150|r. Drag items in to add their IDs. Items already listed are updated."))
    local row = G:CreateRow(card.content, 120)
    local holder = CreateFrame("Frame", nil, row, "BackdropTemplate")
    holder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    holder:SetBackdropColor(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], Theme.bgMedium[4])
    holder:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    local scroll = CreateFrame("ScrollFrame", nil, holder)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetMaxLetters(20000)
    box:SetAutoFocus(false)
    AE:ApplyThemeFont(box, "small")
    box:SetTextColor(1, 1, 1, 1)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    scroll:SetScrollChild(box)
    scroll:SetScript("OnSizeChanged", function(_, w) box:SetWidth(w) end)

    -- AES's scroll thumb, shown only while the text overflows the box.
    local bar = CreateFrame("Slider", nil, scroll)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(8)
    bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    bar:GetThumbTexture():SetSize(8, 20)
    bar:EnableMouse(true)
    bar:SetMinMaxValues(0, 0)
    bar:Hide()
    local syncing = false
    bar:SetScript("OnValueChanged", function(_, v) if not syncing then scroll:SetVerticalScroll(v) end end)
    local function Sync()
        if syncing then return end
        syncing = true
        scroll:UpdateScrollChildRect()
        local range = scroll:GetVerticalScrollRange() or 0
        if scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
        bar:SetShown(range > 0)
        scroll:EnableMouseWheel(range > 0)
        scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", range > 0 and -16 or -6, 6)
        bar:SetMinMaxValues(0, range)
        bar:SetValue(scroll:GetVerticalScroll())
        syncing = false
    end
    box:SetScript("OnTextChanged", function() C_Timer.After(0, Sync) end)
    -- Keep the cursor's line in view.
    box:SetScript("OnCursorChanged", function(_, _, y, _, h)
        C_Timer.After(0, function()
            Sync()
            local top, view = -y, scroll:GetHeight()
            local cur, range = scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange() or 0
            if top < cur then
                scroll:SetVerticalScroll(math.max(0, top))
            elseif top + h > cur + view then
                scroll:SetVerticalScroll(math.min(range, top + h - view))
            end
        end)
    end)
    scroll:SetScript("OnScrollRangeChanged", Sync)
    scroll:SetScript("OnVerticalScroll", Sync)
    if G.StyleScrollThumb then G:StyleScrollThumb(bar) end  -- sizes from the bar's parent: style first, then move
    bar:SetParent(holder)
    bar:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -4, -4)
    bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -4, 4)

    -- The wheel scrolls the box while it can; at its ends the page scrolls.
    scroll:EnableMouseWheel(false)
    scroll:SetScript("OnMouseWheel", function(s, d)
        local cur, range = s:GetVerticalScroll(), s:GetVerticalScrollRange()
        local to = math.max(0, math.min(range, cur - d * 20))
        if to ~= cur then return s:SetVerticalScroll(to) end
        local p = s:GetParent()
        while p and not (p:IsObjectType("ScrollFrame") and p:GetScript("OnMouseWheel")) do p = p:GetParent() end
        if p then p:GetScript("OnMouseWheel")(p, d) end
    end)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() box:SetFocus() end)
    local function Drop()
        local kind, itemID = GetCursorInfo()
        if kind ~= "item" or not itemID then return end
        ClearCursor()
        local t = box:GetText()
        box:SetText(t .. ((t ~= "" and not t:match("\n$")) and "\n" or "") .. itemID .. "\n")
    end
    box:SetScript("OnReceiveDrag", Drop)
    box:HookScript("OnMouseUp", Drop)
    holder:SetScript("OnReceiveDrag", Drop)
    holder:HookScript("OnMouseUp", Drop)
    row:AddWidget(holder, 1)
    card:AddRow(row, 120)

    local bRow = G:CreateRow(card.content, 30)
    local btn = G:CreateButton(bRow, "Import", {
        width = 100, height = 24,
        callback = function()
            local entries, bad = ParseBulk(box:GetText())
            local added = 0
            for _, e in ipairs(entries) do
                if not ADDON.DB:GetItems(list)[e.itemID] then added = added + 1 end
                ADDON.DB:SetItem(e.itemID, e.need, e.cap, list)  -- no cap given: an existing cap stays
            end
            ADDON:Print(("Imported %d, updated %d, skipped %d bad lines."):format(added, #entries - added, bad))
            if bad == 0 then box:SetText("") end
            Repaint()
        end,
    })
    bRow:AddWidget(btn, 0.25)
    card:AddRow(bRow, 30)
end

local function ListCard(scrollChild, yOffset, list)
    local warband = list == "warband"
    local card = G:CreateCard(scrollChild, warband and "Warband List" or "My List", yOffset)
    card:AddLabel(G:Note(warband
        and "Kept in the warband bank for all your characters: at least this many of each. Restock it at the Auction House after your own list; surplus from your bags is deposited at the bank."
        or "Kept in this character's bags. The order is the restock order: most important first."))
    AddRow(card, list)

    local items = ADDON.DB:GetSortedItems(list)
    if #items > 0 then
        card:AddRow(HeaderRow(card.content), 16, 2)
        local ids = {}
        for i, it in ipairs(items) do ids[i] = it.itemID end
        for i, it in ipairs(items) do card:AddRow(ItemRow(card.content, list, it, i, #items, ids), ROW_H, 2) end
    end

    local tools = G:CreateRow(card.content, 34)
    tools:AddWidget(G:CreateButton(tools, "Add Common Consumables", {
        width = 200, height = 24,
        tooltip = "This expansion's go-to potions, flasks, oils and food, at a target of 1. Anything already listed is left as it is.",
        callback = function()
            local n = ADDON.DB:AddCommonConsumables(list)
            ADDON:Print(n > 0 and ("Added %d items."):format(n) or "All the common consumables are already listed.")
            Repaint()
        end,
    }), 0.4)
    tools:AddWidget(G:CreateButton(tools, bulkOpen[list] and "Hide Bulk Add" or "Bulk Add", {
        width = 120, height = 24,
        tooltip = "Add or update many items at once from a pasted list.",
        callback = function() bulkOpen[list] = not bulkOpen[list]; Repaint() end,
    }), 0.25)
    if #items > 0 then
        tools:AddWidget(G:CreateButton(tools, "Clear List", {
            width = 120, height = 24,
            callback = function()
                AE:CreatePrompt({
                    title = "Clear List",
                    text = ("Remove every item from %s?"):format(warband and "the warband list" or "your list"),
                    acceptText = "Clear List",
                    onAccept = function() wipe(ADDON.DB:GetItems(list)); Repaint() end,
                })
            end,
        }), 0.25)
    end
    card:AddRow(tools, 34)

    if bulkOpen[list] then BulkAdd(card, list) end
    return yOffset + card:GetContentHeight() + Theme.paddingSmall
end

-- One card per place, two switches a row (the layout of AES's Automation page).
local SHIFT = "Hold |cffffffffShift|r when opening it to skip this."

local function SettingsCards(scrollChild, yOffset)
    local function Check(row, label, key, tip, store)
        store = store or Settings()
        local value = store[key]
        if key == "autoOpenAtVendor" and value == nil then value = Settings().autoOpenAtAH end
        local c = G:CreateCheckbox(row, label, value == true, function(checked)
            store[key] = checked
            ADDON.Log:Emit("setting", nil, { key = key, on = checked })
            ADDON.UI:Refresh()
        end)
        if tip and c.SetTooltip then c:SetTooltip(tip) end
        row:AddWidget(c, 0.5)
        return c
    end
    local function Card(title, rows)
        local card = G:CreateCard(scrollChild, title, yOffset)
        for _, r in ipairs(rows) do
            local row = G:CreateRow(card.content, 40)
            Check(row, unpack(r[1]))
            if r[2] then Check(row, unpack(r[2])) end
            card:AddRow(row, 40)
        end
        yOffset = yOffset + card:GetContentHeight() + Theme.paddingSmall
        return card
    end

    Card("Auction House", {
        { { "Open at Auction House", "autoOpenAtAH", "The panel docks to the Auction House when something on your lists is short." },
          { "Start Restock on Open", "autoRestock", "Searches the first short item as the Auction House opens. You still click Buy for each one.\n\n" .. SHIFT } },
    })
    Card("Bank", {
        { { "Open at Bank", "autoOpenAtBank", "The panel docks to the bank when something can be pulled or deposited." },
          { "Pull Short Items on Open", "autoRestockBank", "Moves what you're short from your bank, then your warband bank, into your bags.\n\n" .. SHIFT } },
        { { "Deposit Surplus on Open", "autoDepositBank", "Moves everything above your own targets from your bags into the warband bank, after any pull.\n\n" .. SHIFT } },
    })
    Card("Vendors", {
        { { "Open at Vendors", "autoOpenAtVendor", "The panel docks to a vendor that sells something you're short of." },
          { "Buy Short Items on Open", "autoBuyVendor", "Buys what you're short from the vendor straight away, within your caps, your gold and your bag space.\n\n" .. SHIFT } },
    })

    -- This character: the warband pass and Minimum Gold.
    local char = ADDON.DB.char
    local card = G:CreateCard(scrollChild, "This Character", yOffset)
    local row = G:CreateRow(card.content, 40)
    Check(row, "Shop for the Warband", "shopWarband",
        "Offers to restock the warband list at the Auction House after your own. Surplus is deposited at the bank either way.", char)
    local gold = G:CreateEditBox(row, "Minimum Gold", char.goldKeep and tostring(floor(char.goldKeep / 10000)) or "", function(text)
        local g = tonumber(text)
        char.goldKeep = (g and g > 0) and g * 10000 or nil
        ADDON.Log:Emit("setting", nil, { key = "goldKeep", on = char.goldKeep ~= nil })
        ADDON.BankRestock:TakeOverGold()
    end)
    gold.editBox:SetNumeric(true)
    gold.container:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Tops this character up to this much gold from the warband bank at every bank visit. Never deposits. Empty: off.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    gold.container:SetScript("OnLeave", GameTooltip_Hide)
    row:AddWidget(gold, 0.5)
    card:AddRow(row, 40)
    local row2 = G:CreateRow(card.content, 40)
    Check(row2, "Pulse the Action Button", "motion", "When the panel opens with something to do.")
    card:AddRow(row2, 40)
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingSmall
    return yOffset
end

local function BuildTab(scrollChild, yOffset)
    -- Ours, not AES's: name and version on the first card.
    local card = G:CreateCard(scrollChild, "StockClerk " .. ADDON.VersionText(), yOffset)
    card:AddLabel(G:Note("A shopping list for your consumables: set what you want on hand and restock it from the Auction House, your bank or a vendor, within the price caps you set. |cffffffff/clerk log|r shows what it did."))
    yOffset = yOffset + card:GetContentHeight() + Theme.paddingSmall
    yOffset = ListCard(scrollChild, yOffset, "mine")
    yOffset = ListCard(scrollChild, yOffset, "warband")
    yOffset = SettingsCards(scrollChild, yOffset)
    return yOffset - Theme.paddingSmall
end

-- ===========================================================================
-- Wiring
-- ===========================================================================
local NEEDS = { "RegisterContent", "RefreshContent", "OpenPage", "CreateCard", "CreateRow",
                "CreateButton", "CreateEditBox", "CreateCheckbox", "Note", "IsShown" }

-- Once AES's options addon loads: our builder and a tab on its Utilities page.
local function Register()
    G, Theme = AE.GUIFrame, AE.Theme
    local tabs = G and G.TabbedPages and G.TabbedPages[PAGE]
    if not tabs then return A:Fallback("no Utilities page") end
    for _, fn in ipairs(NEEDS) do
        if type(G[fn]) ~= "function" then return A:Fallback("options window has no " .. fn) end
    end
    G:RegisterContent(BUILDER, function(scrollChild, yOffset)
        local ok, y = pcall(BuildTab, scrollChild, yOffset)
        if ok then return y end
        A:Fallback(y)
        return yOffset
    end)
    for _, t in ipairs(tabs) do if t.key == TAB then return end end
    tabs[#tabs + 1] = { key = TAB, text = "StockClerk", builderId = BUILDER }
end

-- One-time notice that the settings moved.
local function Notice()
    local s = Settings()
    if s.aesNoticeShown then return end
    s.aesNoticeShown = true
    AE:CreatePrompt({
        title = "StockClerk",
        text = "With atrocityEssentials loaded, StockClerk's lists and settings live in the AES settings window, under Utilities > StockClerk.",
        acceptText = "Open Settings",
        cancelText = "OK",
        onAccept = function() A:OpenSettings() end,
    })
end

AE = Usable()
if AE then
    ADDON.aesMode = true
    ADDON.AESPanel:Bind(AE)
    ADDON.UI = ADDON.AESPanel

    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self, event, name)
        if event == "PLAYER_LOGIN" then
            C_Timer.After(3, function() if ADDON.aesMode then Notice() end end)
        elseif name == "atrocityEssentials_Options" then
            self:UnregisterEvent("ADDON_LOADED")
            local ok, err = pcall(Register)
            if not ok then A:Fallback(err) end
        end
    end)
    if C_AddOns.IsAddOnLoaded("atrocityEssentials_Options") then
        local ok, err = pcall(Register)
        if not ok then A:Fallback(err) end
    end
end
