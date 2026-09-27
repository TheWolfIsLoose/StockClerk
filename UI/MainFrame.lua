--[[
    Stock Clerk - UI/MainFrame.lua

    Flat atrocityEssentials-style chrome. Plain Frame with one WHITE8X8
    fill and a 1px pure-black overlay border on a dedicated TOOLTIP-strata
    child; header / toolbar / list / footer are internal sub-regions
    separated by 1px black borders alone (no per-section fills). Rows
    have no background either — the only hover signal is a translucent
    grey wash ("mouse is here"), and the only accent is brand mint
    #98FF98 ("this opens something"). Uses the modern ScrollBox +
    ScrollView + DataProvider system introduced in Dragonflight.

    Design system (kept in one place at the top so the theme can be
    tweaked without hunting through the file):

        ROW_HEIGHT           row height in pixels
        BORDER_SIZE          border thickness in pixels (1)
        ANIM_DUR             border colour animation duration in seconds
        Palette.bgDark       window fill
        Palette.bgMedium     control fill (buttons, editbox containers, cap cell)
        Palette.hoverWash    translucent grey "mouse is here" overlay
        Palette.pressFill    translucent grey button press feedback
        Palette.border       pure black, alpha 1
        Palette.brand        #98FF98 accent (focus rings, cap value, title accent)
        Palette.textPrimary / textSecondary / textMuted   greyscale text
        Palette.ok / short   semantic status colours (kept only for text)

    Row shape:

        [icon] [name (item link)]        have    [ need ]   [ max g ]   [ status ]   [🗑]
                                                                                (trash only on hover)

    Interactions:
        - Click the "need" number     -> inline EditBox appears in place, Enter saves.
        - Hover row                   -> trash icon fades in, row highlights.
        - Click trash icon            -> removes item from DB, refreshes list.
        - Hover name / icon           -> Blizzard item tooltip.
        - Middle click name           -> chat link.

    The window is registered with UISpecialFrames so Escape closes it,
    exactly like Bags. Frame position is persisted per-character in
    ADDON.DB.char.uiPos.
--]]

local addonName = ...
local ADDON     = _G[addonName]
local L         = _G[addonName .. "_L"]

local MF = {}
ADDON.MainFrame = MF

-- ---------------------------------------------------------------------------
-- Theme
-- ---------------------------------------------------------------------------
local ROW_HEIGHT = 24

-- Fonts: StockClerk's own font objects, one per Blizzard font it used to
-- borrow (same size and colour), so every UI file shares one face. The face
-- is Expressway when LibSharedMedia has it (ElvUI, EllesmereUI...), else the
-- bundled Barlow Semi Condensed (SIL OFL, Media/). Expressway itself can't
-- ship: its free license forbids embedding in software.
local FONT_FALLBACK = "Interface\\AddOns\\StockClerk\\Media\\BarlowSemiCondensed-Medium.ttf"
local FONT_BASES = {
    Normal = "StockClerkFontNormal", NormalSmall = "StockClerkFontNormalSmall", NormalLarge = "StockClerkFontNormalLarge",
    Highlight = "StockClerkFontHighlight", HighlightSmall = "StockClerkFontHighlightSmall",
    Disable = "StockClerkFontDisable", DisableSmall = "StockClerkFontDisableSmall",
}
local fonts = {}
for name, base in pairs(FONT_BASES) do
    fonts[name] = CreateFont("StockClerkFont" .. name)
    fonts[name]:CopyFontObject(_G[base])
end
-- Called from Build (first open, after every addon has registered media).
local function ApplyFontFace()
    local lsm  = LibStub and LibStub("LibSharedMedia-3.0", true)
    local face = lsm and lsm:Fetch("font", "Expressway", true) or FONT_FALLBACK
    for name, fo in pairs(fonts) do
        -- Size/outline from the Blizzard base: a CopyFontObject copy reports height 0.
        local base = _G[FONT_BASES[name]]
        local _, size, flags
        if base then _, size, flags = base:GetFont() end
        if not size or size <= 0 then
            size = name:find("Small") and 10 or name:find("Large") and 16 or 12
        end
        fo:SetFont(face, size, flags or "")
    end
end

-- ---------------------------------------------------------------------------
-- Palette (after atrocityEssentials: near-black, flat). The window paints
-- one fill; regions are separated by 1px black borders, not extra shades.
-- Accent: mint #98FF98.
-- ---------------------------------------------------------------------------
local Palette = {
    -- bgDark = window; bandTint = faint strip on header/toolbar/footer;
    -- fieldFill = sunken well for editable spots; btnRest = button at rest.
    bgDark        = { 0.031, 0.031, 0.031, 0.97 }, -- window fill (was 0.94)
    bgMedium      = { 0.055, 0.055, 0.055, 0.95 }, -- control fill (buttons, hover wells)
    panelBg       = { 0.060, 0.060, 0.060, 0.98 }, -- Sidecar / LogPopup body
    bandTint      = { 1.000, 1.000, 1.000, 0.035 }, -- section-band overlay (light-on-dark)
    fieldFill     = { 0.000, 0.000, 0.000, 0.55  }, -- editable well fill
    btnRest       = { 1.000, 1.000, 1.000, 0.045 }, -- button-at-rest fill
    -- Interaction wash: grey D9D9D9 @ 0.15 ("the mouse is here"). Never used
    -- to imply selection or brand — that's the border color's job.
    hoverWash     = { 0.851, 0.851, 0.851, 0.15 },
    pressFill     = { 0.851, 0.851, 0.851, 0.22 },
    -- Border color: pure black, drawn 1px on an OVERLAY layer via SetColorTexture.
    border        = { 0.00, 0.00, 0.00, 1.00 },
    -- Atrocity brand (their signature). Used on focus borders, section
    -- headers, title accent word, and the shortfall count number.
    brand         = { 0.596, 1.000, 0.596, 1.00 }, -- #98FF98 (SharedMedia_Tones organic)
    -- Text
    textPrimary   = { 1.00, 1.00, 1.00, 1.00 },
    textSecondary = { 0.78, 0.78, 0.78, 1.00 },
    textMuted     = { 0.50, 0.50, 0.50, 1.00 },
    -- Semantic (kept for status pill / shortfall; muted so they don't
    -- outshine the brand mint)
    ok            = { 0.30, 0.80, 0.40, 1.00 },
    short         = { 0.90, 0.30, 0.30, 1.00 },
    -- Between-rows divider: softer than the black chrome border.
    rowSeparator  = { 0.15, 0.15, 0.15, 1.00 },
}

local BORDER_SIZE = 1
local ANIM_DUR    = 0.15

-- All fills use SetColorTexture: the White8x8 + SetVertexColor idiom renders
-- transparent on retail Midnight.
local TRASH_TEX = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"   -- red X, native asset
local QUESTION_ICON = 134400

-- ---------------------------------------------------------------------------
-- Helpers (atrocity-style theming primitives)
-- ---------------------------------------------------------------------------

-- Turn off texel snapping so 1px borders don't smear across two pixel rows
-- at off-grid UI scales (atrocity's PixelSnapRegions).
local MoneyText = ADDON.MoneyText

local function PixelSnap(tex)
    if not tex then return end
    if tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
    end
end

-- Fill: opaque flat background on ARTWORK sublevel -8 (behind content).
local function ApplyFill(frame, color)
    if not frame._bg then
        frame._bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame._bg:SetAllPoints(true)
        PixelSnap(frame._bg)
    end
    frame._bg:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    frame._bg:Show()
end

-- Band: translucent tint above the window fill (BACKGROUND -6, over
-- ApplyFill's -8) so a strip reads as its own section.
local function ApplyBand(frame, color)
    if not frame._band then
        frame._band = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        frame._band:SetAllPoints(true)
        PixelSnap(frame._band)
    end
    frame._band:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    frame._band:Show()
end

-- 1px black ring on OVERLAY. Returns { top, bottom, left, right } so the
-- border animator can recolour it.
local function AddBlackBorder(frame, color)
    color = color or Palette.border
    local textures = {}
    for _, side in ipairs({"top", "bottom", "left", "right"}) do
        local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        PixelSnap(t)
        textures[side] = t
    end
    textures.top:SetHeight(BORDER_SIZE)
    textures.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    textures.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    textures.bottom:SetHeight(BORDER_SIZE)
    textures.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    textures.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    textures.left:SetWidth(BORDER_SIZE)
    textures.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    textures.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    textures.right:SetWidth(BORDER_SIZE)
    textures.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    textures.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame._border = textures
    return textures
end

-- Shared with Sidecar / LogPopup / BulkImport, which load after this file.
MF.Palette        = Palette
MF.ApplyFill      = ApplyFill
MF.AddBlackBorder = AddBlackBorder

-- SetBorderColor: recolor an existing 4-texture border.
local function SetBorderColor(frame, r, g, b, a)
    if not frame._border then return end
    a = a or 1
    for _, t in pairs(frame._border) do
        t:SetColorTexture(r, g, b, a)
    end
end

-- Fade a widget's border between rest (black) and mint on hover/focus.
local function AttachBorderAnimator(frame)
    if frame._borderAnim then return end
    local group = frame:CreateAnimationGroup()
    local anim = group:CreateAnimation("Animation")
    anim:SetDuration(ANIM_DUR)
    local from, to = {0,0,0,1}, {0,0,0,1}
    local cur = {0,0,0,1}
    group:SetScript("OnUpdate", function(g)
        local p = g:GetProgress() or 0
        cur[1] = from[1] + (to[1] - from[1]) * p
        cur[2] = from[2] + (to[2] - from[2]) * p
        cur[3] = from[3] + (to[3] - from[3]) * p
        cur[4] = from[4] + (to[4] - from[4]) * p
        SetBorderColor(frame, cur[1], cur[2], cur[3], cur[4])
    end)
    group:SetScript("OnFinished", function()
        SetBorderColor(frame, to[1], to[2], to[3], to[4])
        cur[1], cur[2], cur[3], cur[4] = to[1], to[2], to[3], to[4]
    end)
    frame._borderAnim = {
        group = group, from = from, to = to, cur = cur,
        AnimateTo = function(target)
            group:Stop()
            from[1], from[2], from[3], from[4] = cur[1], cur[2], cur[3], cur[4]
            to[1], to[2], to[3], to[4] = target[1], target[2], target[3], target[4] or 1
            group:Play()
        end,
    }
end

-- Hover wash: #D9D9D9 @ 0.15 on ARTWORK 7, not the HIGHLIGHT layer (which
-- would draw over the label). Hooked so existing handlers survive.
local function AddHoverWash(btn, insetX, insetY)
    if btn._hoverWash then return btn._hoverWash end
    insetX = insetX or 1
    insetY = insetY or 1
    local wash = btn:CreateTexture(nil, "ARTWORK", nil, 7)
    wash:SetColorTexture(Palette.hoverWash[1], Palette.hoverWash[2], Palette.hoverWash[3], Palette.hoverWash[4])
    wash:SetPoint("TOPLEFT", insetX, -insetY)
    wash:SetPoint("BOTTOMRIGHT", -insetX, insetY)
    wash:Hide()
    btn:HookScript("OnEnter", function() if not btn._selected then wash:Show() end end)
    btn:HookScript("OnLeave", function() wash:Hide() end)
    btn._hoverWash = wash
    return wash
end

-- Flat button: opaque base + light band, hover wash, press flash, black ring.
local function StyleButton(btn, opts)
    opts = opts or {}
    ApplyFill(btn, opts.fill or Palette.bgMedium)
    ApplyBand(btn, Palette.btnRest)
    AddBlackBorder(btn)
    AddHoverWash(btn)
    -- Press feedback: brighten the tint layer briefly so the button feels
    -- pressed without losing its base fill.
    btn:HookScript("OnMouseDown", function(self)
        if self:IsEnabled() and self:IsEnabled() ~= 0 then
            ApplyBand(self, Palette.pressFill)
        end
    end)
    btn:HookScript("OnMouseUp", function(self)
        ApplyBand(self, Palette.btnRest)
    end)
    if btn.SetNormalFontObject then
        btn:SetNormalFontObject("StockClerkFontNormal")
        btn:SetHighlightFontObject("StockClerkFontHighlight")
        btn:SetDisabledFontObject("StockClerkFontDisable")
    end
end

-- Edit box inside a container frame: the container carries fill and
-- border; mint border on hover/focus.
MF.StyleButton = StyleButton

-- Drawn icons (x, hamburger, plus, funnel, grip): flat bars instead of font
-- glyphs, so they stay crisp and tint as one. bars = { { w, h, y, angle, x }, ... }
-- centred on the frame (y, angle, x optional). Returns tint(color, alpha).
local ICON_REST = { 0.85, 0.85, 0.85 }
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

-- Header icon button: drawn glyph, mint on hover, one-line tooltip.
local function HeaderIcon(parent, bars, tip, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(26, 24)
    local tint = DrawGlyph(btn, bars)
    btn:SetScript("OnEnter", function(self)
        tint(Palette.brand)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(tip)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() tint(ICON_REST); GameTooltip:Hide() end)
    btn:SetScript("OnClick", onClick)
    return btn
end
MF.HeaderIcon = HeaderIcon

local function StyleEditBoxContainer(container, editBox)
    ApplyFill(container, Palette.fieldFill)
    AddBlackBorder(container)
    AttachBorderAnimator(container)
    local function toBrand() container._borderAnim.AnimateTo(Palette.brand) end
    local function toBase()
        if editBox and editBox:HasFocus() then return end
        container._borderAnim.AnimateTo(Palette.border)
    end
    container:EnableMouse(true)
    container:HookScript("OnEnter", toBrand)
    container:HookScript("OnLeave", toBase)
    if editBox then
        editBox:HookScript("OnEditFocusGained", toBrand)
        editBox:HookScript("OnEditFocusLost", function()
            if not container:IsMouseOver() then
                container._borderAnim.AnimateTo(Palette.border)
            end
        end)
        -- The EditBox covers the container's interior and eats its
        -- enter/leave, so mirror the hover onto it: one hover region,
        -- mint on entering either, fade only after leaving both.
        editBox:HookScript("OnEnter", toBrand)
        editBox:HookScript("OnLeave", function()
            if editBox:HasFocus() then return end
            if container:IsMouseOver() or editBox:IsMouseOver() then return end
            container._borderAnim.AnimateTo(Palette.border)
        end)
    end
end

-- Row hover wash, driven directly from RowEnter/RowLeave.
local function ApplyRowHover(frame, on)
    if not frame._rowHover then
        local wash = frame:CreateTexture(nil, "ARTWORK", nil, 7)
        wash:SetColorTexture(Palette.hoverWash[1], Palette.hoverWash[2], Palette.hoverWash[3], Palette.hoverWash[4])
        wash:SetPoint("TOPLEFT", 1, -1)
        wash:SetPoint("BOTTOMRIGHT", -1, 1)
        wash:Hide()
        frame._rowHover = wash
    end
    if on then frame._rowHover:Show() else frame._rowHover:Hide() end
end

-- ---------------------------------------------------------------------------
-- StockClerk never paints item tooltips (that's WoW's and the user's tooltip
-- addon's job). Its own tooltips describe its own controls.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Rows: built once per pooled Button, reused as the ScrollView recycles them.
-- ---------------------------------------------------------------------------
local function BuildRow(row)
    row:SetHeight(ROW_HEIGHT)

    -- Row hover wash is created lazily by ApplyRowHover on first RowEnter.

    -- 2px left accent: short / ok, a second channel beside the Have colour
    -- (colourblind-friendly). A texture, so the grip stays clickable.
    row.accent = row:CreateTexture(nil, "OVERLAY")
    row.accent:SetWidth(2)
    row.accent:SetPoint("TOPLEFT",    row, "TOPLEFT",     0, -1)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT",  0,  1)
    row.accent:Hide()  -- shown only when we have a definite short/ok call

    -- 1px divider along the bottom; BACKGROUND 0 so washes and cells paint over it.
    row.separator = row:CreateTexture(nil, "BACKGROUND", nil, 0)
    row.separator:SetColorTexture(unpack(Palette.rowSeparator))
    row.separator:SetHeight(1)
    row.separator:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    row.separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

    -- Drag grip at the far left (drawn bars); icon and name sit right of it.
    local GRIP_W = 14
    row.grip = CreateFrame("Button", nil, row)
    row.grip:SetSize(GRIP_W, ROW_HEIGHT - 6)
    row.grip:SetPoint("LEFT", 2, 0)
    row.grip:RegisterForDrag("LeftButton")
    row.grip:RegisterForClicks("LeftButtonUp")
    local GRIP_REST = { 0.55, 0.55, 0.55 }
    local tintGrip = DrawGlyph(row.grip, { { 8, 1, 3 }, { 8, 1, 0 }, { 8, 1, -3 } })
    tintGrip(GRIP_REST, 0.85)
    row.grip:SetScript("OnEnter", function(self)
        tintGrip(Palette.brand)
        -- ANCHOR_TOP for consistency.
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Drag to reorder", 1, 1, 1)
        GameTooltip:AddLine("List order sets restock priority.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Shift+click a row to link it in chat.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Click Need or Cap to edit it.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("With the AH open, click a row to search for it.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    row.grip:SetScript("OnLeave", function(self)
        tintGrip(GRIP_REST, 0.85)
        GameTooltip:Hide()
    end)
    row.grip:SetScript("OnDragStart", function(self)
        local r = self:GetParent()
        if not r or not r._itemID or not MF.BeginRowDrag then return end
        MF:BeginRowDrag(r)
    end)
    row.grip:SetScript("OnDragStop", function()
        if MF.EndRowDrag then MF:EndRowDrag() end
    end)

    -- Icon (shifted right by GRIP_W to clear the grip handle).
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", GRIP_W + 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim default 5% border

    -- 1px quality border (Baganator style): a solid square 2px larger than
    -- the icon, drawn just below it, tinted by quality in the row setter.
    row.iconBorder = row:CreateTexture(nil, "OVERLAY", nil, -1)
    row.iconBorder:SetColorTexture(0, 0, 0, 1)
    row.iconBorder:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
    row.iconBorder:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)

    row.name = row:CreateFontString(nil, "OVERLAY", "StockClerkFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    -- Right edge is anchored to row.have (below) so the name ellipsizes as
    -- Have grows with a (+N) suffix.

    -- Have: bags count (red short, mint stocked) plus a dim (+N) for bank and
    -- warband copies. Read-only; an invisible hit frame carries the tooltip
    -- with the per-source breakdown.
    -- Columns right-align on their own edges (headers match):
    --   Have -212 | Need cell -160 (w42) | Cap cell -100 (w50) | Seen -30 (w60) | trash -6
    row.haveCell = CreateFrame("Button", nil, row)
    row.haveCell:SetSize(50, 20)  -- slightly wider than needCell (42) to
                                  -- comfortably fit "999 (+9999)" worst case
    row.haveCell:SetPoint("RIGHT", row, "RIGHT", -212, 0)
    row.haveCell:SetFrameLevel(row:GetFrameLevel() + 2)

    row.have = row.haveCell:CreateFontString(nil, "OVERLAY", "StockClerkFontHighlightSmall")
    row.have:SetPoint("RIGHT", row.haveCell, "RIGHT", -6, 0)
    row.have:SetJustifyH("RIGHT")

    -- Name stops 8px short of the rendered Have text; no word wrap, so a long
    -- name ellipsizes instead of breaking the row height.
    row.name:SetPoint("RIGHT", row.have, "LEFT", -8, 0)

    -- Have tooltip: bags count, then only the sources holding copies (the
    -- reagent bank folds into "bank" since 11.2).
    row.haveCell:SetScript("OnEnter", function(self)
        local r = self:GetParent()
        r:GetScript("OnEnter")(r)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local bd = r._breakdown
        local bags = (bd and bd.bags) or (r._have or 0)
        GameTooltip:SetText(("Have: %d in bags"):format(bags), 1, 1, 1)
        if bd then
            if (bd.bank or 0) > 0 then
                GameTooltip:AddLine(("+%d in bank (this character)"):format(bd.bank), 0.78, 0.78, 0.78)
            end
            if (bd.warband or 0) > 0 then
                GameTooltip:AddLine(("+%d in warband bank (account-wide)"):format(bd.warband), 0.78, 0.78, 0.78)
            end
        end
        GameTooltip:Show()
    end)
    row.haveCell:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        local r = self:GetParent()
        r:GetScript("OnLeave")(r)
    end)

    -- Need and Cap: click-to-edit cells. Faint well at rest; dark fill and a
    -- mint border fade in on hover; a click swaps in an inline edit box with
    -- a darker backing (WireEditor below owns the behaviour).
    -- The value is parented to the cell so it draws above the cell's fill.
    -- The edit box never calls EnableKeyboard(true): a hidden EditBox holding
    -- keyboard capture swallows every key game-wide until /reload. It also
    -- clears focus when hidden (row recycled mid-edit) for the same reason.
    local CELL_FILL_IDLE   = { 0, 0, 0, 0.35 }
    local CELL_FILL_HOVER  = { Palette.bgMedium[1], Palette.bgMedium[2], Palette.bgMedium[3], 1 }
    local CELL_BORDER_IDLE = { Palette.brand[1], Palette.brand[2], Palette.brand[3], 0 }
    local function MakeCell(width, right, maxLetters)
        local cell = CreateFrame("Button", nil, row)
        cell:SetSize(width, 20)
        cell:SetPoint("RIGHT", row, "RIGHT", right, 0)  -- accounting-columns edge
        cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cell:SetFrameLevel(row:GetFrameLevel() + 2)
        ApplyFill(cell, CELL_FILL_IDLE)
        AddBlackBorder(cell, CELL_BORDER_IDLE)
        AttachBorderAnimator(cell)
        cell._fillIdle, cell._fillHover, cell._borderIdle = CELL_FILL_IDLE, CELL_FILL_HOVER, CELL_BORDER_IDLE

        local text = cell:CreateFontString(nil, "OVERLAY", "StockClerkFontHighlightSmall")
        text:SetPoint("RIGHT", cell, "RIGHT", -6, 0)
        text:SetJustifyH("RIGHT")

        local editBg = row:CreateTexture(nil, "BACKGROUND")
        editBg:SetColorTexture(Palette.bgDark[1], Palette.bgDark[2], Palette.bgDark[3], 1)
        editBg:Hide()
        local edit = CreateFrame("EditBox", nil, row)
        edit:SetFontObject("StockClerkFontHighlightSmall")
        edit:SetAutoFocus(false)
        edit:SetNumeric(true)         -- whole numbers only (gold for Cap)
        edit:SetMultiLine(false)      -- Enter reaches OnEnterPressed
        edit:SetMaxLetters(maxLetters)
        edit:SetJustifyH("CENTER")
        edit:SetSize(width, 20)
        edit:SetPoint("CENTER", cell, "CENTER")
        edit:SetFrameLevel(cell:GetFrameLevel() + 1)
        editBg:SetPoint("TOPLEFT",     edit, "TOPLEFT",     -4, 2)
        editBg:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT",  4, -2)
        edit:HookScript("OnHide", function(self) if self:HasFocus() then self:ClearFocus() end end)
        edit:Hide()
        return cell, text, edit, editBg
    end
    row.needCell, row.need, row.needEdit, row.needEditBg   = MakeCell(42, -160, 5)
    row.capCell,  row.cap,  row.priceEdit, row.priceEditBg = MakeCell(50, -100, 7)  -- up to 9,999,999g

    -- Last Seen: dim last AH unit price (updates on every search), or a dash.
    row.lastSeen = row:CreateFontString(nil, "OVERLAY", "StockClerkFontHighlightSmall")
    row.lastSeen:SetPoint("RIGHT", row, "RIGHT", -30, 0)
    row.lastSeen:SetWidth(60)  -- widened for #g#s (was 38)
    row.lastSeen:SetJustifyH("RIGHT")
    -- Invisible mouse target sized to the column so tooltips still work.
    row.lastSeenHit = CreateFrame("Frame", nil, row)
    row.lastSeenHit:SetSize(60, 20)  -- widened to match lastSeen
    row.lastSeenHit:SetPoint("RIGHT", row, "RIGHT", -30, 0)
    row.lastSeenHit:EnableMouse(true)
    row.lastSeenHit:SetScript("OnEnter", function(self)
        -- No price, no tooltip.
        local r = self:GetParent()
        if not r or not r._lastPrice then return end
        local lp = r._lastPrice
        local ago = time() - (lp.seenAt or 0)
        local agoText
        if ago < 60 then agoText = ago .. "s ago"
        elseif ago < 3600 then agoText = math.floor(ago/60) .. "m ago"
        elseif ago < 86400 then agoText = math.floor(ago/3600) .. "h ago"
        else agoText = math.floor(ago/86400) .. "d ago" end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Last seen at AH")
        GameTooltip:AddLine(MoneyText(lp.copper) .. " per unit", 1, 1, 1)
        local how = ({ click = " \194\183 you searched", loop = " \194\183 restock" })[lp.source] or ""
        GameTooltip:AddLine(agoText .. how, 0.7, 0.7, 0.7)
        local staleCutoff = (ADDON.DB:Settings() and ADDON.DB:Settings().lastPriceTTL) or 86400
        if ago > staleCutoff then
            GameTooltip:AddLine("Price is stale -- re-search to refresh", 0.9, 0.6, 0.2)
        end
        GameTooltip:Show()
    end)
    row.lastSeenHit:SetScript("OnLeave", function(self)
        local r = self:GetParent()
        if not r or not r._lastPrice then return end
        GameTooltip:Hide()
    end)

    -- Trash, shown on row hover. Row, cells and trash share RowEnter/RowLeave.
    row.trash = CreateFrame("Button", nil, row)
    row.trash:SetSize(18, 18)
    row.trash:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.trash:SetFrameLevel(row:GetFrameLevel() + 5)
    row.trash:SetNormalTexture(TRASH_TEX)
    row.trash:SetHighlightTexture(TRASH_TEX)
    local ht = row.trash:GetHighlightTexture()
    if ht then ht:SetBlendMode("ADD") end
    row.trash:Hide()
    row.trash:RegisterForClicks("LeftButtonUp")

    local function RowEnter(r)
        ApplyRowHover(r, true)
        r.trash:Show()
    end

    -- Checked right away, not a frame later: moving onto one of the row's own
    -- cells or its trash button keeps the cursor inside the row, so the
    -- hover stays; anywhere else clears it. (The old one-frame delay could
    -- misread a fast exit and leave the highlight stuck.)
    local function RowLeave(r)
        if r:IsMouseOver() then return end
        ApplyRowHover(r, false)
        GameTooltip:Hide()
        r.trash:Hide()
    end

    row:SetScript("OnEnter",  function(self) RowEnter(self) end)
    row:SetScript("OnLeave",  function(self) RowLeave(self) end)
    row.trash:SetScript("OnEnter", function(self) RowEnter(self:GetParent()) end)
    row.trash:SetScript("OnLeave", function(self) RowLeave(self:GetParent()) end)
    row:SetScript("OnClick", function(self, mouseButton)
        -- Shift + Left Click -> paste item link into the active chat edit,
        -- matching the standard Blizzard bag/inventory behavior.
        if mouseButton == "LeftButton" and IsShiftKeyDown() and self._itemLink then
            local edit = ChatEdit_ChooseBoxForSend()
            ChatEdit_ActivateChat(edit)
            edit:Insert(self._itemLink)
            return
        end
        -- Plain Left Click while AH is open -> browse this item at the AH.
        -- Callback logs to the status bar; doesn't buy anything.
        if mouseButton == "LeftButton" and self._itemID
           and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
            local id = self._itemID
            MF:SetStatus(("Searching AH for %s..."):format(self.name:GetText() or ("item:" .. id)))
            -- "click" source tag lets StampLastPrice attribute this lastPrice stamp
            -- to the user's manual row click vs the restock loop's auto search.
            ADDON.AH:SearchItem(id, function(ok, results)
                if not ok then
                    MF:SetStatus("|cffff8888AH search failed: " .. tostring(results) .. "|r")
                    return
                end
                local cheapest = results[1] and results[1].unitPrice
                if cheapest then
                    MF:SetStatus(("Cheapest: %s / unit (%d listings)"):format(
                        MoneyText(cheapest), #results))
                    -- Row list refresh so the Last Seen column
                    -- picks up the new stamp immediately.
                    MF:Refresh()
                else
                    MF:SetStatus("No auctions found")
                end
            end, "click")
        end
    end)
    row:RegisterForClicks("LeftButtonUp")

    -- Inline cell editors (Need and Cap). Both behave identically; only the
    -- prefill, tooltip and commit differ. Click opens; Escape aborts; Enter,
    -- Tab or blur commit. Opening one editor snaps its sibling closed
    -- synchronously -- SetFocus can outrace the deferred OnEditFocusLost, so
    -- without this both editors could briefly show on the same row.
    -- Commit refreshes the list only when the value changed, so clicking
    -- away from an untouched cell doesn't cost a DataProvider rebuild.
    local editors = {}

    local function CloseEdit(r, e)
        local cell = r[e.cell]
        r[e.edit]:ClearFocus()
        r[e.edit]:Hide()
        r[e.bg]:Hide()
        r[e.label]:Show()
        cell[e.active] = false
        if not cell:IsMouseOver() then
            cell._borderAnim.AnimateTo(cell._borderIdle)
            if cell._bg then cell._bg:SetVertexColor(unpack(cell._fillIdle)) end
        end
    end

    local function OpenEdit(r, e)
        for _, other in ipairs(editors) do
            if other ~= e and r[other.edit]:IsShown() then CloseEdit(r, other) end
        end
        local cell, edit = r[e.cell], r[e.edit]
        edit:SetText(e.prefill(r))
        r[e.label]:Hide()
        edit:Show()
        r[e.bg]:Show()
        edit:SetFocus()
        edit:HighlightText()
        cell[e.active] = true
        cell._borderAnim.AnimateTo(Palette.brand)
        if cell._bg then cell._bg:SetVertexColor(unpack(cell._fillHover)) end
    end

    local function CommitEdit(r, e)
        local changed = r._itemID and e.commit(r, r[e.edit]:GetText())
        CloseEdit(r, e)
        if changed then MF:Refresh() end
    end

    local function WireEditor(e)
        editors[#editors + 1] = e
        local cell, edit = row[e.cell], row[e.edit]
        cell:SetScript("OnClick", function(self) OpenEdit(self:GetParent(), e) end)
        cell:SetScript("OnEnter", function(self)
            local r = self:GetParent()
            -- Fire row-level hover too so trash + wash still appear.
            r:GetScript("OnEnter")(r)
            self._borderAnim.AnimateTo(Palette.brand)
            if self._bg then self._bg:SetVertexColor(unpack(self._fillHover)) end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            e.tooltip(r)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function(self)
            if not self[e.active] then
                self._borderAnim.AnimateTo(self._borderIdle)
                if self._bg then self._bg:SetVertexColor(unpack(self._fillIdle)) end
            end
            -- Hide unconditionally. If the mouse is still on the row body,
            -- RowEnter re-fires and paints the native item tooltip.
            GameTooltip:Hide()
            local r = self:GetParent()
            r:GetScript("OnLeave")(r)
        end)
        edit:SetScript("OnEscapePressed", function(self)
            self._escaping = true
            CloseEdit(self:GetParent(), e)
            self._escaping = false
        end)
        edit:SetScript("OnEnterPressed", function(self) CommitEdit(self:GetParent(), e) end)
        edit:SetScript("OnEditFocusLost", function(self)
            if self._escaping or not self:IsShown() then return end
            CommitEdit(self:GetParent(), e)
        end)
        edit:SetScript("OnTabPressed", function(self) self:ClearFocus() end)
    end

    -- Cap: whole gold in the box, copper in the DB. Blank = clear cap.
    WireEditor({
        cell = "capCell", label = "cap", edit = "priceEdit", bg = "priceEditBg",
        active = "_priceEditActive",
        prefill = function(r)
            return r._maxPrice and tostring(math.floor(r._maxPrice / 10000)) or ""
        end,
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
            local priceGold = tonumber(text)
            local maxPriceCopper = (priceGold and priceGold > 0) and (priceGold * 10000) or nil
            if maxPriceCopper == r._maxPrice then return false end
            local oldMax = r._maxPrice
            ADDON.DB:SetItemMaxPrice(r._itemID, maxPriceCopper)
            r._maxPrice = maxPriceCopper
            local name = r.name:GetText() or ("item:" .. r._itemID)
            if maxPriceCopper then
                MF:SetStatus(("Cap for %s set to %dg"):format(name, priceGold))
            else
                MF:SetStatus(("Cap cleared for %s"):format(name))
            end
            ADDON.Log:Emit("cap_change", r._itemID, { fromCopper = oldMax, toCopper = maxPriceCopper })
            r.cap:SetText(maxPriceCopper and ("%dg"):format(priceGold) or "")
            return true
        end,
    })

    -- Need: positive integer target count.
    WireEditor({
        cell = "needCell", label = "need", edit = "needEdit", bg = "needEditBg",
        active = "_needEditActive",
        prefill = function(r) return tostring(r._need or 20) end,
        tooltip = function(r)
            GameTooltip:SetText(("Target: %d"):format(r._need or 20), 1, 1, 1)
            GameTooltip:AddLine("Click to change", 0.7, 0.7, 0.7)
        end,
        commit = function(r, text)
            local newNeed = tonumber(text)
            if not (newNeed and newNeed > 0 and newNeed ~= r._need) then return false end
            local oldNeed = r._need
            ADDON.DB:SetItem(r._itemID, newNeed)
            r._need = newNeed
            r.need:SetText(tostring(newNeed))
            ADDON.Log:Emit("target_change", r._itemID, { from = oldNeed, to = newNeed })
            return true
        end,
    })
end

local function InitializeRow(row, data)
    if not row._built then
        BuildRow(row)
        row._built = true
    end

    -- A pooled row can be rebound while hovered (a refresh mid-hover), and no
    -- OnLeave fires then: set hover from where the cursor actually is.
    local over = row:IsMouseOver()
    ApplyRowHover(row, over)
    row.trash:SetShown(over)

    -- Pooled rows get rebound to other items (refresh, scroll, filter). An
    -- editor left open and focused would keep capturing every key game-wide
    -- while scrolled out of view, so reset editors before binding.
    if row.needEdit and row.needEdit:IsShown() then
        if row.needEdit:HasFocus() then row.needEdit:ClearFocus() end
        row.needEdit:Hide()
        if row.needEditBg then row.needEditBg:Hide() end
        if row.need then row.need:Show() end
        if row.needCell then row.needCell._needEditActive = false end
    end
    if row.priceEdit and row.priceEdit:IsShown() then
        if row.priceEdit:HasFocus() then row.priceEdit:ClearFocus() end
        row.priceEdit:Hide()
        if row.priceEditBg then row.priceEditBg:Hide() end
        if row.cap then row.cap:Show() end
        if row.capCell then row.capCell._priceEditActive = false end
    end

    row._itemID   = data.itemID
    row._need     = data.need
    row._maxPrice = data.maxPrice

    -- No ring to repaint. Row focus comes from
    -- the cell-level border animation on the active editor.

    local name, link, quality, _, _, _, _, _, _, tex = C_Item.GetItemInfo(data.itemID)
    local icon = tex or select(5, C_Item.GetItemInfoInstant(data.itemID)) or QUESTION_ICON
    row.icon:SetTexture(icon)

    -- Quality colour (grey poor, white common, ...), black while unknown. A cold
    -- item re-runs this row once GET_ITEM_INFO_RECEIVED resolves quality.
    if quality then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        row.iconBorder:SetColorTexture(r, g, b, 1)
    else
        row.iconBorder:SetColorTexture(0, 0, 0, 1)
    end
    row._itemLink = link
    if link then
        row.name:SetText((link:gsub("|h%[(.-)%]|h", "|h%1|h")))
    else
        -- Async resolve for cold items; fall back to stored name.
        row.name:SetText(data.name or ("item:" .. data.itemID))
        ADDON.ItemResolver:Resolve(data.itemID, function(id, nm, ln)
            if row._itemID == id and ln then
                row.name:SetText((ln:gsub("|h%[(.-)%]|h", "|h%1|h")))
                row._itemLink = ln
            end
        end)
    end

    local bd     = ADDON.Inventory:GetBreakdown(data.itemID)
    local have   = bd.bags
    local stashed = bd.bank + bd.warband

    row._have      = have
    row._breakdown = bd

    -- Have: bags count coloured by status (red short, mint stocked); the
    -- (+N) stash suffix stays grey. Per-source detail is in the tooltip.
    local haveColor = ""
    local haveColorEnd = ""
    if data.need and data.need > 0 then
        local short = data.need - have
        if short > 0 then
            haveColor    = "|cffe5624a"  -- muted red, "short"
            haveColorEnd = "|r"
        else
            haveColor    = "|cff98FF98"  -- brand mint, "stocked"
            haveColorEnd = "|r"
        end
    end
    local haveText = haveColor .. tostring(have) .. haveColorEnd
    if stashed > 0 then
        haveText = haveText .. ("  |cff888888(+%d)|r"):format(stashed)
    end
    row.have:SetText(haveText)

    -- Need column: the plain target number (secondary text tint so it
    -- doesn't compete with the mint cap value or the semantic status pill).
    row.need:SetText(("|cffCCCCCC%d|r"):format(data.need))

    -- Cap: mint "Ng", red when last seen is above the cap (a buy would be
    -- refused; the cap is inclusive), or a dash when unset (buys at market;
    -- the confirm flyout warns "No cap set").
    if data.maxPrice then
        local capColor = "98FF98" -- brand mint by default (cap is fine or no data)
        if data.lastPrice and data.lastPrice.copper
           and data.lastPrice.copper > data.maxPrice then
            capColor = "ff8888" -- red: last-seen strictly exceeds our cap (priced out)
        end
        -- Whole-gold entry only, so display collapses to "Ng".
        row.cap:SetText(("|cff%s%dg|r"):format(capColor, math.floor(data.maxPrice / 10000)))
    else
        row.cap:SetText("|cff555555\226\128\148|r") -- em-dash for a real "unset" glyph
    end

    -- Last Seen: grey fades further once older than settings.lastPriceTTL
    -- (24h) so a stale price doesn't read as current.
    row._lastPrice = data.lastPrice
    if data.lastPrice and data.lastPrice.copper then
        local age = time() - (data.lastPrice.seenAt or 0)
        local staleCutoff = (ADDON.DB:Settings() and ADDON.DB:Settings().lastPriceTTL) or 86400
        local color = (age > staleCutoff) and "777777" or "CCCCCC"
        -- Gold and silver only here; the tooltip has exact copper.
        row.lastSeen:SetText(("|cff%s%s|r"):format(color, MoneyText(data.lastPrice.copper, "silver")))
    else
        row.lastSeen:SetText("|cff555555\226\128\148|r")
    end

    -- Trace only when this row's numbers change, not on every repaint.
    if ADDON.debug then
        MF._initRowLast = MF._initRowLast or {}
        local sig = ("%d/%d/%d"):format(have, stashed, data.need)
        if MF._initRowLast[data.itemID] ~= sig then
            MF._initRowLast[data.itemID] = sig
            ADDON.Debug("Row", ("id=%d bags=%d stashed=%d need=%d"):format(data.itemID, have, stashed, data.need))
        end
    end

    local short = data.need - have
    if short > 0 then
        -- Palette.short (muted red)
        row.accent:SetColorTexture(0xe5/255, 0x62/255, 0x4a/255, 1)
    else
        -- Mint green -- matches the Have-column stocked color
        row.accent:SetColorTexture(0x4a/255, 0xde/255, 0x80/255, 1)
    end
    row.accent:Show()

    -- Trash click wire. Read from row._itemID rather than closing over
    -- `data`, so a recycled row can't accidentally delete a stale item.
    row.trash:SetScript("OnClick", function(self)
        local r = self:GetParent()
        local id = r and r._itemID
        if id then
            local nameForLog = r._itemLink or ("item:" .. id)
            ADDON.DB:RemoveItem(id)
            ADDON.Inventory:Invalidate()
            if ADDON.Log then
                ADDON.Log:Emit("remove", id, { name = nameForLog })
            end
            MF:Refresh()
        end
    end)

    -- Hide inline editors if they were left showing during a refresh
    row.needEdit:Hide()
    row.needEditBg:Hide()
    row.need:Show()
    row.priceEdit:Hide()
    row.priceEditBg:Hide()
    row.cap:Show()
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------
-- Toolbar edit box in a styled container. The placeholder is an overlay
-- font string (GetText stays ""), shown while empty and unfocused; it names
-- the field, and the hover tooltip (tipTitle / tipBody) explains it.
local function MakeEditBox(parent, placeholder, width, isNumeric, maxLetters, tipTitle, tipBody)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 22)

    local container = CreateFrame("Frame", nil, row)
    container:SetAllPoints()

    local eb = CreateFrame("EditBox", nil, container)
    eb:SetPoint("TOPLEFT", 6, -3)
    eb:SetPoint("BOTTOMRIGHT", -6, 3)
    eb:SetFontObject("StockClerkFontHighlight")
    eb:SetTextColor(1, 1, 1, 1)
    eb:SetAutoFocus(false)
    if isNumeric then eb:SetNumeric(true) end
    if maxLetters then eb:SetMaxLetters(maxLetters) end

    if placeholder then
        local ph = container:CreateFontString(nil, "OVERLAY", "StockClerkFontDisableSmall")
        ph:SetPoint("LEFT", eb, "LEFT", 0, 0)
        ph:SetPoint("RIGHT", eb, "RIGHT", 0, 0)
        ph:SetJustifyH("LEFT")
        ph:SetText(placeholder)
        -- Slightly brighter than pure textMuted so hints stay legible on the
        -- new banded toolbar without competing with real user input.
        ph:SetTextColor(0.62, 0.62, 0.62, 1)

        local function refresh()
            local hasText = eb:GetText() ~= ""
            local hasFocus = eb:HasFocus()
            ph:SetShown(not hasText and not hasFocus)
        end
        eb:HookScript("OnEditFocusGained", refresh)
        eb:HookScript("OnEditFocusLost",   refresh)
        eb:HookScript("OnTextChanged",     refresh)
        refresh()
        row.placeholder = ph
    end

    StyleEditBoxContainer(container, eb)
    -- A hidden focused EditBox keeps capturing game-wide keys: clear on hide.
    eb:HookScript("OnHide", function(self)
        if self:HasFocus() then self:ClearFocus() end
    end)
    -- Tooltip anchored 4px above the box: ANCHOR_TOP overlaps the box and
    -- flickers (cursor lands on the tooltip, OnLeave, repeat). Hidden only
    -- once the cursor leaves both the border area and the input.
    if tipTitle then
        container:HookScript("OnEnter", function()
            GameTooltip:SetOwner(container, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("BOTTOM", container, "TOP", 0, 4)
            GameTooltip:SetText(tipTitle, 1, 1, 1)
            if tipBody then GameTooltip:AddLine(tipBody, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end)
        eb:HookScript("OnEnter", function() container:GetScript("OnEnter")(container) end)
        local function hide()
            if not container:IsMouseOver() and not eb:IsMouseOver() then GameTooltip:Hide() end
        end
        container:HookScript("OnLeave", hide)
        eb:HookScript("OnLeave", hide)
    end
    row.editBox = eb
    row.container = container
    return row
end

function MF:Build()
    ApplyFontFace()
    if self.frame then return self.frame end

    -- ---- Root frame: one fill, 1px black border, regions split by borders.
    local f = CreateFrame("Frame", "StockClerkFrame", UIParent, "BackdropTemplate")
    f:SetSize(420, 400)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    -- 420x400 is the designed minimum; no ceiling.
    f:SetResizeBounds(420, 400)  -- min-only; no max = unbounded
    f:EnableMouse(true)
    -- Needed: toolbar typing broke without it, and OnKeyDown (Escape stops a
    -- restock) needs raw keys when no edit box has focus.
    f:EnableKeyboard(true)

    -- Border on a child frame at TOOLTIP strata so nothing draws over it.
    ApplyFill(f, Palette.bgDark)
    local borderFrame = CreateFrame("Frame", nil, f)
    borderFrame:SetAllPoints(f)
    borderFrame:SetFrameStrata("TOOLTIP")
    borderFrame:SetFrameLevel(f:GetFrameLevel() + 100)
    AddBlackBorder(borderFrame)

    -- Escape closes the window via UISpecialFrames (when no edit box has focus).
    tinsert(UISpecialFrames, "StockClerkFrame")

    -- SetPropagateKeyboardInput is sticky: an error before it runs would
    -- swallow every key game-wide. So actions run in pcall and propagate is
    -- set exactly once, as the last line. No early returns in here.
    f:SetScript("OnKeyDown", function(self, key)
        local consumed = false

        -- Escape stops an active auto-purchase loop.
        if key == "ESCAPE" and ADDON.RestockLoop and ADDON.RestockLoop:IsActive() then
            consumed = true
            pcall(function() ADDON.RestockLoop:Stop("user_esc") end)

        end

        -- Handled keys stop here; everything else reaches game bindings.
        self:SetPropagateKeyboardInput(not consumed)
    end)

    -- Every close path (Escape, x, /clerk) ends in Hide, so this is the one
    -- place to release keyboard capture: a focused hidden edit box would
    -- otherwise swallow keys game-wide.
    f:SetScript("OnHide", function()
        -- Close the side panel first (it's UIParent-parented); pcall so an
        -- error there can't skip the keyboard reset below.
        if ADDON.Sidecar and ADDON.Sidecar.Hide then
            pcall(function() ADDON.Sidecar:Hide() end)
        end

        -- Reset propagate: the root frame keeps the keyboard while hidden.
        f:SetPropagateKeyboardInput(true)

        local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focused and focused.ClearFocus then focused:ClearFocus() end

        -- A drag must not survive a close (its ticker would poll forever).
        if MF._dragTicker then
            MF._dragTicker:Cancel(); MF._dragTicker = nil
        end
        MF._dragItemID = nil
        MF._dropIndex  = nil
        if MF._dragMarker then MF._dragMarker:Hide() end
        -- Close any open row editor (discarding the edit, like closing a
        -- dialog), or a pooled row would reopen with a stale editor on it.
        if MF.scrollBox and MF.scrollBox.EnumerateFrames then
            for _, row in MF.scrollBox:EnumerateFrames() do
                if row.needEdit then
                    row.needEdit:Hide()
                    if row.needEditBg then row.needEditBg:Hide() end
                    if row.need then row.need:Show() end
                    if row.needCell then row.needCell._needEditActive = false end
                end
                if row.priceEdit then
                    row.priceEdit:Hide()
                    if row.priceEditBg then row.priceEditBg:Hide() end
                    if row.cap then row.cap:Show() end
                    if row.capCell then row.capCell._priceEditActive = false end
                end
            end
        end
    end)

    -- Position + size (both persisted per-character). Size lives on the
    -- same uiPos table so one save/restore cycle handles both.
    local pos = ADDON.DB.char.uiPos
    if pos and pos.point then
        f:ClearAllPoints()
        f:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER")
    end
    if pos and pos.width and pos.height then
        f:SetSize(pos.width, pos.height)
    end

    -- ---- Header: title, version, icons; drag to move ---------------------
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(26)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:EnableMouse(true)
    ApplyBand(header, Palette.bandTint)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        local existing = ADDON.DB.char.uiPos or {}
        existing.point, existing.x, existing.y = point, x, y
        ADDON.DB.char.uiPos = existing
    end)

    local headerSep = header:CreateTexture(nil, "OVERLAY", nil, 6)
    headerSep:SetColorTexture(Palette.border[1], Palette.border[2], Palette.border[3], 1)
    headerSep:SetHeight(BORDER_SIZE)
    headerSep:SetPoint("BOTTOMLEFT", 0, 0)
    headerSep:SetPoint("BOTTOMRIGHT", 0, 0)
    PixelSnap(headerSep)

    local title = header:CreateFontString(nil, "OVERLAY", "StockClerkFontNormalLarge")
    title:SetPoint("LEFT", header, "LEFT", 12, 0)
    title:SetText("|cff98FF98Stock|r|cffFFFFFFClerk|r")
    title:SetShadowOffset(0, 0)

    -- Version from the .toc; amber for alpha/beta. A git checkout still has
    -- the packager keyword "@project-version@", shown as "dev".
    local rawVersion = C_AddOns and C_AddOns.GetAddOnMetadata
                       and C_AddOns.GetAddOnMetadata("StockClerk", "Version") or ""
    local isUnsubstituted = rawVersion == "" or rawVersion:sub(1, 1) == "@"
    local versionText, versionColor
    if isUnsubstituted then
        versionText = "dev"
        versionColor = "|cff888888"
    else
        -- Tags already start with "v"; don't prefix another.
        if rawVersion:sub(1, 1) == "v" or rawVersion:sub(1, 1) == "V" then
            versionText = rawVersion
        else
            versionText = "v" .. rawVersion
        end
        local isPrerelease = rawVersion:match("%-alpha") or rawVersion:match("%-beta")
        versionColor = isPrerelease and "|cffFFAA00" or "|cff888888"
    end
    local versionLabel = header:CreateFontString(nil, "OVERLAY", "StockClerkFontNormalSmall")
    versionLabel:SetPoint("LEFT", title, "RIGHT", 6, -1)  -- -1 to baseline-align vs the Large title
    versionLabel:SetText(versionColor .. versionText .. "|r")
    versionLabel:SetShadowOffset(0, 0)

    local closeX = HeaderIcon(header, { { 12, 2, 0, math.pi / 4 }, { 12, 2, 0, -math.pi / 4 } },
        "Close", function() MF:Hide() end)
    closeX:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    local hamburgerBtn = HeaderIcon(header, { { 14, 2, 4 }, { 14, 2, 0 }, { 14, 2, -4 } },
        "Settings & Activity", function(self) ADDON.Sidecar:Toggle(self) end)
    hamburgerBtn:SetPoint("RIGHT", closeX, "LEFT", -2, 0)
    MF._hamburgerBtn = hamburgerBtn

    -- ---- Toolbar: add an item --------------------------------------------
    local toolbar = CreateFrame("Frame", nil, f)
    toolbar:SetHeight(30)
    toolbar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    ApplyBand(toolbar, Palette.bandTint)

    local toolbarSep = toolbar:CreateTexture(nil, "OVERLAY", nil, 6)
    toolbarSep:SetColorTexture(Palette.border[1], Palette.border[2], Palette.border[3], 1)
    toolbarSep:SetHeight(BORDER_SIZE)
    toolbarSep:SetPoint("BOTTOMLEFT", 0, 0)
    toolbarSep:SetPoint("BOTTOMRIGHT", 0, 0)
    PixelSnap(toolbarSep)

    -- Item ID + Target. Item ID only (names are ambiguous across ranks);
    -- blank Target = 1. Caps are set per row after seeing AH prices.
    -- Item ID stretches to fill whatever the window width leaves.
    local addEB   = MakeEditBox(toolbar, "Item ID, Enter to add", 130, true, 8, "Item ID",
        L.ADDBOX_TOOLTIP or "Type an item ID, or drag an item from your bags onto this window.")
    local countEB = MakeEditBox(toolbar, "Target",   60, true, 5, "Target",
        "How many to keep in your bags. Blank = 1.")
    local addBox   = addEB.editBox
    local countBox = countEB.editBox

    -- Enter in either box adds the item. The square button is bulk import:
    -- a drawn "list +" icon (three lines, a plus at the bottom right).
    local bulkBtn = CreateFrame("Button", nil, toolbar)
    bulkBtn:SetSize(22, 22)
    bulkBtn:SetPoint("RIGHT", toolbar, "RIGHT", -12, 0)
    countEB:SetPoint("RIGHT", bulkBtn, "LEFT", -8, 0)
    addEB:SetPoint("LEFT", toolbar, "LEFT", 12, 0)
    addEB:SetPoint("RIGHT", countEB, "LEFT", -8, 0)
    StyleButton(bulkBtn)
    local tintBulk = DrawGlyph(bulkBtn, {
        { 10, 2, 5, nil, -2 }, { 10, 2, 1, nil, -2 }, { 5, 2, -3, nil, -4.5 },  -- list
        { 7, 2, -4, nil, 4 }, { 2, 7, -4, nil, 4 },                               -- plus
    })
    bulkBtn:HookScript("OnEnter", function(self)  -- Hook, not Set: keeps StyleButton's hover wash
        tintBulk(Palette.brand)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Bulk import", 1, 1, 1)
        GameTooltip:AddLine("Paste a list of item IDs, one per line, to add them all at once.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    bulkBtn:HookScript("OnLeave", function() GameTooltip:Hide(); tintBulk(ICON_REST) end)
    bulkBtn:SetScript("OnClick", function() ADDON.BulkImport:Open() end)

    local function DoAdd()
        local raw = addBox:GetText()
        if not raw or raw == "" then return end
        -- Positive integers only (no links or names).
        local itemID = tonumber(raw)
        if not itemID or itemID <= 0 or math.floor(itemID) ~= itemID then
            MF:SetStatus("|cffff8888Item ID must be a number (e.g. 212283)|r")
            return
        end
        -- Silent default drops from 20 to 1 for zero-friction quick-add.
        local need = tonumber(countBox:GetText()) or 1

        -- Resolve warms the item cache; an unknown id is reported and skipped.
        ADDON.ItemResolver:Resolve(itemID, function(resolvedID, name, _)
            if not resolvedID then
                MF:SetStatus(("|cffff8888Unknown item ID: %d|r"):format(itemID))
                return
            end
            ADDON.DB:SetItem(resolvedID, need)
            ADDON.Inventory:Invalidate()
            if ADDON.Log then
                ADDON.Log:Emit("add", resolvedID, {
                    name       = name,
                    need       = need,
                })
            end
            -- Clear and unfocus both so the placeholders re-show.
            addBox:SetText("")
            countBox:SetText("")
            addBox:ClearFocus()
            countBox:ClearFocus()
            MF:SetStatus(("Added %s (need %d)"):format(name, need))
            MF:Refresh()
        end)
    end

    addBox:SetScript("OnEnterPressed", function() DoAdd() addBox:ClearFocus() end)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    countBox:SetScript("OnEnterPressed", function() DoAdd() addBox:ClearFocus() end)
    countBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- ---- Quick add: shift-click or drop an item on the Item ID box, or
    -- shift-click a link while the box is focused. All three only fill the
    -- box; Enter still commits. Scoped to the box, so chat links are unaffected.

    -- itemID from whatever the cursor holds, or nil.
    local function CursorItemID()
        local kind, arg1, arg2 = GetCursorInfo()
        if kind == "item" then
            -- ("item", itemID, link); some builds sent a link as arg1.
            local id = tonumber(arg1)
            if id then return id end
            if type(arg1) == "string" then
                id = tonumber(arg1:match("item:(%d+)"))
                if id then return id end
            end
            if type(arg2) == "string" then
                id = tonumber(arg2:match("item:(%d+)"))
                if id then return id end
            end
        end
        return nil
    end

    -- Fill the box, clear the cursor, focus so Enter commits.
    local function StampAddBox(itemID)
        if not itemID then return end
        addBox:SetText(tostring(itemID))
        addBox:SetFocus()
        -- HighlightText in the same tick as SetFocus can no-op; wait a frame.
        C_Timer.After(0, function()
            if addBox:HasFocus() then addBox:HighlightText() end
        end)
        if ClearCursor then ClearCursor() end
        MF:SetStatus(("Quick-add: item %d (press Enter to add)"):format(itemID))
    end

    -- Accept drops on the container too. HookScript: the container's hover
    -- animation already uses its handlers.
    local dropTarget = addEB.container or addBox
    dropTarget:EnableMouse(true)
    dropTarget:RegisterForDrag("LeftButton")
    dropTarget:HookScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        -- Click on the box (or its container padding) focuses the input.
        addBox:SetFocus()
    end)
    dropTarget:HookScript("OnReceiveDrag", function()
        local id = CursorItemID()
        if id then StampAddBox(id) end
    end)

    -- The EditBox sits on top and receives the drop, so handle it there too;
    -- the container handler covers the thin border ring.
    addBox:RegisterForDrag("LeftButton")
    addBox:HookScript("OnReceiveDrag", function()
        local id = CursorItemID()
        if id then StampAddBox(id) end
    end)

    -- Mint outline while the cursor holds an item (CURSOR_CHANGED; there is
    -- no CURSOR_UPDATE on retail).
    local mint = { 0x98/255, 0xFF/255, 0x98/255 }
    local function edgeTex(parent)
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(mint[1], mint[2], mint[3], 1)
        t:Hide()
        return t
    end
    local dropEdges = {
        edgeTex(dropTarget), edgeTex(dropTarget),
        edgeTex(dropTarget), edgeTex(dropTarget),
    }
    dropEdges[1]:SetPoint("TOPLEFT",     dropTarget, "TOPLEFT",     -1,  1)
    dropEdges[1]:SetPoint("TOPRIGHT",    dropTarget, "TOPRIGHT",     1,  1)
    dropEdges[1]:SetHeight(1)
    dropEdges[2]:SetPoint("BOTTOMLEFT",  dropTarget, "BOTTOMLEFT",  -1, -1)
    dropEdges[2]:SetPoint("BOTTOMRIGHT", dropTarget, "BOTTOMRIGHT",  1, -1)
    dropEdges[2]:SetHeight(1)
    dropEdges[3]:SetPoint("TOPLEFT",     dropTarget, "TOPLEFT",     -1,  1)
    dropEdges[3]:SetPoint("BOTTOMLEFT",  dropTarget, "BOTTOMLEFT",  -1, -1)
    dropEdges[3]:SetWidth(1)
    dropEdges[4]:SetPoint("TOPRIGHT",    dropTarget, "TOPRIGHT",     1,  1)
    dropEdges[4]:SetPoint("BOTTOMRIGHT", dropTarget, "BOTTOMRIGHT",  1, -1)
    dropEdges[4]:SetWidth(1)

    local dropWatcher = CreateFrame("Frame", nil, dropTarget)
    dropWatcher:RegisterEvent("CURSOR_CHANGED")
    dropWatcher:SetScript("OnEvent", function()
        local show = CursorItemID() ~= nil
        for _, edge in ipairs(dropEdges) do edge:SetShown(show) end
    end)

    -- Save toolbar boxes on self so BuildRow's inline editors can reach
    -- them for unified Tab navigation across toolbar + row-body cells.
    self.addBox   = addBox
    self.countBox = countBox

    -- Tab (or Shift+Tab) switches between the two boxes.
    addBox:SetScript("OnTabPressed", function() countBox:SetFocus() end)
    countBox:SetScript("OnTabPressed", function() addBox:SetFocus() end)

    -- ---- Column headers ----------------------------------------------------
    -- Full window width so the band matches the toolbar and footer (anchored
    -- to f: listHolder anchors to headers, so anchoring back would loop).
    -- Rows sit 22px inside f (list inset 4 + scroll bar 18), so right-anchored
    -- labels subtract ROW_RIGHT_INSET to line up with the row offsets.
    local ROW_RIGHT_INSET = 22
    local headers = CreateFrame("Frame", nil, f)
    headers:SetHeight(20)
    headers:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, 0)
    headers:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    -- Same whisper-band as the toolbar. Reads as "column-header strip" so
    -- the labels have visual weight even without a colored fill of their own.
    ApplyBand(headers, Palette.bandTint)

    local headersSep = headers:CreateTexture(nil, "OVERLAY", nil, 6)
    headersSep:SetColorTexture(Palette.border[1], Palette.border[2], Palette.border[3], 1)
    headersSep:SetHeight(BORDER_SIZE)
    headersSep:SetPoint("BOTTOMLEFT", 0, 0)
    headersSep:SetPoint("BOTTOMRIGHT", 0, 0)
    PixelSnap(headersSep)

    -- mode "left": LEFT at xOffset; "right" / "center": RIGHT or CENTER at
    -- xOffset from the right, shifted by ROW_RIGHT_INSET so callers can pass
    -- the same offsets BuildRow uses.
    local function MakeHeader(text, mode, xOffset)
        local fs = headers:CreateFontString(nil, "OVERLAY", "StockClerkFontNormalSmall")
        fs:SetTextColor(Palette.brand[1], Palette.brand[2], Palette.brand[3], 1)
        fs:SetText(text)
        if mode == "left" then
            fs:SetPoint("LEFT", headers, "LEFT", xOffset, 0)
        elseif mode == "right" then
            fs:SetPoint("RIGHT", headers, "RIGHT", xOffset - ROW_RIGHT_INSET, 0)
        else -- center
            fs:SetPoint("CENTER", headers, "RIGHT", xOffset - ROW_RIGHT_INSET, 0)
        end
        return fs
    end
    -- Right edges match the row columns; Need/Cap sit 6px in, over the digits.
    MakeHeader("Item", "left",    36)     -- left edge + 24 (icon + 12 pad)
    MakeHeader("Have", "right",   -212)   -- right-edge with Have text
    MakeHeader("Need", "right",   -166)   -- cell right -160 - 6 inset
    MakeHeader("Cap",  "right",   -106)   -- cell right -100 - 6 inset
    MakeHeader("Seen", "right",   -30)    -- Seen text right edge

    -- "Show only short items" filter: drawn funnel next to the Item header.
    -- Dim mint = off, bright mint = on; the tooltip carries the meaning.
    local filterChip = CreateFrame("Button", nil, headers)
    filterChip:SetSize(18, 16)
    filterChip:SetPoint("LEFT", headers, "LEFT", 62, 0)
    filterChip:EnableMouse(true)

    local tintChip = DrawGlyph(filterChip, { { 12, 2, 4 }, { 8, 2, 0 }, { 4, 2, -4 } })
    local function paintChip() tintChip(Palette.brand, ADDON.DB:GetStuckOnly() and 1 or 0.55) end

    filterChip:SetScript("OnClick", function()
        ADDON.DB:SetStuckOnly(not ADDON.DB:GetStuckOnly())
        paintChip()
        MF:Refresh()
    end)
    filterChip:SetScript("OnEnter", function(self)
        tintChip(Palette.brand)  -- full mint on hover, on or off
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local on = ADDON.DB:GetStuckOnly()
        GameTooltip:SetText((on and "|cff98FF98Filter ON|r  " or "") ..
            L.FILTER_STUCK_ONLY, 1, 1, 1)
        GameTooltip:AddLine(L.FILTER_STUCK_TOOLTIP, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    filterChip:SetScript("OnLeave", function()
        paintChip()  -- return to persisted ON/OFF alpha
        GameTooltip:Hide()
    end)

    self.filterChip     = filterChip
    self._paintFilterChip = paintChip

    paintChip()

    -- ---- Footer: action feedback on the left, Restock on the right --------
    local footer = CreateFrame("Frame", nil, f)
    footer:SetHeight(30)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    -- Same whisper-band as toolbar/headers so the footer feels like a
    -- balanced counterweight to the toolbar, not just an afterthought row.
    ApplyBand(footer, Palette.bandTint)

    local footerSep = footer:CreateTexture(nil, "OVERLAY", nil, 6)
    footerSep:SetColorTexture(Palette.border[1], Palette.border[2], Palette.border[3], 1)
    footerSep:SetHeight(BORDER_SIZE)
    footerSep:SetPoint("TOPLEFT", 0, 0)
    footerSep:SetPoint("TOPRIGHT", 0, 0)
    PixelSnap(footerSep)

    -- Status text runs from the left inset to the Restock button's left
    -- edge, so long messages truncate instead of sliding under it.
    local statusBar = footer:CreateFontString(nil, "OVERLAY", "StockClerkFontNormalSmall")
    statusBar:SetPoint("LEFT", 14, 0)
    statusBar:SetJustifyH("LEFT")
    statusBar:SetWordWrap(false)  -- one line; oversized text truncates instead of stacking
    statusBar:SetMaxLines(1)      -- v1.1: hard single-line clamp so ellipsis kicks in cleanly at min-width
    self.statusBar = statusBar
    self._statusBarNeedsAnchor = true  -- deferred: restockBtn not built yet

    -- Restock: idle "Restock at AH / from Bank (N)", running "Stop restock".
    -- Buying happens in the confirm flyout, so a double-click here can't buy.
    local restockBtn = CreateFrame("Button", nil, footer)
    restockBtn:SetSize(160, 22)  -- fits "Restock from Bank (12)"
    restockBtn:SetPoint("RIGHT", -12, 0)

    if self._statusBarNeedsAnchor then
        statusBar:SetPoint("RIGHT", restockBtn, "LEFT", -8, 0)
        self._statusBarNeedsAnchor = nil
    end
    StyleButton(restockBtn)
    local restockBtnText = restockBtn:CreateFontString(nil, "OVERLAY", "StockClerkFontNormal")
    restockBtnText:SetPoint("CENTER")
    restockBtnText:SetTextColor(1, 1, 1, 1)
    restockBtn._label = restockBtnText
    restockBtnText:SetText("Restock at AH")

    restockBtn:SetScript("OnClick", function()
        local loop, br = ADDON.RestockLoop, ADDON.BankRestock
        if br:IsActive() then br:Stop("stopped by you"); return end
        if ADDON.bankOpen and not loop:IsActive() then br:Start(); return end
        if loop:IsActive() then
            loop:Stop("user_stop")
        else
            loop:Start()
        end
    end)

    restockBtn:HookScript("OnEnter", function(self)  -- Hook, not Set: keeps StyleButton's hover wash
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local loop = ADDON.RestockLoop
        if ADDON.BankRestock:IsActive() then
            GameTooltip:SetText("Stop pulling", 1, 1, 1)
            GameTooltip:AddLine("Stops after the item currently moving.", 0.7, 0.7, 0.7, true)
        elseif loop and loop:IsActive() then
            GameTooltip:SetText("Stop restock", 1, 1, 1)
            GameTooltip:AddLine("Ends the current walk. Any armed buy is discarded.", 0.7, 0.7, 0.7, true)
        elseif ADDON.bankOpen then
            GameTooltip:SetText("Restock from Bank", 1, 1, 1)
            GameTooltip:AddLine("Moves exactly what you're short from your bank, then your warband bank, into your bags.", 0.7, 0.7, 0.7, true)
            local reason = MF:_RestockDisabledReason()
            if reason then
                GameTooltip:AddLine(" ", 1, 1, 1)
                GameTooltip:AddLine(("Unavailable: %s"):format(reason),
                    Palette.short[1], Palette.short[2], Palette.short[3], true)
            end
        else
            GameTooltip:SetText("Restock at AH", 1, 1, 1)
            GameTooltip:AddLine("Walks your shortlist and prompts for each buy.", 0.7, 0.7, 0.7, true)
            GameTooltip:AddLine("Rows priced above your cap are skipped silently.", 0.7, 0.7, 0.7, true)
            -- Disabled-reason readout so a greyed-out button explains itself.
            local reason = MF:_RestockDisabledReason()
            if reason then
                GameTooltip:AddLine(" ", 1, 1, 1)
                GameTooltip:AddLine(("Unavailable: %s"):format(reason),
                    Palette.short[1], Palette.short[2], Palette.short[3], true)
            end
        end
        GameTooltip:Show()
    end)
    restockBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- Without this a disabled Restock shows no tooltip (and no reason).
    restockBtn:SetMotionScriptsWhileDisabled(true)

    self.restockBtn = restockBtn

    -- ---- Confirm / summary flyout, below the main frame ------------------
    -- armed: plan on the left, [Skip] [Buy (Ns)]; Buy unlocks after a short
    -- countdown like other WoW confirmations. summary: end-of-run recap.
    -- Right-click the body to stop. Below the window, away from the rows,
    -- so a misclick can't hit Buy.
    local toast = CreateFrame("Frame", nil, f, "BackdropTemplate")
    toast:SetSize(360, 44)
    toast:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -1)  -- 1px seam, matches style guide
    toast:SetFrameStrata(f:GetFrameStrata())
    toast:SetFrameLevel(f:GetFrameLevel() + 20)
    toast:EnableMouse(true)
    toast:Hide()

    -- Mint-accented backdrop distinct from the base window fill so the
    -- flyout reads as a live, actionable surface.
    local toastBG = toast:CreateTexture(nil, "BACKGROUND")
    toastBG:SetAllPoints()
    toastBG:SetColorTexture(0.055, 0.075, 0.055, 0.98)
    -- 1px mint border; kept on MF so the stash warning can pulse it amber.
    local topL = toast:CreateTexture(nil, "OVERLAY")
    topL:SetColorTexture(Palette.brand[1], Palette.brand[2], Palette.brand[3], 0.85)
    topL:SetPoint("TOPLEFT"); topL:SetPoint("TOPRIGHT"); topL:SetHeight(1)
    local botL = toast:CreateTexture(nil, "OVERLAY")
    botL:SetColorTexture(Palette.brand[1], Palette.brand[2], Palette.brand[3], 0.85)
    botL:SetPoint("BOTTOMLEFT"); botL:SetPoint("BOTTOMRIGHT"); botL:SetHeight(1)
    local lefL = toast:CreateTexture(nil, "OVERLAY")
    lefL:SetColorTexture(Palette.brand[1], Palette.brand[2], Palette.brand[3], 0.85)
    lefL:SetPoint("TOPLEFT"); lefL:SetPoint("BOTTOMLEFT"); lefL:SetWidth(1)
    local rigL = toast:CreateTexture(nil, "OVERLAY")
    rigL:SetColorTexture(Palette.brand[1], Palette.brand[2], Palette.brand[3], 0.85)
    rigL:SetPoint("TOPRIGHT"); rigL:SetPoint("BOTTOMRIGHT"); rigL:SetWidth(1)

    -- Content strings (armed mode)
    local titleFS = toast:CreateFontString(nil, "OVERLAY", "StockClerkFontNormal")
    titleFS:SetPoint("TOPLEFT", 10, -6)
    titleFS:SetPoint("RIGHT", -160, 0)  -- leave room for two buttons
    titleFS:SetJustifyH("LEFT")
    titleFS:SetTextColor(1, 1, 1, 1)
    titleFS:SetWordWrap(false)   -- truncate long titles, don't wrap into sub

    -- Amber "already have some in bank / warband" lines, shown when relevant.
    local stashBankFS = toast:CreateFontString(nil, "OVERLAY", "StockClerkFontHighlightSmall")
    stashBankFS:SetJustifyH("LEFT")
    stashBankFS:SetTextColor(1.0, 0.66, 0.4, 1)  -- amber (matches "No cap set")
    stashBankFS:SetWordWrap(false)
    stashBankFS:Hide()

    local stashWarbandFS = toast:CreateFontString(nil, "OVERLAY", "StockClerkFontHighlightSmall")
    stashWarbandFS:SetJustifyH("LEFT")
    stashWarbandFS:SetTextColor(1.0, 0.66, 0.4, 1)  -- amber
    stashWarbandFS:SetWordWrap(false)
    stashWarbandFS:Hide()

    local subFS = toast:CreateFontString(nil, "OVERLAY", "StockClerkFontHighlightSmall")
    subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -1)
    subFS:SetPoint("RIGHT", -160, 0)
    subFS:SetJustifyH("LEFT")
    subFS:SetTextColor(0.78, 0.78, 0.78, 1)
    subFS:SetWordWrap(false)     -- truncate long subs (bleeds under close btn was overflow root)

    -- Skip button (always available, sized to match Buy)
    local skipBtn = CreateFrame("Button", nil, toast)
    skipBtn:SetSize(64, 22)
    skipBtn:SetPoint("RIGHT", -78, 0)
    StyleButton(skipBtn)
    local skipText = skipBtn:CreateFontString(nil, "OVERLAY", "StockClerkFontNormal")
    skipText:SetPoint("CENTER")
    skipText:SetText("Skip")
    skipBtn:SetScript("OnClick", function()
        MF:_StopToastPulse()
        if MF._toastHandlers and MF._toastHandlers.onSkip then
            MF._toastHandlers.onSkip()
        end
    end)

    -- Primary button: dual-purpose. Armed mode = "Buy (Ns)" -> "Buy".
    -- Summary mode = "Close". Handler switches based on _toastMode.
    local primaryBtn = CreateFrame("Button", nil, toast)
    primaryBtn:SetSize(70, 22)
    primaryBtn:SetPoint("RIGHT", -8, 0)
    StyleButton(primaryBtn)
    local primaryText = primaryBtn:CreateFontString(nil, "OVERLAY", "StockClerkFontNormal")
    primaryText:SetPoint("CENTER")
    primaryText:SetText("Buy")

    -- Mint-tinted fill for the Buy button when armed. Hidden by default.
    local primaryFill = primaryBtn:CreateTexture(nil, "ARTWORK")
    primaryFill:SetColorTexture(Palette.brand[1], Palette.brand[2], Palette.brand[3], 0.35)
    primaryFill:SetPoint("TOPLEFT", 1, -1)
    primaryFill:SetPoint("BOTTOMRIGHT", -1, 1)
    primaryFill:Hide()

    primaryBtn:SetScript("OnClick", function()
        if MF._toastMode == "armed" then
            -- Countdown gate: silently ignore clicks until arm delay elapses.
            if MF._toastArmReady and MF._toastHandlers and MF._toastHandlers.onBuy then
                MF:_StopToastPulse()
                MF._toastHandlers.onBuy()
            end
        elseif MF._toastMode == "summary" then
            MF:HideToast()
        end
    end)

    -- Right-click the flyout body = stop the run.
    toast:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            if MF._toastHandlers and MF._toastHandlers.onStop then
                MF._toastHandlers.onStop()
            end
        end
    end)

    -- Hover tooltip explains the flow, esp. the countdown.
    toast:SetScript("OnEnter", function(self)
        if MF._toastMode ~= "armed" then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Confirm purchase", 1, 1, 1)
        GameTooltip:AddLine("Buy: complete this purchase. Waits a beat to prevent accidents.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Skip: pass on this item, keep going.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Right-click: stop the whole restock.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    toast:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.confirmToast     = toast
    self._toastTitle      = titleFS
    self._toastSub        = subFS
    self._toastStashBank    = stashBankFS
    self._toastStashWarband = stashWarbandFS
    self._toastSkip       = skipBtn
    self._toastPrimary    = primaryBtn
    self._toastPrimaryTxt = primaryText
    self._toastPrimaryFill= primaryFill
    self._toastBorderTex  = { topL, botL, lefL, rigL }
    self._toastMode       = nil
    self._toastHandlers   = nil
    self._toastArmReady   = false

    -- ---- Resize grip: Blizzard's chat-frame size grabber art ---------------
    local GRIP_UP        = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
    local GRIP_DOWN      = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down"
    local GRIP_HIGHLIGHT = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight"
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 5)
    grip:EnableMouse(true)
    grip:SetNormalTexture(GRIP_UP)
    grip:SetPushedTexture(GRIP_DOWN)
    grip:SetHighlightTexture(GRIP_HIGHLIGHT)
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        -- Persist new size alongside position on the same uiPos table.
        local point, _, _, x, y = f:GetPoint()
        local existing = ADDON.DB.char.uiPos or {}
        existing.point, existing.x, existing.y = point, x, y
        existing.width, existing.height = f:GetWidth(), f:GetHeight()
        ADDON.DB.char.uiPos = existing
    end)
    grip:SetScript("OnEnter", function()
        GameTooltip:SetOwner(grip, "ANCHOR_LEFT")
        GameTooltip:SetText("Drag to resize", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f:HookScript("OnShow", function() MF:RefreshRestockBtn() end)

    -- When the window hides, drop any tooltip owned by something inside it
    -- (no OnLeave fires when the owner just vanishes).
    f:HookScript("OnHide", function()
        local owner = GameTooltip:GetOwner()
        while owner do
            if owner == f then
                GameTooltip:Hide()
                return
            end
            owner = owner.GetParent and owner:GetParent() or nil
        end
    end)

    -- ---- ScrollBox (list of rows) --------------------------------------
    local listHolder = CreateFrame("Frame", nil, f)
    listHolder:SetPoint("TOPLEFT", headers, "BOTTOMLEFT", 4, -2)
    listHolder:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -4, 2)

    local scrollBox = CreateFrame("Frame", nil, listHolder, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT")
    scrollBox:SetPoint("BOTTOMRIGHT", -18, 0)

    local scrollBar = CreateFrame("EventFrame", nil, listHolder, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT",     scrollBox, "TOPRIGHT",    2, 0)
    scrollBar:SetPoint("BOTTOMLEFT",  scrollBox, "BOTTOMRIGHT", 2, 0)

    -- Set the element factory before attaching a DataProvider, or
    -- SetDataProvider errors ("elementFactory was nil").
    local scrollView = CreateScrollBoxListLinearView()
    scrollView:SetElementInitializer("Button", InitializeRow)
    scrollView:SetElementExtent(ROW_HEIGHT)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, scrollView)

    local dataProvider = CreateDataProvider()
    scrollView:SetDataProvider(dataProvider)

    self.frame        = f
    self.scrollBox    = scrollBox
    self.scrollView   = scrollView
    self.dataProvider = dataProvider

    -- Empty-state onboarding text, wrapped to the list width.
    self.emptyText = listHolder:CreateFontString(nil, "OVERLAY", "StockClerkFontDisable")
    self.emptyText:SetPoint("TOPLEFT", listHolder, "TOPLEFT", 16, -18)
    self.emptyText:SetPoint("TOPRIGHT", listHolder, "TOPRIGHT", -16, -18)
    self.emptyText:SetJustifyH("LEFT")
    self.emptyText:SetJustifyV("TOP")
    self.emptyText:SetWordWrap(true)
    self.emptyText:SetSpacing(3)
    self.emptyText:SetText(L.EMPTY_LIST or "No items tracked. Add one above.")
    self.emptyText:Hide()

    return f
end

-- ---------------------------------------------------------------------------
-- Refresh: rebuild the DataProvider (Auctionator's pattern; flushing and
-- re-inserting can reuse frames without re-running the initializer).
-- Refresh coalesces: any number of calls in one frame = one rebuild.
-- ---------------------------------------------------------------------------
function MF:Refresh()
    if self._refreshPending then return end
    if not self.frame or not self.scrollBox then return end
    self._refreshPending = true
    C_Timer.After(0, function()
        self._refreshPending = false
        self:_RefreshNow()
    end)
end

-- Immediate rebuild, for callers that must see the change right away.
function MF:_RefreshNow()
    if not self.frame or not self.scrollBox then return end

    local items = ADDON.DB:GetSortedItems()

    -- Filter on: only items you're short on (bags below target). The DB flag
    -- keeps its old name (char.ui.stuckOnly) so the saved state carries over.
    local stuckOnly = ADDON.DB:GetStuckOnly()
    if stuckOnly then
        local filtered = {}
        for _, it in ipairs(items) do
            if (ADDON.Inventory:GetCount(it.itemID) or 0) < it.need then
                filtered[#filtered + 1] = it
            end
        end
        items = filtered
    end
    -- Keep the chip visual in sync each refresh (safe idempotent paint).
    if self._paintFilterChip then self._paintFilterChip() end

    if #items == 0 then
        -- Empty provider still needs to be swapped in so any prior rows
        -- are cleared out.
        local emptyProvider = CreateDataProvider()
        self.scrollBox:SetDataProvider(emptyProvider, ScrollBoxConstants.RetainScrollPosition)
        self.dataProvider = emptyProvider
        self.emptyText:Show()
        -- skipLog: these are state, not events; logging them would bury the
        -- log in repaint noise.
        self.emptyText:SetText(stuckOnly
            and "|cff888888Nothing is short. Click the filter icon to see the full list.|r"
            or  L.EMPTY_LIST)
        self.emptyText:Show()
        self:RefreshRestockBtn()
        return
    end
    self.emptyText:Hide()

    local newProvider = CreateDataProvider()
    for i, it in ipairs(items) do
        newProvider:Insert({
            itemID      = it.itemID,
            name        = it.name,
            need        = it.need,
            maxPrice    = it.maxPrice,
            lastPrice   = it.lastPrice,   -- { copper, seenAt, source }; feeds the Last Seen column
            _index      = i,
        })
    end

    -- Keep the scroll position across refreshes.
    self.scrollBox:SetDataProvider(newProvider, ScrollBoxConstants.RetainScrollPosition)
    self.dataProvider = newProvider

    -- Short count comes from Loop:PreviewShortfallCount: same math as a click.
    self:RefreshRestockBtn()
end

-- Restock button: idle / running label and enabled state. A disabled idle
-- button explains why on hover (_RestockDisabledReason).
function MF:RefreshRestockBtn(shortCount)
    if not self.restockBtn then return end
    -- Same shortfall math as the loop, so the button and a click agree.
    if shortCount == nil then
        if ADDON.RestockLoop and ADDON.RestockLoop.PreviewShortfallCount then
            shortCount = ADDON.RestockLoop:PreviewShortfallCount()
        else
            shortCount = 0
        end
    end
    self._lastShortCount = shortCount
    local loop = ADDON.RestockLoop
    local btn  = self.restockBtn
    local muted = Palette.textMuted

    if ADDON.BankRestock:IsActive() then
        btn._label:SetText("Stop pulling")
        btn._label:SetTextColor(1, 1, 1, 1)
        btn:Enable(); btn:EnableMouse(true)
        return
    end

    -- At a banker the same button restocks from the bank; the count is
    -- short items that have copies there.
    if ADDON.bankOpen and not (loop and loop:IsActive()) then
        local n = ADDON.BankRestock:PullableCount()
        btn._label:SetText(n > 0 and ("Restock from Bank (%d)"):format(n) or "Restock from Bank")
        if n > 0 then
            btn._label:SetTextColor(1, 1, 1, 1)
            btn:Enable(); btn:EnableMouse(true)
        else
            btn._label:SetTextColor(muted[1], muted[2], muted[3], 1)
            btn:Disable(); btn:EnableMouse(true)
        end
        return
    end

    if loop and loop:IsActive() then
        if btn._label then
            btn._label:SetText("Stop restock")
            btn._label:SetTextColor(1, 1, 1, 1)
        end
        btn:Enable(); btn:EnableMouse(true)
        return
    end

    -- Idle. Enable only when AH open + shortfall > 0.
    local ahOpen  = AuctionHouseFrame and AuctionHouseFrame:IsShown()
    local canStart = ahOpen and shortCount > 0
    if btn._label then
        btn._label:SetText(shortCount > 0 and ("Restock at AH (%d)"):format(shortCount) or "Restock at AH")
        if canStart then
            btn._label:SetTextColor(1, 1, 1, 1)
        else
            btn._label:SetTextColor(muted[1], muted[2], muted[3], 1)
        end
    end
    if canStart then
        btn:Enable(); btn:EnableMouse(true)
    else
        btn:Disable(); btn:EnableMouse(true)  -- keep mouse on so tooltip works when disabled
    end
end

-- Human-readable reason the disabled Restock button is disabled.
-- Returns nil when the button is enabled (nothing to explain).
function MF:_RestockDisabledReason()
    local loop = ADDON.RestockLoop
    if loop and loop:IsActive() then return nil end
    if ADDON.bankOpen then
        if ADDON.BankRestock:PullableCount() == 0 then
            return "Nothing you're short on is in your bank or warband bank."
        end
        return nil
    end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        return "Auction House isn't open."
    end
    local short = self._lastShortCount
    if short == nil then
        if ADDON.RestockLoop and ADDON.RestockLoop.PreviewShortfallCount then
            short = ADDON.RestockLoop:PreviewShortfallCount()
        else
            short = 0
        end
    end
    if short == 0 then
        return "Nothing to restock -- every row is at or above its need."
    end
    return nil
end

-- Undo the AH dock: back to the pre-dock spot (or the saved position).
-- No-op when not docked.
function MF:Undock()
    local f = self.frame
    if not (self._docked and f) then return end
    local pre = self._preDockPos
    if not (pre and pre.point) then pre = ADDON.DB.char.uiPos end
    f:ClearAllPoints()
    if pre and pre.point then
        f:SetPoint(pre.point, UIParent, pre.point, pre.x or 0, pre.y or 0)
    else
        f:SetPoint("CENTER")
    end
    self._docked = false
    self._preDockPos = nil
end

function MF:DockToAHIfOpen()
    local f, host = self.frame, _G.AuctionHouseFrame
    if not (f and host and host:IsShown()) then return end
    if self._docked then return end -- already docked, don't overwrite _preDockPos
    local point, _, _, x, y = f:GetPoint()
    self._preDockPos = { point = point, x = x, y = y }
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", host, "TOPRIGHT", 1, 0)
    self._docked = true
    if ADDON.Sidecar and ADDON.Sidecar:IsShown() then
        ADDON.Sidecar:Toggle()  -- hide
        ADDON.Sidecar:Toggle()  -- show at new anchor
    end
end

-- ---------------------------------------------------------------------------
-- Confirm flyout API (called from RestockLoop):
--   ShowArmedToast(plan, handlers)  arm with countdown; handlers onBuy/onSkip/onStop
--   ShowSummaryToast(text)          end-of-run recap
--   HideToast()
-- Buy unlocks after 1.5s (label counts whole seconds); Skip is live at once.
-- ---------------------------------------------------------------------------
local COUNTDOWN_SECONDS = 1.5
local COUNTDOWN_TICK    = 0.5

function MF:_StopToastCountdown()
    if self._toastTicker then
        self._toastTicker:Cancel()
        self._toastTicker = nil
    end
end

-- Stash warning: pulse the flyout border mint/amber every 0.5s until Buy,
-- Skip or hide, to draw the eye to the "already have some" lines.
local PULSE_MINT  = { Palette.brand[1], Palette.brand[2], Palette.brand[3], 0.85 }
local PULSE_AMBER = { 1.0, 0.66, 0.4, 0.95 }

function MF:_StartToastPulse()
    if self._toastPulseTicker then return end
    if not self._toastBorderTex then return end
    local state = false  -- false = mint (rest), true = amber (warn)
    self._toastPulseTicker = C_Timer.NewTicker(0.5, function()
        state = not state
        local c = state and PULSE_AMBER or PULSE_MINT
        for _, tex in ipairs(self._toastBorderTex) do
            tex:SetColorTexture(c[1], c[2], c[3], c[4])
        end
    end)
end

function MF:_StopToastPulse()
    if self._toastPulseTicker then
        self._toastPulseTicker:Cancel()
        self._toastPulseTicker = nil
    end
    -- Always back to mint, so the next arm doesn't inherit amber.
    if self._toastBorderTex then
        for _, tex in ipairs(self._toastBorderTex) do
            tex:SetColorTexture(PULSE_MINT[1], PULSE_MINT[2], PULSE_MINT[3], PULSE_MINT[4])
        end
    end
end

function MF:ShowArmedToast(plan, handlers)
    if not self.confirmToast then return end
    self:_StopToastCountdown()
    self:_StopToastPulse()  -- ensure any prior arm's pulse doesn't bleed in
    self._toastMode     = "armed"
    self._toastHandlers = handlers or {}
    self._toastArmReady = false

    -- Armed layout width (summary mode widens it).
    self._toastTitle:ClearAllPoints()
    self._toastTitle:SetPoint("TOPLEFT", 10, -6)
    self._toastTitle:SetPoint("RIGHT", -160, 0)

    -- One amber line per source holding copies, then start the pulse.
    local shownStashLines = 0
    if plan.hasStash then
        if (plan.stashBank or 0) > 0 then
            self._toastStashBank:ClearAllPoints()
            self._toastStashBank:SetPoint("TOPLEFT", self._toastTitle, "BOTTOMLEFT", 0, -1)
            self._toastStashBank:SetPoint("RIGHT", -160, 0)
            self._toastStashBank:SetText(("You have %d in bank (this character)"):format(plan.stashBank))
            self._toastStashBank:Show()
            shownStashLines = shownStashLines + 1
        else
            self._toastStashBank:Hide()
        end
        if (plan.stashWarband or 0) > 0 then
            self._toastStashWarband:ClearAllPoints()
            local anchor = (shownStashLines > 0) and self._toastStashBank or self._toastTitle
            self._toastStashWarband:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -1)
            self._toastStashWarband:SetPoint("RIGHT", -160, 0)
            self._toastStashWarband:SetText(("You have %d in warband bank (account-wide)"):format(plan.stashWarband))
            self._toastStashWarband:Show()
            shownStashLines = shownStashLines + 1
        else
            self._toastStashWarband:Hide()
        end
    else
        self._toastStashBank:Hide()
        self._toastStashWarband:Hide()
    end

    -- Sub line under the last visible line.
    self._toastSub:ClearAllPoints()
    local subAnchor = self._toastTitle
    if self._toastStashWarband:IsShown() then
        subAnchor = self._toastStashWarband
    elseif self._toastStashBank:IsShown() then
        subAnchor = self._toastStashBank
    end
    self._toastSub:SetPoint("TOPLEFT", subAnchor, "BOTTOMLEFT", 0, -1)
    self._toastSub:SetPoint("RIGHT", -160, 0)

    self.confirmToast:SetHeight(44 + shownStashLines * 13)

    -- Title: qty x name (22 chars max). Sub: total and cap; amber "No cap set".
    local nm = plan.name or "?"
    if #nm > 22 then nm = nm:sub(1, 21) .. "\226\128\166" end  -- ellipsis
    self._toastTitle:SetText(("%d x |cffffffff%s|r"):format(plan.planQuantity or 0, nm))

    local totalTxt = MoneyText(plan.plannedSpend or 0)
    if plan.maxPrice then
        self._toastSub:SetText(("%s  \194\183  Cap %s / unit"):format(totalTxt, MoneyText(plan.maxPrice, "silver")))
        self._toastSub:SetTextColor(0.78, 0.78, 0.78, 1)
    else
        self._toastSub:SetText(("%s  \194\183  No cap set"):format(totalTxt))
        self._toastSub:SetTextColor(1.0, 0.66, 0.4, 1)  -- amber warning
    end

    -- Skip is live.
    self._toastSkip:Enable(); self._toastSkip:EnableMouse(true)

    -- Buy starts locked, showing the countdown.
    self._toastPrimary:Disable()
    self._toastPrimaryFill:Hide()
    self._toastPrimaryTxt:SetTextColor(0.78, 0.78, 0.78, 1)

    local remaining = COUNTDOWN_SECONDS
    self._toastPrimaryTxt:SetText(("Buy (%ds)"):format(math.ceil(remaining)))

    self.confirmToast:Show()

    if plan.hasStash then
        self:_StartToastPulse()
    end

    -- Label shows whole seconds (ceil) while the ticker runs at 0.5s.
    local totalTicks = math.ceil(COUNTDOWN_SECONDS / COUNTDOWN_TICK)
    self._toastTicker = C_Timer.NewTicker(COUNTDOWN_TICK, function()
        if self._toastMode ~= "armed" then return end
        remaining = remaining - COUNTDOWN_TICK
        if remaining > 0 then
            self._toastPrimaryTxt:SetText(("Buy (%ds)"):format(math.ceil(remaining)))
        else
            -- Arm complete: enable, mint-fill on, brighten label.
            self._toastArmReady = true
            self._toastPrimaryTxt:SetText("Buy")
            self._toastPrimaryTxt:SetTextColor(0.95, 1.0, 0.95, 1)
            self._toastPrimary:Enable()
            self._toastPrimaryFill:Show()
            self:_StopToastCountdown()
        end
    end, totalTicks)
end

function MF:ShowSummaryToast(summary)
    if not self.confirmToast then return end
    self:_StopToastCountdown()
    self:_StopToastPulse()  -- summary is a stopping surface -- no pulse
    -- Hide any lingering stash lines from a previous armed state so the
    -- summary layout matches the original 44px, 2-line shape.
    if self._toastStashBank then self._toastStashBank:Hide() end
    if self._toastStashWarband then self._toastStashWarband:Hide() end
    self.confirmToast:SetHeight(44)
    self._toastMode     = "summary"
    self._toastHandlers = nil
    self._toastArmReady = false

    local title = summary.title or "Restock done"
    local sub   = summary.sub or ""
    self._toastTitle:SetText(title)
    self._toastTitle:SetTextColor(1, 1, 1, 1)
    self._toastSub:SetText(sub)
    self._toastSub:SetTextColor(0.78, 0.78, 0.78, 1)

    -- One button in summary mode: widen the text so long recaps don't wrap under it.
    self._toastTitle:ClearAllPoints()
    self._toastTitle:SetPoint("TOPLEFT", 10, -6)
    self._toastTitle:SetPoint("RIGHT", -100, 0)
    self._toastSub:ClearAllPoints()
    self._toastSub:SetPoint("TOPLEFT", self._toastTitle, "BOTTOMLEFT", 0, -1)
    self._toastSub:SetPoint("RIGHT", -100, 0)

    -- Skip hidden in summary mode; only [Close] on the primary.
    self._toastSkip:Disable(); self._toastSkip:EnableMouse(false)
    self._toastSkip:Hide()
    self._toastPrimary:Enable()
    self._toastPrimaryFill:Hide()
    self._toastPrimaryTxt:SetTextColor(1, 1, 1, 1)

    -- Auto-closes after 3s, counting down like Buy; Close works throughout.
    local SUMMARY_CLOSE_SECONDS = 3
    local remaining = SUMMARY_CLOSE_SECONDS
    self._toastPrimaryTxt:SetText(("Close (%ds)"):format(remaining))

    self.confirmToast:Show()

    -- Ticker updates label + auto-hides at zero. Cancel any prior timer
    -- so a rapid stop/complete sequence doesn't stack two auto-hides.
    if self._summaryAutoHide then
        self._summaryAutoHide:Cancel(); self._summaryAutoHide = nil
    end
    self._summaryAutoHide = C_Timer.NewTicker(1.0, function()
        if self._toastMode ~= "summary" then return end
        remaining = remaining - 1
        if remaining > 0 then
            self._toastPrimaryTxt:SetText(("Close (%ds)"):format(remaining))
        else
            self:HideToast()
        end
    end, SUMMARY_CLOSE_SECONDS)
end

function MF:HideToast()
    self:_StopToastCountdown()
    self:_StopToastPulse()
    if self._summaryAutoHide then
        self._summaryAutoHide:Cancel(); self._summaryAutoHide = nil
    end
    self._toastMode     = nil
    self._toastHandlers = nil
    self._toastArmReady = false
    if self._toastSkip then self._toastSkip:Show() end
    if self._toastStashBank then self._toastStashBank:Hide() end
    if self._toastStashWarband then self._toastStashWarband:Hide() end
    if self.confirmToast then self.confirmToast:Hide() end
end

-- Footer text (feedback: stays until the next action). Also logged as a
-- detail entry unless skipLog; empty text clears the footer only.
function MF:SetStatus(text, skipLog)
    if self.statusBar then self.statusBar:SetText(text or "") end
    if not skipLog and text and text ~= "" and ADDON.Log and ADDON.Log.Emit then
        ADDON.Log:Emit("status", nil, { text = text })
    end
end

-- ---------------------------------------------------------------------------
-- Reorder (mouse only): drag a row's grip. List order = restock order.
-- ---------------------------------------------------------------------------

-- Drag: a mint insertion line follows the cursor to the nearest gap between
-- visible rows; drop reorders via DB:ReorderItems. Above/below the rows
-- means top/bottom.

local function EnsureInsertionMarker(self)
    if self._dragMarker then return self._dragMarker end
    local m = self.scrollBox:CreateTexture(nil, "OVERLAY", nil, 7)
    m:SetColorTexture(Palette.brand[1], Palette.brand[2], Palette.brand[3], 1)
    m:SetHeight(2)
    m:Hide()
    self._dragMarker = m
    return m
end

-- Gap nearest cursorY by row midpoints: 1 = before the first row,
-- size+1 = after the last.
function MF:_ResolveDropIndex(cursorY)
    if not self.scrollBox or not self.dataProvider then return 1 end
    local size = self.dataProvider:GetSize()
    if size == 0 then return 1 end

    -- Collect visible rows sorted by data index.
    local visible = {}
    for _, r in self.scrollBox:EnumerateFrames() do
        if r._itemID then
            -- Look up data index by itemID.
            for i = 1, size do
                local d = self.dataProvider:Find(i)
                if d and d.itemID == r._itemID then
                    visible[#visible + 1] = { idx = i, frame = r, top = r:GetTop(), bottom = r:GetBottom() }
                    break
                end
            end
        end
    end
    if #visible == 0 then return 1 end
    table.sort(visible, function(a, b) return a.idx < b.idx end)

    -- Above the topmost visible row's top edge -> insert before first
    -- visible row.
    if cursorY >= visible[1].top then return visible[1].idx end
    -- Below the bottom row's bottom edge -> insert after last visible.
    if cursorY <= visible[#visible].bottom then return visible[#visible].idx + 1 end

    for _, v in ipairs(visible) do
        local mid = (v.top + v.bottom) / 2
        if cursorY >= mid then
            return v.idx           -- upper half: insert BEFORE this row
        end
    end
    return visible[#visible].idx + 1
end

function MF:_PlaceInsertionMarker(targetIndex)
    if not self._dragMarker or not self.scrollBox or not self.dataProvider then return end
    local size = self.dataProvider:GetSize()
    local m = self._dragMarker
    m:ClearAllPoints()
    if targetIndex > size then
        -- After the last visible row.
        local last
        for _, r in self.scrollBox:EnumerateFrames() do
            if r._itemID and (not last or r:GetBottom() < last:GetBottom()) then
                last = r
            end
        end
        if last then
            m:SetPoint("TOPLEFT",  last, "BOTTOMLEFT",  0, 1)
            m:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, 1)
            m:Show()
        end
        return
    end
    -- Insert before row at targetIndex.
    for _, r in self.scrollBox:EnumerateFrames() do
        if r._itemID then
            local d = self.dataProvider:Find(targetIndex)
            if d and r._itemID == d.itemID then
                m:SetPoint("BOTTOMLEFT",  r, "TOPLEFT",  0, -1)
                m:SetPoint("BOTTOMRIGHT", r, "TOPRIGHT", 0, -1)
                m:Show()
                return
            end
        end
    end
end

function MF:BeginRowDrag(row)
    if not row or not row._itemID or self._dragItemID then return end
    self._dragItemID = row._itemID
    EnsureInsertionMarker(self)
    -- Cursor comes in native pixels; divide by UIParent's scale.
    self._dragTicker = C_Timer.NewTicker(0, function()
        if not self._dragItemID then return end
        local scale = UIParent:GetEffectiveScale()
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / scale
        local idx = self:_ResolveDropIndex(cursorY)
        self._dropIndex = idx
        self:_PlaceInsertionMarker(idx)
    end)
end

function MF:EndRowDrag()
    if not self._dragItemID then return end
    local movedID = self._dragItemID
    local target  = self._dropIndex
    if self._dragTicker then self._dragTicker:Cancel(); self._dragTicker = nil end
    self._dragItemID = nil
    self._dropIndex  = nil
    if self._dragMarker then self._dragMarker:Hide() end

    if not target or not self.dataProvider or not ADDON.DB or not ADDON.DB.ReorderItems then
        return
    end

    -- Remove, then reinsert at target (one lower if the item moved down,
    -- since removing it shifted the rest up).
    local size = self.dataProvider:GetSize()
    local order = {}
    local fromIdx
    for i = 1, size do
        local d = self.dataProvider:Find(i)
        if d then
            if d.itemID == movedID then
                fromIdx = i
            else
                order[#order + 1] = d.itemID
            end
        end
    end
    if not fromIdx or fromIdx == target then return end
    local insertAt = (target > fromIdx) and (target - 1) or target
    table.insert(order, math.min(#order + 1, math.max(1, insertAt)), movedID)
    ADDON.DB:ReorderItems(order)
    self:Refresh()
end

-- ---------------------------------------------------------------------------
-- Show / Hide
-- ---------------------------------------------------------------------------
-- fromAH only when the caller knows; a plain Show() must not clear the flag
-- Core just set.
function MF:Show(fromAH)
    self:Build()
    if fromAH ~= nil then
        self.openedByAH = fromAH and true or false
        -- An explicit manual open (Toggle passes false) means the user now
        -- owns the window: closing the bank mustn't close it either.
        if not fromAH then self.openedByBank = false end
    end
    self.frame:Show()
    self:Refresh()
    -- Already at the AH (auto-open off, then /clerk): dock from here.
    self:DockToAHIfOpen()
end

function MF:Hide()
    -- Side panel cleanup lives in the frame's OnHide, shared by every close path.
    if self.frame then self.frame:Hide() end
end

function MF:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show(false)
    end
end
