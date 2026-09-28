--[[
    Stock Clerk - UI/BulkImport.lua

    Bulk import panel: paste many item IDs at once. Opened by the square
    button on the toolbar; docks to the main window's right edge like the
    side panel (opening one closes the other).

    One item per line, space-separated: itemID, then optionally target, then cap.
      target  positive integer, default 1
      cap     whole gold, optional (blank = no cap)
    Blank lines and lines starting with # or // are skipped. A bad line is
    reported and skipped; the rest still commit, with one Refresh at the end.
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
                entry.err = "too many numbers (ID, target, cap)"
            else
                local id = tonumber(tokens[1])
                if not id or id <= 0 or math.floor(id) ~= id then
                    entry.ok = false; entry.err = "not an item ID"
                else
                    entry.itemID = id
                    local need = 1
                    if tokens[2] then
                        need = tonumber(tokens[2])
                        if not need or need <= 0 or math.floor(need) ~= need then
                            entry.ok = false
                            entry.err = "target must be a whole number"
                        end
                    end
                    if entry.ok == nil then
                        entry.need = need
                        if tokens[3] then
                            local capGold = tonumber(tokens[3])
                            if not capGold or capGold < 0 or math.floor(capGold) ~= capGold then
                                entry.ok = false
                                entry.err = "cap must be whole gold"
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
-- Runs the parsed batch. Returns added, updated (already listed), errored.
local function CommitBatch(entries)
    local added, skipped, errored = 0, 0, 0
    for _, e in ipairs(entries) do
        if e.ok then
            local list = ADDON.MainFrame:View()  -- into the list on screen
            local existed = ADDON.DB:GetItems(list)[e.itemID] ~= nil
            ADDON.DB:SetItem(e.itemID, e.need, e.maxPriceCopper, list)
            if existed then
                skipped = skipped + 1
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
-- UI (see Dev/STYLE.md)
-- ---------------------------------------------------------------------------
local MF = ADDON.MainFrame
local PALETTE = MF.Palette
local WIDTH, PAD = 260, 12

local function BuildFrame()
    MF.ApplyFontFace()
    local f = MF.DockedPanel("StockClerkBulkImport")
    tinsert(UISpecialFrames, "StockClerkBulkImport")  -- Escape closes it

    local title = f:CreateFontString(nil, "OVERLAY", "StockClerkFont")
    title:SetPoint("TOPLEFT", PAD, -10)
    title:SetText("|cff98FF98Bulk import|r")

    local closeX = MF.HeaderIcon(f, MF.CLOSE_GLYPH, "Close", function() f:Hide() end)
    closeX:SetPoint("TOPRIGHT", -4, -4)

    local instr = f:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    instr:SetPoint("TOPLEFT", PAD, -32)
    instr:SetPoint("RIGHT", -PAD, 0)
    instr:SetJustifyH("LEFT")
    instr:SetText("Drop items here, or paste one per line: |cffffffffID|r, |cffffffffID target|r or |cffffffffID target cap|r (cap in gold).")
    instr:SetTextColor(0.8, 0.8, 0.8, 1)

    -- Paste area fills the panel between the instructions and the status line.
    local well = CreateFrame("Frame", nil, f)
    well:SetPoint("TOPLEFT", PAD, -72)
    well:SetPoint("BOTTOMRIGHT", -PAD, 72)
    MF.ApplyFill(well, PALETTE.fieldFill)
    local wellEdges = MF.AddBlackBorder(well)

    local scroll = CreateFrame("ScrollFrame", "StockClerkBulkImportScroll", well, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 2, -2)
    scroll:SetPoint("BOTTOMRIGHT", -22, 2)  -- room for the scroll bar

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(WIDTH - 2 * PAD - 26)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(4000)
    edit:SetTextInsets(6, 6, 4, 4)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    edit:HookScript("OnHide", function(self) if self:HasFocus() then self:ClearFocus() end end)
    scroll:SetScrollChild(edit)
    local status  -- set below

    -- Dropping an item (drag, or click while holding it) adds its ID on a
    -- new line; an ID already listed is skipped.
    local function AddDropped()
        local id = MF.CursorItemID()
        if not id then return false end
        ClearCursor()
        local text = edit:GetText()
        for _, e in ipairs(ParseBulkText(text)) do
            if e.itemID == id then
                status:SetText(("Item %d is already listed."):format(id))
                return true
            end
        end
        if text ~= "" and not text:find("\n$") then text = text .. "\n" end
        edit:SetText(text .. id .. "\n")
        edit:SetCursorPosition(#edit:GetText())
        local n = #ParseBulkText(edit:GetText())
        status:SetText(("%d item%s ready. Drop more, or press Add all."):format(n, n == 1 and "" or "s"))
        return true
    end
    for _, target in ipairs({ well, edit }) do
        target:HookScript("OnReceiveDrag", AddDropped)
    end
    edit:HookScript("OnMouseUp", AddDropped)
    -- Clicking the well: drop a held item, else focus the box.
    well:EnableMouse(true)
    well:SetScript("OnMouseDown", function() if not AddDropped() then edit:SetFocus() end end)

    -- Mint border while the cursor holds an item: "you can drop here".
    local function PaintDropZone()
        local c = MF.CursorItemID() and PALETTE.brand or PALETTE.border
        for _, t in ipairs(wellEdges) do t:SetColorTexture(c[1], c[2], c[3], 1) end
    end
    well:RegisterEvent("CURSOR_CHANGED")
    well:SetScript("OnEvent", PaintDropZone)

    -- Example shown while empty and unfocused (multi-line boxes have no placeholder).
    local ghost = edit:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    ghost:SetPoint("TOPLEFT", 6, -4)
    ghost:SetJustifyH("LEFT")
    ghost:SetText("For example:\n212283\n212283 20\n212283 20 500")
    ghost:SetTextColor(0.5, 0.5, 0.5, 0.8)
    local function RefreshGhost()
        ghost:SetShown(edit:GetText() == "" and not edit:HasFocus())
    end
    edit:HookScript("OnTextChanged", RefreshGhost)
    edit:HookScript("OnEditFocusGained", RefreshGhost)
    edit:HookScript("OnEditFocusLost", RefreshGhost)

    status = f:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    status:SetPoint("BOTTOMLEFT", PAD, 38)
    status:SetPoint("BOTTOMRIGHT", -PAD, 38)
    status:SetHeight(28)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("TOP")

    local addBtn = CreateFrame("Button", nil, f)
    addBtn:SetPoint("BOTTOMLEFT", PAD, 10)
    addBtn:SetPoint("BOTTOMRIGHT", -PAD, 10)
    addBtn:SetHeight(22)
    MF.StyleButton(addBtn)
    addBtn:SetText("Add all")
    addBtn:SetScript("OnClick", function()
        local entries = ParseBulkText(edit:GetText())
        if #entries == 0 then
            status:SetText("|cffff8888Nothing to add yet.|r")
            return
        end
        local added, updated, errored = CommitBatch(entries)
        MF:Refresh()
        local msg = ("%d added, %d updated"):format(added, updated)
        if errored > 0 then
            -- Stay open so the bad lines can be fixed; name the first two.
            local bad = {}
            for _, e in ipairs(entries) do
                if not e.ok and #bad < 2 then bad[#bad + 1] = ("line %d: %s"):format(e.line, e.err) end
            end
            status:SetText(("|cffff8888%s, %d skipped.|r %s"):format(msg, errored, table.concat(bad, "; ")))
        else
            edit:SetText("")
            status:SetText("")
            MF:SetStatus("|cff98ff98Bulk import: " .. msg .. (MF:View() == "warband" and " on the warband list" or "") .. ".|r")
            f:Hide()
        end
    end)

    f:SetScript("OnShow", RefreshGhost)
    BI.frame = f
    return f
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------
function BI:Open()
    MF:ShowPanel(self.frame or BuildFrame())
end

function BI:Close()
    if self.frame then self.frame:Hide() end
end

function BI:Toggle()
    if self.frame and self.frame:IsShown() then self:Close() else self:Open() end
end
