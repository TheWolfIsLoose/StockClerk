--[[
    Stock Clerk - UI/SettingsDropdown.lua
    Compact settings surface attached to the header cog button.

    Toggles + fields:
      - Auto-purchase on/off (QA-10)
      - Budget (gold, required when auto is on) (QA-10a)
      - Session spent readout (informational)
      - Auto-open at AH (existing setting, moved from elsewhere)

    Design notes:
      - Renders as a small floating panel anchored to the cog button.
        Not a StaticPopup: too heavy for a settings surface. Not a
        separate window: users shouldn't have to hunt for it.
      - Click-to-confirm enable modal per user preference. First-time
        enable pops a StaticPopup counting uncapped items that will
        be excluded from auto-runs.
      - Budget field is a plain gold-value editbox. Blank/0 = unset.
        Auto-purchase requires a non-nil budget to actually run
        (fail-safe in RestockLoop; UI just warns).
--]]

local addonName = ...
local ADDON     = _G[addonName]

local Settings = {}
ADDON.SettingsDropdown = Settings

-- (No WHITE_TEX path -- we use SetColorTexture for solid fills. The
-- WoW "White8x8" atlas returns a texture whose own alpha gates the
-- vertex-color alpha to zero on retail Midnight, which is why the first
-- draft of this dropdown rendered as fully transparent.)

local function P()
    return (ADDON.MainFrame and ADDON.MainFrame.Palette) or {
        bg        = { 0.06, 0.06, 0.06, 0.98 },
        bgMedium  = { 0.10, 0.10, 0.10, 1 },
        bgDark    = { 0.04, 0.04, 0.04, 1 },
        bandTint  = { 1, 1, 1, 0.02 },
        border    = { 0, 0, 0, 1 },
        brand     = { 0.60, 1.00, 0.60, 1 },
    }
end

-- ---------------------------------------------------------------------------
-- Enable-confirmation StaticPopup (QA-10)
-- ---------------------------------------------------------------------------
StaticPopupDialogs["STOCKCLERK_AUTO_ENABLE"] = {
    text         = "Enable auto-purchase?\n\n%d tracked items have no price cap set. Those items will be SKIPPED by auto-purchase.\n\nBudget: %s per loop.",
    button1      = "Enable",
    button2      = "Cancel",
    OnAccept     = function()
        ADDON.DB:Settings().autoPurchase = true
        if ADDON.Log then
            ADDON.Log:Emit("auto_toggle", nil, { on = true })
        end
        if ADDON.SettingsDropdown and ADDON.SettingsDropdown.Refresh then
            ADDON.SettingsDropdown:Refresh()
        end
        if ADDON.MainFrame and ADDON.MainFrame.Refresh then
            ADDON.MainFrame:Refresh()
        end
    end,
    OnCancel     = function() end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ---------------------------------------------------------------------------
-- Build the dropdown (lazy)
-- ---------------------------------------------------------------------------
local function BuildDropdown(anchor)
    -- Full-screen click-catcher behind the panel. Parented to UIParent
    -- at the same strata so it swallows a click anywhere off the panel
    -- and closes it. Without this, the dropdown lingers behind other
    -- UI whenever the user clicks away, forcing them to click the cog
    -- again to dismiss.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    catcher:Hide()

    local f = CreateFrame("Frame", "StockClerkSettingsDropdown", UIParent, "BackdropTemplate")
    f:SetSize(260, 180)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(10)                       -- above the catcher
    f:SetToplevel(true)
    f:EnableMouse(true)                       -- swallow clicks on the panel
    f:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    f:Hide()

    -- Catcher only fires when the click missed the panel (the panel is
    -- above the catcher and swallows its own clicks via EnableMouse).
    catcher:SetScript("OnClick", function() f:Hide() end)
    f._catcher = catcher

    -- Solid fill + 1px black border, matching MainFrame's chrome vocab.
    -- Uses SetColorTexture (not SetTexture path + SetVertexColor); see
    -- the top-of-file note on why the atlas path renders transparent.
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(P().bg[1], P().bg[2], P().bg[3], P().bg[4] or 1)

    local function edge(anchorA, anchorB, isHoriz)
        local t = f:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetColorTexture(0, 0, 0, 1)
        if isHoriz then
            t:SetHeight(1)
            t:SetPoint(anchorA, 0, 0)
            t:SetPoint(anchorB, 0, 0)
        else
            t:SetWidth(1)
            t:SetPoint(anchorA, 0, 0)
            t:SetPoint(anchorB, 0, 0)
        end
    end
    edge("TOPLEFT",     "TOPRIGHT",    true)
    edge("BOTTOMLEFT",  "BOTTOMRIGHT", true)
    edge("TOPLEFT",     "BOTTOMLEFT",  false)
    edge("TOPRIGHT",    "BOTTOMRIGHT", false)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cff98FF98Settings|r")

    -- Auto-purchase toggle
    local autoCheck = CreateFrame("CheckButton", "StockClerkAutoCheck", f, "UICheckButtonTemplate")
    autoCheck:SetPoint("TOPLEFT", 8, -32)
    autoCheck:SetSize(22, 22)
    _G[autoCheck:GetName() .. "Text"]:SetText("Auto-purchase (opt in)")
    _G[autoCheck:GetName() .. "Text"]:SetTextColor(0.9, 0.9, 0.9, 1)
    f._autoCheck = autoCheck

    -- Explanation line under the toggle
    local autoHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    autoHint:SetPoint("TOPLEFT", 30, -54)
    autoHint:SetPoint("RIGHT", -8, 0)
    autoHint:SetJustifyH("LEFT")
    autoHint:SetWordWrap(true)
    autoHint:SetText("Skips uncapped items. Esc cancels a running loop.")

    -- Budget field (QA-10a)
    local budgetLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    budgetLabel:SetPoint("TOPLEFT", 12, -80)
    budgetLabel:SetText("Budget per loop (gold):")

    -- EditBox for the budget. Backing frame for the border.
    local budgetBg = f:CreateTexture(nil, "BACKGROUND")
    budgetBg:SetColorTexture(P().bgDark[1], P().bgDark[2], P().bgDark[3], 1)
    budgetBg:SetPoint("TOPLEFT", 12, -100)
    budgetBg:SetSize(120, 22)

    local budgetEdit = CreateFrame("EditBox", nil, f)
    budgetEdit:SetFontObject("GameFontHighlight")
    budgetEdit:SetAutoFocus(false)
    budgetEdit:SetNumeric(true)
    budgetEdit:SetMaxLetters(9)
    budgetEdit:SetJustifyH("LEFT")
    budgetEdit:SetPoint("TOPLEFT", 16, -102)
    budgetEdit:SetSize(112, 18)
    f._budgetEdit = budgetEdit

    -- Session-so-far spent readout (from Log:Aggregate since session start).
    local spentLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    spentLabel:SetPoint("TOPLEFT", 140, -103)
    spentLabel:SetPoint("RIGHT", -8, 0)
    spentLabel:SetJustifyH("LEFT")
    spentLabel:SetWordWrap(false)
    f._spentLabel = spentLabel

    -- Auto-open at AH (moved here from... nowhere; was previously
    -- settings-file-only). Modest inclusion, one checkbox.
    local ahCheck = CreateFrame("CheckButton", "StockClerkAHCheck", f, "UICheckButtonTemplate")
    ahCheck:SetPoint("TOPLEFT", 8, -132)
    ahCheck:SetSize(22, 22)
    _G[ahCheck:GetName() .. "Text"]:SetText("Auto-open at Auction House")
    _G[ahCheck:GetName() .. "Text"]:SetTextColor(0.9, 0.9, 0.9, 1)
    f._ahCheck = ahCheck

    -- --- Wire callbacks ------------------------------------------------
    autoCheck:SetScript("OnClick", function(self)
        local s = ADDON.DB:Settings()
        if self:GetChecked() then
            -- Enable path: pop confirmation modal first. Roll back the
            -- visual check state; the modal's OnAccept will re-set it.
            self:SetChecked(false)
            local uncapped = 0
            for _, entry in pairs(ADDON.DB:GetItems()) do
                if not entry.maxPrice then uncapped = uncapped + 1 end
            end
            local budgetText = s.autoBudgetGold and (s.autoBudgetGold .. "g") or "not set (will use unlimited)"
            local dlg = StaticPopup_Show("STOCKCLERK_AUTO_ENABLE", uncapped, budgetText)
            -- If the popup was suppressed for any reason (e.g. another
            -- popup already at max) just enable without confirmation.
            if not dlg then
                s.autoPurchase = true
                if ADDON.Log then ADDON.Log:Emit("auto_toggle", nil, { on = true }) end
                Settings:Refresh()
                if ADDON.MainFrame then ADDON.MainFrame:Refresh() end
            end
        else
            -- Disable is one-click, no confirmation.
            s.autoPurchase = false
            if ADDON.Log then ADDON.Log:Emit("auto_toggle", nil, { on = false }) end
            Settings:Refresh()
            if ADDON.MainFrame then ADDON.MainFrame:Refresh() end
        end
    end)

    local function CommitBudget()
        local s = ADDON.DB:Settings()
        local n = tonumber(budgetEdit:GetText())
        if n and n > 0 then
            s.autoBudgetGold = n
        else
            s.autoBudgetGold = nil
        end
        Settings:Refresh()
    end
    budgetEdit:SetScript("OnEnterPressed",   function(self) self:ClearFocus() end)
    budgetEdit:SetScript("OnEditFocusLost",  CommitBudget)
    budgetEdit:SetScript("OnEscapePressed",  function(self) self:ClearFocus() end)

    ahCheck:SetScript("OnClick", function(self)
        ADDON.DB:Settings().autoOpenAtAH = self:GetChecked() and true or false
    end)

    -- Show/Hide handlers pair up the click-catcher with the panel so
    -- outside-click dismiss works, and clear focus on close so the
    -- budget edit doesn't hold the cursor after the panel goes away.
    f:SetScript("OnShow", function() catcher:Show() end)
    f:SetScript("OnHide", function()
        catcher:Hide()
        if budgetEdit:HasFocus() then budgetEdit:ClearFocus() end
    end)

    Settings.frame = f
    return f
end

-- ---------------------------------------------------------------------------
-- Public: refresh the widgets from the DB settings.
-- ---------------------------------------------------------------------------
function Settings:Refresh()
    local f = self.frame
    if not f then return end
    local s = ADDON.DB:Settings()

    f._autoCheck:SetChecked(s.autoPurchase and true or false)
    f._ahCheck:SetChecked(s.autoOpenAtAH and true or false)

    if s.autoBudgetGold then
        f._budgetEdit:SetText(tostring(s.autoBudgetGold))
    else
        f._budgetEdit:SetText("")
    end

    -- Session spent readout uses LogFrame.filter.since if set, else "today".
    local since = (ADDON.LogFrame and ADDON.LogFrame.filter and ADDON.LogFrame.filter.since)
        or (time() - 86400)
    local agg = ADDON.Log and ADDON.Log:Aggregate(since) or { spentCopper = 0 }
    local spentG = math.floor((agg.spentCopper or 0) / 10000)
    f._spentLabel:SetText(("spent %dg"):format(spentG))
end

-- ---------------------------------------------------------------------------
-- Public: toggle the dropdown anchored to the given button.
-- ---------------------------------------------------------------------------
function Settings:Toggle(anchor)
    local f = self.frame or BuildDropdown(anchor)
    if f:IsShown() then
        f:Hide()
    else
        self:Refresh()
        f:Show()
    end
end

function Settings:Hide()
    if self.frame then self.frame:Hide() end
end
