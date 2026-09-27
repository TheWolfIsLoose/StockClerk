--[[
    Stock Clerk - UI/Sidecar.lua

    Side panel: settings, "Add common consumables" and Recent Activity.
    Toggled by the header hamburger; hangs off the main window's right edge.

    Layout:
      * ~260w fixed, height matches MainFrame
      * Top section: Settings (auto-open and Express-Restock toggles) and
        "Add common consumables".
      * Hairline 1px divider
      * Bottom section: Recent Activity feed (newest first): buys, cap
        changes and restock start/stop. `/clerk log` shows everything.
]]

local addonName = ...
local ADDON     = _G[addonName]

local Sidecar = {}
ADDON.Sidecar = Sidecar

local Palette = ADDON.MainFrame.Palette
local ApplyFill, AddBlackBorder = ADDON.MainFrame.ApplyFill, ADDON.MainFrame.AddBlackBorder

local WIDTH = 260

-- -------------------------------------------------------------------------
-- Build the Sidecar panel lazily.
-- -------------------------------------------------------------------------
local function Build(anchor)
    local f = CreateFrame("Frame", "StockClerkSidecar", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 400)  -- height overridden in Toggle to match MainFrame
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(20)
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:Hide()

    ApplyFill(f, Palette.panelBg)
    AddBlackBorder(f)

    -- Anchor default (may be re-anchored by Toggle if MainFrame moves).
    if anchor then
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 1, 0)
    else
        f:SetPoint("CENTER")
    end

    -- ---- Settings section --------------------------------------------
    local settingsTitle = f:CreateFontString(nil, "OVERLAY", "StockClerkFontNormal")
    settingsTitle:SetPoint("TOPLEFT", 12, -10)
    settingsTitle:SetText("|cff98FF98Settings|r")

    -- Checkbox rows: label says what it does; a tooltip only where it
    -- needs more than the label. The label is part of the click area.
    local function Check(y, label, key, tipTitle, tipBody)
        -- Flat box: dark well + black border like the edit boxes, a mint
        -- square when on, a faint wash on hover.
        local c = CreateFrame("CheckButton", nil, f)
        c:SetPoint("TOPLEFT", 14, y - 3)
        c:SetSize(16, 16)
        c:SetHitRectInsets(0, -(WIDTH - 40), 0, 0)
        ApplyFill(c, Palette.fieldFill)
        AddBlackBorder(c)
        local tick = c:CreateTexture(nil, "OVERLAY")
        tick:SetColorTexture(Palette.brand[1], Palette.brand[2], Palette.brand[3], 1)
        tick:SetSize(8, 8)
        tick:SetPoint("CENTER")
        c:SetCheckedTexture(tick)
        local wash = c:CreateTexture(nil, "HIGHLIGHT")
        wash:SetColorTexture(1, 1, 1, 0.12)
        wash:SetAllPoints()
        local text = c:CreateFontString(nil, "OVERLAY", "StockClerkFontHighlight")
        text:SetPoint("LEFT", c, "RIGHT", 8, 0)
        text:SetText(label)
        c:SetScript("OnClick", function(self)
            local on = self:GetChecked() and true or false
            ADDON.DB:Settings()[key] = on
            ADDON.Log:Emit("setting", nil, { key = key, on = on })
        end)
        if tipTitle then
            c:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tipTitle, 1, 1, 1)
                GameTooltip:AddLine(tipBody, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            c:SetScript("OnLeave", GameTooltip_Hide)
        end
        c._key = key
        return c
    end
    -- The autoRestock key predates the "Express-Restock" label and stays
    -- for saved-settings compatibility.
    f._checks = {
        Check(-30, "Auto-open at Auction House", "autoOpenAtAH"),
        Check(-52, "Auto-open at Bank",          "autoOpenAtBank"),
        Check(-74, "Express-Restock at Auction House", "autoRestock",
            "Express-Restock at Auction House",
            "When you open the AH and something is short, start buying right away. You still confirm each purchase."),
        Check(-96, "Express-Restock at Bank", "autoRestockBank",
            "Express-Restock at Bank",
            "When you open your bank and something is short, pull it from your bank and warband bank right away."),
    }

    -- Side panel buttons use the main window's button recipe.
    local function Button(y, label, tipTitle, tipBody, onClick)
        local b = CreateFrame("Button", nil, f)
        b:SetPoint("TOPLEFT", 12, y)
        b:SetPoint("RIGHT", -12, 0)
        b:SetHeight(22)
        ADDON.MainFrame.StyleButton(b)
        b:SetText(label)
        b:SetNormalFontObject("StockClerkFontHighlight")
        b:HookScript("OnEnter", function(self)  -- Hook, not Set: keeps the hover wash
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tipTitle, 1, 1, 1)
            GameTooltip:AddLine(tipBody, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", GameTooltip_Hide)
        b:SetScript("OnClick", onClick)
        return b
    end
    Button(-126, "Add common consumables", "Add common consumables",
        "Adds this expansion's go-to potions, flasks and weapon oils with a target of 1. Items already on your list are left as they are.",
        function()
            local n  = ADDON.DB:AddCommonConsumables()
            local mf = ADDON.MainFrame
            if mf.frame and mf.frame:IsShown() then mf:Refresh() end
            mf:SetStatus(n > 0
                and ("Added %d items. Remove any you don't need with the red X on each row."):format(n)
                or  "All the common consumables are already on your list.")
        end)

    -- ---- Divider -----------------------------------------------------
    local divider = f:CreateTexture(nil, "OVERLAY", nil, 6)
    divider:SetColorTexture(0, 0, 0, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 8, -158)
    divider:SetPoint("TOPRIGHT", -8, -158)

    -- ---- Activity feed section --------------------------------------
    local feedTitle = f:CreateFontString(nil, "OVERLAY", "StockClerkFontNormal")
    feedTitle:SetPoint("TOPLEFT", 12, -166)
    feedTitle:SetText("|cff98FF98Recent Activity|r")

    -- Hovering the title explains the feed and how to send a bug report;
    -- the "/clerk log" link opens the full log.
    local feedHelp = CreateFrame("Frame", nil, f)
    feedHelp:SetAllPoints(feedTitle)
    feedHelp:EnableMouse(true)
    local function ShowFeedHelp(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText("Recent Activity", 1, 1, 1)
        GameTooltip:AddLine("What StockClerk did, newest first.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Something not working?", 1, 1, 1)
        GameTooltip:AddLine("1. Type /clerk log (or click the link) and press Ctrl+C.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("2. Paste it into your bug report.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("If the problem happens again and again: type /clerk debug first, repeat the problem, then /clerk log.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end
    feedHelp:SetScript("OnEnter", ShowFeedHelp)
    feedHelp:SetScript("OnLeave", GameTooltip_Hide)

    local feedLink = CreateFrame("Button", nil, f)
    feedLink:SetPoint("TOPRIGHT", -12, -168)
    feedLink:SetSize(60, 14)
    local feedHint = feedLink:CreateFontString(nil, "OVERLAY", "StockClerkFontDisableSmall")
    feedHint:SetPoint("RIGHT")
    feedHint:SetText("/clerk log")
    feedHint:SetTextColor(0.42, 0.42, 0.42, 1)
    feedLink:SetScript("OnEnter", function(self)
        feedHint:SetTextColor(Palette.brand[1], Palette.brand[2], Palette.brand[3], 1)
        ShowFeedHelp(self)
    end)
    feedLink:SetScript("OnLeave", function()
        feedHint:SetTextColor(0.42, 0.42, 0.42, 1)
        GameTooltip:Hide()
    end)
    feedLink:SetScript("OnClick", function() ADDON.LogPopup:Toggle() end)

    -- Scrollframe hosts the feed rows. Simple, no fancy pooling -- the
    -- panel is bounded and refreshes on Emit, so ~30 rows is the ceiling.
    local scrollBg = f:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetColorTexture(Palette.bgDark[1], Palette.bgDark[2], Palette.bgDark[3], 0.6)
    scrollBg:SetPoint("TOPLEFT", 8, -188)
    scrollBg:SetPoint("BOTTOMRIGHT", -8, 8)

    local scrollFrame = CreateFrame("ScrollFrame", "StockClerkSidecarScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -190)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 10)  -- -28 leaves room for the scrollbar

    local feedContent = CreateFrame("Frame", nil, scrollFrame)
    feedContent:SetSize(WIDTH - 40, 1)  -- height grows in Refresh
    scrollFrame:SetScrollChild(feedContent)
    f._feedContent = feedContent
    f._feedRows = {}

    Sidecar.frame = f
    return f
end

-- One feed line: grey [time], then the log's wording with the item name in
-- its quality colour. Returns the text and whether it's a failure (red).
local function FormatEntry(entry)
    local failed = entry.kind == "error" or entry.kind == "buy_fail"
    return ("|cff888888[%s]|r %s"):format(date("%H:%M", entry.ts or time()), ADDON.Log:Format(entry, false, true)), failed
end

-- -------------------------------------------------------------------------
-- Public: Refresh both sections.
-- -------------------------------------------------------------------------
function Sidecar:Refresh()
    local f = self.frame
    if not f then return end
    local s = ADDON.DB:Settings()

    -- Settings widgets
    for _, c in ipairs(f._checks) do c:SetChecked(s[c._key] and true or false) end

    -- Activity feed: activity-level entries only (the log window has the
    -- rest). Cap changes on one item within 10s collapse to the newest so
    -- retyping a cap doesn't flood the feed.
    for _, r in ipairs(f._feedRows) do r:Hide() end

    local raw = {}
    if ADDON.Log and ADDON.Log.Query then
        raw = ADDON.Log:Query()  -- newest-first
    end

    local CAP_DEBOUNCE_SEC = 10

    local entries = {}
    local lastCapByItem = {}  -- itemID -> ts of last kept cap_change
    for i = 1, #raw do
        local e = raw[i]
        if ADDON.Log.LEVEL[e.kind] == "activity" then
            if e.kind == "cap_change" and e.itemID then
                local prev = lastCapByItem[e.itemID]
                -- Raw is newest-first, so "prev" is a NEWER kept entry;
                -- we drop this one if it's within 10s of that newer one.
                if prev and (prev - (e.ts or 0)) < CAP_DEBOUNCE_SEC then
                    -- Swallow
                else
                    lastCapByItem[e.itemID] = e.ts or 0
                    entries[#entries + 1] = e
                end
            else
                entries[#entries + 1] = e
            end
        end
    end

    local MAX = 30
    local content = f._feedContent
    local y = 0
    for i = 1, math.min(#entries, MAX) do
        local e = entries[i]
        local row = f._feedRows[i]
        if not row then
            -- Row i always sits at the same height; a cut-off line shows in
            -- full in a tooltip (no horizontal scrolling in WoW's scroll frames).
            row = CreateFrame("Frame", nil, content)
            row:SetPoint("TOPLEFT", 4, -y)
            row:SetPoint("RIGHT", -4, 0)
            row:SetHeight(14)
            row.text = row:CreateFontString(nil, "ARTWORK", "StockClerkFontHighlightSmall")
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
            f._feedRows[i] = row
        end
        -- The line's base colour lives on the font string, so the item name's
        -- |r falls back to it (red for failures) instead of to white.
        local text, failed = FormatEntry(e)
        row.text:SetText(text)
        if failed then row.text:SetTextColor(1, 0.53, 0.53) else row.text:SetTextColor(1, 1, 1) end
        row:Show()
        y = y + 14
    end
    content:SetHeight(math.max(1, y))
end

-- -------------------------------------------------------------------------
-- Public: toggle the panel anchored to the header hamburger button. We
-- prefer to anchor to the MainFrame's TOPRIGHT (not the button) so the
-- sidecar hangs off the window itself; the button is only passed so we
-- can traverse up to the frame if MainFrame's reference isn't available.
-- -------------------------------------------------------------------------
function Sidecar:Toggle(anchorButton)
    local mainFrame = (ADDON.MainFrame and ADDON.MainFrame.frame) or nil
    local anchor    = mainFrame or (anchorButton and anchorButton:GetParent()) or UIParent
    local f = self.frame or Build(anchor)

    if f:IsShown() then
        f:Hide()
        return
    end

    -- Re-anchor to current main frame each open so a moved main window
    -- carries the sidecar with it. Match height to the main frame.
    f:ClearAllPoints()
    if mainFrame then
        f:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 1, 0)
        f:SetHeight(mainFrame:GetHeight())
    else
        f:SetPoint("CENTER")
    end

    if ADDON.BulkImport then ADDON.BulkImport:Close() end  -- one panel at a time
    self:Refresh()
    f:Show()
end

function Sidecar:Hide()
    if self.frame then self.frame:Hide() end
end

function Sidecar:IsShown()
    return self.frame and self.frame:IsShown()
end

-- -------------------------------------------------------------------------
-- Bridge: when the log emits a new entry AND the sidecar is open, refresh
-- the feed. Log.lua already has a hook that refreshes LogFrame if it's
-- open; we ride the same convention by having Log check for us too.
-- Rather than editing Log.lua to know about a second consumer, we hook
-- Log:Emit here at file-load time.
-- -------------------------------------------------------------------------
do
    if ADDON.Log and ADDON.Log.Emit and not ADDON.Log._sidecar_hook then
        local origEmit = ADDON.Log.Emit
        ADDON.Log.Emit = function(self, kind, itemID, payload)
            origEmit(self, kind, itemID, payload)
            -- Only kinds the feed shows; status messages (most emits)
            -- would rebuild the feed for no visible change.
            if ADDON.Log.LEVEL[kind] == "activity" and Sidecar.frame and Sidecar.frame:IsShown() then
                -- Guard: avoid recursive refresh if a Refresh() call ends
                -- up emitting its own log entry (nothing today does, but
                -- cheap insurance for future changes).
                if not Sidecar._refreshing then
                    Sidecar._refreshing = true
                    pcall(Sidecar.Refresh, Sidecar)
                    Sidecar._refreshing = false
                end
            end
        end
        ADDON.Log._sidecar_hook = true
    end
end
