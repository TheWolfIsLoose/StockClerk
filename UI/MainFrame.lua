--[[
    Stock Clerk - UI/MainFrame.lua
    The shopping-list window: header (title, side panel, close), toolbar
    (Item ID, Target, bulk import), the list (ScrollBox of rows), and a
    footer (last action + Restock button; the checkout bar during a
    restock). Style rules: Dev/STYLE.md. The helpers here are shared with
    the side panel, bulk import and log windows (MF.*).

    Row: [grip] [icon] name ........ have (+stash)  [need]  [cap]  seen  [x]
    Click Need or Cap to edit; shift-click to link; with the AH open, click
    to search. Drag the grip to reorder (list order = restock priority).
    During and after a restock the grip shows the row's mark instead
    (queued, current, bought, over cap...).
--]]

local addonName = ...
local ADDON     = _G[addonName]

local MF = {}
ADDON.MainFrame = MF

local ROW_HEIGHT = 24
local MoneyText  = ADDON.MoneyText
local EMPTY_LIST = "No items yet.\n\nAdd items by:\n |cffffffff1.|r Typing an item ID into the Item ID box and pressing Enter\n |cffffffff2.|r Dragging an item from your bags onto the Item ID box\n |cffffffff3.|r Opening bulk import (the button right of Target) to drop or paste many at once"

-- ---------------------------------------------------------------------------
-- Fonts: three sizes in white, plus grey for disabled buttons. Face is Expressway when LibSharedMedia has it
-- (ElvUI, EllesmereUI...), else the bundled Barlow Semi Condensed (SIL OFL,
-- Media/). Expressway can't ship: its free license forbids embedding.
-- ---------------------------------------------------------------------------
local FONT_FALLBACK = "Interface\\AddOns\\StockClerk\\Media\\BarlowSemiCondensed-Medium.ttf"
local FONTS = {
    StockClerkFontSmall = { 10, 1 }, StockClerkFont = { 12, 1 }, StockClerkFontLarge = { 16, 1 },
    StockClerkFontDisabled = { 12, 0.5 },
}
for name, spec in pairs(FONTS) do
    local fo = CreateFont(name)
    fo:SetFont(FONT_FALLBACK, spec[1], "")
    fo:SetTextColor(spec[2], spec[2], spec[2])
    FONTS[name] = { fo = fo, size = spec[1] }
end
-- Switch to Expressway once other addons have registered their media (first
-- build of any StockClerk window). Font strings follow their font object.
function MF.ApplyFontFace()
    if MF._fontsApplied then return end
    MF._fontsApplied = true
    local lsm  = LibStub and LibStub("LibSharedMedia-3.0", true)
    local face = lsm and lsm:Fetch("font", "Expressway", true)
    if face then
        for _, f in pairs(FONTS) do f.fo:SetFont(face, f.size, "") end
    end
end

-- ---------------------------------------------------------------------------
-- Palette (after atrocityEssentials: near-black, flat). The window paints one
-- fill; regions are separated by 1px black lines, not extra shades.
-- ---------------------------------------------------------------------------
local Palette = {
    bgDark       = { 0.031, 0.031, 0.031, 0.97 }, -- window
    bgMedium     = { 0.055, 0.055, 0.055, 0.95 }, -- buttons, hovered cells
    panelBg      = { 0.060, 0.060, 0.060, 0.98 }, -- side panels, log window
    bandTint     = { 1, 1, 1, 0.035 },            -- faint strip: header, toolbar, headers, footer
    fieldFill    = { 0, 0, 0, 0.55 },             -- sunken well for editable spots
    btnRest      = { 1, 1, 1, 0.045 },            -- button at rest
    hoverWash    = { 0.851, 0.851, 0.851, 0.15 }, -- "the mouse is here"
    pressFill    = { 0.851, 0.851, 0.851, 0.22 },
    border       = { 0, 0, 0, 1 },
    brand        = { 0.596, 1, 0.596, 1 },        -- mint #98FF98: hover, focus, on
    short        = { 0.90, 0.30, 0.30, 1 },
    rowSeparator = { 0.15, 0.15, 0.15, 1 },
}
MF.Palette = Palette

local TRASH_TEX     = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"  -- native red X
local QUESTION_ICON = 134400
local ICON_REST     = { 0.85, 0.85, 0.85 }

-- ---------------------------------------------------------------------------
-- Style helpers. Fills use SetColorTexture (White8x8 + SetVertexColor renders
-- transparent on retail); 1px lines turn off texel snapping so they don't
-- smear across two pixel rows at off-grid UI scales.
-- ---------------------------------------------------------------------------
local function Solid(frame, layer, sublevel, color)
    local t = frame:CreateTexture(nil, layer, nil, sublevel)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    t:SetSnapToPixelGrid(false)
    t:SetTexelSnappingBias(0)
    return t
end

-- Opaque background (BACKGROUND -8). Recolourable: frame._bg.
local function ApplyFill(frame, color)
    frame._bg = frame._bg or Solid(frame, "BACKGROUND", -8, color)
    frame._bg:SetAllPoints()
    frame._bg:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

-- Translucent strip over the fill (BACKGROUND -6).
local function ApplyBand(frame, color)
    frame._band = frame._band or Solid(frame, "BACKGROUND", -6, color)
    frame._band:SetAllPoints()
    frame._band:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

-- A 1px line along one edge ("TOP" / "BOTTOM").
local function AddRule(frame, edge, color)
    local t = Solid(frame, "OVERLAY", 6, color or Palette.border)
    t:SetHeight(1)
    t:SetPoint(edge .. "LEFT")
    t:SetPoint(edge .. "RIGHT")
    return t
end

-- 1px ring. Returns its four lines (also frame._border) for recolouring.
local function AddBlackBorder(frame, color)
    local ring = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = Solid(frame, "OVERLAY", 7, color or Palette.border)
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else
            t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side)
        end
        ring[#ring + 1] = t
    end
    frame._border = ring
    return ring
end

local function SetBorderColor(frame, c)
    for _, t in ipairs(frame._border) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end

-- Fade a widget's border to a target colour (mint on hover/focus, back on leave).
local function AttachBorderAnimator(frame)
    local group = frame:CreateAnimationGroup()
    group:CreateAnimation("Animation"):SetDuration(0.15)
    local from, to, cur = { 0, 0, 0, 1 }, { 0, 0, 0, 1 }, { 0, 0, 0, 1 }
    group:SetScript("OnUpdate", function(g)
        local p = g:GetProgress() or 0
        for i = 1, 4 do cur[i] = from[i] + (to[i] - from[i]) * p end
        SetBorderColor(frame, cur)
    end)
    group:SetScript("OnFinished", function()
        for i = 1, 4 do cur[i] = to[i] end
        SetBorderColor(frame, cur)
    end)
    frame._borderAnim = {
        AnimateTo = function(target)
            group:Stop()
            for i = 1, 4 do from[i], to[i] = cur[i], target[i] or 1 end
            group:Play()
        end,
    }
end

-- Flat button: opaque base + light band, hover wash (ARTWORK 7, not HIGHLIGHT,
-- which would wash out the label), press flash, black ring. Scripts are
-- hooked, so callers must HookScript too or the wash dies.
local function StyleButton(btn)
    ApplyFill(btn, Palette.bgMedium)
    ApplyBand(btn, Palette.btnRest)
    AddBlackBorder(btn)
    local wash = Solid(btn, "ARTWORK", 7, Palette.hoverWash)
    wash:SetPoint("TOPLEFT", 1, -1)
    wash:SetPoint("BOTTOMRIGHT", -1, 1)
    wash:Hide()
    btn:HookScript("OnEnter", function() wash:Show() end)
    btn:HookScript("OnLeave", function() wash:Hide() end)
    btn:HookScript("OnMouseDown", function(self) if self:IsEnabled() then ApplyBand(self, Palette.pressFill) end end)
    btn:HookScript("OnMouseUp", function(self) ApplyBand(self, Palette.btnRest) end)
    btn:SetNormalFontObject("StockClerkFont")
    btn:SetHighlightFontObject("StockClerkFont")
    btn:SetDisabledFontObject("StockClerkFontDisabled")
end

-- Drawn icon: flat bars instead of font glyphs, crisp and tinted as one.
-- bars = { { w, h, y, angle, x }, ... } centred on the frame. Returns tint(color, alpha).
local function DrawGlyph(frame, bars)
    local tex = {}
    for i, b in ipairs(bars) do
        local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetSize(b[1], b[2])
        t:SetPoint("CENTER", b[5] or 0, b[3] or 0)
        if b[4] then t:SetRotation(b[4]) end
        tex[i] = t
    end
    local function tint(c, a) for _, t in ipairs(tex) do t:SetColorTexture(c[1], c[2], c[3], a or 1) end end
    tint(ICON_REST)
    return tint
end

-- Header icon button: drawn glyph, mint on hover, one-line tooltip (below
-- unless anchor says otherwise).
local CLOSE_GLYPH = { { 12, 2, 0, math.pi / 4 }, { 12, 2, 0, -math.pi / 4 } }
local function HeaderIcon(parent, bars, tip, onClick, anchor)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(26, 24)
    local tint = DrawGlyph(btn, bars)
    btn:SetScript("OnEnter", function(self)
        tint(Palette.brand)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_BOTTOM")
        GameTooltip:SetText(tip)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() tint(ICON_REST); GameTooltip:Hide() end)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- itemID of whatever the cursor holds, or nil. ("item", itemID, link); some
-- builds sent a link as arg1.
local function CursorItemID()
    local kind, arg1, arg2 = GetCursorInfo()
    if kind ~= "item" then return nil end
    return tonumber(arg1)
        or (type(arg1) == "string" and tonumber(arg1:match("item:(%d+)")))
        or (type(arg2) == "string" and tonumber(arg2:match("item:(%d+)")))
        or nil
end

-- Side panels (settings, bulk import) hang off the window's right edge at its
-- height; only one shows at a time.
local function DockedPanel(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(260, 400)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(20)
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:Hide()
    ApplyFill(f, Palette.panelBg)
    AddBlackBorder(f)
    return f
end
function MF:ShowPanel(panel)
    for _, other in ipairs({ ADDON.Sidecar.frame, ADDON.BulkImport.frame }) do
        if other and other ~= panel then other:Hide() end
    end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 1, 0)
    panel:SetHeight(self.frame:GetHeight())
    panel:Show()
end

MF.ApplyFill, MF.AddBlackBorder, MF.StyleButton = ApplyFill, AddBlackBorder, StyleButton
MF.DrawGlyph, MF.HeaderIcon, MF.CLOSE_GLYPH = DrawGlyph, HeaderIcon, CLOSE_GLYPH
MF.CursorItemID, MF.DockedPanel = CursorItemID, DockedPanel

-- Toolbar edit box: a styled container (sunken well, mint border on hover or
-- focus) around the EditBox, which covers the container and eats its hover,
-- so both count as one hover region. The placeholder names the field (shown
-- while empty and unfocused); the tooltip explains it.
local function MakeEditBox(parent, placeholder, maxLetters, tipTitle, tipBody)
    local box = CreateFrame("Frame", nil, parent)
    box:SetHeight(22)
    box:EnableMouse(true)
    ApplyFill(box, Palette.fieldFill)
    AddBlackBorder(box)
    AttachBorderAnimator(box)

    local eb = CreateFrame("EditBox", nil, box)
    eb:SetPoint("TOPLEFT", 6, -3)
    eb:SetPoint("BOTTOMRIGHT", -6, 3)
    eb:SetFontObject("StockClerkFont")
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(maxLetters)
    -- A hidden focused EditBox keeps capturing game-wide keys: clear on hide.
    eb:HookScript("OnHide", function(self) if self:HasFocus() then self:ClearFocus() end end)
    box.editBox = eb

    local ph = box:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    ph:SetPoint("LEFT", eb)
    ph:SetPoint("RIGHT", eb)
    ph:SetJustifyH("LEFT")
    ph:SetText(placeholder)
    ph:SetTextColor(0.62, 0.62, 0.62, 1)
    local function refresh() ph:SetShown(eb:GetText() == "" and not eb:HasFocus()) end

    local function over() return box:IsMouseOver() or eb:IsMouseOver() end
    local function enter()
        box._borderAnim.AnimateTo(Palette.brand)
        -- 4px above the box: ANCHOR_TOP overlaps it and flickers.
        GameTooltip:SetOwner(box, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOM", box, "TOP", 0, 4)
        GameTooltip:SetText(tipTitle, 1, 1, 1)
        GameTooltip:AddLine(tipBody, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end
    local function leave()
        if over() then return end
        GameTooltip:Hide()
        if not eb:HasFocus() then box._borderAnim.AnimateTo(Palette.border) end
    end
    box:SetScript("OnEnter", enter)
    box:SetScript("OnLeave", leave)
    eb:HookScript("OnEnter", enter)
    eb:HookScript("OnLeave", leave)
    eb:HookScript("OnEditFocusGained", function() refresh(); box._borderAnim.AnimateTo(Palette.brand) end)
    eb:HookScript("OnEditFocusLost", function()
        refresh()
        if not over() then box._borderAnim.AnimateTo(Palette.border) end
    end)
    eb:HookScript("OnTextChanged", refresh)
    refresh()
    return box, eb
end

-- ---------------------------------------------------------------------------
-- Rows. Built once per pooled Button and rebound as the ScrollView recycles
-- them. StockClerk never paints item tooltips (WoW's and the player's
-- tooltip addon's job); its tooltips describe its own controls.
-- ---------------------------------------------------------------------------
local CELL_FILL_IDLE   = { 0, 0, 0, 0.35 }
local CELL_FILL_HOVER  = { Palette.bgMedium[1], Palette.bgMedium[2], Palette.bgMedium[3], 1 }
local CELL_BORDER_IDLE = { Palette.brand[1], Palette.brand[2], Palette.brand[3], 0 }

-- Restock marks: kind -> { shape, colour }. Shapes are drawn bars.
MF.marks = {}  -- itemID -> { kind, tip }
local MARK_SHAPES = {
    check   = { { 5, 2, -1.5, -math.pi / 4, -2.5 }, { 9, 2, 0, math.pi / 4, 1.5 } },
    chevron = { { 6, 2, 2, -math.pi / 4 }, { 6, 2, -2, math.pi / 4 } },
    dot     = { { 3, 3, 0 } },
    dash    = { { 8, 2, 0 } },
}
local MARK_GREY, MARK_AMBER = { 0.55, 0.55, 0.55 }, { 1.0, 0.66, 0.4 }
local MARK_STYLES = {
    queued  = { "dot", MARK_GREY },       current = { "chevron", Palette.brand },
    done    = { "check", Palette.brand }, skipped = { "dash", MARK_GREY },
    over    = { "dash", MARK_AMBER },     failed  = { "dash", Palette.short },
}

local function SetRowHover(row, on)
    row._wash:SetShown(on)
    row.trash:SetShown(on)
end

-- While hovered, a row checks each frame that the cursor is still inside it
-- and clears itself when it isn't. Its own mouse areas (grip, cells, Seen,
-- trash) don't each have to report the exit.
local function WatchRowHover(row)
    if row:IsMouseOver() then return end
    SetRowHover(row, false)
    row:SetScript("OnUpdate", nil)
end

local function BuildRow(row)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")

    row._wash = Solid(row, "ARTWORK", 7, Palette.hoverWash)
    row._wash:SetPoint("TOPLEFT", 1, -1)
    row._wash:SetPoint("BOTTOMRIGHT", -1, 1)
    row._wash:Hide()
    -- 2px left accent (short / stocked), a second channel beside the Have
    -- colour; a texture, so the grip stays clickable.
    row.accent = row:CreateTexture(nil, "OVERLAY")
    row.accent:SetWidth(2)
    row.accent:SetPoint("TOPLEFT", 0, -1)
    row.accent:SetPoint("BOTTOMLEFT", 0, 1)
    AddRule(row, "BOTTOM", Palette.rowSeparator):SetDrawLayer("BACKGROUND", 0)

    local function RowEnter(r)
        SetRowHover(r, true)
        r:SetScript("OnUpdate", WatchRowHover)
    end
    -- Moving onto one of the row's own mouse areas keeps the cursor inside the
    -- row, so the hover stays; WatchRowHover clears it on the real exit.
    local function RowLeave(r)
        if r:IsMouseOver() then return end
        GameTooltip:Hide()
        WatchRowHover(r)
    end
    -- Child mouse areas light the row too when the cursor enters them directly.
    local function OnChildEnter(child) RowEnter(child:GetParent()) end
    local function OnChildLeave(child) GameTooltip:Hide(); RowLeave(child:GetParent()) end

    -- Drag grip.
    local GRIP_W, GRIP_REST = 14, { 0.55, 0.55, 0.55 }
    row.grip = CreateFrame("Button", nil, row)
    row.grip:SetSize(GRIP_W, ROW_HEIGHT - 6)
    row.grip:SetPoint("LEFT", 2, 0)
    row.grip:RegisterForDrag("LeftButton")
    row.gripGlyph = CreateFrame("Frame", nil, row.grip)
    row.gripGlyph:SetAllPoints()
    local tintGrip = DrawGlyph(row.gripGlyph, { { 8, 1, 3 }, { 8, 1, 0 }, { 8, 1, -3 } })
    tintGrip(GRIP_REST, 0.85)
    -- Restock marks take the grip's place; one drawn glyph per shape.
    row.markGlyphs = {}
    for shape, bars in pairs(MARK_SHAPES) do
        local g = CreateFrame("Frame", nil, row.grip)
        g:SetAllPoints()
        g:Hide()
        g.tint = DrawGlyph(g, bars)
        row.markGlyphs[shape] = g
    end
    row._current = Solid(row, "ARTWORK", 6, { Palette.brand[1], Palette.brand[2], Palette.brand[3], 0.08 })
    row._current:SetPoint("TOPLEFT", 1, -1)
    row._current:SetPoint("BOTTOMRIGHT", -1, 1)
    row._current:Hide()
    row.grip:SetScript("OnEnter", function(self)
        OnChildEnter(self)
        tintGrip(Palette.brand)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        -- A marked row leads with its restock result; hints return after the run.
        local mark = MF.marks[self:GetParent()._itemID]
        if mark then GameTooltip:SetText(mark.tip, 1, 1, 1, 1, true) end
        if MF:Busy() then return GameTooltip:Show() end
        if mark then GameTooltip:AddLine(" ") end
        GameTooltip[mark and "AddLine" or "SetText"](GameTooltip, "Drag to reorder", 1, 1, 1)
        GameTooltip:AddLine("List order sets restock priority.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Shift+click a row to link it in chat.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Click Need or Cap to edit it.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("With the AH open, click a row to search for it.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    row.grip:SetScript("OnLeave", function(self) tintGrip(GRIP_REST, 0.85); OnChildLeave(self) end)
    row.grip:SetScript("OnDragStart", function(self)
        if not MF:Busy() then MF:BeginRowDrag(self:GetParent()) end  -- the run's queue is fixed
    end)
    row.grip:SetScript("OnDragStop", function() MF:EndRowDrag() end)

    -- Icon with a 1px quality border (Baganator style), coloured when bound.
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", GRIP_W + 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim the default border
    row.iconBorder = row:CreateTexture(nil, "OVERLAY", nil, -1)
    row.iconBorder:SetPoint("TOPLEFT", row.icon, -1, 1)
    row.iconBorder:SetPoint("BOTTOMRIGHT", row.icon, 1, -1)

    -- Columns right-align on their own edges (the headers use the same numbers):
    --   Have -212 | Need cell -160 (w42) | Cap cell -100 (w50) | Seen -30 (w60) | trash -6
    -- Have: bags count plus a dim (+N) for bank and warband; the invisible
    -- cell carries the per-source tooltip.
    row.haveCell = CreateFrame("Button", nil, row)
    row.haveCell:SetSize(50, 20)
    row.haveCell:SetPoint("RIGHT", -212, 0)
    row.haveCell:SetFrameLevel(row:GetFrameLevel() + 2)
    row.have = row.haveCell:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    row.have:SetPoint("RIGHT", -6, 0)
    row.haveCell:SetScript("OnEnter", function(self)
        OnChildEnter(self)
        local bd = self:GetParent()._breakdown
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(("Have: %d in bags"):format(bd.bags), 1, 1, 1)
        if bd.bank > 0 then GameTooltip:AddLine(("+%d in bank (this character)"):format(bd.bank), 0.78, 0.78, 0.78) end
        if bd.warband > 0 then GameTooltip:AddLine(("+%d in warband bank (account-wide)"):format(bd.warband), 0.78, 0.78, 0.78) end
        GameTooltip:Show()
    end)
    row.haveCell:SetScript("OnLeave", OnChildLeave)

    -- Name ends 8px short of the Have text; no wrap, so long names ellipsize.
    row.name = row:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.have, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Need and Cap: click-to-edit cells (faint well; dark fill and mint border
    -- on hover). A click swaps in an inline edit box. The edit box never calls
    -- EnableKeyboard(true), and clears focus when hidden (row recycled
    -- mid-edit): a hidden EditBox holding the keyboard swallows every key
    -- game-wide until /reload.
    local function MakeCell(width, right, maxLetters)
        local cell = CreateFrame("Button", nil, row)
        cell:SetSize(width, 20)
        cell:SetPoint("RIGHT", right, 0)
        cell:SetFrameLevel(row:GetFrameLevel() + 2)
        ApplyFill(cell, CELL_FILL_IDLE)
        AddBlackBorder(cell, CELL_BORDER_IDLE)
        AttachBorderAnimator(cell)
        local text = cell:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")  -- on the cell: draws over its fill
        text:SetPoint("RIGHT", -6, 0)
        local edit = CreateFrame("EditBox", nil, row)
        edit:SetFontObject("StockClerkFontSmall")
        edit:SetAutoFocus(false)
        edit:SetNumeric(true)
        edit:SetMaxLetters(maxLetters)
        edit:SetJustifyH("CENTER")
        edit:SetSize(width, 20)
        edit:SetPoint("CENTER", cell)
        edit:SetFrameLevel(cell:GetFrameLevel() + 1)
        edit.bg = Solid(row, "BACKGROUND", 0, Palette.bgDark)
        edit.bg:SetPoint("TOPLEFT", edit, -4, 2)
        edit.bg:SetPoint("BOTTOMRIGHT", edit, 4, -2)
        edit.bg:Hide()
        edit:HookScript("OnHide", function(self) if self:HasFocus() then self:ClearFocus() end end)
        edit:Hide()
        return cell, text, edit
    end
    row.needCell, row.need, row.needEdit = MakeCell(42, -160, 5)
    row.capCell,  row.cap,  row.capEdit  = MakeCell(50, -100, 7)  -- up to 9,999,999g

    -- Last Seen: dim last AH unit price, or a dash; tooltip with age and source.
    row.lastSeen = row:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    row.lastSeen:SetPoint("RIGHT", -30, 0)
    row.lastSeen:SetWidth(60)
    row.lastSeen:SetJustifyH("RIGHT")
    local seenHit = CreateFrame("Frame", nil, row)
    seenHit:SetSize(60, 20)
    seenHit:SetPoint("RIGHT", -30, 0)
    seenHit:EnableMouse(true)
    seenHit:SetScript("OnEnter", function(self)
        OnChildEnter(self)
        local lp = self:GetParent()._lastPrice
        if not lp then return end
        local ago = time() - lp.seenAt
        local agoText = ago < 60 and ago .. "s ago" or ago < 3600 and math.floor(ago / 60) .. "m ago"
            or ago < 86400 and math.floor(ago / 3600) .. "h ago" or math.floor(ago / 86400) .. "d ago"
        local how = ({ click = " \194\183 you searched", loop = " \194\183 restock" })[lp.source] or ""
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Last seen at AH")
        GameTooltip:AddLine(MoneyText(lp.copper) .. " per unit", 1, 1, 1)
        GameTooltip:AddLine(agoText .. how, 0.7, 0.7, 0.7)
        if ago > ADDON.DB:Settings().lastPriceTTL then
            GameTooltip:AddLine("Price is stale -- re-search to refresh", 0.9, 0.6, 0.2)
        end
        GameTooltip:Show()
    end)
    seenHit:SetScript("OnLeave", OnChildLeave)

    -- Trash, shown on hover. Reads r._itemID at click time, so a recycled row
    -- can't delete a stale item.
    row.trash = CreateFrame("Button", nil, row)
    row.trash:SetSize(18, 18)
    row.trash:SetPoint("RIGHT", -6, 0)
    row.trash:SetFrameLevel(row:GetFrameLevel() + 5)
    row.trash:SetNormalTexture(TRASH_TEX)
    row.trash:SetHighlightTexture(TRASH_TEX, "ADD")
    row.trash:Hide()
    row.trash:SetScript("OnEnter", OnChildEnter)
    row.trash:SetScript("OnLeave", function(self) RowLeave(self:GetParent()) end)
    row.trash:SetScript("OnClick", function(self)
        local r = self:GetParent()
        ADDON.DB:RemoveItem(r._itemID)
        ADDON.Log:Emit("remove", r._itemID, { name = r._itemLink })
        MF:Refresh()
    end)

    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    row:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        if IsShiftKeyDown() and self._itemLink then  -- link in chat, like bags
            local edit = ChatEdit_ChooseBoxForSend()
            ChatEdit_ActivateChat(edit)
            edit:Insert(self._itemLink)
        elseif AuctionHouseFrame and AuctionHouseFrame:IsShown() and not MF:Busy() then  -- browse, never buys;
            -- not during a restock, whose own search it would cancel
            MF:SetStatus(("Searching AH for %s..."):format(self.name:GetText()))
            ADDON.AH:SearchItem(self._itemID, function(ok, results)
                if not ok then return MF:SetStatus("|cffff8888AH search failed: " .. tostring(results) .. "|r") end
                if results[1] then
                    MF:SetStatus(("Cheapest: %s / unit (%d listings)"):format(MoneyText(results[1].unitPrice), #results))
                else
                    MF:SetStatus("No auctions found")
                end
            end, "click")
        end
    end)

    -- Inline editors for Need and Cap: same behaviour, different prefill,
    -- tooltip and commit. Click opens (closing the sibling at once: SetFocus
    -- can outrace the deferred focus-lost); Escape discards; Enter, Tab or
    -- blur commit. Refresh only when the value changed.
    local editors = {}
    local function CloseEdit(e)
        local cell, edit = row[e.cell], row[e.edit]
        edit:ClearFocus()
        edit:Hide()
        edit.bg:Hide()
        row[e.label]:Show()
        cell.editing = false
        if not cell:IsMouseOver() then
            cell._borderAnim.AnimateTo(CELL_BORDER_IDLE)
            cell._bg:SetVertexColor(unpack(CELL_FILL_IDLE))
        end
    end
    function row.CloseEditors()
        for _, e in ipairs(editors) do
            if row[e.edit]:IsShown() then CloseEdit(e) end
        end
    end
    local function CommitEdit(e)
        local changed = row._itemID and e.commit(row, row[e.edit]:GetText())
        CloseEdit(e)
        if changed then MF:Refresh() end
    end
    local function WireEditor(e)
        editors[#editors + 1] = e
        local cell, edit = row[e.cell], row[e.edit]
        cell:SetScript("OnClick", function()
            row.CloseEditors()
            edit:SetText(e.prefill(row))
            row[e.label]:Hide()
            edit:Show()
            edit.bg:Show()
            edit:SetFocus()
            edit:HighlightText()
            cell.editing = true
        end)
        cell:SetScript("OnEnter", function(self)
            OnChildEnter(self)
            self._borderAnim.AnimateTo(Palette.brand)
            self._bg:SetVertexColor(unpack(CELL_FILL_HOVER))
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            e.tooltip(row)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function(self)
            if not self.editing then
                self._borderAnim.AnimateTo(CELL_BORDER_IDLE)
                self._bg:SetVertexColor(unpack(CELL_FILL_IDLE))
            end
            OnChildLeave(self)
        end)
        edit:SetScript("OnEscapePressed", function(self)
            self.escaping = true
            CloseEdit(e)
            self.escaping = false
        end)
        edit:SetScript("OnEnterPressed", function() CommitEdit(e) end)
        edit:SetScript("OnEditFocusLost", function(self)
            if not self.escaping and self:IsShown() then CommitEdit(e) end
        end)
        edit:SetScript("OnTabPressed", function(self) self:ClearFocus() end)
    end

    -- Cap: whole gold in the box, copper in the DB. Blank = no cap.
    WireEditor({
        cell = "capCell", label = "cap", edit = "capEdit",
        prefill = function(r) return r._maxPrice and tostring(math.floor(r._maxPrice / 10000)) or "" end,
        tooltip = function(r)
            if r._maxPrice then
                GameTooltip:SetText(("Max %dg / unit"):format(math.floor(r._maxPrice / 10000)), 1, 1, 1)
                GameTooltip:AddLine("Click to change  \194\183  blank = no cap", 0.7, 0.7, 0.7)
            else
                GameTooltip:SetText("No price cap set", 1, 1, 1)
                GameTooltip:AddLine("Click to set a max gold/unit", 0.7, 0.7, 0.7)
            end
        end,
        commit = function(r, text)
            local gold = tonumber(text)
            local copper = (gold and gold > 0) and gold * 10000 or nil
            if copper == r._maxPrice then return false end
            ADDON.DB:SetItemMaxPrice(r._itemID, copper)
            MF:SetStatus(copper and ("Cap for %s set to %dg"):format(r.name:GetText(), gold)
                or ("Cap cleared for %s"):format(r.name:GetText()))
            ADDON.Log:Emit("cap_change", r._itemID, { fromCopper = r._maxPrice, toCopper = copper })
            r._maxPrice = copper
            return true
        end,
    })

    -- Need: a positive whole number.
    WireEditor({
        cell = "needCell", label = "need", edit = "needEdit",
        prefill = function(r) return tostring(r._need) end,
        tooltip = function(r)
            GameTooltip:SetText(("Target: %d"):format(r._need), 1, 1, 1)
            GameTooltip:AddLine("Click to change", 0.7, 0.7, 0.7)
        end,
        commit = function(r, text)
            local need = tonumber(text)
            if not (need and need > 0 and need ~= r._need) then return false end
            ADDON.DB:SetItem(r._itemID, need)
            ADDON.Log:Emit("target_change", r._itemID, { from = r._need, to = need })
            r._need = need
            return true
        end,
    })
end

local function ShowLink(fs, link)  -- item name in its quality colour, without [ ]
    fs:SetText((link:gsub("|h%[(.-)%]|h", "|h%1|h")))
end

local function InitializeRow(row, data)
    if not row._built then BuildRow(row); row._built = true end

    -- A pooled row gets rebound to another item (refresh, scroll, filter),
    -- possibly while hovered (no OnLeave fires) or mid-edit (a focused hidden
    -- editor would capture every key). Reset both before binding.
    row.CloseEditors()
    local over = row:IsMouseOver()
    SetRowHover(row, over)
    row:SetScript("OnUpdate", over and WatchRowHover or nil)

    local itemID = data.itemID
    row._itemID, row._index, row._need, row._maxPrice, row._lastPrice = itemID, data.index, data.need, data.maxPrice, data.lastPrice

    local _, link, quality, _, _, _, _, _, _, tex = C_Item.GetItemInfo(itemID)
    row.icon:SetTexture(tex or select(5, C_Item.GetItemInfoInstant(itemID)) or QUESTION_ICON)
    -- Quality colour; black until the item loads (GET_ITEM_INFO_RECEIVED repaints).
    if quality then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        row.iconBorder:SetColorTexture(r, g, b, 1)
    else
        row.iconBorder:SetColorTexture(0, 0, 0, 1)
    end
    row._itemLink = link
    if link then
        ShowLink(row.name, link)
    else
        row.name:SetText(data.name)
        ADDON.ItemResolver:Resolve(itemID, function(id, _, ln)
            if row._itemID == id and ln then
                ShowLink(row.name, ln)
                row._itemLink = ln
            end
        end)
    end

    -- Have: red when short, mint when stocked; the (+N) stash stays grey.
    local bd = ADDON.Inventory:GetBreakdown(itemID)
    local stashed, short = bd.bank + bd.warband, data.need - bd.bags
    row._breakdown = bd
    row.have:SetText((short > 0 and "|cffe5624a%d|r" or "|cff98FF98%d|r"):format(bd.bags)
        .. (stashed > 0 and ("  |cff888888(+%d)|r"):format(stashed) or ""))
    row.accent:SetColorTexture(unpack(short > 0 and { 0xe5 / 255, 0x62 / 255, 0x4a / 255 } or { 0x4a / 255, 0xde / 255, 0x80 / 255 }))
    row.need:SetText(("|cffCCCCCC%d|r"):format(data.need))

    -- Restock mark in the grip's place; the current item gets a mint wash.
    local mark = MF.marks[itemID]
    local style = mark and MARK_STYLES[mark.kind]
    row.gripGlyph:SetShown(not style)
    for shape, g in pairs(row.markGlyphs) do g:SetShown(style and style[1] == shape) end
    if style then row.markGlyphs[style[1]].tint(style[2]) end
    row._current:SetShown(mark and mark.kind == "current" or false)
    if mark and mark.kind == "current" then row.accent:SetColorTexture(unpack(Palette.brand)) end

    -- Cap: mint "Ng"; red when last seen is above it (a buy would be refused);
    -- a dash when unset (buys at market; checkout warns "No cap set").
    local lp = data.lastPrice
    if data.maxPrice then
        local over = lp and lp.copper > data.maxPrice
        row.cap:SetText(("|cff%s%dg|r"):format(over and "ff8888" or "98FF98", math.floor(data.maxPrice / 10000)))
    else
        row.cap:SetText("|cff555555\226\128\148|r")
    end
    -- Last Seen: gold and silver (the tooltip has copper); greyer once stale.
    if lp then
        local stale = time() - lp.seenAt > ADDON.DB:Settings().lastPriceTTL
        row.lastSeen:SetText(("|cff%s%s|r"):format(stale and "777777" or "CCCCCC", MoneyText(lp.copper, "silver")))
    else
        row.lastSeen:SetText("|cff555555\226\128\148|r")
    end

    if ADDON.debug then  -- trace only when this row's numbers change
        MF._traced = MF._traced or {}
        local sig = ("%d/%d/%d"):format(bd.bags, stashed, data.need)
        if MF._traced[itemID] ~= sig then
            MF._traced[itemID] = sig
            ADDON.Debug("Row", ("id=%d bags=%d stashed=%d need=%d"):format(itemID, bd.bags, stashed, data.need))
        end
    end
end

-- Position and size, per character.
local function SavePosition(f, withSize)
    local pos, point, _, _, x, y = ADDON.DB.char.uiPos, f:GetPoint()
    pos.point, pos.x, pos.y = point, x, y
    if withSize then pos.width, pos.height = f:GetWidth(), f:GetHeight() end
end

function MF:Build()
    if self.frame then return self.frame end
    MF.ApplyFontFace()

    -- ---- Root frame -------------------------------------------------------
    local f = CreateFrame("Frame", "StockClerkFrame", UIParent)
    local pos = ADDON.DB.char.uiPos
    f:SetSize(pos.width or 420, pos.height or 400)
    f:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(420, 400)  -- the designed minimum; no maximum
    f:EnableMouse(true)
    ApplyFill(f, Palette.bgDark)
    -- Border on a child at TOOLTIP strata so nothing draws over it.
    local borderFrame = CreateFrame("Frame", nil, f)
    borderFrame:SetAllPoints()
    borderFrame:SetFrameStrata("TOOLTIP")
    AddBlackBorder(borderFrame)
    tinsert(UISpecialFrames, "StockClerkFrame")  -- Escape closes it (when no edit box has focus)

    -- Escape during a restock stops it. The keyboard is needed for that (and
    -- toolbar typing broke without it). SetPropagateKeyboardInput is sticky,
    -- so the action runs in pcall and propagate is set once, last: an error
    -- must never leave every game key swallowed.
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        local consumed = key == "ESCAPE" and MF:Busy()
        if consumed then pcall(MF.StopRun, "user_esc") end
        self:SetPropagateKeyboardInput(not consumed)
    end)

    -- Every close path (Escape, x, /clerk) ends here: release the keyboard,
    -- close panels, editors and any drag, and drop tooltips owned inside the
    -- window (no OnLeave fires when the owner just vanishes).
    f:SetScript("OnHide", function()
        pcall(function() ADDON.Sidecar:Hide(); ADDON.BulkImport:Close() end)
        f:SetPropagateKeyboardInput(true)
        local focused = GetCurrentKeyBoardFocus()
        if focused then focused:ClearFocus() end
        MF:EndRowDrag(true)
        for _, row in MF.scrollBox:EnumerateFrames() do row.CloseEditors() end
        local owner = GameTooltip:GetOwner()
        while owner do
            if owner == f then GameTooltip:Hide(); break end
            owner = owner:GetParent()
        end
    end)
    f:SetScript("OnShow", function() MF:RefreshRestockBtn() end)

    -- ---- Header: title, version, side panel, close; drag to move ----------
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(26)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:EnableMouse(true)
    ApplyBand(header, Palette.bandTint)
    AddRule(header, "BOTTOM")
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing(); SavePosition(f) end)

    local title = header:CreateFontString(nil, "OVERLAY", "StockClerkFontLarge")
    title:SetPoint("LEFT", 12, 0)
    title:SetText("|cff98FF98Stock|rClerk")
    -- Version ("dev 7c13266" in a git checkout); amber for alpha/beta.
    local version = ADDON.VersionText()
    local versionLabel = header:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    versionLabel:SetPoint("LEFT", title, "RIGHT", 6, -1)
    versionLabel:SetText(((version:match("%-alpha") or version:match("%-beta")) and "|cffFFAA00" or "|cff888888") .. version .. "|r")

    local closeX = HeaderIcon(header, CLOSE_GLYPH, "Close", function() MF:Hide() end)
    closeX:SetPoint("RIGHT", -4, 0)
    HeaderIcon(header, { { 14, 2, 4 }, { 14, 2, 0 }, { 14, 2, -4 } }, "Settings & Activity",
        function() ADDON.Sidecar:Toggle() end):SetPoint("RIGHT", closeX, "LEFT", -2, 0)

    -- ---- Toolbar: Item ID, Target, bulk import ----------------------------
    local toolbar = CreateFrame("Frame", nil, f)
    toolbar:SetHeight(30)
    toolbar:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    toolbar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    ApplyBand(toolbar, Palette.bandTint)
    AddRule(toolbar, "BOTTOM")

    -- Item IDs only (names are ambiguous across ranks); blank Target = 1.
    -- Caps are set per row, after seeing AH prices. Item ID takes the width.
    local addEB, addBox = MakeEditBox(toolbar, "Item ID or drag an item, Enter to add", 8, "Item ID",
        "Type an item ID (or drag an item from your bags onto this box) and press Enter. Add a Target first if you want more than 1.")
    local countEB, countBox = MakeEditBox(toolbar, "Target", 5, "Target", "How many to keep in your bags. Blank = 1.")
    countEB:SetWidth(60)

    -- Bulk import: a drawn "list +" icon.
    local bulkBtn = CreateFrame("Button", nil, toolbar)
    bulkBtn:SetSize(22, 22)
    bulkBtn:SetPoint("RIGHT", -12, 0)
    countEB:SetPoint("RIGHT", bulkBtn, "LEFT", -8, 0)
    addEB:SetPoint("LEFT", 12, 0)
    addEB:SetPoint("RIGHT", countEB, "LEFT", -8, 0)
    StyleButton(bulkBtn)
    local tintBulk = DrawGlyph(bulkBtn, {
        { 10, 2, 5, nil, -2 }, { 10, 2, 1, nil, -2 }, { 5, 2, -3, nil, -4.5 },  -- list
        { 7, 2, -4, nil, 4 }, { 2, 7, -4, nil, 4 },                               -- plus
    })
    bulkBtn:HookScript("OnEnter", function(self)
        tintBulk(Palette.brand)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Bulk import", 1, 1, 1)
        GameTooltip:AddLine("Paste a list of item IDs, one per line, to add them all at once.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    bulkBtn:HookScript("OnLeave", function() GameTooltip:Hide(); tintBulk(ICON_REST) end)
    bulkBtn:SetScript("OnClick", function() ADDON.BulkImport:Toggle() end)

    -- Enter in either box adds the item.
    local function DoAdd()
        local itemID = tonumber(addBox:GetText())
        if not itemID or itemID == 0 then return end
        local need = tonumber(countBox:GetText()) or 1
        ADDON.ItemResolver:Resolve(itemID, function(resolvedID, name)
            if not resolvedID then return MF:SetStatus(("|cffff8888Unknown item ID: %d|r"):format(itemID)) end
            ADDON.DB:SetItem(resolvedID, need)
            ADDON.Log:Emit("add", resolvedID, { name = name, need = need })
            addBox:SetText("")
            countBox:SetText("")
            MF:SetStatus(("Added %s (need %d)"):format(name, need))
            MF:Refresh()
        end)
    end
    for _, box in ipairs({ addBox, countBox }) do
        box:SetScript("OnEnterPressed", function() DoAdd(); addBox:ClearFocus(); countBox:ClearFocus() end)
        box:SetScript("OnEscapePressed", box.ClearFocus)
    end
    addBox:SetScript("OnTabPressed", function() countBox:SetFocus() end)
    countBox:SetScript("OnTabPressed", function() addBox:SetFocus() end)

    -- Quick add: drop an item on the Item ID box (or click it while holding
    -- one) to fill in its ID; Enter still commits. A mint outline shows while
    -- the cursor holds an item.
    local function StampDrop()
        local id = CursorItemID()
        if not id then return end
        ClearCursor()
        addBox:SetText(id)
        addBox:SetFocus()
        C_Timer.After(0, function() addBox:HighlightText() end)  -- same tick as SetFocus can no-op
        MF:SetStatus(("Quick-add: item %d (press Enter to add)"):format(id))
    end
    for _, target in ipairs({ addEB, addBox }) do
        target:RegisterForDrag("LeftButton")
        target:HookScript("OnReceiveDrag", StampDrop)
    end
    addEB:HookScript("OnMouseUp", function(_, button) if button == "LeftButton" then addBox:SetFocus() end end)
    local dropRing = CreateFrame("Frame", nil, addEB)
    dropRing:SetPoint("TOPLEFT", -1, 1)
    dropRing:SetPoint("BOTTOMRIGHT", 1, -1)
    AddBlackBorder(dropRing, Palette.brand)
    dropRing:Hide()
    local watcher = CreateFrame("Frame", nil, f)
    watcher:RegisterEvent("CURSOR_CHANGED")
    watcher:SetScript("OnEvent", function() dropRing:SetShown(CursorItemID() ~= nil) end)

    -- ---- Column headers ---------------------------------------------------
    -- Full width so the band matches the toolbar and footer. Rows sit 22px in
    -- from the right (list inset 4 + scroll bar 18), so labels subtract that
    -- to line up with the row offsets.
    local headers = CreateFrame("Frame", nil, f)
    headers:SetHeight(20)
    headers:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT")
    headers:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT")
    ApplyBand(headers, Palette.bandTint)
    AddRule(headers, "BOTTOM")
    local function Header(text, x)
        local fs = headers:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
        fs:SetTextColor(unpack(Palette.brand))
        fs:SetText(text)
        if x > 0 then fs:SetPoint("LEFT", x, 0) else fs:SetPoint("RIGHT", x - 22, 0) end
    end
    Header("Item", 36)
    Header("Have", -212)
    Header("Need", -166)  -- Need/Cap: cell edge -6, over the digits
    Header("Cap",  -106)
    Header("Seen", -30)

    -- "Short items only" filter: drawn funnel, dim mint off, bright mint on.
    local filterBtn = CreateFrame("Button", nil, headers)
    filterBtn:SetSize(18, 16)
    filterBtn:SetPoint("LEFT", 62, 0)
    local tintFilter = DrawGlyph(filterBtn, { { 12, 2, 4 }, { 8, 2, 0 }, { 4, 2, -4 } })
    local function paintFilter() tintFilter(Palette.brand, ADDON.DB:GetStuckOnly() and 1 or 0.55) end
    filterBtn:SetScript("OnClick", function()
        ADDON.DB:SetStuckOnly(not ADDON.DB:GetStuckOnly())
        paintFilter()
        MF:Refresh()
    end)
    filterBtn:SetScript("OnEnter", function(self)
        tintFilter(Palette.brand)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText((ADDON.DB:GetStuckOnly() and "|cff98FF98Filter ON|r  " or "") .. "Show only: items you're short on", 1, 1, 1)
        GameTooltip:AddLine("Hide items you already have enough of in your bags.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    filterBtn:SetScript("OnLeave", function() paintFilter(); GameTooltip:Hide() end)
    paintFilter()

    -- ---- Footer: last action on the left, Restock on the right ------------
    local footer = CreateFrame("Frame", nil, f)
    footer:SetHeight(30)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    ApplyBand(footer, Palette.bandTint)
    AddRule(footer, "TOP")

    -- Restock: "Restock at AH (N)", or "Restock from Bank (N)" at a banker.
    -- During an AH restock the same button is Buy (right edge fixed, so the
    -- cursor never moves); RestockLoop debounces it against a double click.
    local restockBtn = CreateFrame("Button", nil, footer)
    restockBtn:SetSize(160, 22)
    restockBtn:SetPoint("RIGHT", -12, 0)
    StyleButton(restockBtn)
    restockBtn:SetMotionScriptsWhileDisabled(true)  -- a disabled button still explains itself
    restockBtn:SetScript("OnClick", function()
        local loop, br = ADDON.RestockLoop, ADDON.BankRestock
        if loop:IsActive() then loop:Fire()
        elseif br:IsActive() then return
        elseif ADDON.bankOpen then br:Start()
        else loop:Start() end
    end)
    restockBtn:HookScript("OnEnter", function(self)
        local state = MF:RestockState()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(state.tip, 1, 1, 1)
        for _, line in ipairs(state.lines) do GameTooltip:AddLine(line, 0.7, 0.7, 0.7, true) end
        if state.reason then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Unavailable: " .. state.reason, Palette.short[1], Palette.short[2], Palette.short[3], true)
        end
        GameTooltip:Show()
    end)
    restockBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.restockBtn = restockBtn

    -- Status text truncates before the Restock button.
    local statusBar = footer:CreateFontString(nil, "OVERLAY", "StockClerkFontSmall")
    statusBar:SetPoint("LEFT", 14, 0)
    statusBar:SetPoint("RIGHT", restockBtn, "LEFT", -8, 0)
    statusBar:SetJustifyH("LEFT")
    statusBar:SetWordWrap(false)
    statusBar:SetMaxLines(1)
    self.statusBar = statusBar

    -- Checkout bar (during a restock, in place of the status text):
    --   [x]  16 x Flask of the Shattered Sun          [Skip] [Buy]
    --        7,424g  2 of 4 (or amber warnings)
    -- x (far from Buy) and Escape are the only ways to stop a run.
    local stopX = HeaderIcon(footer, { { 9, 2, 0, math.pi / 4 }, { 9, 2, 0, -math.pi / 4 } },
        "Stop (or press Escape)", function() MF.StopRun("user_stop") end, "ANCHOR_TOP")
    stopX:SetSize(20, 24)
    stopX:SetPoint("LEFT", 3, 0)
    local skipBtn = CreateFrame("Button", nil, footer)
    skipBtn:SetSize(50, 22)
    skipBtn:SetPoint("RIGHT", restockBtn, "LEFT", -6, 0)
    StyleButton(skipBtn)
    skipBtn:SetText("Skip")
    skipBtn:SetScript("OnClick", function() ADDON.RestockLoop:Skip() end)
    local function CheckoutLine(font, point, y)
        local fs = footer:CreateFontString(nil, "OVERLAY", font)
        fs:SetPoint(point .. "LEFT", 24, y)
        fs:SetPoint("RIGHT", skipBtn, "LEFT", -8, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:Hide()
        return fs
    end
    self.checkout = { CheckoutLine("StockClerkFont", "TOP", -3), CheckoutLine("StockClerkFontSmall", "BOTTOM", 3),
                      stopX = stopX, skip = skipBtn }
    stopX:Hide()
    skipBtn:Hide()

    -- ---- Resize grip (Blizzard's chat-frame size grabber art) -------------
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 5)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); SavePosition(f, true) end)
    grip:SetScript("OnEnter", function()
        GameTooltip:SetOwner(grip, "ANCHOR_LEFT")
        GameTooltip:SetText("Drag to resize", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", GameTooltip_Hide)

    -- ---- The list -----------------------------------------------------------
    local listHolder = CreateFrame("Frame", nil, f)
    listHolder:SetPoint("TOPLEFT", headers, "BOTTOMLEFT", 4, -2)
    listHolder:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -4, 2)
    local scrollBox = CreateFrame("Frame", nil, listHolder, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT")
    scrollBox:SetPoint("BOTTOMRIGHT", -18, 0)
    local scrollBar = CreateFrame("EventFrame", nil, listHolder, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 0)
    -- The element factory must be set before a DataProvider is attached.
    local scrollView = CreateScrollBoxListLinearView()
    scrollView:SetElementInitializer("Button", InitializeRow)
    scrollView:SetElementExtent(ROW_HEIGHT)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, scrollView)
    self.dataProvider = CreateDataProvider()
    scrollView:SetDataProvider(self.dataProvider)
    self.scrollBox = scrollBox

    self.emptyText = listHolder:CreateFontString(nil, "OVERLAY", "StockClerkFont")
    self.emptyText:SetPoint("TOPLEFT", 16, -18)
    self.emptyText:SetPoint("TOPRIGHT", -16, -18)
    self.emptyText:SetJustifyH("LEFT")
    self.emptyText:SetSpacing(3)

    self.frame = f
    return f
end

-- ---------------------------------------------------------------------------
-- Refresh: swap in a fresh DataProvider (Auctionator's pattern: re-filling one
-- can reuse frames without re-running the initializer). Coalesced: any number
-- of calls in one frame make one rebuild.
-- ---------------------------------------------------------------------------
function MF:Refresh()
    if self._refreshPending or not self.frame then return end
    self._refreshPending = true
    C_Timer.After(0, function()
        self._refreshPending = false
        self:_RefreshNow()
    end)
end

function MF:_RefreshNow()
    if not self.frame then return end
    local stuckOnly = ADDON.DB:GetStuckOnly()
    local provider = CreateDataProvider()
    for i, it in ipairs(ADDON.DB:GetSortedItems()) do
        -- Filter on: only items short in the bags.
        if not stuckOnly or ADDON.Inventory:GetBreakdown(it.itemID).bags < it.need then
            it.index = i
            provider:Insert(it)
        end
    end
    self.scrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
    self.dataProvider = provider
    if self._scrollTo then  -- the restock's current item
        local id = self._scrollTo
        self._scrollTo = nil
        self.scrollBox:ScrollToElementDataByPredicate(function(d) return d.itemID == id end, ScrollBoxConstants.AlignNearest)
    end
    local empty = provider:GetSize() == 0
    self.emptyText:SetShown(empty)
    if empty then
        -- skipLog: repaint state, not an event.
        self.emptyText:SetText(stuckOnly and "|cff888888Nothing is short. Click the filter icon to see the full list.|r" or EMPTY_LIST)
    end
    self:RefreshRestockBtn()
end

-- What the Restock button shows and does right now: label, enabled, tooltip
-- title and lines, and why it's disabled (nil when it isn't).
function MF:RestockState()
    local loop, br = ADDON.RestockLoop, ADDON.BankRestock
    if br:IsActive() then
        return { label = "Pulling...", enabled = false, tip = "Restock from Bank",
                 lines = { "Moving what you're short into your bags. Press Escape or the x to stop." } }
    elseif loop:IsActive() then
        local wait, plan = loop:BuyWait(), loop.state.armedPlan
        local st = { label = "Buy", enabled = wait == 0, tip = "Buy",
                     lines = { "Buy this item, then move on to the next.", "Skip passes on it; Escape or the x stops." } }
        if wait then  -- armed: say what, and why Buy may be waiting
            if wait > 0 and #plan.warnings > 0 then st.label = ("Buy (%d)"):format(math.ceil(wait)) end
            st.tip = ("Buy %d %s for %s"):format(plan.planQuantity, plan.name, MoneyText(plan.plannedSpend))
            for _, w in ipairs(plan.warnings) do st.lines[#st.lines + 1] = "|cffffa866" .. w .. "|r" end
        end
        return st
    elseif ADDON.bankOpen then
        local n = br:PullableCount()
        return { label = n > 0 and ("Restock from Bank (%d)"):format(n) or "Restock from Bank", enabled = n > 0,
                 tip = "Restock from Bank",
                 lines = { "Moves exactly what you're short from your bank, then your warband bank, into your bags." },
                 reason = n == 0 and "Nothing you're short on is in your bank or warband bank." or nil }
    end
    local n = loop:PreviewShortfallCount()
    local ahOpen = AuctionHouseFrame and AuctionHouseFrame:IsShown()
    return { label = n > 0 and ("Restock at AH (%d)"):format(n) or "Restock at AH", enabled = ahOpen and n > 0,
             tip = "Restock at AH",
             lines = { "Goes down your list in order; you click Buy for each item.", "Items above your cap are marked and passed over." },
             reason = not ahOpen and "Auction House isn't open."
                   or n == 0 and "Nothing to restock -- every row is at or above its need." or nil }
end

function MF:RefreshRestockBtn()
    if not self.restockBtn then return end
    local state = self:RestockState()
    self.restockBtn:SetText(state.label)
    self.restockBtn:SetEnabled(state.enabled)
    self.checkout.skip:SetEnabled(ADDON.RestockLoop:BuyWait() ~= nil)
end

-- ---------------------------------------------------------------------------
-- Restock runs (RestockLoop at the AH, BankRestock at the bank)
-- ---------------------------------------------------------------------------
function MF:Busy()
    return ADDON.RestockLoop:IsActive() or ADDON.BankRestock:IsActive()
end

-- reason: "user_esc" or "user_stop" (the x).
function MF.StopRun(reason)
    if ADDON.RestockLoop:IsActive() then ADDON.RestockLoop:Stop(reason) end
    if ADDON.BankRestock:IsActive() then ADDON.BankRestock:Stop("stopped by you") end
end

-- Row mark for itemID (kind = nil removes it); "current" scrolls it into view.
function MF:Mark(itemID, kind, tip)
    self.marks[itemID] = kind and { kind = kind, tip = tip } or nil
    if kind == "current" then self._scrollTo = itemID end
    self:Refresh()
end

function MF:ClearMarks()
    if not next(self.marks) then return end
    wipe(self.marks)
    self:Refresh()
end

-- Footer as the checkout bar (two lines), or back to the status text (nil).
function MF:SetCheckout(line1, line2)
    if not self.frame then return end
    local on, co = line1 ~= nil, self.checkout
    self.statusBar:SetShown(not on)
    co[1]:SetShown(on); co[2]:SetShown(on); co.stopX:SetShown(on)
    co.skip:SetShown(on and ADDON.RestockLoop:IsActive())
    -- Narrower Buy, same right edge: it still covers where Restock was clicked.
    self.restockBtn:SetWidth(on and 100 or 160)
    if on then co[1]:SetText(line1); co[2]:SetText(line2 or "") end
    self:RefreshRestockBtn()
end

-- ---------------------------------------------------------------------------
-- Docking to the AH window. The side panels are anchored to the main window,
-- so they move with it.
-- ---------------------------------------------------------------------------
function MF:DockToAHIfOpen()
    local f, host = self.frame, AuctionHouseFrame
    if self._preDockPos or not (f and host and host:IsShown()) then return end
    local point, _, _, x, y = f:GetPoint()
    self._preDockPos = { point = point, x = x, y = y }
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", host, "TOPRIGHT", 1, 0)
end

-- Back to where it was before docking. No-op when not docked.
function MF:Undock()
    local pre = self._preDockPos
    if not pre then return end
    self._preDockPos = nil
    self.frame:ClearAllPoints()
    self.frame:SetPoint(pre.point, UIParent, pre.point, pre.x, pre.y)
end

-- Footer text: feedback on the last action, until the next one. Also logged
-- (as detail) unless skipLog.
function MF:SetStatus(text, skipLog)
    if self.statusBar then self.statusBar:SetText(text or "") end
    if not skipLog and text and text ~= "" then ADDON.Log:Emit("status", nil, { text = text }) end
end

-- ---------------------------------------------------------------------------
-- Drag to reorder (the grip). A mint line follows the cursor to the nearest
-- gap between visible rows; dropping reorders the list (= restock order).
-- Above or below the rows means top or bottom.
-- ---------------------------------------------------------------------------

-- Gap nearest cursorY: 1 = before the first row, size+1 = after the last.
-- Also returns the row to draw the line against and which edge.
function MF:_DropTarget(cursorY)
    local rows = {}
    for _, r in self.scrollBox:EnumerateFrames() do
        if r:IsShown() and r._index then rows[#rows + 1] = r end
    end
    if #rows == 0 then return nil end
    table.sort(rows, function(a, b) return a._index < b._index end)
    for _, r in ipairs(rows) do
        if cursorY >= (r:GetTop() + r:GetBottom()) / 2 then return r._index, r, "TOP" end
    end
    local last = rows[#rows]
    return last._index + 1, last, "BOTTOM"
end

function MF:BeginRowDrag(row)
    if self._dragID then return end
    self._dragID = row._itemID
    if not self._dragLine then
        self._dragLine = Solid(self.scrollBox, "OVERLAY", 7, Palette.brand)
        self._dragLine:SetHeight(2)
    end
    self._dragTicker = C_Timer.NewTicker(0, function()
        local _, y = GetCursorPosition()
        local index, row, edge = self:_DropTarget(y / UIParent:GetEffectiveScale())
        self._dropIndex = index
        self._dragLine:ClearAllPoints()
        if row then  -- just outside the row's edge
            local other, dy = edge == "TOP" and "BOTTOM" or "TOP", edge == "TOP" and -1 or 1
            self._dragLine:SetPoint(other .. "LEFT", row, edge .. "LEFT", 0, dy)
            self._dragLine:SetPoint(other .. "RIGHT", row, edge .. "RIGHT", 0, dy)
        end
        self._dragLine:SetShown(row ~= nil)
    end)
end

-- Drop (or, with cancel, just end the drag).
function MF:EndRowDrag(cancel)
    if not self._dragID then return end
    local movedID, target = self._dragID, self._dropIndex
    self._dragTicker:Cancel()
    self._dragID, self._dropIndex, self._dragTicker = nil, nil, nil
    self._dragLine:Hide()
    if cancel or not target then return end
    -- Remove, then reinsert at target (one lower if moving down, since the
    -- removal shifted the rest up).
    local order, from = {}, nil
    for i, d in self.dataProvider:Enumerate() do
        if d.itemID == movedID then from = i else order[#order + 1] = d.itemID end
    end
    if not from or from == target then return end
    table.insert(order, math.max(1, math.min(#order + 1, target > from and target - 1 or target)), movedID)
    ADDON.DB:ReorderItems(order)
    self:Refresh()
end

-- ---------------------------------------------------------------------------
-- Show / Hide
-- ---------------------------------------------------------------------------
function MF:Show()
    self:Build()
    self.frame:Show()
    self:Refresh()
    self:DockToAHIfOpen()  -- opened while already at the AH
end

function MF:Hide()
    if self.frame then self.frame:Hide() end  -- cleanup runs in the frame's OnHide
end
