--[[
    StockClerk - UI/BulkImport.lua

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
-- Parser
-- ---------------------------------------------------------------------------
-- A whole number >= min, or nil.
local function Whole(tok, min)
    local n = tonumber(tok)
    return n and n >= min and n % 1 == 0 and n or nil
end

-- One entry per non-empty, non-comment line:
--   { line=1, raw="...", ok=true,  itemID=N, need=N, maxPriceCopper=N|nil }
--   { line=2, raw="...", ok=false, err="..." }
local function ParseBulkText(text)
    local out, lineNo = {}, 0
    for raw in ((text or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        lineNo = lineNo + 1
        local line = raw:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") and not line:match("^//") then
            local id, need, cap, extra = line:match("^(%S+)%s*(%S*)%s*(%S*)%s*(.-)$")
            id, need, cap = Whole(id, 1), need == "" and 1 or Whole(need, 1), cap == "" and 0 or Whole(cap, 0)
            local err = extra ~= "" and "too many numbers (ID, target, cap)" or not id and "not an item ID"
                or not need and "target must be a whole number" or not cap and "cap must be whole gold" or nil
            out[#out + 1] = { line = lineNo, raw = raw, ok = not err, err = err, itemID = id, need = need,
                              maxPriceCopper = not err and cap > 0 and cap * 10000 or nil }
        end
    end
    return out
end

-- Dev/smoke.lua checks the parser.
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
    title:SetText("Bulk import")
    f.title = title

    local closeX = MF.HeaderIcon(f, MF.CLOSE_GLYPH, "Close", function() f:Hide() end)
    closeX:SetPoint("TOPRIGHT", -4, -4)

    local instr = f:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    instr:SetPoint("TOPLEFT", PAD, -32)
    instr:SetPoint("RIGHT", -PAD, 0)
    instr:SetJustifyH("LEFT")
    instr:SetText("Drop items here, or paste one per line: |cffffffffID|r, |cffffffffID target|r or |cffffffffID target cap|r (cap in gold).")
    instr:SetTextColor(0.74, 0.74, 0.74, 1)

    -- Paste area fills the panel between the instructions and the status line.
    local well = CreateFrame("Frame", nil, f)
    well:SetPoint("TOPLEFT", PAD, -72)
    well:SetPoint("BOTTOMRIGHT", -PAD, 72)
    MF.ApplyFill(well, PALETTE.fieldFill)
    local wellEdges = MF.AddBlackBorder(well, PALETTE.ringRest)

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

    -- White border while the cursor holds an item: "you can drop here".
    local function PaintDropZone()
        local c = MF.CursorItemID() and PALETTE.brand or PALETTE.ringRest
        for _, t in ipairs(wellEdges) do t:SetColorTexture(c[1], c[2], c[3], 1) end
    end
    well:RegisterEvent("CURSOR_CHANGED")
    well:SetScript("OnEvent", PaintDropZone)

    -- Example shown while empty and unfocused (multi-line boxes have no placeholder).
    local ghost = edit:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    ghost:SetPoint("TOPLEFT", 6, -4)
    ghost:SetJustifyH("LEFT")
    ghost:SetText("For example:\n212283\n212283 20\n212283 20 500")
    ghost:SetTextColor(0.55, 0.55, 0.55, 1)
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
    addBtn:SetHeight(20)
    MF.StyleButton(addBtn)
    addBtn:SetText("Add all")
    addBtn:SetScript("OnClick", function()
        local entries = ParseBulkText(edit:GetText())
        if #entries == 0 then
            status:SetText("|cffff6666Nothing to add yet.|r")
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
            status:SetText(("|cffff6666%s, %d skipped.|r %s"):format(msg, errored, table.concat(bad, "; ")))
        else
            edit:SetText("")
            status:SetText("")
            MF:SetStatus("Bulk import: " .. msg .. (MF:View() == "warband" and " on the warband list" or "") .. ".")
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
    self:Paint()
end

-- Title in the accent: it imports into the list on screen.
function BI:Paint()
    if self.frame then self.frame.title:SetTextColor(unpack(PALETTE.brand)) end
end

function BI:Close()
    if self.frame then self.frame:Hide() end
end

function BI:Toggle()
    if self.frame and self.frame:IsShown() then self:Close() else self:Open() end
end
