--[[
    Stock Clerk - UI/Sidecar.lua

    v0.7 redesign: right-docked companion panel that merges the two v0.6
    surfaces (SettingsDropdown + LogFrame) into a single flyout. Toggled
    from the header hamburger button. Anchored TOPLEFT to the MainFrame's
    TOPRIGHT so it grows out to the right without covering the list.

    Layout:
      * ~260w fixed, height matches MainFrame
      * Top section: Settings (auto-purchase toggle, default cap, budget,
        auto-open at AH). Ported from SettingsDropdown so users see the
        same fields in the same order.
      * Hairline 1px divider
      * Bottom section: Recent Activity feed (last ~30 entries, newest
        first). Two-tier filtering will land in Phase D; this initial
        build shows every entry uncoloured for parity.

    Persistence:
      * char.ui.sidecar_open  boolean, remembered per character so the
        panel stays open across reloads/sessions when the user prefers it

    Fallback contract:
      * SettingsDropdown remains loaded so any external caller (macro,
        slash command, other addon) that calls
        ADDON.SettingsDropdown:Toggle(...) still works.
      * The hamburger's phase-A stub prefers Sidecar when present and
        falls back to SettingsDropdown; installing this file switches
        the header button to Sidecar automatically.
]]

local addonName = ...
local ADDON     = _G[addonName]

local Sidecar = {}
ADDON.Sidecar = Sidecar

-- -------------------------------------------------------------------------
-- Palette shim: mirror MainFrame's when available so the sidecar matches
-- the current theme, but degrade to sensible defaults on early Boot before
-- MainFrame has published its palette table.
-- -------------------------------------------------------------------------
local function P()
    return (ADDON.MainFrame and ADDON.MainFrame.Palette) or {
        bg       = { 0.06, 0.06, 0.06, 0.98 },
        bgMedium = { 0.10, 0.10, 0.10, 1 },
        bgDark   = { 0.04, 0.04, 0.04, 1 },
        bandTint = { 1, 1, 1, 0.02 },
        border   = { 0, 0, 0, 1 },
        brand    = { 0.60, 1.00, 0.60, 1 },
    }
end

local WIDTH = 260

-- -------------------------------------------------------------------------
-- Small helpers copied from MainFrame's style vocab so the sidecar reads
-- as the same chrome without introducing a shared style module (that's a
-- Phase F/refactor concern, not v0.7).
-- -------------------------------------------------------------------------
local function ApplyFill(frame, colour)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetAllPoints()
    t:SetColorTexture(colour[1], colour[2], colour[3], colour[4] or 1)
    return t
end

local function AddBlackEdge(frame, side)
    local t = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    t:SetColorTexture(0, 0, 0, 1)
    if side == "left" then
        t:SetWidth(1); t:SetPoint("TOPLEFT", 0, 0); t:SetPoint("BOTTOMLEFT", 0, 0)
    elseif side == "right" then
        t:SetWidth(1); t:SetPoint("TOPRIGHT", 0, 0); t:SetPoint("BOTTOMRIGHT", 0, 0)
    elseif side == "top" then
        t:SetHeight(1); t:SetPoint("TOPLEFT", 0, 0); t:SetPoint("TOPRIGHT", 0, 0)
    else
        t:SetHeight(1); t:SetPoint("BOTTOMLEFT", 0, 0); t:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    return t
end

-- -------------------------------------------------------------------------
-- Build the Sidecar panel lazily. Uses the same StaticPopup contract for
-- auto-purchase enable that SettingsDropdown does -- both surfaces point
-- at the shared "STOCKCLERK_AUTO_ENABLE" dialog, so the confirmation
-- flow is identical no matter which one triggered it.
-- -------------------------------------------------------------------------
local function Build(anchor)
    local f = CreateFrame("Frame", "StockClerkSidecar", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 400)  -- height overridden in Toggle to match MainFrame
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(20)
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:Hide()

    ApplyFill(f, P().bg)
    AddBlackEdge(f, "top")
    AddBlackEdge(f, "bottom")
    AddBlackEdge(f, "left")
    AddBlackEdge(f, "right")

    -- Anchor default (may be re-anchored by Toggle if MainFrame moves).
    if anchor then
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 1, 0)
    else
        f:SetPoint("CENTER")
    end

    -- ---- Settings section --------------------------------------------
    local settingsTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settingsTitle:SetPoint("TOPLEFT", 12, -10)
    settingsTitle:SetText("|cff98FF98Settings|r")

    -- Auto-purchase toggle
    local autoCheck = CreateFrame("CheckButton", "StockClerkSidecarAutoCheck", f, "UICheckButtonTemplate")
    autoCheck:SetPoint("TOPLEFT", 8, -32)
    autoCheck:SetSize(22, 22)
    _G[autoCheck:GetName() .. "Text"]:SetText("Auto-purchase (opt in)")
    _G[autoCheck:GetName() .. "Text"]:SetTextColor(0.9, 0.9, 0.9, 1)
    f._autoCheck = autoCheck

    local autoHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    autoHint:SetPoint("TOPLEFT", 30, -54)
    autoHint:SetPoint("RIGHT", -8, 0)
    autoHint:SetJustifyH("LEFT")
    autoHint:SetWordWrap(true)
    autoHint:SetText("Uncapped items skipped unless a default is set. Esc cancels a running loop.")

    -- Default cap
    local defCapLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    defCapLabel:SetPoint("TOPLEFT", 12, -84)
    defCapLabel:SetText("Default cap per unit, gold:")

    local defCapBg = f:CreateTexture(nil, "BACKGROUND")
    defCapBg:SetColorTexture(P().bgDark[1], P().bgDark[2], P().bgDark[3], 1)
    defCapBg:SetPoint("TOPLEFT", 12, -102)
    defCapBg:SetSize(120, 22)

    local defCapEdit = CreateFrame("EditBox", nil, f)
    defCapEdit:SetFontObject("GameFontHighlight")
    defCapEdit:SetAutoFocus(false)
    defCapEdit:SetNumeric(true)
    defCapEdit:SetMaxLetters(7)
    defCapEdit:SetJustifyH("LEFT")
    defCapEdit:SetPoint("TOPLEFT", 16, -104)
    defCapEdit:SetSize(112, 18)
    f._defCapEdit = defCapEdit

    -- Budget
    local budgetLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    budgetLabel:SetPoint("TOPLEFT", 12, -130)
    budgetLabel:SetText("Auto budget per day, gold:")

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

    -- Auto-open at AH
    local ahCheck = CreateFrame("CheckButton", "StockClerkSidecarAHCheck", f, "UICheckButtonTemplate")
    ahCheck:SetPoint("TOPLEFT", 8, -172)
    ahCheck:SetSize(22, 22)
    _G[ahCheck:GetName() .. "Text"]:SetText("Auto-open at Auction House")
    _G[ahCheck:GetName() .. "Text"]:SetTextColor(0.9, 0.9, 0.9, 1)
    f._ahCheck = ahCheck

    -- Daily auto-spend readout
    local spentLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    spentLabel:SetPoint("TOPLEFT", 12, -200)
    spentLabel:SetPoint("RIGHT", -8, 0)
    spentLabel:SetJustifyH("LEFT")
    spentLabel:SetWordWrap(false)
    f._spentLabel = spentLabel

    -- ---- Divider -----------------------------------------------------
    local divider = f:CreateTexture(nil, "OVERLAY", nil, 6)
    divider:SetColorTexture(0, 0, 0, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 8, -226)
    divider:SetPoint("TOPRIGHT", -8, -226)

    -- ---- Activity feed section --------------------------------------
    local feedTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    feedTitle:SetPoint("TOPLEFT", 12, -234)
    feedTitle:SetText("|cff98FF98Recent Activity|r")

    -- "log" hint anchored to feedTitle's right so the user can find the
    -- full log dump. Phase D wires the /clerk log popup; for now it just
    -- notes the slash command.
    local feedHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    feedHint:SetPoint("TOPRIGHT", -12, -238)
    feedHint:SetText("|cff6a6a6a/clerk log|r")

    -- Scrollframe hosts the feed rows. Simple, no fancy pooling -- the
    -- panel is bounded and refreshes on Emit, so ~30 rows is the ceiling.
    local scrollBg = f:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetColorTexture(P().bgDark[1], P().bgDark[2], P().bgDark[3], 0.6)
    scrollBg:SetPoint("TOPLEFT", 8, -256)
    scrollBg:SetPoint("BOTTOMRIGHT", -8, 8)

    local scrollFrame = CreateFrame("ScrollFrame", "StockClerkSidecarScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -258)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 10)  -- -28 leaves room for the scrollbar

    local feedContent = CreateFrame("Frame", nil, scrollFrame)
    feedContent:SetSize(WIDTH - 40, 1)  -- height grows in Refresh
    scrollFrame:SetScrollChild(feedContent)
    f._feedContent = feedContent
    f._feedRows = {}

    -- ---- Wire behavior ----------------------------------------------
    autoCheck:SetScript("OnClick", function(self)
        local s = ADDON.DB:Settings()
        if self:GetChecked() then
            -- Bounce the visual check so RequestAutoEnable's popup
            -- controls the final state; matches SettingsDropdown flow.
            self:SetChecked(false)
            if ADDON.SettingsDropdown and ADDON.SettingsDropdown.RequestAutoEnable then
                ADDON.SettingsDropdown:RequestAutoEnable()
            else
                s.autoPurchase = true
                if ADDON.Log then ADDON.Log:Emit("auto_toggle", nil, { on = true }) end
            end
        else
            s.autoPurchase = false
            if ADDON.Log then ADDON.Log:Emit("auto_toggle", nil, { on = false }) end
            Sidecar:Refresh()
            if ADDON.MainFrame then ADDON.MainFrame:Refresh() end
        end
    end)

    local function CommitBudget()
        local s = ADDON.DB:Settings()
        local n = tonumber(budgetEdit:GetText())
        s.autoBudgetGold = (n and n > 0) and n or nil
        Sidecar:Refresh()
    end
    budgetEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    budgetEdit:SetScript("OnEditFocusLost", CommitBudget)
    budgetEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local function CommitDefCap()
        local s = ADDON.DB:Settings()
        local n = tonumber(defCapEdit:GetText() or "")
        s.defaultMaxCopper = (n and n > 0) and (n * 10000) or nil
        Sidecar:Refresh()
        if ADDON.MainFrame and ADDON.MainFrame.Refresh then ADDON.MainFrame:Refresh() end
    end
    defCapEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    defCapEdit:SetScript("OnEditFocusLost", CommitDefCap)
    defCapEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    ahCheck:SetScript("OnClick", function(self)
        ADDON.DB:Settings().autoOpenAtAH = self:GetChecked() and true or false
    end)

    f:SetScript("OnHide", function()
        if budgetEdit:HasFocus() then budgetEdit:ClearFocus() end
        if defCapEdit:HasFocus() then defCapEdit:ClearFocus() end
    end)

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
        return ("|cff98FF98[%s]|r bought %sx%s (%dg)"):format(when, itemLink or "?", pay.qty or "?", g)
    elseif kind == "cap_change" then
        local from = pay.fromCopper and math.floor(pay.fromCopper / 10000) .. "g" or "unset"
        local to   = pay.toCopper   and math.floor(pay.toCopper   / 10000) .. "g" or "unset"
        return ("|cffe5e0a5[%s]|r cap %s -> %s on %s"):format(when, from, to, itemLink or "?")
    elseif kind == "auto_refuse" then
        return ("|cffe5624a[%s]|r auto skipped: %s"):format(when, pay.reason or "?")
    elseif kind == "buy_fail" then
        return ("|cffe5624a[%s]|r buy failed on %s (%s)"):format(when, itemLink or "?", pay.reason or "?")
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
    f._autoCheck:SetChecked(s.autoPurchase and true or false)
    f._ahCheck:SetChecked(s.autoOpenAtAH and true or false)

    if s.autoBudgetGold then
        f._budgetEdit:SetText(tostring(s.autoBudgetGold))
    else
        f._budgetEdit:SetText("")
    end

    if s.defaultMaxCopper and s.defaultMaxCopper > 0 then
        f._defCapEdit:SetText(tostring(math.floor(s.defaultMaxCopper / 10000)))
    else
        f._defCapEdit:SetText("")
    end

    local autoSpendG = math.floor((ADDON.DB:GetDailyAutoSpend() or 0) / 10000)
    local budgetG    = s.autoBudgetGold
    local resetAt    = ADDON.DB.GetDailyResetAt and ADDON.DB:GetDailyResetAt() or nil
    local resetH = ""
    if resetAt then
        local secs = math.max(0, resetAt - GetServerTime())
        resetH = (" (resets in %.1fh)"):format(secs / 3600)
    end
    if budgetG then
        f._spentLabel:SetText(("auto spent today: %dg / %dg%s"):format(autoSpendG, budgetG, resetH))
    else
        f._spentLabel:SetText(("auto spent today: %dg%s (no budget set)"):format(autoSpendG, resetH))
    end

    -- Activity feed. Rebuild the visible rows from scratch each Refresh
    -- since the ceiling is small (~30 entries) and correctness beats
    -- fancy incremental diffing for a v0.7 initial implementation.
    for _, r in ipairs(f._feedRows) do r:Hide() end

    local entries = {}
    if ADDON.Log and ADDON.Log.Query then
        entries = ADDON.Log:Query()  -- returns newest-first
    end

    local MAX = 30
    local content = f._feedContent
    local y = 0
    for i = 1, math.min(#entries, MAX) do
        local e = entries[i]
        local row = f._feedRows[i]
        if not row then
            row = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
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
        if ADDON.DB and ADDON.DB.db and ADDON.DB.db.char then
            ADDON.DB.db.char.ui = ADDON.DB.db.char.ui or {}
            ADDON.DB.db.char.ui.sidecar_open = false
        end
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

    if ADDON.DB and ADDON.DB.db and ADDON.DB.db.char then
        ADDON.DB.db.char.ui = ADDON.DB.db.char.ui or {}
        ADDON.DB.db.char.ui.sidecar_open = true
    end
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
            if Sidecar.frame and Sidecar.frame:IsShown() then
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
