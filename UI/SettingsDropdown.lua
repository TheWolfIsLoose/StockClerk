--[[
    Stock Clerk - UI/SettingsDropdown.lua
    Compact settings surface attached to the header cog button.

    Toggles + fields:
      - Auto-purchase on/off (QA-10)
      - Daily auto budget (gold, required when auto is on; realm-reset aligned)
      - Daily auto-spend readout (informational; manual buys excluded by design)
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
    text         = "Enable auto-purchase?\n\n%d tracked items have no price cap set. Those items will be SKIPPED by auto-purchase.\n\nAuto budget: %s per day (resets at daily realm reset). Manual buys are never limited.",
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
    -- Height grew to 218 in v0.5 to fit the PT-1 Batch 2 "Default cap per
    -- unit" row between the auto-hint and the auto-budget line.
    f:SetSize(260, 218)
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
    autoHint:SetText("Uncapped items skipped unless a default is set. Esc cancels a running loop.")

    -- Default cap field (PT-1 v0.5 Batch 2). When set, auto-mode uses
    -- this cap for items with no per-item maxPrice; leave blank to
    -- preserve the v0.4 "uncapped => auto skip" contract. Accepts the
    -- same g/s/c syntax as the row inline editor.
    local defCapLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    defCapLabel:SetPoint("TOPLEFT", 12, -80)
    defCapLabel:SetText("Default cap per unit (auto only):")

    local defCapBg = f:CreateTexture(nil, "BACKGROUND")
    defCapBg:SetColorTexture(P().bgDark[1], P().bgDark[2], P().bgDark[3], 1)
    defCapBg:SetPoint("TOPLEFT", 12, -100)
    defCapBg:SetSize(120, 22)

    local defCapEdit = CreateFrame("EditBox", nil, f)
    defCapEdit:SetFontObject("GameFontHighlight")
    defCapEdit:SetAutoFocus(false)
    defCapEdit:SetNumeric(false) -- accepts g/s/c tokens
    defCapEdit:SetMaxLetters(14)
    defCapEdit:SetJustifyH("LEFT")
    defCapEdit:SetPoint("TOPLEFT", 16, -102)
    defCapEdit:SetSize(112, 18)
    f._defCapEdit = defCapEdit

    -- Budget field (QA-10a)
    local budgetLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    budgetLabel:SetPoint("TOPLEFT", 12, -128)
    budgetLabel:SetText("Auto budget per day (gold):")

    -- EditBox for the budget. Backing frame for the border.
    local budgetBg = f:CreateTexture(nil, "BACKGROUND")
    budgetBg:SetColorTexture(P().bgDark[1], P().bgDark[2], P().bgDark[3], 1)
    budgetBg:SetPoint("TOPLEFT", 12, -148)
    budgetBg:SetSize(120, 22)

    local budgetEdit = CreateFrame("EditBox", nil, f)
    budgetEdit:SetFontObject("GameFontHighlight")
    budgetEdit:SetAutoFocus(false)
    budgetEdit:SetNumeric(true)
    budgetEdit:SetMaxLetters(9)
    budgetEdit:SetJustifyH("LEFT")
    budgetEdit:SetPoint("TOPLEFT", 16, -150)
    budgetEdit:SetSize(112, 18)
    f._budgetEdit = budgetEdit

    -- Daily auto-spend readout. Full-width line at the panel bottom so
    -- the budget fraction + reset countdown never clips (v0.4: moved
    -- from the 112px slot beside the budget box).
    local spentLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    spentLabel:SetPoint("TOPLEFT", 12, -196)
    spentLabel:SetPoint("RIGHT", -8, 0)
    spentLabel:SetJustifyH("LEFT")
    spentLabel:SetWordWrap(false)
    f._spentLabel = spentLabel

    -- Auto-open at AH (moved here from... nowhere; was previously
    -- settings-file-only). Modest inclusion, one checkbox.
    local ahCheck = CreateFrame("CheckButton", "StockClerkAHCheck", f, "UICheckButtonTemplate")
    ahCheck:SetPoint("TOPLEFT", 8, -172)
    ahCheck:SetSize(22, 22)
    _G[ahCheck:GetName() .. "Text"]:SetText("Auto-open at Auction House")
    _G[ahCheck:GetName() .. "Text"]:SetTextColor(0.9, 0.9, 0.9, 1)
    f._ahCheck = ahCheck

    -- --- Wire callbacks ------------------------------------------------
    autoCheck:SetScript("OnClick", function(self)
        local s = ADDON.DB:Settings()
        if self:GetChecked() then
            -- Enable path: roll back the visual check state, then pop
            -- the confirmation modal; its OnAccept performs the enable.
            self:SetChecked(false)
            Settings:RequestAutoEnable()
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

    -- Default cap commit: same g/s/c parser as the row editor. Blank
    -- clears the default (auto reverts to skipping uncapped items).
    -- Bad input surfaces via MainFrame status and leaves the setting
    -- unchanged so a typo can't silently drop the default.
    local function CommitDefCap()
        local s = ADDON.DB:Settings()
        local raw = defCapEdit:GetText() or ""
        local copper, ok = nil, true
        if ADDON.DB and ADDON.DB.ParsePriceString then
            copper, ok = ADDON.DB.ParsePriceString(raw)
        else
            local n = tonumber(raw)
            copper = (n and n > 0) and (n * 10000) or nil
        end
        if not ok then
            if ADDON.MainFrame and ADDON.MainFrame.SetStatus then
                ADDON.MainFrame:SetStatus(("|cffff8888Default cap unchanged: couldn't parse '%s' (try 12g, 12g50s, 500c).|r"):format(raw))
            end
            Settings:Refresh() -- restore prior text
            return
        end
        s.defaultMaxCopper = copper
        Settings:Refresh()
        if ADDON.MainFrame and ADDON.MainFrame.Refresh then ADDON.MainFrame:Refresh() end
    end
    defCapEdit:SetScript("OnEnterPressed",   function(self) self:ClearFocus() end)
    defCapEdit:SetScript("OnEditFocusLost",  CommitDefCap)
    defCapEdit:SetScript("OnEscapePressed",  function(self) self:ClearFocus() end)

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
        if defCapEdit:HasFocus() then defCapEdit:ClearFocus() end
    end)

    Settings.frame = f
    return f
end

-- ---------------------------------------------------------------------------
-- Public: request enabling auto-purchase WITH the click-to-confirm
-- modal counting uncapped items. Single entry point used by both the
-- settings checkbox and `/clerk auto on`, so no caller can bypass the
-- QA-10 confirmation requirement. (The slash-command path previously
-- enabled directly -- code-review v0.2.0..HEAD finding 5, scope creep.)
function Settings:RequestAutoEnable()
    local s = ADDON.DB:Settings()
    local uncapped = 0
    for _, entry in pairs(ADDON.DB:GetItems()) do
        if not entry.maxPrice then uncapped = uncapped + 1 end
    end
    -- PT-1 v0.5 Batch 2: if a global default cap is set, uncapped items
    -- are NOT skipped -- they inherit the default. Reflect that in the
    -- confirmation modal so "12 uncapped items will be skipped" doesn't
    -- lie to the user when auto will actually buy them at the default.
    local defC = s.defaultMaxCopper
    local budgetText
    if defC and defC > 0 and uncapped > 0 then
        -- Uncapped items are not skipped; they inherit the default. Zero
        -- out the uncapped count so the popup template's "N will be
        -- skipped" bullet reads accurately, and fold the default-cap
        -- notice into budgetText (the template only substitutes two
        -- values, so we have to reuse an existing slot).
        local shortText = (ADDON.DB.FormatCopperShort and ADDON.DB.FormatCopperShort(defC))
            or (("%dg"):format(math.floor(defC / 10000)))
        uncapped = 0
        local budgetPart = s.autoBudgetGold and (s.autoBudgetGold .. "g") or "not set"
        budgetText = ("%s  \194\183  default cap %s per unit"):format(budgetPart, shortText)
    else
        budgetText = s.autoBudgetGold and (s.autoBudgetGold .. "g") or "not set (will use unlimited)"
    end
    local dlg = StaticPopup_Show("STOCKCLERK_AUTO_ENABLE", uncapped, budgetText)
    -- If the popup was suppressed for any reason (another popup at max
    -- stack), fall back to enabling without confirmation rather than
    -- silently doing nothing.
    if not dlg then
        s.autoPurchase = true
        if ADDON.Log then ADDON.Log:Emit("auto_toggle", nil, { on = true }) end
        self:Refresh()
        if ADDON.MainFrame and ADDON.MainFrame.Refresh then ADDON.MainFrame:Refresh() end
    end
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

    -- PT-1 v0.5 Batch 2: default cap readout.
    if f._defCapEdit then
        if s.defaultMaxCopper and s.defaultMaxCopper > 0 then
            local fmtFn = ADDON.DB and ADDON.DB.FormatCopperShort
            f._defCapEdit:SetText(fmtFn and fmtFn(s.defaultMaxCopper) or tostring(math.floor(s.defaultMaxCopper / 10000)) .. "g")
        else
            f._defCapEdit:SetText("")
        end
    end

    -- Daily auto-spend readout: spent toward the daily auto budget
    -- since the last realm daily reset (manual buys don't count here
    -- by design -- see DB.lua budget semantics). Seconds-until-reset
    -- labeled in hours so the day boundary is legible at a glance.
    local autoSpendG = math.floor((ADDON.DB:GetDailyAutoSpend() or 0) / 10000)
    local budgetG    = s.autoBudgetGold
    local resetAt    = ADDON.DB.GetDailyResetAt and ADDON.DB:GetDailyResetAt() or nil
    local resetH     = ""
    if resetAt then
        local secs = math.max(0, resetAt - GetServerTime())
        resetH = (" (resets in %.1fh)"):format(secs / 3600)
    end
    if budgetG then
        f._spentLabel:SetText(("auto spent today: %dg / %dg%s"):format(autoSpendG, budgetG, resetH))
    else
        f._spentLabel:SetText(("auto spent today: %dg%s (no budget set)"):format(autoSpendG, resetH))
    end
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
