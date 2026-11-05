--[[
    StockClerk - AES/Panel.lua
    The on-screen window while AES is loaded: a docked side panel in AES's
    look instead of the main window. Same UI contract the logic uses on the
    main window (Show, Hide, Refresh, Mark, ClearMarks, SetStatus,
    SetCheckout ...); AES/Adapter.lua makes it ADDON.UI.

    Docked flush right of the window it serves (2px gap, that window's full
    height, fixed width): the Auction House, the merchant, the bank (AES's own
    bank window, else Blizzard's). When another bag addon owns the bank there
    is nothing to dock to and it floats: drag to move, position saved.
    It opens only when there is something to do here, or a line to read.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local P = { marks = {} }
ADDON.AESPanel = P

local ipairs, min, floor = ipairs, math.min, math.floor

local WIDTH, PAD, ROW_H, BUTTON_H, GAP = 200, 10, 22, 26, 6

local frame, rows = nil, {}
local AE  -- atrocityEssentials.NS, set by the adapter before anything is built

function P:Bind(ns) AE = ns end

local function Loop() return ADDON.RestockLoop end
local function BR() return ADDON.BankRestock end
local function Money(c, p) return ADDON.MoneyText(c, p) end

-- Where we are: the place the panel serves.
local function At()
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then return "ah" end
    if ADDON.bankOpen then return "bank" end
    if ADDON.merchantOpen then return "vendor" end
end

------------------------------------------------------------------- building
local function Text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local S = AE.Skins
    if S and S.SetFont then S.SetFont(fs, size, "") else AE:ApplyThemeFont(fs, size) end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function Button(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(BUTTON_H)
    local S = AE.Skins
    if S and S.Button then pcall(S.Button, b) end
    b.label = Text(b, 12, "CENTER")
    b.label:SetPoint("LEFT", 4, 0)
    b.label:SetPoint("RIGHT", -4, 0)
    b:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    if S and S.Hover then pcall(S.Hover, b) end  -- after our scripts
    return b
end

local function SetButton(b, text, enabled, tip)
    b.label:SetText(text)
    b:SetEnabled(enabled)
    local c = enabled and AE.Theme.textSecondary or AE.Theme.textMuted
    b.label:SetTextColor(c[1], c[2], c[3], 1)
    b.tip = tip
    b:Show()
end

-- On an over-cap row: raise the cap on the spot (whole gold, Enter commits).
local function CapBox(row)
    local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    box:SetSize(44, 18)
    local S = AE.Skins
    if S and S.EditBox then pcall(S.EditBox, box) end
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(6)
    box:SetJustifyH("RIGHT")
    box:SetTextInsets(3, 3, 0, 0)
    AE:ApplyThemeFont(box, "small")
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", function(self)
        local g = tonumber(self:GetText())
        ADDON.DB:SetItemMaxPrice(row.itemID, (g and g > 0) and g * 10000 or nil, row.lane)
        self:ClearFocus()
        P:Refresh()
    end)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Your cap, in gold. Raise it and restock again.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", GameTooltip_Hide)
    return box
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, frame.list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", frame.list, "RIGHT", 0, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.count = Text(row, 11, "RIGHT")
    row.count:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.cap = CapBox(row)
    row.cap:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.name = Text(row, 11)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    row.name:SetWordWrap(false)
    -- The mark: a thin bar on the left edge (current / done / over cap ...).
    row.edge = row:CreateTexture(nil, "OVERLAY")
    row.edge:SetWidth(2)
    row.edge:SetPoint("TOPLEFT", row, "TOPLEFT", -PAD + 2, -2)
    row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", -PAD + 2, 2)
    row:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        if self.tip then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(self.tip, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    local S = AE.Skins
    if S and S.RowHover then pcall(S.RowHover, row) end
    rows[i] = row
    return row
end

local function Build()
    local S = AE.Skins
    frame = CreateFrame("Frame", "StockClerkAESPanel", UIParent)
    P.frame = frame
    frame:SetWidth(WIDTH)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:Hide()
    if S and S.Backdrop then S.Backdrop(frame) end

    frame.title = Text(frame, 14, "CENTER")
    frame.title:SetPoint("TOP", 0, -PAD)
    local b = AE.GUITheme and AE.GUITheme.brand or AE.Theme.accent
    frame.title:SetTextColor(b[1], b[2], b[3])

    frame.list = CreateFrame("Frame", nil, frame)
    frame.list:SetPoint("TOPLEFT", PAD, -PAD - 24)
    frame.list:SetPoint("TOPRIGHT", -PAD, -PAD - 24)
    frame.list:SetHeight(1)

    -- Footer: status and checkout lines over the action buttons.
    frame.footer = CreateFrame("Frame", nil, frame)
    frame.footer:SetPoint("BOTTOMLEFT", PAD, PAD)
    frame.footer:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    frame.primary = Button(frame.footer)
    -- During an AH run: Stop | Skip | Buy, Buy where Restock was.
    frame.stop = Button(frame.footer)
    frame.skip = Button(frame.footer)
    frame.second = Button(frame.footer)   -- bank: Deposit over Pull when both apply
    frame.stop:SetWidth(46)
    frame.skip:SetWidth(52)
    frame.stop:SetPoint("BOTTOMLEFT", 0, 0)
    frame.skip:SetPoint("LEFT", frame.stop, "RIGHT", 4, 0)
    frame.second:SetPoint("BOTTOMLEFT", frame.primary, "TOPLEFT", 0, 4)
    frame.second:SetPoint("BOTTOMRIGHT", frame.primary, "TOPRIGHT", 0, 4)

    frame.line2 = Text(frame.footer, 11)
    frame.line1 = Text(frame.footer, 12)
    frame.status = Text(frame.footer, 11)
    for _, fs in ipairs({ frame.line1, frame.line2, frame.status }) do fs:SetWordWrap(true) end

    -- Drag to move only while floating (no window to dock to).
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) if f.floating then f:StartMoving() end end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint()
        ADDON.DB.char.aesPanelPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    frame.primary:SetScript("OnClick", function() if frame.onPrimary then frame.onPrimary() end end)
    frame.second:SetScript("OnClick", function() if frame.onSecond then frame.onSecond() end end)
    frame.skip:SetScript("OnClick", function() Loop():Skip() end)
    frame.stop:SetScript("OnClick", function() Loop():Stop("user_stop") end)
end

------------------------------------------------------------------ hosting
local function Host(at)
    if at == "ah" then return AuctionHouseFrame end
    if at == "vendor" then return MerchantFrame end
    if at == "bank" then
        -- AES's Bags module parks BankFrame under a hidden parent, still
        -- "shown", so the test is IsVisible.
        for _, name in ipairs({ "AE_BankFrame", "BankFrame" }) do
            local f = _G[name]
            if f and f:IsVisible() then return f end
        end
    end
end

local function Place(at)
    local host = Host(at)
    frame:ClearAllPoints()
    frame.floating = not host
    if host then
        frame:SetParent(host)
        frame:SetFrameStrata(host:GetFrameStrata())
        frame:SetPoint("TOPLEFT", host, "TOPRIGHT", 2, 0)
        frame:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", 2, 0)
    else
        frame:SetParent(UIParent)
        frame:SetFrameStrata("DIALOG")
        local p = ADDON.DB.char.aesPanelPos
        if p then frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
        else frame:SetPoint("CENTER", UIParent, "CENTER", 300, 100) end
    end
end

-------------------------------------------------------------- what to show
-- What a Restock of `lane` costs at last seen prices (over-cap items left out).
local function LaneCost(lane)
    local cost, loop = 0, Loop()
    for _, it in ipairs(ADDON.DB:GetSortedItems(lane)) do
        local short, lp = loop:Short(lane, it.itemID, it.need), it.lastPrice
        if short > 0 and lp and not (it.maxPrice and lp.copper > it.maxPrice) then cost = cost + short * lp.copper end
    end
    return cost
end

local function Model(at)
    local m, loop, br = { items = {} }, Loop(), BR()
    local run = loop.state
    local function Add(itemID, lane, count, cap)
        m.items[#m.items + 1] = { itemID = itemID, count = count, lane = lane, cap = cap }
    end

    if at == "ah" then
        local lane = run.active and run.lane or loop:NextLane() or "mine"
        m.lane = lane
        m.title = lane == "warband" and "Restock Warband" or "Restock"
        local list = run.active and run.queue or ADDON.DB:GetSortedItems(lane)
        for _, it in ipairs(list) do
            local short = loop:Short(lane, it.itemID, it.need)
            if run.active or short > 0 or P.marks[it.itemID] then Add(it.itemID, lane, short, it.maxPrice) end
        end
        m.any = #m.items > 0
    elseif at == "vendor" then
        m.title = "Vendor"
        local plan, seen = ADDON.Merchant:Plan(), {}
        for _, p in ipairs(plan) do
            Add(p.item.itemID, "mine", p.batches * p.s.batch, p.item.maxPrice)
            seen[p.item.itemID] = true
        end
        local items = ADDON.DB:GetItems()
        for id in pairs(P.marks) do  -- bought rows stay listed with their mark
            if not seen[id] and items[id] then Add(id, "mine", 0, items[id].maxPrice) end
        end
        m.any = #plan > 0
    elseif at == "bank" then
        m.title = "Bank"
        -- What you're short; surplus when depositing or when nothing is short.
        local list = not (br:IsActive() and br.dir == "deposit") and br:Shortfalls() or {}
        if #list == 0 then list = br:Surpluses() end
        local items = ADDON.DB:GetItems()
        for _, s in ipairs(list) do Add(s.itemID, "mine", s.short or s.count or 0, items[s.itemID] and items[s.itemID].maxPrice) end
        m.pull, m.deposit = br:PullableCount(), br:DepositableCount()
        m.any = m.pull > 0 or m.deposit > 0
    end
    return m
end

local MARK_COLOR = {
    current = function() return AE.GUITheme and AE.GUITheme.brand or AE.Theme.accent end,
    queued  = function() return AE.Theme.textMuted end,
    done    = function() return AE.Theme.success end,
    over    = function() return AE.Theme.warning end,
    failed  = function() return AE.Theme.error end,
    skipped = function() return AE.Theme.textMuted end,
}

---------------------------------------------------------------- painting
local function PaintRows(m)
    -- As many rows as fit above the footer; the rest are summed up.
    local room = frame.floating and 12 or floor((frame:GetHeight() - 24 - PAD * 3 - frame.footer:GetHeight()) / ROW_H)
    room = math.max(1, room)
    local shown = min(#m.items, room)
    if #m.items > room then shown = room - 1 end
    for i = 1, #rows do rows[i]:Hide() end
    for i = 1, shown do
        local it, row = m.items[i], Row(i)
        row.itemID, row.lane = it.itemID, it.lane
        row.icon:SetTexture(C_Item.GetItemIconByID(it.itemID) or 134400)
        local name, _, quality = C_Item.GetItemInfo(it.itemID)
        row.name:SetText(name or ("item " .. it.itemID))
        local r, g, b = 1, 1, 1
        if quality then r, g, b = C_Item.GetItemQualityColor(quality) end
        row.name:SetTextColor(r, g, b)
        local mark = P.marks[it.itemID]
        row.tip = mark and mark.tip
        if mark and MARK_COLOR[mark.kind] then
            local c = MARK_COLOR[mark.kind]()
            row.edge:SetColorTexture(c[1], c[2], c[3], 1)
            row.edge:Show()
        else
            row.edge:Hide()
        end
        local over = mark and mark.kind == "over"
        row.cap:SetShown(over)
        row.count:SetShown(not over)
        if over then
            if not row.cap:HasFocus() then row.cap:SetText(it.cap and floor(it.cap / 10000) or "") end
        else
            local done = mark and mark.kind == "done"
            row.count:SetText(done and "Done" or (it.count > 0 and it.count or ""))
            local c = done and AE.Theme.success or AE.Theme.textSecondary
            row.count:SetTextColor(c[1], c[2], c[3])
        end
        row:Show()
    end
    if #m.items > shown then
        local row = Row(shown + 1)
        row.itemID, row.tip = nil, nil
        row.icon:SetTexture(nil)
        row.edge:Hide()
        row.cap:Hide()
        row.count:Show()
        row.count:SetText("")
        row.name:SetText(("+%d more"):format(#m.items - shown))
        local c = AE.Theme.textMuted
        row.name:SetTextColor(c[1], c[2], c[3])
        row:Show()
    end
    frame.list:SetHeight(math.max(1, (#m.items > shown and shown + 1 or shown) * ROW_H))
end

-- Footer text lines stack upward from the buttons: line2, line1, status.
local function PaintFooter(m, at)
    local T, loop, br = AE.Theme, Loop(), BR()
    frame.stop:Hide(); frame.skip:Hide(); frame.second:Hide()
    frame.primary:ClearAllPoints()
    frame.primary:SetPoint("BOTTOMLEFT", 0, 0)
    frame.primary:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.onPrimary, frame.onSecond = nil, nil

    if at == "ah" and loop:IsActive() then
        frame.stop:Show(); frame.skip:Show()
        frame.primary:ClearAllPoints()
        frame.primary:SetPoint("BOTTOMLEFT", frame.skip, "BOTTOMRIGHT", 4, 0)
        frame.primary:SetPoint("BOTTOMRIGHT", 0, 0)
        SetButton(frame.stop, "Stop", true)
        local wait, plan = loop:BuyWait(), loop.state.armedPlan
        SetButton(frame.skip, "Skip", wait ~= nil)
        SetButton(frame.primary, (wait and wait > 0 and plan and #plan.warnings > 0)
            and ("Buy (%d)"):format(math.ceil(wait)) or "Buy", wait == 0,
            plan and ("Buy %d %s for %s"):format(plan.planQuantity, plan.name, Money(plan.plannedSpend)))
        frame.onPrimary = function() loop:Fire() end
    elseif at == "ah" then
        local lane = m.lane
        local n, cost = loop:PreviewShortfallCount(lane), LaneCost(lane)
        local label = (lane == "warband" and "Restock Warband (%d)" or "Restock (%d)"):format(n)
        if cost > 0 then label = label .. " \194\183 " .. Money(cost, "gold") end
        SetButton(frame.primary, n > 0 and label or "Restock", n > 0 and loop:NextLane() ~= nil,
            n > 0 and "Total at last seen prices; items above their cap aren't counted." or nil)
        frame.onPrimary = function() loop:Start(false, lane) end
    elseif at == "vendor" then
        local n, cost = ADDON.Merchant:Preview()
        SetButton(frame.primary, n > 0 and (("Buy (%d)"):format(n) .. " \194\183 " .. Money(cost, "gold")) or "Buy", n > 0)
        frame.onPrimary = function() ADDON.Merchant:Restock() end
    elseif at == "bank" then
        if br:IsActive() then
            SetButton(frame.primary, "Stop", true)
            frame.onPrimary = function() br:Stop("stopped") end
        else
            local pull, dep = m.pull or 0, m.deposit or 0
            if pull > 0 then
                SetButton(frame.primary, ("Pull from Bank (%d)"):format(pull), true,
                    "Moves exactly what you're short from your bank, then your warband bank, into your bags.")
                frame.onPrimary = function() br:Start(false, "pull") end
                if dep > 0 then
                    SetButton(frame.second, ("Deposit to Warband (%d)"):format(dep), true)
                    frame.onSecond = function() br:Start(false, "deposit") end
                end
            else
                SetButton(frame.primary, dep > 0 and ("Deposit to Warband (%d)"):format(dep) or "Nothing to Move", dep > 0,
                    dep > 0 and "Moves everything above your own targets from your bags into the warband bank." or nil)
                frame.onPrimary = function() br:Start(false, "deposit") end
            end
        end
    end

    -- Text above the buttons, across the panel's full width.
    local base = BUTTON_H + (frame.second:IsShown() and BUTTON_H + 4 or 0)
    local y = 0
    local function Line(fs, text, color)
        if not text or text == "" then fs:Hide(); return end
        fs:ClearAllPoints()
        fs:SetPoint("BOTTOMLEFT", frame.footer, "BOTTOMLEFT", 0, base + GAP + y)
        fs:SetPoint("BOTTOMRIGHT", frame.footer, "BOTTOMRIGHT", 0, base + GAP + y)
        fs:SetText(text)
        fs:SetTextColor(color[1], color[2], color[3])
        fs:Show()
        y = y + fs:GetStringHeight() + 3
    end
    local co = P.checkout
    Line(frame.line2, co and co[2], T.textMuted)
    Line(frame.line1, co and co[1], { 1, 1, 1 })
    Line(frame.status, P.status, T.textSecondary)
    frame.footer:SetHeight(base + y + GAP)
end

local function Paint()
    local at = At()
    if not (frame and frame:IsShown() and at) then return end
    local m = Model(at)
    frame.title:SetText(m.title or "")
    PaintFooter(m, at)
    PaintRows(m)
    if frame.floating then
        frame:SetHeight(PAD * 3 + 24 + frame.list:GetHeight() + frame.footer:GetHeight())
    end
end

------------------------------------------------------ the logic's contract
-- One repaint per frame however many changes came in.
function P:Refresh()
    if self.queued or not (frame and frame:IsShown()) then return end
    self.queued = true
    C_Timer.After(0, function() self.queued = false; Paint() end)
end
P.RefreshRestockBtn = P.Refresh

function P:Mark(itemID, kind, tip)
    self.marks[itemID] = kind and { kind = kind, tip = tip } or nil
    self:Refresh()
end

function P:ClearMarks() wipe(self.marks); self:Refresh() end

function P:SetStatus(text, skipLog)
    self.status = text
    if not skipLog and text and text ~= "" then ADDON.Log:Emit("status", nil, { text = text }) end
    self:Refresh()
end

function P:SetCheckout(line1, line2)
    self.checkout = line1 and { line1, line2 } or nil
    self:Refresh()
end

-- Opened for a visit when there's something to do (or a line to read).
-- Placed a beat later: bag addons show their bank window after the event.
function P:Show()
    C_Timer.After(0.1, function()
        local at = At()
        if not at then return end
        if not frame then Build() end
        if not (Model(at).any or self.status) then return end
        Place(at)
        frame:Show()
        Paint()
    end)
end

function P:Hide()
    if frame then frame:Hide() end
    self.status, self.checkout = nil, nil
    wipe(self.marks)
end

-- A short pulse round the action: there is something to do here.
function P:PulseRestock()
    if not (frame and frame:IsShown() and frame.primary:IsEnabled() and ADDON.DB:Settings().motion) then return end
    local glow = frame.glow
    if not glow then
        glow = CreateFrame("Frame", nil, frame.primary)
        glow:SetAllPoints()
        frame.glow = glow
    end
    glow:Show()
    AE:PaintPulseBorder(glow, { color = AE.GUITheme and AE.GUITheme.brand or AE.Theme.accent, size = 2 })
    C_Timer.After(3, function() AE:StopPulseBorder(glow); glow:Hide() end)
end

-- The main window's view switch, gold glint and docking have no part here.
function P:SetView() end
function P:GlintGold() end
function P:DockIfOpen() end
function P:Undock() end
