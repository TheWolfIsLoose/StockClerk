--[[
    Stock Clerk - UI/BulkImport.lua

    Bulk item-ID paste dialog. Reached from the "+…" button on the main
    frame toolbar. Accepts a multi-line paste and adds every valid line
    in one commit.

    Format (per line, space-separated):
        itemID
        itemID target
        itemID target cap

    Where:
        itemID  - positive integer (bare digits; item links must be
                  reduced to a numeric ID by the user before paste)
        target  - positive integer stock target (silent default: 1 to
                  match v1.1's zero-friction single-add behaviour)
        cap     - whole-gold price cap (converted to copper on commit);
                  optional, blank = no cap

    Rules:
      - Blank lines and lines starting with '#' or '//' are skipped.
      - Any parse or validation error on a line is reported inline and
        that line is skipped; other lines still commit. No partial-line
        recovery — the whole line either commits or is skipped.
      - Commit runs synchronously against ADDON.DB:SetItem then triggers
        one Refresh at the end (avoids O(n) refresh storm).

    Behaviour is deliberately conservative: no name lookups, no
    item-link expansion, no server round-trips. It's a power-user paste
    surface, not a search UI.
]]

local addonName = ...
local ADDON     = _G[addonName]

local BI = {}
ADDON.BulkImport = BI

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------
local DIALOG_W        = 420
local DIALOG_H        = 340
local PAD             = 14
local EDIT_H          = 180   -- multi-line paste area height
local BTN_H           = 24
local GHOST_LINES = {
    "212283",              -- id only, default target 1, no cap
    "212283 20",           -- id + target
    "212283 20 500",       -- id + target + cap (500g)
    "212283 5",            -- id + target
}

-- ---------------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------------
-- Returns a table of results, one entry per NON-EMPTY line:
--   { line=1, raw="...", ok=true,  itemID=N, need=N, maxPriceCopper=N|nil }
--   { line=2, raw="...", ok=false, err="..." }
-- Blank and comment lines produce no entry (silently skipped).
local function ParseBulkText(text)
    if type(text) ~= "string" or text == "" then return {} end
    local out = {}
    local lineNo = 0
    for rawLine in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        lineNo = lineNo + 1
        local line = rawLine:match("^%s*(.-)%s*$")  -- trim
        if line ~= "" and not line:match("^#") and not line:match("^//") then
            -- Tokenise on whitespace runs. Reject anything with more
            -- than 3 tokens rather than silently ignoring extras so a
            -- stray field surfaces as an obvious error.
            local tokens = {}
            for tok in line:gmatch("%S+") do tokens[#tokens + 1] = tok end
            local entry = { line = lineNo, raw = rawLine }
            if #tokens < 1 then
                entry.ok = false; entry.err = "empty"
            elseif #tokens > 3 then
                entry.ok = false
                entry.err = "too many fields (expected: id [target [cap]])"
            else
                local id = tonumber(tokens[1])
                if not id or id <= 0 or math.floor(id) ~= id then
                    entry.ok = false; entry.err = "invalid item ID"
                else
                    entry.itemID = id
                    local need = 1  -- v1.1 silent default
                    if tokens[2] then
                        need = tonumber(tokens[2])
                        if not need or need <= 0 or math.floor(need) ~= need then
                            entry.ok = false
                            entry.err = "target must be a positive integer"
                        end
                    end
                    if entry.ok == nil then
                        entry.need = need
                        if tokens[3] then
                            local capGold = tonumber(tokens[3])
                            if not capGold or capGold < 0 or math.floor(capGold) ~= capGold then
                                entry.ok = false
                                entry.err = "cap must be a whole number of gold"
                            elseif capGold > 0 then
                                entry.maxPriceCopper = capGold * 10000
                            end
                        end
                    end
                    if entry.ok == nil then entry.ok = true end
                end
            end
            out[#out + 1] = entry
        end
    end
    return out
end

-- Expose for future test surfaces (headless parser check)
BI.ParseBulkText = ParseBulkText

-- ---------------------------------------------------------------------------
-- Commit
-- ---------------------------------------------------------------------------
-- Runs the parsed batch. Returns counts { added, skipped, errored }.
local function CommitBatch(entries)
    local added, skipped, errored = 0, 0, 0
    for _, e in ipairs(entries) do
        if e.ok then
            local existed = ADDON.DB.char and ADDON.DB.char.items
                and ADDON.DB.char.items[e.itemID] ~= nil
            ADDON.DB:SetItem(e.itemID, e.need, e.maxPriceCopper, e.maxPriceCopper and "user" or nil)
            if existed then
                skipped = skipped + 1  -- overwrite still counts as "already there"
            else
                added = added + 1
            end
        else
            errored = errored + 1
        end
    end
    return added, skipped, errored
end

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------
-- Styling mirrors the main window's palette so the popup reads as part
-- of the same addon rather than a floating stock Blizzard dialog. See
-- UI/MainFrame.lua Palette{} for source-of-truth values.
local PALETTE = {
    bgDark   = { 0.031, 0.031, 0.031, 0.97 }, -- main window fill
    fieldFill = { 0.000, 0.000, 0.000, 0.55 }, -- editable well
    btnRest  = { 1.000, 1.000, 1.000, 0.045 }, -- button-at-rest fill
    hoverWash = { 0.851, 0.851, 0.851, 0.15 }, -- hover overlay
    border   = { 0.00, 0.00, 0.00, 1.00 },     -- pure-black 1px chrome
    brand    = { 0.596, 1.000, 0.596, 1.00 },  -- #98FF98 mint accent
    text     = { 1.00, 1.00, 1.00, 1.00 },
    textDim  = { 0.78, 0.78, 0.78, 1.00 },
    textMute = { 0.50, 0.50, 0.50, 1.00 },
}
local frame  -- lazy-built singleton

-- Solid fill on the BACKGROUND layer of a Frame or Region.
local function ApplyFill(parent, color, subLevel)
    local tex = parent:CreateTexture(nil, "BACKGROUND", nil, subLevel or -7)
    tex:SetAllPoints(true)
    tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return tex
end

-- 4-texture pure-black 1px ring on the OVERLAY layer. Same shape the
-- main window uses via AddBlackBorder.
local function AddBorder(parent, color)
    color = color or PALETTE.border
    local edges = {}
    for _, side in ipairs({"top", "bottom", "left", "right"}) do
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        edges[side] = t
    end
    edges.top:SetHeight(1);    edges.top:SetPoint("TOPLEFT", 0, 0);       edges.top:SetPoint("TOPRIGHT", 0, 0)
    edges.bottom:SetHeight(1); edges.bottom:SetPoint("BOTTOMLEFT", 0, 0);  edges.bottom:SetPoint("BOTTOMRIGHT", 0, 0)
    edges.left:SetWidth(1);    edges.left:SetPoint("TOPLEFT", 0, 0);      edges.left:SetPoint("BOTTOMLEFT", 0, 0)
    edges.right:SetWidth(1);   edges.right:SetPoint("TOPRIGHT", 0, 0);    edges.right:SetPoint("BOTTOMRIGHT", 0, 0)
    return edges
end

local function StyleFrame(f)
    ApplyFill(f, PALETTE.bgDark)
    -- Border lives on a raised child frame at TOOLTIP strata so nothing
    -- inside can paint over it -- same recipe MainFrame uses.
    local borderFrame = CreateFrame("Frame", nil, f)
    borderFrame:SetAllPoints(f)
    borderFrame:SetFrameStrata("TOOLTIP")
    borderFrame:SetFrameLevel(f:GetFrameLevel() + 100)
    AddBorder(borderFrame)
end

local function StyleBtn(btn)
    ApplyFill(btn, PALETTE.btnRest, -6)
    local hover = btn:CreateTexture(nil, "BORDER")
    hover:SetAllPoints()
    hover:SetColorTexture(PALETTE.hoverWash[1], PALETTE.hoverWash[2],
                          PALETTE.hoverWash[3], PALETTE.hoverWash[4])
    hover:Hide()
    btn:HookScript("OnEnter", function() hover:Show() end)
    btn:HookScript("OnLeave", function() hover:Hide() end)
    AddBorder(btn)
end

local function BuildFrame()
    local f = CreateFrame("Frame", "StockClerkBulkImport", UIParent, "BackdropTemplate")
    f:SetSize(DIALOG_W, DIALOG_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    StyleFrame(f)

    -- ---- Title ---------------------------------------------------------
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText("Bulk Import")
    -- Mint accent on the title word to match the main-window title band
    title:SetTextColor(PALETTE.brand[1], PALETTE.brand[2], PALETTE.brand[3], 1)

    -- ---- Close (top-right) --------------------------------------------
    local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", 2, 2)
    closeX:SetScript("OnClick", function() f:Hide() end)

    -- ---- Instructions --------------------------------------------------
    local instr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    instr:SetPoint("TOPLEFT", PAD, -PAD - 24)
    instr:SetPoint("TOPRIGHT", -PAD, -PAD - 24)
    instr:SetJustifyH("LEFT")
    instr:SetText("One item per line. Formats: |cffffffffid|r, |cffffffffid target|r, |cffffffffid target cap|r (cap = gold).")

    -- ---- Multi-line paste area ----------------------------------------
    -- ScrollFrame + EditBox is the standard WoW pattern for a multi-line
    -- text field that grows past its visible area.
    local scroll = CreateFrame("ScrollFrame", "StockClerkBulkImportScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PAD, -76)
    scroll:SetPoint("TOPRIGHT", -PAD - 22, -76)  -- -22 to clear the scroll bar
    scroll:SetHeight(EDIT_H)

    -- Backdrop for the edit area so it reads as an inset field. Uses
    -- fieldFill + pure-black border to match MainFrame's editbox wells.
    local scrollBg = CreateFrame("Frame", nil, scroll)
    scrollBg:SetPoint("TOPLEFT", -2, 2)
    scrollBg:SetPoint("BOTTOMRIGHT", 22, -2)  -- +22 clears the scroll bar
    scrollBg:SetFrameLevel(scroll:GetFrameLevel() - 1)
    ApplyFill(scrollBg, PALETTE.fieldFill, -5)
    AddBorder(scrollBg)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(DIALOG_W - 2 * PAD - 22)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(4000)
    edit:SetTextInsets(6, 6, 4, 4)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)

    -- Ghost / example placeholder. Shown when the edit box is empty
    -- and unfocused. Not a real placeholder (WoW's EditBox has no
    -- built-in placeholder support for multi-line), so we render our
    -- own FontString and toggle it on OnTextChanged / focus events.
    local ghost = edit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ghost:SetPoint("TOPLEFT", 6, -4)
    ghost:SetJustifyH("LEFT")
    ghost:SetJustifyV("TOP")
    local ghostText = "Example paste:\n"
    for _, ex in ipairs(GHOST_LINES) do ghostText = ghostText .. ex .. "\n" end
    ghostText = ghostText:sub(1, -2)  -- strip trailing newline
    ghost:SetText(ghostText)
    ghost:SetTextColor(0.5, 0.5, 0.5, 0.7)

    local function RefreshGhost()
        local text = edit:GetText()
        if text == "" and not edit:HasFocus() then
            ghost:Show()
        else
            ghost:Hide()
        end
    end
    edit:HookScript("OnTextChanged", RefreshGhost)
    edit:HookScript("OnEditFocusGained", function() ghost:Hide() end)
    edit:HookScript("OnEditFocusLost", RefreshGhost)
    RefreshGhost()

    -- ---- Status line (below edit) -------------------------------------
    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", PAD, -76 - EDIT_H - 8)
    status:SetPoint("TOPRIGHT", -PAD, -76 - EDIT_H - 8)
    status:SetJustifyH("LEFT")
    status:SetHeight(28)
    status:SetText("")

    local function SetStatus(text, colour)
        if colour == "err" then
            status:SetText("|cffff8888" .. text .. "|r")
        elseif colour == "ok" then
            status:SetText("|cff98ff98" .. text .. "|r")
        else
            status:SetText(text)
        end
    end

    -- ---- Buttons -------------------------------------------------------
    local addBtn = CreateFrame("Button", nil, f)
    addBtn:SetSize(96, BTN_H)
    addBtn:SetPoint("BOTTOMLEFT", PAD, PAD)
    StyleBtn(addBtn)
    local addTxt = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addTxt:SetPoint("CENTER")
    addTxt:SetText("Add All")
    addTxt:SetTextColor(1, 1, 1, 1)

    local cancelBtn = CreateFrame("Button", nil, f)
    cancelBtn:SetSize(72, BTN_H)
    cancelBtn:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    StyleBtn(cancelBtn)
    local cancelTxt = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cancelTxt:SetPoint("CENTER")
    cancelTxt:SetText("Close")
    cancelTxt:SetTextColor(0.9, 0.9, 0.9, 1)

    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    addBtn:SetScript("OnClick", function()
        local text = edit:GetText()
        local entries = ParseBulkText(text)
        if #entries == 0 then
            SetStatus("Nothing to import.", "err")
            return
        end
        local added, skipped, errored = CommitBatch(entries)
        if ADDON.MainFrame and ADDON.MainFrame.Refresh then
            ADDON.MainFrame:Refresh()
        end
        -- Build a summary line. Report all three counts even when a
        -- category is zero so the caller can see at a glance that the
        -- parser was consulted for everything they pasted.
        local msg = ("%d added \194\183 %d overwrote \194\183 %d error%s")
            :format(added, skipped, errored, errored == 1 and "" or "s")
        if errored > 0 then
            -- On errors we KEEP the dialog open so the user can see the
            -- inline diagnostics and fix the offending lines. Append the
            -- first two error lines so it's actionable at a glance
            -- without scrolling the paste area.
            local shown, buf = 0, {}
            for _, e in ipairs(entries) do
                if not e.ok and shown < 2 then
                    buf[#buf + 1] = ("line %d: %s"):format(e.line, e.err)
                    shown = shown + 1
                end
            end
            if #buf > 0 then msg = msg .. "\n" .. table.concat(buf, "; ") end
            SetStatus(msg, "err")
        else
            -- Full success: close the dialog. The main window's status
            -- footer echoes the summary so the user still sees
            -- confirmation of what was added.
            edit:SetText("")
            RefreshGhost()
            SetStatus("", nil)
            if ADDON.MainFrame and ADDON.MainFrame.SetStatus then
                ADDON.MainFrame:SetStatus("|cff98ff98" .. msg .. "|r")
            end
            f:Hide()
        end
    end)

    -- Close-on-escape at the frame level too so the dialog can be
    -- dismissed from anywhere, not just the edit box.
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    frame = f
    return f
end

-- ---------------------------------------------------------------------------
-- Public: Open / Close
-- ---------------------------------------------------------------------------
function BI:Open()
    if not frame then BuildFrame() end
    frame:Show()
    frame:Raise()
end

function BI:Close()
    if frame then frame:Hide() end
end
