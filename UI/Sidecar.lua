--[[
    Stock Clerk - UI/Sidecar.lua

    v0.7 redesign: right-docked companion panel that merges the two v0.6
    surfaces (SettingsDropdown + LogFrame) into a single flyout. Toggled
    from the header hamburger button. Anchored TOPLEFT to the MainFrame's
    TOPRIGHT so it grows out to the right without covering the list.

    Layout:
      * ~260w fixed, height matches MainFrame
      * Top section: Settings (auto-open and Express-Restock toggles) and
        the list builders (common consumables, bulk import).
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

-- Log kinds the activity feed shows.
local FEED_KINDS = {
    buy_success = true,
    buy_fail    = true,
    cap_change  = true,
    auto_refuse = true,
    loop_start  = true,
    loop_stop   = true,
    bank_pull   = true,
}

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
        local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        c:SetPoint("TOPLEFT", 8, y)
        c:SetSize(22, 22)
        c:SetHitRectInsets(0, -(WIDTH - 40), 0, 0)
        local text = c:CreateFontString(nil, "OVERLAY", "StockClerkFontHighlight")
        text:SetPoint("LEFT", c, "RIGHT", 2, 0)
        text:SetText(label)
        c:SetScript("OnClick", function(self)
            ADDON.DB:Settings()[key] = self:GetChecked() and true or false
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

    -- List builders. Same button recipe as the main window.
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
    Button(-152, "Bulk import item IDs", "Bulk import item IDs",
        "Paste a list of item IDs, one per line, to add them all at once.",
        function() ADDON.BulkImport:Open() end)

    -- ---- Divider -----------------------------------------------------
    local divider = f:CreateTexture(nil, "OVERLAY", nil, 6)
    divider:SetColorTexture(0, 0, 0, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 8, -184)
    divider:SetPoint("TOPRIGHT", -8, -184)

    -- ---- Activity feed section --------------------------------------
    local feedTitle = f:CreateFontString(nil, "OVERLAY", "StockClerkFontNormal")
    feedTitle:SetPoint("TOPLEFT", 12, -192)
    feedTitle:SetText("|cff98FF98Recent Activity|r")

    -- "log" hint anchored to feedTitle's right so the user can find the
    -- full log dump.
    local feedHint = f:CreateFontString(nil, "OVERLAY", "StockClerkFontDisableSmall")
    feedHint:SetPoint("TOPRIGHT", -12, -196)
    feedHint:SetText("|cff6a6a6a/clerk log|r")

    -- Scrollframe hosts the feed rows. Simple, no fancy pooling -- the
    -- panel is bounded and refreshes on Emit, so ~30 rows is the ceiling.
    local scrollBg = f:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetColorTexture(Palette.bgDark[1], Palette.bgDark[2], Palette.bgDark[3], 0.6)
    scrollBg:SetPoint("TOPLEFT", 8, -214)
    scrollBg:SetPoint("BOTTOMRIGHT", -8, 8)

    local scrollFrame = CreateFrame("ScrollFrame", "StockClerkSidecarScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -216)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 10)  -- -28 leaves room for the scrollbar

    local feedContent = CreateFrame("Frame", nil, scrollFrame)
    feedContent:SetSize(WIDTH - 40, 1)  -- height grows in Refresh
    scrollFrame:SetScrollChild(feedContent)
    f._feedContent = feedContent
    f._feedRows = {}

    Sidecar.frame = f
    return f
end

-- -------------------------------------------------------------------------
-- Format one log entry as one line of feed text. Deliberately short -- the
-- sidecar is a preview, not the full log. Phase D adds tag prefixes
-- ([BUY]/[CAP]/[AUTO-BLOCK]) and cap-change debouncing.
-- -------------------------------------------------------------------------
local function FormatEntry(entry)
    local kind = entry.kind or "?"
    local pay  = entry.payload or {}
    local itemLink = nil
    if entry.itemID then
        -- GetItemInfo may return nil if the client hasn't cached this id
        -- yet; fall back to id string in that case.
        local _, link = GetItemInfo(entry.itemID)
        itemLink = link or ("item:" .. entry.itemID)
    end
    local when = date("%H:%M", entry.ts or time())

    if kind == "buy_success" then
        local g = math.floor((pay.spentCopper or 0) / 10000)
        return ("|cff98FF98[%s] [BUY]|r %sx%s (%dg)"):format(when, itemLink or "?", pay.qty or "?", g)
    elseif kind == "bank_pull" then
        return ("|cff98FF98[%s] [BANK]|r %sx%s from bank"):format(when, itemLink or "?", pay.qty or "?")
    elseif kind == "cap_change" then
        local from = pay.fromCopper and math.floor(pay.fromCopper / 10000) .. "g" or "unset"
        local to   = pay.toCopper   and math.floor(pay.toCopper   / 10000) .. "g" or "unset"
        return ("|cffe5e0a5[%s] [CAP]|r %s -> %s on %s"):format(when, from, to, itemLink or "?")
    elseif kind == "auto_refuse" then
        return ("|cffe5624a[%s] [AUTO-BLOCK]|r %s"):format(when, pay.reason or "?")
    elseif kind == "buy_fail" then
        return ("|cffe5624a[%s] [BUY-FAIL]|r %s (%s)"):format(when, itemLink or "?", pay.reason or "?")
    elseif kind == "target_change" then
        return ("|cffcccccc[%s]|r target %s -> %s on %s"):format(when, pay.from or "?", pay.to or "?", itemLink or "?")
    elseif kind == "add" then
        return ("|cffcccccc[%s]|r added %s (need %s)"):format(when, itemLink or "?", pay.need or "?")
    elseif kind == "remove" then
        return ("|cff888888[%s]|r removed %s|r"):format(when, itemLink or "?")
    elseif kind == "loop_start" then
        return ("|cff98FF98[%s]|r loop start (%s, %s items)"):format(when, pay.mode or "?", pay.queueSize or 0)
    elseif kind == "loop_stop" then
        local g = math.floor((pay.spentCopper or 0) / 10000)
        return ("|cff888888[%s]|r loop stop: %s (%dg spent)"):format(when, pay.reason or "?", g)
    elseif kind == "auto_toggle" then
        return ("|cffcccccc[%s]|r auto %s"):format(when, pay.on and "ON" or "OFF")
    elseif kind == "status" then
        return ("|cff888888[%s]|r %s"):format(when, pay.text or "")
    else
        return ("|cff888888[%s]|r %s|r"):format(when, kind)
    end
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

    -- Activity feed. Two-tier model per v0.7 spec:
    -- * BASIC (this sidecar): curated action-focused entries only.
    --   Buys, cap changes (debounced 10s per item), and auto-blocks.
    --   Cap-change debouncing collapses rapid retyping of the cap edit
    --   box so the feed doesn't churn on every keystroke.
    -- * VERBOSE (LogPopup / `/clerk log`): everything, unfiltered.
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
        if FEED_KINDS[e.kind] then
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
            row = content:CreateFontString(nil, "ARTWORK", "StockClerkFontHighlightSmall")
            row:SetPoint("TOPLEFT", 4, -y)
            row:SetPoint("RIGHT", -4, 0)
            row:SetJustifyH("LEFT")
            row:SetWordWrap(false)
            f._feedRows[i] = row
        else
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -y)
            row:SetPoint("RIGHT", -4, 0)
        end
        row:SetText(FormatEntry(e))
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
            if FEED_KINDS[kind] and Sidecar.frame and Sidecar.frame:IsShown() then
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
