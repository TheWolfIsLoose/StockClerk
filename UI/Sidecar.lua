--[[
    StockClerk - UI/Sidecar.lua
    Side panel (the header's hamburger): settings, "Add common consumables",
    and Recent activity (activity-level log entries, newest first).
--]]

local addonName = ...
local ADDON     = _G[addonName]

local Sidecar = {}
ADDON.Sidecar = Sidecar

local MF      = ADDON.MainFrame
local Palette = MF.Palette
local FEED_MAX, CAP_DEBOUNCE = 30, 10  -- feed lines; seconds

local function Tooltip(owner, title, body)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(body, 0.74, 0.74, 0.74, true)
    GameTooltip:Show()
end

local function Build()
    MF.ApplyFontFace()
    local f = MF.DockedPanel("StockClerkSidecar")

    local settingsTitle = f:CreateFontString(nil, "OVERLAY", "StockClerkFont")
    settingsTitle:SetPoint("TOPLEFT", 12, -10)
    settingsTitle:SetText("|cff98FF98Settings|r")

    -- Flat checkbox (light well, gray ring, mint square when on) whose label is
    -- part of the click area, 24px tall (WCAG 2.5.8). Tooltip only where the label needs more.
    -- store: the table the setting lives in (account settings unless given).
    local function Check(y, label, key, tip, store)
        local c = CreateFrame("CheckButton", nil, f)
        c:SetPoint("TOPLEFT", 14, y - 3)
        c:SetSize(16, 16)
        c:SetHitRectInsets(0, -220, -4, -4)
        MF.ApplyFill(c, Palette.fieldFill)
        MF.AddBlackBorder(c, Palette.ringRest)
        local tick = c:CreateTexture(nil, "OVERLAY")
        tick:SetColorTexture(0.596, 1, 0.596)  -- mint: settings aren't tied to a list view
        tick:SetSize(8, 8)
        tick:SetPoint("CENTER")
        c:SetCheckedTexture(tick)
        local wash = c:CreateTexture(nil, "HIGHLIGHT")
        wash:SetColorTexture(1, 1, 1, 0.12)
        wash:SetAllPoints()
        local text = c:CreateFontString(nil, "OVERLAY", "StockClerkFont")
        text:SetPoint("LEFT", c, "RIGHT", 8, 0)
        text:SetText(label)
        c:SetScript("OnClick", function(self)
            local on = self:GetChecked()
            local t = store or ADDON.DB:Settings()
            t[key] = on
            ADDON.Log:Emit("setting", nil, { key = key, on = on })
        end)
        if tip then
            c:SetScript("OnEnter", function(self) Tooltip(self, label, tip) end)
            c:SetScript("OnLeave", GameTooltip_Hide)
        end
        c.key, c.store = key, store
        return c
    end
    -- "autoRestock" predates the Express restock name; kept for saved settings.
    f.checks = {
        Check(-30, "Auto-open at Auction House", "autoOpenAtAH"),
        Check(-54, "Auto-open at bank", "autoOpenAtBank"),
        Check(-78, "Express restock at Auction House", "autoRestock",
            "When you open the AH and something is short, start buying right away. You still confirm each purchase."),
        Check(-102, "Express restock at bank", "autoRestockBank",
            "When you open your bank and something is short, pull it from your bank and warband bank right away."),
        -- Per character. Label width: the panel must not get wider (check in-game).
        Check(-126, "Shop for the warband on this character", "shopWarband",
            "Offer to restock the warband list after your own shopping at the Auction House. Surplus is always deposited at the bank.",
            ADDON.DB.char),
    }

    local add = CreateFrame("Button", nil, f)
    add:SetPoint("TOPLEFT", 12, -156)
    add:SetPoint("RIGHT", -12, 0)
    add:SetHeight(22)
    MF.StyleButton(add)
    add:SetText("Add common consumables")
    add:HookScript("OnEnter", function(self)
        Tooltip(self, "Add common consumables",
            "Adds this expansion's go-to potions, flasks and weapon oils with a target of 1 to the list on screen. Items already on it are left as they are.")
    end)
    add:HookScript("OnLeave", GameTooltip_Hide)
    add:SetScript("OnClick", function()
        local n = ADDON.DB:AddCommonConsumables(MF:View())
        MF:Refresh()
        MF:SetStatus(n > 0 and ("Added %d items. Remove any you don't need with the red X on each row."):format(n)
            or "All the common consumables are already on your list.")
    end)

    local divider = f:CreateTexture(nil, "OVERLAY")
    divider:SetColorTexture(0, 0, 0, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 8, -188)
    divider:SetPoint("TOPRIGHT", -8, -188)

    -- Recent activity. Hovering the title (or the "/clerk log" link, which
    -- opens the log) explains how to send a bug report.
    local feedTitle = f:CreateFontString(nil, "OVERLAY", "StockClerkFont")
    feedTitle:SetPoint("TOPLEFT", 12, -196)
    feedTitle:SetText("|cff98FF98Recent activity|r")
    local function FeedHelp(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText("Recent activity", 1, 1, 1)
        GameTooltip:AddLine("What StockClerk did, newest first.", 0.74, 0.74, 0.74, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Something not working?", 1, 1, 1)
        GameTooltip:AddLine("1. Type /clerk log (or click the link) and press Ctrl+C.", 0.74, 0.74, 0.74, true)
        GameTooltip:AddLine("2. Paste it into your bug report.", 0.74, 0.74, 0.74, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("If the problem happens again and again: type /clerk debug first, repeat the problem, then /clerk log.", 0.74, 0.74, 0.74, true)
        GameTooltip:Show()
    end
    local help = CreateFrame("Frame", nil, f)
    help:SetAllPoints(feedTitle)
    help:EnableMouse(true)
    help:SetScript("OnEnter", FeedHelp)
    help:SetScript("OnLeave", GameTooltip_Hide)

    local link = CreateFrame("Button", nil, f)
    link:SetPoint("TOPRIGHT", -12, -198)
    link:SetSize(60, 14)
    link:SetHitRectInsets(0, 0, -5, -5)  -- 24px target
    local linkText = link:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    linkText:SetPoint("RIGHT")
    linkText:SetText("/clerk log")
    linkText:SetTextColor(0.55, 0.55, 0.55)
    link:SetScript("OnEnter", function(self) linkText:SetTextColor(unpack(Palette.brand)); FeedHelp(self) end)
    link:SetScript("OnLeave", function() linkText:SetTextColor(0.55, 0.55, 0.55); GameTooltip:Hide() end)
    link:SetScript("OnClick", function() ADDON.LogPopup:Toggle() end)

    local feedBg = f:CreateTexture(nil, "BACKGROUND")
    feedBg:SetColorTexture(Palette.bgDark[1], Palette.bgDark[2], Palette.bgDark[3], 0.6)
    feedBg:SetPoint("TOPLEFT", 8, -218)
    feedBg:SetPoint("BOTTOMRIGHT", -8, 8)
    local scroll = CreateFrame("ScrollFrame", "StockClerkSidecarScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -220)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)  -- room for the scroll bar
    f.feed = CreateFrame("Frame", nil, scroll)
    f.feed:SetSize(220, 1)
    scroll:SetScrollChild(f.feed)
    f.feedRows = {}

    Sidecar.frame = f
    return f
end

-- Feed line i, created on first use at a fixed height. A cut-off line shows
-- in full in a tooltip (WoW's scroll frames don't scroll sideways).
local function FeedRow(f, i)
    local row = f.feedRows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, f.feed)
    row:SetPoint("TOPLEFT", 4, -(i - 1) * 14)
    row:SetPoint("RIGHT", -4, 0)
    row:SetHeight(14)
    row.text = row:CreateFontString(nil, "ARTWORK", "StockClerkFontSmall")
    row.text:SetAllPoints()
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        if not self.text:IsTruncated() then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.text:GetText(), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    f.feedRows[i] = row
    return row
end

function Sidecar:Refresh()
    local f = self.frame
    local settings = ADDON.DB:Settings()
    for _, c in ipairs(f.checks) do c:SetChecked((c.store or settings)[c.key]) end

    -- Activity entries, newest first. Cap changes on one item within 10s
    -- collapse to the newest, so retyping a cap doesn't flood the feed.
    local shown, lastCap = 0, {}
    for _, e in ipairs(ADDON.Log:Query()) do
        if shown == FEED_MAX then break end
        local keep = ADDON.Log.LEVEL[e.kind] == "activity"
        if keep and e.kind == "cap_change" then
            keep = not (lastCap[e.itemID] and lastCap[e.itemID] - e.ts < CAP_DEBOUNCE)
            if keep then lastCap[e.itemID] = e.ts end
        end
        if keep then
            shown = shown + 1
            local row = FeedRow(f, shown)
            -- Base colour on the font string (red for failures), so the item
            -- name's |r falls back to it; the name itself is quality-coloured.
            row.text:SetText(("|cff8c8c8c[%s]|r %s"):format(date("%H:%M", e.ts), ADDON.Log:Format(e, false, true)))
            row.text:SetTextColor(unpack((e.kind == "error" or e.kind == "buy_fail") and { 1, 0.533, 0.533 } or { 1, 1, 1 }))
            row:Show()
        end
    end
    for i = shown + 1, #f.feedRows do f.feedRows[i]:Hide() end
    f.feed:SetHeight(math.max(1, shown * 14))
end

-- Log calls this for each new activity entry.
function Sidecar:OnActivity()
    if self:IsShown() then self:Refresh() end
end

function Sidecar:Toggle()
    local f = self.frame or Build()
    if f:IsShown() then return f:Hide() end
    self:Refresh()
    MF:ShowPanel(f)
end

function Sidecar:Hide()
    if self.frame then self.frame:Hide() end
end

function Sidecar:IsShown()
    return self.frame and self.frame:IsShown()
end
