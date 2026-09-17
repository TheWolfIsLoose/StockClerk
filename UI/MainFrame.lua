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
local ROW_HEIGHT = 30

-- ---------------------------------------------------------------------------
-- Palette — ported from atrocityEssentials' ThemeDefaults (near-black,
-- flat, ElvUI-family). One rule: the WINDOW paints one fill; nested regions
-- get separated only by 1px pure-black borders, not by additional shades.
-- Accent = SharedMedia_Tones organic mint green #98FF98, kept everywhere the addon used to paint
-- gold (title, focus borders, section labels).
-- ---------------------------------------------------------------------------
local Palette = {
    -- Backgrounds. Three overlapping opacity tiers, each with a clear role:
    --   bgDark    = the window itself. Bumped from 0.94 -> 0.97 so world
    --              art doesn't bleed through the addon body.
    --   bandTint  = section "banding" — a very thin translucent overlay used
    --              on the toolbar, header row, and footer. Reads instantly
    --              as "this is a distinct band" without needing per-section
    --              borders. Same trick atrocityEssentials uses on its own
    --              Display Settings / Position / Font Settings headers.
    --   fieldFill = editable well fill. Toolbar edit boxes, price/need cells
    --              at rest — gives interactive spots a persistent "sunken"
    --              tone so a scanning eye can find them without hovering.
    --   btnRest   = button-at-rest fill so Add / Restock / Close read as
    --              buttons even before hover. Hover still brightens on top.
    bgDark        = { 0.031, 0.031, 0.031, 0.97 }, -- window fill (was 0.94)
    bgLight       = { 0.055, 0.055, 0.055, 0.85 }, -- (unused legacy)
    bgMedium      = { 0.055, 0.055, 0.055, 0.95 }, -- (legacy — kept for compat)
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
    brandDim      = { 0.451, 0.506, 1.000, 0.55 },
    -- Text
    textPrimary   = { 1.00, 1.00, 1.00, 1.00 },
    textSecondary = { 0.78, 0.78, 0.78, 1.00 },
    textMuted     = { 0.50, 0.50, 0.50, 1.00 },
    -- Semantic (kept for status pill / shortfall; muted so they don't
    -- outshine the brand mint)
    ok            = { 0.30, 0.80, 0.40, 1.00 },
    short         = { 0.90, 0.30, 0.30, 1.00 },
}

local BORDER_SIZE = 1
local ANIM_DUR    = 0.15

local WHITE_TEX = "Interface\\Buttons\\WHITE8x8"
local TRASH_TEX = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"   -- red X, native asset
local QUESTION_ICON = 134400

-- ---------------------------------------------------------------------------
-- Helpers (atrocity-style theming primitives)
-- ---------------------------------------------------------------------------

-- PixelSnap: turn off texel snapping / bias so 1px borders don't smear across
-- two physical pixel rows when the UI scale is off-grid. Verbatim from atrocity's
-- AE:PixelSnapRegions (Core/AddonTheme.lua). Every border texture goes through
-- this or you get the classic "1px line looks 2px thick and blurry" bug.
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
        frame._bg:SetTexture(WHITE_TEX)
        PixelSnap(frame._bg)
    end
    frame._bg:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    frame._bg:Show()
end

-- Band overlay: a translucent tint layered ON TOP of the window fill so a
-- section reads as a distinct band without needing its own opaque color or
-- an extra border. Draws on BACKGROUND sublevel -6 (above ApplyFill's -8 but
-- still behind content). Used for toolbar / header row / footer.
local function ApplyBand(frame, color)
    if not frame._band then
        frame._band = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        frame._band:SetAllPoints(true)
        frame._band:SetTexture(WHITE_TEX)
        PixelSnap(frame._band)
    end
    frame._band:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    frame._band:Show()
end

-- BlackBorder: 1px pure-black frame around any region, on the OVERLAY layer
-- of a dedicated child frame so nothing else can paint over it. Atrocity uses
-- a whole tooltip-strata border frame for the window; for interior widgets a
-- 4-texture ring on the widget itself is enough.
-- Returns { top, bottom, left, right } for later recolor (focus animation).
local function AddBlackBorder(frame, color)
    color = color or Palette.border
    local textures = {}
    for _, side in ipairs({"top", "bottom", "left", "right"}) do
        local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(WHITE_TEX)
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

-- SetBorderColor: recolor an existing 4-texture border.
local function SetBorderColor(frame, r, g, b, a)
    if not frame._border then return end
    a = a or 1
    for _, t in pairs(frame._border) do
        t:SetColorTexture(r, g, b, a)
    end
end

-- Animated border color: smoothly transition a widget's border between
-- the resting color (black) and a target (brand mint on hover/focus).
-- Atrocity's EditBox uses the same pattern (AnimateEditBoxBorder).
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

-- HoverWash: the atrocity signature interaction — a grey #D9D9D9 @ 0.15
-- rectangle on ARTWORK sublevel 7 (NOT the HIGHLIGHT layer; HIGHLIGHT would
-- draw over OVERLAY font strings and wash the label out). Hooked (not Set)
-- so existing OnEnter/OnLeave handlers survive.
local function AddHoverWash(btn, insetX, insetY)
    if btn._hoverWash then return btn._hoverWash end
    insetX = insetX or 1
    insetY = insetY or 1
    local wash = btn:CreateTexture(nil, "ARTWORK", nil, 7)
    wash:SetTexture(WHITE_TEX)
    wash:SetColorTexture(Palette.hoverWash[1], Palette.hoverWash[2], Palette.hoverWash[3], Palette.hoverWash[4])
    wash:SetPoint("TOPLEFT", insetX, -insetY)
    wash:SetPoint("BOTTOMRIGHT", -insetX, insetY)
    wash:Hide()
    btn:HookScript("OnEnter", function() if not btn._selected then wash:Show() end end)
    btn:HookScript("OnLeave", function() wash:Hide() end)
    btn._hoverWash = wash
    return wash
end

-- StyleButton: turn a plain Button into an atrocity-flat button.
-- Two-layer fill so buttons read as filled even against the near-black window:
--   ApplyFill  -> opaque bgMedium base (BACKGROUND -8)
--   ApplyBand  -> Palette.btnRest light tint (BACKGROUND -6)
-- Press feedback swaps the band layer to a brighter/wash tint; hover wash
-- adds a further overlay on ARTWORK. Border is a 1px black ring on top.
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
        btn:SetNormalFontObject("GameFontNormal")
        btn:SetHighlightFontObject("GameFontHighlight")
        btn:SetDisabledFontObject("GameFontDisable")
    end
end

-- StyleEditBox: for a plain WoW EditBox that already lives inside a
-- container Frame (the container gets the border + fill; the EditBox stays
-- transparent). Wires up brand-mint border animation on hover/focus.
local function StyleEditBoxContainer(container, editBox)
    -- Deeper well fill (Palette.fieldFill = near-black @ 55%) so the box
    -- reads as an interactive sunken input even when it sits on top of a
    -- toolbar band that itself is slightly brighter than the window body.
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
    end
end

-- Row hover wash: on-demand rectangle we manage without wash-registration
-- (we're driving it from RowEnter/RowLeave directly so it works even though
-- the row uses non-HookScript SetScript handlers).
local function ApplyRowHover(frame, on)
    if not frame._rowHover then
        local wash = frame:CreateTexture(nil, "ARTWORK", nil, 7)
        wash:SetTexture(WHITE_TEX)
        wash:SetColorTexture(Palette.hoverWash[1], Palette.hoverWash[2], Palette.hoverWash[3], Palette.hoverWash[4])
        wash:SetPoint("TOPLEFT", 1, -1)
        wash:SetPoint("BOTTOMRIGHT", -1, 1)
        wash:Hide()
        frame._rowHover = wash
    end
    if on then frame._rowHover:Show() else frame._rowHover:Hide() end
end

local function ShowItemTooltip(anchor, itemID)
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)

    -- Append our own storage breakdown so the user sees where the item
    -- lives across bags / bank / reagent / warband. Only lines with a
    -- non-zero count are shown, so a common-case tooltip only picks up
    -- one extra line at most.
    if ADDON.Inventory and ADDON.Inventory.GetBreakdown then
        local bd = ADDON.Inventory:GetBreakdown(itemID)
        if bd.total > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffffd200Stock Clerk|r", 1, 1, 1)
            if bd.bags    > 0 then GameTooltip:AddDoubleLine("  Bags",         tostring(bd.bags),    0.8, 0.8, 0.8, 1, 1, 1) end
            if bd.bank    > 0 then GameTooltip:AddDoubleLine("  Personal bank",tostring(bd.bank),    0.8, 0.8, 0.8, 1, 1, 1) end
            if bd.reagent > 0 then GameTooltip:AddDoubleLine("  Reagent bank", tostring(bd.reagent), 0.8, 0.8, 0.8, 1, 1, 1) end
            if bd.warband > 0 then GameTooltip:AddDoubleLine("  Warband bank", tostring(bd.warband), 0.8, 0.8, 0.8, 1, 1, 1) end
            GameTooltip:AddDoubleLine("  Total", tostring(bd.total), 1, 0.82, 0, 1, 0.82, 0)
        end
    end

    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Row template setup
--
-- Each row is a Button (so we get OnClick / OnEnter / OnLeave for free).
-- We build the child widgets once inside :Init() and reuse them as the
-- ScrollView recycles the frame across scrolls / refreshes.
-- ---------------------------------------------------------------------------
local function BuildRow(row)
    row:SetHeight(ROW_HEIGHT)

    -- Row hover wash is created lazily by ApplyRowHover on first RowEnter.

    -- Icon
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim default 5% border

    -- Name (fills leftmost region up to the Have column). The right edge
    -- stops at -330 to leave room for four right-aligned columns (Have,
    -- Need, Price Cap, Status) plus trash, with each column properly
    -- centered under its header.
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -330, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Have column: pure display of the bags-only count, with a dim
    -- (+N bank/warband/reagent) suffix if the stash is non-empty. No
    -- cell chrome and no click affordance — this value only comes from
    -- inventory, the user never edits it here. Right-edge-aligned at -270
    -- so the number tucks flush against the Need cell's left edge.
    row.have = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.have:SetPoint("RIGHT", row, "RIGHT", -270, 0)
    row.have:SetJustifyH("RIGHT")

    -- Need column: dedicated editable cell for the target count. Styled
    -- exactly like the Price Cap cell — transparent at rest, dark fill +
    -- brand border fade in on hover, click opens an inline editor in place.
    row.needCell = CreateFrame("Button", nil, row)
    row.needCell:SetSize(56, 20)
    row.needCell:SetPoint("RIGHT", row, "RIGHT", -200, 0)
    row.needCell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.needCell:SetFrameLevel(row:GetFrameLevel() + 2)

    -- Faint at-rest fill (was alpha 0). Reads as a clickable well without
    -- being loud — a scanning eye picks out "editable" cells at a glance.
    -- Hover ramps to full opacity via NEED_FILL_HOVER.
    local NEED_FILL_IDLE   = { 0, 0, 0, 0.35 }
    local NEED_FILL_HOVER  = { Palette.bgMedium[1], Palette.bgMedium[2], Palette.bgMedium[3], 1 }
    local NEED_BORDER_IDLE = { Palette.brand[1], Palette.brand[2], Palette.brand[3], 0 }
    ApplyFill(row.needCell, NEED_FILL_IDLE)
    AddBlackBorder(row.needCell, NEED_BORDER_IDLE)
    AttachBorderAnimator(row.needCell)
    row.needCell._fillIdle   = NEED_FILL_IDLE
    row.needCell._fillHover  = NEED_FILL_HOVER
    row.needCell._borderIdle = NEED_BORDER_IDLE

    -- FontString is parented to the CELL (not the row) so it inherits the
    -- cell's higher FrameLevel and draws ABOVE the cell's fill texture,
    -- rather than underneath it. Fixes QA-6: at idle the cell fill is
    -- alpha 0.35 (value shows through by luck), but on hover the fill
    -- goes to full opacity and previously eclipsed the value entirely.
    row.need = row.needCell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.need:SetPoint("CENTER", row.needCell, "CENTER")
    row.need:SetJustifyH("CENTER")

    -- Price Cap column: dedicated cell for the max price / unit. Click to
    -- edit. Always visible so the user can see (and change) the cap without
    -- hunting for it inside the count string. Wider than the Need cell (72
    -- vs 56) to comfortably hold 4-digit gold values like "9999g".
    row.capCell = CreateFrame("Button", nil, row)
    row.capCell:SetSize(72, 20)
    row.capCell:SetPoint("RIGHT", row, "RIGHT", -110, 0)
    row.capCell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.capCell:SetFrameLevel(row:GetFrameLevel() + 2)

    -- Cap cell: no idle fill or border — the value sits directly on the
    -- window background (same visual weight as the Have column). On hover
    -- the border grows in as brand mint and a subtle dark fill appears,
    -- so the affordance ("this opens something") stays discoverable. All
    -- colours start at alpha 0 and animate up.
    -- Same faint at-rest fill as the Need cell (see NEED_FILL_IDLE comment).
    local CAP_FILL_IDLE = { 0, 0, 0, 0.35 }
    local CAP_FILL_HOVER = { Palette.bgMedium[1], Palette.bgMedium[2], Palette.bgMedium[3], 1 }
    local CAP_BORDER_IDLE = { Palette.brand[1], Palette.brand[2], Palette.brand[3], 0 }
    ApplyFill(row.capCell, CAP_FILL_IDLE)
    AddBlackBorder(row.capCell, CAP_BORDER_IDLE)
    AttachBorderAnimator(row.capCell)
    row.capCell._fillIdle   = CAP_FILL_IDLE
    row.capCell._fillHover  = CAP_FILL_HOVER
    row.capCell._borderIdle = CAP_BORDER_IDLE

    -- See row.need above: parented to the cell so it draws over the fill.
    row.cap = row.capCell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.cap:SetPoint("CENTER", row.capCell, "CENTER")
    row.cap:SetJustifyH("CENTER")

    -- Inline Need editor (hidden until needCell is clicked). Anchored to
    -- the needCell so it lands exactly where the value was. The needCell
    -- carries the border animation; the editor just needs a slightly
    -- darker fill so the caret has enough contrast.
    row.needEditBg = row:CreateTexture(nil, "BACKGROUND")
    row.needEditBg:SetTexture(WHITE_TEX)
    row.needEditBg:SetVertexColor(Palette.bgDark[1], Palette.bgDark[2], Palette.bgDark[3], 1)
    row.needEditBg:Hide()

    row.needEdit = CreateFrame("EditBox", nil, row)
    row.needEdit:SetFontObject("GameFontHighlight")
    row.needEdit:SetAutoFocus(false)
    row.needEdit:SetNumeric(true)
    row.needEdit:SetMaxLetters(5)
    row.needEdit:SetJustifyH("CENTER")
    row.needEdit:SetSize(56, 20)
    row.needEdit:SetPoint("CENTER", row.needCell, "CENTER")
    row.needEditBg:SetPoint("TOPLEFT",     row.needEdit, "TOPLEFT",     -4, 2)
    row.needEditBg:SetPoint("BOTTOMRIGHT", row.needEdit, "BOTTOMRIGHT",  4, -2)
    row.needEdit:SetFrameLevel(row.needCell:GetFrameLevel() + 1)
    row.needEdit:Hide()

    -- Price cap inline editor (hidden until the cap cell is clicked).
    -- Anchored TO the cap cell so it lands exactly where the value was.
    -- The cap cell already carries the flat black border and brand-mint
    -- focus animation — the editor just needs a slightly darker fill so
    -- the caret has enough contrast.
    row.priceEditBg = row:CreateTexture(nil, "BACKGROUND")
    row.priceEditBg:SetTexture(WHITE_TEX)
    row.priceEditBg:SetVertexColor(Palette.bgDark[1], Palette.bgDark[2], Palette.bgDark[3], 1)
    row.priceEditBg:Hide()

    row.priceEdit = CreateFrame("EditBox", nil, row)
    row.priceEdit:SetFontObject("GameFontHighlight")
    row.priceEdit:SetAutoFocus(false)
    row.priceEdit:SetNumeric(true)
    row.priceEdit:SetMaxLetters(7)
    row.priceEdit:SetJustifyH("CENTER")
    row.priceEdit:SetSize(72, 20)
    row.priceEdit:SetPoint("CENTER", row.capCell, "CENTER")
    row.priceEditBg:SetPoint("TOPLEFT",     row.priceEdit, "TOPLEFT",     -4, 2)
    row.priceEditBg:SetPoint("BOTTOMRIGHT", row.priceEdit, "BOTTOMRIGHT",  4, -2)
    row.priceEdit:SetFrameLevel(row.capCell:GetFrameLevel() + 1)
    row.priceEdit:Hide()

    -- Status pill (ok / -N) - Status column.
    -- Flat, 1px black border, subtle fill. The COLORED TEXT (green ok /
    -- red -N) carries the semantic; the pill itself stays neutral so the
    -- overall aesthetic reads as one palette instead of a traffic-light
    -- panel.
    row.pill = CreateFrame("Frame", nil, row)
    row.pill:SetSize(52, 20)
    row.pill:SetPoint("RIGHT", row, "RIGHT", -36, 0)
    ApplyFill(row.pill, Palette.bgMedium)
    AddBlackBorder(row.pill)
    row.pill.text = row.pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.pill.text:SetPoint("CENTER")

    -- Trash button (visible on hover only).
    --
    -- Tooltip / trash-visibility model:
    --   * Both `row:OnEnter/OnLeave` and `trash:OnEnter/OnLeave` route
    --     to shared helpers (RowEnter / RowLeave). Whichever the mouse is
    --     over, the row is "hovered" and the trash + tooltip are up.
    --   * On leave, we defer one frame and check both frames' IsMouseOver.
    --     If neither is hovered, we tear the tooltip down. This survives
    --     slow exits through the GameTooltip frame (which is NOT part of
    --     the row's mouse-over region), which previously caused a stuck
    --     tooltip because trash:OnEnter had re-shown it with no matching
    --     hide path.
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
        if r._itemID then ShowItemTooltip(r, r._itemID) end
        r.trash:Show()
    end

    local function RowLeave(r)
        -- Defer one frame so IsMouseOver reflects the settled state after
        -- WoW has processed all pending Enter/Leave dispatches. Then hide
        -- iff the pointer is truly off both the row and the trash button.
        C_Timer.After(0, function()
            if r:IsMouseOver() or r.trash:IsMouseOver() then
                return -- still hovering some part of the row cluster
            end
            ApplyRowHover(r, false)
            GameTooltip:Hide()
            r.trash:Hide()
        end)
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
            ADDON.AH:SearchItem(id, function(ok, results)
                if not ok then
                    MF:SetStatus("|cffff8888AH search failed: " .. tostring(results) .. "|r")
                    return
                end
                local cheapest = results[1] and results[1].unitPrice
                if cheapest then
                    MF:SetStatus(("Cheapest: %s / unit (%d listings)"):format(
                        GetCoinTextureString(cheapest), #results))
                else
                    MF:SetStatus("No auctions found")
                end
            end)
        end
    end)
    row:RegisterForClicks("LeftButtonUp")

    -- Cap cell hover + click: opens the inline price editor.
    local function OpenPriceEdit(r)
        local currentG = r._maxPrice and math.floor(r._maxPrice / 10000) or nil
        r.priceEdit:SetText(currentG and tostring(currentG) or "")
        r.cap:Hide()
        r.priceEdit:Show()
        r.priceEditBg:Show()
        r.priceEdit:SetFocus()
        r.priceEdit:HighlightText()
        r.capCell._priceEditActive = true
        r.capCell._borderAnim.AnimateTo(Palette.brand)
        if r.capCell._bg then r.capCell._bg:SetVertexColor(unpack(r.capCell._fillHover)) end
    end
    row.capCell:SetScript("OnClick", function(self)
        OpenPriceEdit(self:GetParent())
    end)
    row.capCell:SetScript("OnEnter", function(self)
        local r = self:GetParent()
        -- Delegate to row hover so tooltip + trash + wash all appear.
        r:GetScript("OnEnter")(r)
        -- Border animates to brand mint — the "this opens something" signal.
        self._borderAnim.AnimateTo(Palette.brand)
        if self._bg then self._bg:SetVertexColor(unpack(self._fillHover)) end
        GameTooltip:Hide()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if r._maxPrice then
            GameTooltip:SetText(("Max %dg / unit"):format(math.floor(r._maxPrice / 10000)), 1, 1, 1)
            GameTooltip:AddLine("Click to change  \194\183  blank = no cap", 0.7, 0.7, 0.7)
        else
            GameTooltip:SetText("No price cap set", 1, 1, 1)
            GameTooltip:AddLine("Click to set a max gold/unit", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    row.capCell:SetScript("OnLeave", function(self)
        if not self._priceEditActive then
            self._borderAnim.AnimateTo(self._borderIdle)
            if self._bg then self._bg:SetVertexColor(unpack(self._fillIdle)) end
        end
        self:GetParent():GetScript("OnLeave")(self:GetParent())
    end)

    -- Need cell hover + click: opens the inline target editor. Mirrors the
    -- capCell wiring exactly so both editable cells behave identically.
    local function OpenNeedEdit(r)
        r.needEdit:SetText(tostring(r._need or 20))
        r.need:Hide()
        r.needEdit:Show()
        r.needEditBg:Show()
        r.needEdit:SetFocus()
        r.needEdit:HighlightText()
        r.needCell._needEditActive = true
        r.needCell._borderAnim.AnimateTo(Palette.brand)
        if r.needCell._bg then r.needCell._bg:SetVertexColor(unpack(r.needCell._fillHover)) end
    end
    row.needCell:SetScript("OnClick", function(self)
        OpenNeedEdit(self:GetParent())
    end)
    row.needCell:SetScript("OnEnter", function(self)
        local r = self:GetParent()
        r:GetScript("OnEnter")(r)
        self._borderAnim.AnimateTo(Palette.brand)
        if self._bg then self._bg:SetVertexColor(unpack(self._fillHover)) end
        GameTooltip:Hide()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(("Target: %d"):format(r._need or 20), 1, 1, 1)
        GameTooltip:AddLine("Click to change", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    row.needCell:SetScript("OnLeave", function(self)
        if not self._needEditActive then
            self._borderAnim.AnimateTo(self._borderIdle)
            if self._bg then self._bg:SetVertexColor(unpack(self._fillIdle)) end
        end
        self:GetParent():GetScript("OnLeave")(self:GetParent())
    end)

    local function CloseNeedEdit(r)
        r.needEdit:ClearFocus()
        r.needEdit:Hide()
        r.needEditBg:Hide()
        r.need:Show()
        r.needCell._needEditActive = false
        if not r.needCell:IsMouseOver() then
            r.needCell._borderAnim.AnimateTo(r.needCell._borderIdle)
            if r.needCell._bg then r.needCell._bg:SetVertexColor(unpack(r.needCell._fillIdle)) end
        end
    end
    -- Commit Need edit: reads the current text, writes to DB if valid,
    -- and refreshes the list ONLY if the value actually changed. Skipping
    -- the refresh in the no-op case is important: a Tab from need -> cap
    -- (or need -> next row) triggers this commit via OnEditFocusLost, and
    -- an unnecessary MF:Refresh() rebuilds the DataProvider between the
    -- Tab keystroke and the deferred FocusRowCell open, which leaves the
    -- ScrollView without spawned rows for FindFrame() to return -- so the
    -- next cell silently no-ops. Guarding on 'value changed' keeps the
    -- happy Tab path clean.
    local function CommitNeedEdit(r)
        local newNeed = tonumber(r.needEdit:GetText())
        local changed = false
        if newNeed and newNeed > 0 and r._itemID and newNeed ~= r._need then
            ADDON.DB:SetItem(r._itemID, newNeed)
            r._need = newNeed
            -- Update the inline fontstring immediately so the user sees
            -- the new value even though we skip the full Refresh.
            if r.need then r.need:SetText(tostring(newNeed)) end
            changed = true
        end
        CloseNeedEdit(r)
        if changed then MF:Refresh() end
    end
    row.needEdit:SetScript("OnEscapePressed", function(self)
        -- Escape = cancel: set the abort flag BEFORE clearing focus so the
        -- OnEditFocusLost handler (which fires on ClearFocus) knows to
        -- close-without-committing instead of doing a blur-commit.
        self._escaping = true
        CloseNeedEdit(self:GetParent())
        self._escaping = false
    end)
    row.needEdit:SetScript("OnEnterPressed", function(self)
        CommitNeedEdit(self:GetParent())
    end)
    -- QA-8: commit on blur. If the user tabs away or clicks elsewhere
    -- (anywhere that steals focus), treat that as a commit rather than
    -- silently discarding the typed value. Escape still cancels via the
    -- _escaping flag set above.
    row.needEdit:SetScript("OnEditFocusLost", function(self)
        if self._escaping then return end
        local r = self:GetParent()
        if r.needEdit:IsShown() then CommitNeedEdit(r) end
    end)
    -- QA-7: Tab advances to this row's Price Cap; Shift+Tab moves back
    -- to the toolbar's Price Cap field (previous cell in row-major order).
    -- OnEditFocusLost above will commit the pending value before the
    -- next target's SetFocus fires.
    row.needEdit:SetScript("OnTabPressed", function(self)
        local r = self:GetParent()
        if IsShiftKeyDown() then
            MF:TabFromCell(r, "need", -1)
        else
            MF:TabFromCell(r, "need", 1)
        end
    end)

    -- Price editor: Escape aborts; Enter, Tab, or blur commit
    -- (blank = clear cap).
    local function ClosePriceEdit(r)
        r.priceEdit:ClearFocus()
        r.priceEdit:Hide()
        r.priceEditBg:Hide()
        r.cap:Show()
        r.capCell._priceEditActive = false
        if not r.capCell:IsMouseOver() then
            r.capCell._borderAnim.AnimateTo(r.capCell._borderIdle)
            if r.capCell._bg then r.capCell._bg:SetVertexColor(unpack(r.capCell._fillIdle)) end
        end
    end
    -- Same 'skip refresh in no-op case' guard as CommitNeedEdit -- see
    -- comment there for why this matters for Tab traversal.
    local function CommitPriceEdit(r)
        local changed = false
        if r._itemID then
            local raw = r.priceEdit:GetText()
            local priceGold = tonumber(raw)
            local maxPriceCopper = (priceGold and priceGold > 0) and (priceGold * 10000) or nil
            if maxPriceCopper ~= r._maxPrice then
                ADDON.DB:SetItemMaxPrice(r._itemID, maxPriceCopper)
                r._maxPrice = maxPriceCopper
                local name = r.name:GetText() or ("item:" .. r._itemID)
                if maxPriceCopper then
                    MF:SetStatus(("Cap for %s set to %dg"):format(name, priceGold))
                else
                    MF:SetStatus(("Cap cleared for %s"):format(name))
                end
                -- Update the inline fontstring so the change is visible
                -- without a full Refresh.
                if r.cap then
                    r.cap:SetText(maxPriceCopper and ("%dg"):format(priceGold) or "")
                end
                changed = true
            end
        end
        ClosePriceEdit(r)
        if changed then MF:Refresh() end
    end
    row.priceEdit:SetScript("OnEscapePressed", function(self)
        self._escaping = true
        ClosePriceEdit(self:GetParent())
        self._escaping = false
    end)
    row.priceEdit:SetScript("OnEnterPressed", function(self)
        CommitPriceEdit(self:GetParent())
    end)
    -- QA-8: commit on blur (see row.needEdit's OnEditFocusLost).
    row.priceEdit:SetScript("OnEditFocusLost", function(self)
        if self._escaping then return end
        local r = self:GetParent()
        if r.priceEdit:IsShown() then CommitPriceEdit(r) end
    end)
    row.priceEdit:SetScript("OnTabPressed", function(self)
        local r = self:GetParent()
        if IsShiftKeyDown() then
            MF:TabFromCell(r, "price", -1)
        else
            MF:TabFromCell(r, "price", 1)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Row initializer (called by ScrollView for each visible row)
-- ---------------------------------------------------------------------------
local function InitializeRow(row, data)
    if not row._built then
        BuildRow(row)
        row._built = true
    end

    row._itemID   = data.itemID
    row._need     = data.need
    row._maxPrice = data.maxPrice

    local name, link, quality, _, _, _, _, _, _, tex = C_Item.GetItemInfo(data.itemID)
    local icon = tex or select(5, C_Item.GetItemInfoInstant(data.itemID)) or QUESTION_ICON
    row.icon:SetTexture(icon)
    row._itemLink = link
    if link then
        row.name:SetText(link)
    else
        -- Async resolve for cold items; fall back to stored name.
        row.name:SetText(data.name or ("item:" .. data.itemID))
        ADDON.ItemResolver:Resolve(data.itemID, function(id, nm, ln)
            if row._itemID == id and ln then
                row.name:SetText(ln)
                row._itemLink = ln
            end
        end)
    end

    -- The row's main count is BAGS ONLY — what the character can actually
    -- use right now. Non-bag storage (bank/reagent/warband) is folded into
    -- a dim `(+N elsewhere)` annotation appended to the count line so the
    -- user always sees where the rest of their stockpile lives without
    -- the primary metric being invariant to bag<->bank moves.
    local bd     = ADDON.Inventory:GetBreakdown(data.itemID)
    local have   = bd.bags
    local stashed = bd.bank + bd.reagent + bd.warband

    row._have      = have
    row._breakdown = bd

    -- Have column: bags-only count (white) with optional dim suffix that
    -- names where any stashed copies live. Bags stays the primary metric;
    -- the suffix is context, not a total.
    local haveText = tostring(have)
    if stashed > 0 then
        local parts = {}
        if bd.bank    > 0 then parts[#parts+1] = bd.bank    .. " bank"    end
        if bd.reagent > 0 then parts[#parts+1] = bd.reagent .. " reagent" end
        if bd.warband > 0 then parts[#parts+1] = bd.warband .. " warband" end
        haveText = haveText .. ("  |cff888888(+%d: %s)|r"):format(stashed, table.concat(parts, ", "))
    end
    row.have:SetText(haveText)

    -- Need column: the plain target number (secondary text tint so it
    -- doesn't compete with the mint cap value or the semantic status pill).
    row.need:SetText(("|cffCCCCCC%d|r"):format(data.need))

    -- Cap column value. Dim '--' when no cap; brand-mint when set. The
    -- number is the emphasized element in the row (per atrocity's rule:
    -- accent color goes on the value, not on the chrome).
    if data.maxPrice then
        -- Use a lighter tint of the brand hue for the value itself — pure
        -- Brand mint #98FF98 on near-black reads cleanly at small sizes
        -- (same tone the addon uses in tooltip headers and status text).
        row.cap:SetText(("|cff98FF98%dg|r"):format(math.floor(data.maxPrice / 10000)))
    else
        row.cap:SetText("|cff555555\226\128\148|r") -- em-dash for a real "unset" glyph
    end

    if ADDON.debug then
        print(("|cff98FF98[SC:debug]|r InitializeRow: id=%d bags=%d stashed=%d need=%d"):format(
            data.itemID, have, stashed, data.need))
    end

    -- Status pill: neutral flat cell; color lives in the text only.
    local short = data.need - have
    if short > 0 then
        -- Red short text (#e5624a — muted red, tuned to sit with the dark bg
        -- and the brand mint without shouting).
        row.pill.text:SetText(("|cffe5624a-%d|r"):format(short))
    else
        row.pill.text:SetText("|cff4ade80ok|r")
    end

    -- Row background: NONE. Atrocity's aesthetic is one window fill; rows
    -- are separated by the 1px black bottom border from the header/list and
    -- by content spacing, not by per-row backgrounds. Selection = hover wash.
    -- (Status is signaled by the pill text color + the cap-column number, not
    -- by a full-row wash.)

    -- Trash click wire. Read from row._itemID rather than closing over
    -- `data`, so a recycled row can't accidentally delete a stale item.
    row.trash:SetScript("OnClick", function(self)
        local r = self:GetParent()
        local id = r and r._itemID
        if id then
            ADDON.DB:RemoveItem(id)
            ADDON.Inventory:Invalidate()
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
    row.pill:Show()
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------
-- Small factory: a labeled, atrocity-styled editbox in a container.
-- Returns the container frame; the actual EditBox is at container.editBox.
-- Factory for a labeled EditBox with atrocity chrome. The `placeholder`
-- arg (string, optional) draws dim ghost text inside the box while it's
-- empty and unfocused — exactly the browser-style hint pattern. It clears
-- the moment the user focuses OR types, and returns when both conditions
-- reverse. Placeholder is a FontString overlay, NOT the EditBox's real
-- text, so :GetText() still returns "" when the user hasn't typed — no
-- special case needed at read time.
local function MakeEditBox(parent, labelText, width, isNumeric, maxLetters, placeholder)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 38)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(labelText)
    label:SetTextColor(Palette.textSecondary[1], Palette.textSecondary[2], Palette.textSecondary[3], 1)

    local container = CreateFrame("Frame", nil, row)
    container:SetHeight(22)
    container:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    container:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -14)

    local eb = CreateFrame("EditBox", nil, container)
    eb:SetPoint("TOPLEFT", 6, -3)
    eb:SetPoint("BOTTOMRIGHT", -6, 3)
    eb:SetFontObject("GameFontHighlight")
    eb:SetTextColor(1, 1, 1, 1)
    eb:SetAutoFocus(false)
    if isNumeric then eb:SetNumeric(true) end
    if maxLetters then eb:SetMaxLetters(maxLetters) end

    -- Optional placeholder / hint text (dim grey, italicized by way of the
    -- softer font object). Sits on the same layer as the EditBox text; the
    -- three script handlers below keep it in sync with focus + content.
    if placeholder then
        local ph = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
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
    row.editBox = eb
    row.container = container
    row.label = label
    return row
end

function MF:Build()
    if self.frame then return self.frame end

    -- ---- Root frame (no template; atrocity-flat window) ----------------
    -- Plain Frame: single WHITE8X8 fill + 1px black overlay border. Header,
    -- toolbar, list, and footer are drawn as sub-regions separated by 1px
    -- black bottom borders, not stacked backdrops. All of this is the
    -- ElvUI/atrocityEssentials aesthetic verbatim.
    local f = CreateFrame("Frame", "StockClerkFrame", UIParent, "BackdropTemplate")
    f:SetSize(680, 500)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    -- Min width is driven by the toolbar row (widest fixed thing in the
    -- window): 12 pad + 240 (Item) + 12 + 100 (Target) + 12 + 120 (Price
    -- Cap) + 12 + 96 (Add) + 12 pad = 616. Rounded up to 640 for a bit
    -- of visual breathing room; QA-1 was pinned at 560 which clipped
    -- Add Item off the right edge and wrapped the hint text.
    -- Min height keeps enough room for the toolbar + hint + column
    -- headers + a couple of rows + footer.
    -- Max: enough vertical room for very long lists on a 4K display,
    -- plus horizontal slack for very-long item names.
    if f.SetResizeBounds then
        f:SetResizeBounds(640, 320, 1200, 1200)
    else
        f:SetMinResize(640, 320)
        f:SetMaxResize(1200, 1200)
    end
    f:EnableMouse(true)
    -- Re-enable keyboard on the root frame. Removing this broke
    -- typing into the toolbar EditBoxes entirely -- turns out the
    -- previous 'keyboard stuck after Escape' issue wasn't from
    -- EnableKeyboard(true) itself but from the OnKeyDown handler
    -- below leaving SetPropagateKeyboardInput(false) sticky after an
    -- Escape. We keep EnableKeyboard(true) so child EditBoxes can
    -- receive keystrokes, and we harden the OnKeyDown to explicitly
    -- restore propagate=true after handling Escape.
    f:EnableKeyboard(true)

    -- Window fill + border. Border sits on a dedicated child frame at
    -- TOOLTIP strata so nothing draws over it (atrocity's own recipe: they
    -- go so far as to raise the border frame 100 levels above the parent).
    ApplyFill(f, Palette.bgDark)
    local borderFrame = CreateFrame("Frame", nil, f)
    borderFrame:SetAllPoints(f)
    borderFrame:SetFrameStrata("TOOLTIP")
    borderFrame:SetFrameLevel(f:GetFrameLevel() + 100)
    AddBlackBorder(borderFrame)

    -- ESC closes the window. UISpecialFrames handles this natively so
    -- long as no editbox has focus -- when ESC is pressed the topmost
    -- UISpecialFrames entry gets Hide()d automatically. We STILL need
    -- the OnKeyDown below (a) to keep SetPropagateKeyboardInput(true)
    -- so other frame-level keys pass through to game bindings while
    -- our window is shown, and (b) to leave propagate=true as the
    -- steady-state after any Escape-close so the next keystroke
    -- doesn't feel 'stuck'.
    tinsert(UISpecialFrames, "StockClerkFrame")
    f:SetScript("OnKeyDown", function(self, key)
        -- Always let keys propagate to game bindings by default. Editboxes
        -- swallow keys BEFORE this handler when they have focus, so this
        -- only runs for keystrokes that hit the raw window (no editbox
        -- focused, no addBtn focused). Letting everything propagate is
        -- the right default -- users expect B to open bags, Enter to open
        -- chat, macro keys to fire, etc.
        self:SetPropagateKeyboardInput(true)
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

    -- ---- Header (title bar) --------------------------------------------
    -- Height 32, no fill of its own (window paints one bg), 1px black
    -- bottom border to separate it from the toolbar. Title has an accented
    -- word ("Stock") in brand mint and a neutral second word ("Clerk") —
    -- verbatim structure from atrocity's AccentedTitle recipe.
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(32)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:EnableMouse(true)
    -- Same whisper-band as toolbar/headers/footer so all four framing
    -- regions share one hierarchy language ("any lighter strip = structural
    -- band, list body stays untinted").
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
    headerSep:SetTexture(WHITE_TEX)
    headerSep:SetColorTexture(Palette.border[1], Palette.border[2], Palette.border[3], 1)
    headerSep:SetHeight(BORDER_SIZE)
    headerSep:SetPoint("BOTTOMLEFT", 0, 0)
    headerSep:SetPoint("BOTTOMRIGHT", 0, 0)
    PixelSnap(headerSep)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", header, "LEFT", 12, 0)
    title:SetText("|cff98FF98Stock|r|cffFFFFFFClerk|r")
    title:SetShadowOffset(0, 0)

    -- Close X button in the header (atrocity's aesClose recipe, WoW-adapted).
    -- Uses a font-string "×" since we don't have the atrocity texture; the
    -- shape is functionally the same and it snaps to pixels cleanly.
    local closeX = CreateFrame("Button", nil, header)
    closeX:SetSize(28, 22)
    closeX:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    local closeXText = closeX:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeXText:SetPoint("CENTER")
    closeXText:SetText("×")
    closeXText:SetTextColor(0.85, 0.85, 0.85, 1)
    closeX:SetScript("OnEnter", function(self)
        closeXText:SetTextColor(Palette.brand[1], Palette.brand[2], Palette.brand[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Close")
        GameTooltip:Show()
    end)
    closeX:SetScript("OnLeave", function()
        closeXText:SetTextColor(0.85, 0.85, 0.85, 1)
        GameTooltip:Hide()
    end)
    closeX:SetScript("OnClick", function() MF:Hide() end)

    -- ---- Toolbar (add item + controls) ---------------------------------
    -- Sits directly under the header. No fill; the labels + editboxes
    -- provide enough visual weight. Ends with a 1px black bottom border
    -- separating it from the list.
    local toolbar = CreateFrame("Frame", nil, f)
    toolbar:SetHeight(48)
    toolbar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    -- Layer 1: subtle brighter band so the toolbar reads as its own strip
    -- above the list, atrocity-style. Alpha is intentionally tiny (~3.5%)
    -- so it's a whisper, not a stripe.
    ApplyBand(toolbar, Palette.bandTint)

    local toolbarSep = toolbar:CreateTexture(nil, "OVERLAY", nil, 6)
    toolbarSep:SetTexture(WHITE_TEX)
    toolbarSep:SetColorTexture(Palette.border[1], Palette.border[2], Palette.border[3], 1)
    toolbarSep:SetHeight(BORDER_SIZE)
    toolbarSep:SetPoint("BOTTOMLEFT", 0, 0)
    toolbarSep:SetPoint("BOTTOMRIGHT", 0, 0)
    PixelSnap(toolbarSep)

    -- Compact single-word labels for the numeric fields so labels don't
    -- run into the neighbouring column when the editbox itself is narrow.
    -- Wider containers (100 / 110) give the labels comfortable slack too.
    -- The 6th argument is a PLACEHOLDER (ghost text), not an initial value.
    -- Boxes start empty; the hints disappear the moment the user focuses.
    -- countBox empty falls back to 20 in DoAdd; priceBox empty means "no
    -- cap" — both semantics are unchanged from the previous default.
    -- v0.2.0 scope: itemID-only. Item name resolution is deferred to a
    -- future release (see Dev/NOTES QA-2 backlog) because Blizzard's API
    -- returns non-deterministic matches when a name maps to multiple
    -- itemIDs (rank 1/2/3 craft variants, event duplicates), and there's
    -- no addon-facing enumerate-by-name endpoint to disambiguate.
    -- Numeric-only input avoids the ambiguity entirely.
    local addEB   = MakeEditBox(toolbar, "Item ID",         240, true,  8,     "e.g. 212283")
    local countEB = MakeEditBox(toolbar, "Target",          100, true,  5,     "20")
    local priceEB = MakeEditBox(toolbar, "Price Cap / Unit", 120, true,  7,     "none")
    local addBox   = addEB.editBox
    local countBox = countEB.editBox
    local priceBox = priceEB.editBox

    addEB:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 12, -4)
    countEB:SetPoint("LEFT", addEB, "RIGHT", 12, 0)
    priceEB:SetPoint("LEFT", countEB, "RIGHT", 12, 0)

    local addBtn = CreateFrame("Button", nil, toolbar)
    addBtn:SetSize(96, 22)
    addBtn:SetPoint("LEFT", priceEB, "RIGHT", 12, -6)
    StyleButton(addBtn)
    local addBtnText = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addBtnText:SetPoint("CENTER")
    addBtnText:SetText(L.BTN_ADD_ITEM or "Add Item")
    addBtnText:SetTextColor(1, 1, 1, 1)

    local function DoAdd()
        local raw = addBox:GetText()
        if not raw or raw == "" then return end
        -- itemID-only path. Strict validation: reject anything that isn't
        -- a positive integer, including item links (users can still
        -- Shift-click into chat, extract the numeric id, and paste it).
        -- Full 'paste an item link and extract the id' UX is v0.3 work.
        local itemID = tonumber(raw)
        if not itemID or itemID <= 0 or math.floor(itemID) ~= itemID then
            MF:SetStatus("|cffff8888Item ID must be a number (e.g. 212283)|r")
            return
        end
        local need = tonumber(countBox:GetText()) or 20
        local priceGold = tonumber(priceBox:GetText())
        local maxPriceCopper = (priceGold and priceGold > 0) and (priceGold * 10000) or nil

        -- ItemResolver still runs (async cache-warm path) so we get the
        -- item's canonical name + link for the status message and for
        -- the row display. Failure just means the id doesn't exist on
        -- the client -- we log it and bail without adding.
        ADDON.ItemResolver:Resolve(itemID, function(resolvedID, name, _)
            if not resolvedID then
                MF:SetStatus(("|cffff8888Unknown item ID: %d|r"):format(itemID))
                return
            end
            ADDON.DB:SetItem(resolvedID, need, maxPriceCopper)
            ADDON.Inventory:Invalidate()
            -- Reset all three fields AND clear focus on all three so the
            -- placeholder hooks (which hide while focused) re-show.
            addBox:SetText("")
            countBox:SetText("")
            priceBox:SetText("")
            addBox:ClearFocus()
            countBox:ClearFocus()
            priceBox:ClearFocus()
            local pMsg = maxPriceCopper and (", cap %dg"):format(priceGold) or ""
            MF:SetStatus(("Added %s (need %d%s)"):format(name, need, pMsg))
            MF:Refresh()
        end)
    end
    addBtn:SetScript("OnClick", DoAdd)

    -- ---- Add-button keyboard focus (Tab stop) --------------------------
    -- WoW Buttons don't get keyboard focus the way EditBoxes do, so we
    -- roll our own: a visible mint focus ring around the button when it
    -- is the current Tab stop, EnableKeyboard(true) with an OnKeyDown
    -- handler for Tab / Shift+Tab / Enter / Space / Escape, and helpers
    -- MF:FocusAddButton / MF:BlurAddButton to move focus into and out of
    -- it programmatically. Without this, priceBox forward-Tab would have
    -- to jump past the Add button straight into the list, and mouse-
    -- averse users could never trigger Add without Enter-inside-a-box.
    local ring = addBtn:CreateTexture(nil, "OVERLAY")
    ring:SetPoint("TOPLEFT", addBtn, "TOPLEFT", -2, 2)
    ring:SetPoint("BOTTOMRIGHT", addBtn, "BOTTOMRIGHT", 2, -2)
    ring:SetColorTexture(0, 0, 0, 0) -- transparent center; edges drawn via 4 sub-textures below
    ring:Hide()
    -- Blizzard textures don't support border-only strokes, so build the
    -- ring from four 1px mint edges rather than a filled rect.
    local function edge(parent, r, g, b, a)
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(r, g, b, a)
        return t
    end
    local mint = { 0x98/255, 0xFF/255, 0x98/255, 1 }
    local edgeT = edge(addBtn, mint[1], mint[2], mint[3], mint[4])
    local edgeB = edge(addBtn, mint[1], mint[2], mint[3], mint[4])
    local edgeL = edge(addBtn, mint[1], mint[2], mint[3], mint[4])
    local edgeR = edge(addBtn, mint[1], mint[2], mint[3], mint[4])
    edgeT:SetPoint("TOPLEFT", -2, 2); edgeT:SetPoint("TOPRIGHT", 2, 2); edgeT:SetHeight(1)
    edgeB:SetPoint("BOTTOMLEFT", -2, -2); edgeB:SetPoint("BOTTOMRIGHT", 2, -2); edgeB:SetHeight(1)
    edgeL:SetPoint("TOPLEFT", -2, 2); edgeL:SetPoint("BOTTOMLEFT", -2, -2); edgeL:SetWidth(1)
    edgeR:SetPoint("TOPRIGHT", 2, 2); edgeR:SetPoint("BOTTOMRIGHT", 2, -2); edgeR:SetWidth(1)
    edgeT:Hide(); edgeB:Hide(); edgeL:Hide(); edgeR:Hide()

    local function setRing(shown)
        edgeT:SetShown(shown); edgeB:SetShown(shown)
        edgeL:SetShown(shown); edgeR:SetShown(shown)
    end

    self.addBtn = addBtn

    function MF:FocusAddButton()
        -- Steal focus from any currently-focused EditBox so its blur
        -- commit fires (mirrors what happens when Tab moves between two
        -- editboxes).
        local cur = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if cur and cur.ClearFocus then cur:ClearFocus() end
        addBtn:EnableKeyboard(true)
        addBtn:SetPropagateKeyboardInput(false)
        setRing(true)
        self._addBtnFocused = true
    end

    function MF:BlurAddButton()
        addBtn:SetPropagateKeyboardInput(true)
        addBtn:EnableKeyboard(false)
        setRing(false)
        self._addBtnFocused = false
    end

    addBtn:SetScript("OnKeyDown", function(_, key)
        if not MF._addBtnFocused then return end
        if key == "TAB" then
            -- Defer BOTH the blur and the focus transfer by one frame
            -- so the current Tab keystroke is fully consumed by this
            -- OnKeyDown (propagate stays false) and doesn't double-hop
            -- into the newly-focused control.
            local shift = IsShiftKeyDown()
            C_Timer.After(0, function()
                MF:BlurAddButton()
                if shift then
                    if priceBox then priceBox:SetFocus() end
                else
                    -- Forward from Add button goes into the list; wrap
                    -- back to addBox if the list is empty.
                    if not MF:TabToFirstRowCell() then
                        if addBox then addBox:SetFocus() end
                    end
                end
            end)
        elseif key == "ENTER" or key == "SPACE" then
            DoAdd()
            -- DoAdd clears the editbox focuses on success. Keep keyboard
            -- focus on the Add button so the user can immediately Shift+
            -- Tab back to Price Cap or Tab into the list without a mouse.
        elseif key == "ESCAPE" then
            MF:BlurAddButton()
        end
    end)
    -- Clicking the button (mouse) should also clear the keyboard-focus
    -- state so we don't leave a stale ring behind.
    addBtn:HookScript("OnClick", function() MF:BlurAddButton() end)

    -- If any toolbar editbox gains focus while the Add button had the
    -- ring, drop the ring. Prevents 'two focused controls' visual bug
    -- when the user clicks an editbox with a mouse after tabbing into
    -- the Add button.
    for _, eb in ipairs({ addBox, countBox, priceBox }) do
        eb:HookScript("OnEditFocusGained", function()
            if MF._addBtnFocused then MF:BlurAddButton() end
        end)
    end

    addBox:SetScript("OnEnterPressed", function() DoAdd() addBox:ClearFocus() end)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    countBox:SetScript("OnEnterPressed", function() DoAdd() addBox:ClearFocus() end)
    countBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    priceBox:SetScript("OnEnterPressed", function() DoAdd() addBox:ClearFocus() end)
    priceBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Save toolbar boxes on self so BuildRow's inline editors can reach
    -- them for unified Tab navigation across toolbar + row-body cells.
    self.addBox   = addBox
    self.countBox = countBox
    self.priceBox = priceBox

    -- Tab navigation across the add-item form. Matches standard desktop
    -- form behavior: Tab moves forward through Item -> Target -> Price Cap
    -- and continues into the first shopping-list row's editable cells
    -- (QA-7: unified row-major loop). Shift+Tab reverses.
    -- WoW EditBoxes fire OnTabPressed for the Tab key (no modifier check
    -- in the event itself — IsShiftKeyDown() reads live state).
    -- Forward tab chain: addBox -> countBox -> priceBox -> addBtn -> rows -> (wrap to addBox)
    -- Reverse chain is the mirror. addBtn is a Button, not an EditBox,
    -- so its Tab handling lives in its OnKeyDown above (set up by
    -- MF:FocusAddButton). The row list's reverse wrap now targets addBtn
    -- instead of priceBox (see MF:TabFromCell) so the button is a full
    -- Tab-stop citizen.
    addBox:SetScript("OnTabPressed", function(self)
        if IsShiftKeyDown() then
            -- Shift+Tab from toolbar's first field wraps to the LAST
            -- editable cell in the list (last row's Price Cap). If the
            -- list is empty, wrap to the Add button instead so the
            -- reverse loop still passes through every stop.
            if not MF:TabToLastRowCell() then MF:FocusAddButton() end
        else
            countBox:SetFocus()
        end
    end)
    countBox:SetScript("OnTabPressed", function(self)
        if IsShiftKeyDown() then addBox:SetFocus() else priceBox:SetFocus() end
    end)
    priceBox:SetScript("OnTabPressed", function(self)
        if IsShiftKeyDown() then
            countBox:SetFocus()
        else
            -- Forward Tab from the toolbar's last editbox now goes to
            -- the Add button (was: straight into the list). From there
            -- Tab continues into the row list.
            MF:FocusAddButton()
        end
    end)

    -- ---- Hint (below toolbar) ------------------------------------------
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 12, -6)
    hint:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -12, -6)
    hint:SetJustifyH("LEFT")
    -- Dimmer than the toolbar band so this recedes visually — it's help text,
    -- not primary content. Alpha via a slightly darker grey than before.
    hint:SetText("|cff6a6a6aShift+Click to link \194\183 Click 'x' to remove \194\183 Click a value to edit it \194\183 Left-click a row (AH open) to search|r")

    -- ---- Column headers -----------------------------------------------
    -- Sits under the hint; no fill (matches atrocity's headerless section
    -- headers — the labels themselves + the 1px bottom border are enough).
    -- Labels in brand mint (accent = section-header rule).
    -- Header frame stretches FULL window width (TOPRIGHT anchored to `f`'s
    -- TOPRIGHT with 0 inset) so its band matches the toolbar/footer bands
    -- for aesthetic uniformity — no visible cutoff before the scroll bar.
    -- Anchoring to a descendant of listHolder would produce a circular
    -- dependency (listHolder anchors TOPLEFT to headers, BOTTOMLEFT), so
    -- `f` is the only safe reference here.
    --
    -- The header labels themselves (built by MakeHeader below) use RIGHT-
    -- anchored offsets that must reference the row-right-edge, NOT the
    -- header-frame-right-edge. Rows live inside scrollBox which is inset
    -- 22px from f (listHolder 4px + scroll bar 18px), so we compensate by
    -- passing xOffset - 22 to every RIGHT- or CENTER-anchored MakeHeader
    -- call (see ROW_RIGHT_INSET below).
    local ROW_RIGHT_INSET = 22
    local headers = CreateFrame("Frame", nil, f)
    headers:SetHeight(20)
    headers:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -12, -4)
    headers:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    -- Same whisper-band as the toolbar. Reads as "column-header strip" so
    -- the labels have visual weight even without a colored fill of their own.
    ApplyBand(headers, Palette.bandTint)

    local headersSep = headers:CreateTexture(nil, "OVERLAY", nil, 6)
    headersSep:SetTexture(WHITE_TEX)
    headersSep:SetColorTexture(Palette.border[1], Palette.border[2], Palette.border[3], 1)
    headersSep:SetHeight(BORDER_SIZE)
    headersSep:SetPoint("BOTTOMLEFT", 0, 0)
    headersSep:SetPoint("BOTTOMRIGHT", 0, 0)
    PixelSnap(headersSep)

    -- Header helper. `mode` picks the anchoring rule so labels sit exactly
    -- over their cell regardless of column width:
    --   "left"   — LEFT edge at xOffset from headers' LEFT  (Item column)
    --   "right"  — RIGHT edge at xOffset from headers' RIGHT (right-aligned
    --              value like Have, where the cell has no chrome)
    --   "center" — label CENTER at xOffset from headers' RIGHT (matches the
    --              cell's center anchor — use for every cell-based column)
    -- Right/center modes automatically shift xOffset LEFT by ROW_RIGHT_INSET
    -- so the caller can pass the same offset used in BuildRow (which is
    -- relative to row.RIGHT) even though headers is anchored to f.RIGHT.
    local function MakeHeader(text, mode, xOffset)
        local fs = headers:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
    -- Column pixel positions. Cells in BuildRow anchor their RIGHT edge to
    -- row.RIGHT (SetPoint("RIGHT", row, "RIGHT", -N, 0)). To sit each
    -- header LABEL over the visual CENTER of its cell, subtract half the
    -- cell's width from that RIGHT-edge offset:
    --   needCell: right at -200, width 56 -> center at -200 - 28 = -228
    --   capCell:  right at -110, width 72 -> center at -110 - 36 = -146
    --   pill:     right at  -36, width 52 -> center at  -36 - 26 =  -62
    -- Have is a right-justified FontString whose right edge sits at -270,
    -- so its header is right-anchored to the same -270 for edge-alignment.
    MakeHeader("Item",      "left",    52)      -- left edge + 40 (icon + 12 pad)
    MakeHeader("Have",      "right",   -270)    -- right-edge-aligned bags value
    MakeHeader("Need",      "center",  -228)    -- centered over needCell
    MakeHeader("Price Cap", "center",  -146)    -- centered over capCell
    MakeHeader("Status",    "center",  -62)     -- centered over pill

    -- ---- Footer / bottom bar ------------------------------------------
    -- Fixed 36px bar; status text on the left, action buttons on the right.
    -- 1px black top border to separate from the list.
    local footer = CreateFrame("Frame", nil, f)
    footer:SetHeight(38)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    -- Same whisper-band as toolbar/headers so the footer feels like a
    -- balanced counterweight to the toolbar, not just an afterthought row.
    ApplyBand(footer, Palette.bandTint)

    local footerSep = footer:CreateTexture(nil, "OVERLAY", nil, 6)
    footerSep:SetTexture(WHITE_TEX)
    footerSep:SetColorTexture(Palette.border[1], Palette.border[2], Palette.border[3], 1)
    footerSep:SetHeight(BORDER_SIZE)
    footerSep:SetPoint("TOPLEFT", 0, 0)
    footerSep:SetPoint("TOPRIGHT", 0, 0)
    PixelSnap(footerSep)

    local statusBar = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusBar:SetPoint("LEFT", 14, 0)
    statusBar:SetPoint("RIGHT", footer, "RIGHT", -260, 0)
    statusBar:SetJustifyH("LEFT")
    self.statusBar = statusBar

    local closeBtn = CreateFrame("Button", nil, footer)
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("RIGHT", -12, 0)
    StyleButton(closeBtn)
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeBtnText:SetPoint("CENTER")
    closeBtnText:SetText(L.BTN_CLOSE or "Close")
    closeBtnText:SetTextColor(1, 1, 1, 1)
    closeBtn:SetScript("OnClick", function() MF:Hide() end)

    local restockBtn = CreateFrame("Button", nil, footer)
    restockBtn:SetSize(140, 22)
    restockBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    StyleButton(restockBtn)
    local restockBtnText = restockBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    restockBtnText:SetPoint("CENTER")
    restockBtnText:SetTextColor(1, 1, 1, 1)
    restockBtn._label = restockBtnText
    restockBtnText:SetText("Restock at AH")
    restockBtn:SetScript("OnClick", function()
        if ADDON.RestockLoop:IsActive() then
            ADDON.RestockLoop:Stop("Restock loop stopped.")
        else
            ADDON.RestockLoop:Start()
        end
    end)
    -- Wrap Enable/Disable to visually dim (StyleButton doesn't hook these
    -- because plain Buttons don't call them; we drive it from RefreshRestockBtn).
    self.restockBtn = restockBtn

    -- ---- Resize grip (bottom-right corner) -----------------------------
    -- Uses Blizzard's built-in ChatIM SizeGrabber textures — the same
    -- diagonal-hash art the chat frame uses — so the affordance reads as
    -- native and stays inside its 16x16 bounding box (no rotation math,
    -- no bleed past the window border). SetResizeBounds above enforces
    -- the min/max; this Button just triggers StartSizing.
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

    -- ---- ScrollBox (list of rows) --------------------------------------
    local listHolder = CreateFrame("Frame", nil, f)
    listHolder:SetPoint("TOPLEFT", headers, "BOTTOMLEFT", 4, -2)
    listHolder:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -4, 2)

    local scrollBox = CreateFrame("Frame", nil, listHolder, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT")
    scrollBox:SetPoint("BOTTOMRIGHT", -18, 0)

    -- (headers' right edge is anchored above, right after headers is
    -- created — anchoring here would create a circular dependency because
    -- listHolder itself anchors to headers.)

    local scrollBar = CreateFrame("EventFrame", nil, listHolder, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT",     scrollBox, "TOPRIGHT",    2, 0)
    scrollBar:SetPoint("BOTTOMLEFT",  scrollBox, "BOTTOMRIGHT", 2, 0)

    -- Order matters: current builds validate that the element factory is
    -- set before a DataProvider is attached, otherwise SetDataProvider
    -- errors out with "elementFactory was nil". Configure the view first,
    -- initialize with the scroll bar, then hand off the DataProvider.
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

    -- Empty-state text (hidden by default)
    self.emptyText = listHolder:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    self.emptyText:SetPoint("CENTER")
    self.emptyText:SetText(L.EMPTY_LIST or "No items tracked. Add one above.")
    self.emptyText:Hide()

    return f
end

-- ---------------------------------------------------------------------------
-- Refresh: rebuild the DataProvider from ADDON.DB.
-- Follows the Auctionator pattern of replacing the DataProvider each
-- refresh (see Source/Components/ResultsListing/Mixins/ResultsListing.lua).
-- Flushing + re-inserting can leave the ScrollView reusing frames without
-- re-invoking the row initializer, which causes stale counts.
-- ---------------------------------------------------------------------------
function MF:Refresh()
    if not self.frame or not self.scrollBox then return end

    if ADDON.debug then
        print("|cff98FF98[SC:debug]|r MainFrame:Refresh() called (frame shown: " .. tostring(self.frame:IsShown()) .. ")")
    end

    local items = ADDON.DB:GetSortedItems()

    if #items == 0 then
        -- Empty provider still needs to be swapped in so any prior rows
        -- are cleared out.
        local emptyProvider = CreateDataProvider()
        self.scrollBox:SetDataProvider(emptyProvider, ScrollBoxConstants.RetainScrollPosition)
        self.dataProvider = emptyProvider
        self.emptyText:Show()
        self:SetStatus("0 items tracked")
        return
    end
    self.emptyText:Hide()

    local newProvider = CreateDataProvider()
    local shortCount = 0
    for i, it in ipairs(items) do
        -- GetCount returns bags-only, matching what the row displays.
        -- Shortfall is thus "my bags are below target", not "my total
        -- across everything is below target" — aligned with the metric
        -- shown to the user.
        local have = ADDON.Inventory:GetCount(it.itemID) or 0
        if have < it.need then shortCount = shortCount + 1 end
        newProvider:Insert({
            itemID   = it.itemID,
            name     = it.name,
            need     = it.need,
            maxPrice = it.maxPrice,
            _index   = i,
        })
    end

    -- Swap the provider. Passing RetainScrollPosition keeps the user's
    -- scroll offset stable across refreshes so restocking updates don't
    -- yank the list back to the top.
    self.scrollBox:SetDataProvider(newProvider, ScrollBoxConstants.RetainScrollPosition)
    self.dataProvider = newProvider

    if shortCount > 0 then
        self:SetStatus(("|cff98FF98%d items tracked|r  |cff888888|||r  |cfff87171%d short|r"):format(#items, shortCount))
    else
        self:SetStatus(("|cff98FF98%d items tracked|r  |cff888888|||r  |cff4ade80all stocked|r"):format(#items))
    end

    self:RefreshRestockBtn(shortCount)
end

-- Enable the Restock button only when the AH is open AND we have at least
-- one shortfall item to restock. The loop itself handles empty queues and
-- caps -- this is just first-line UX so the button doesn't look clickable
-- when it can't do anything.
function MF:RefreshRestockBtn(shortCount)
    if not self.restockBtn then return end
    if shortCount == nil then
        shortCount = 0
        for _, it in ipairs(ADDON.DB:GetSortedItems()) do
            local have = ADDON.Inventory:GetCount(it.itemID) or 0
            if have < it.need then shortCount = shortCount + 1 end
        end
    end
    local ahOpen = AuctionHouseFrame and AuctionHouseFrame:IsShown()
    local looping = ADDON.RestockLoop and ADDON.RestockLoop:IsActive()
    local btn = self.restockBtn
    if looping then
        if btn._label then btn._label:SetText("Stop restock") end
        btn:Enable()
        btn:EnableMouse(true)
        if btn._label then btn._label:SetTextColor(1, 1, 1, 1) end
    else
        if btn._label then btn._label:SetText("Restock at AH") end
        local enabled = ahOpen and shortCount > 0
        if enabled then
            btn:Enable()
            btn:EnableMouse(true)
            if btn._label then btn._label:SetTextColor(1, 1, 1, 1) end
        else
            btn:Disable()
            btn:EnableMouse(false)
            if btn._label then btn._label:SetTextColor(Palette.textMuted[1], Palette.textMuted[2], Palette.textMuted[3], 1) end
        end
    end
end

function MF:SetStatus(text)
    if self.statusBar then self.statusBar:SetText(text or "") end
end

-- ---------------------------------------------------------------------------
-- Tab navigation across toolbar + list-body cells (QA-7)
-- ---------------------------------------------------------------------------
-- Row-major, unified loop: toolbar Item -> Target -> Price Cap -> row 1's
-- Need -> row 1's Price Cap -> row 2's Need -> ... -> wraps back to Item.
-- Shift+Tab reverses.
--
-- Row ordering comes from the DataProvider so scrolling doesn't reshuffle
-- the Tab sequence. Because rows are RECYCLED by the ScrollView, the
-- current row-Button for a given data index has to be resolved at Tab
-- time via scrollBox:FindFrame(elementData). If the target row is not
-- currently rendered (off-screen), we scroll to it first, then defer the
-- focus + open to the next frame so the ScrollView has time to spawn or
-- re-target the Button.

-- Open the given row's inline editor for the given cell ("need"|"price").
-- The Open* helpers live inside BuildRow's closure, so we call them by
-- simulating an OnClick on the cell Button -- same code path the user
-- takes with the mouse. This keeps the focus / border / value hide logic
-- in exactly one place per cell.
local function OpenRowCellEditor(row, cell)
    if not row then return end
    -- If the Add button had keyboard focus, drop its ring so we don't
    -- end up with two 'focused' controls at once.
    if MF._addBtnFocused then MF:BlurAddButton() end
    local target = (cell == "need") and row.needCell or row.capCell
    if target and target:GetScript("OnClick") then
        target:GetScript("OnClick")(target)
    end
end

-- Given a data index in the current provider, focus its Nth cell.
--
-- We ALWAYS defer the actual open by one frame via C_Timer.After(0).
-- Reason: when this is called from a Tab keystroke, the *source* editor
-- is losing focus at the same moment, which triggers OnEditFocusLost ->
-- CommitNeedEdit/CommitPriceEdit -> MF:Refresh() -> the DataProvider is
-- replaced and every row Frame is potentially rebound to a different
-- element. Resolving FindFrame(elementData) BEFORE that settles gives a
-- stale Button and the open silently no-ops on the second row.
-- Deferring lets the blur commit + Refresh + rebind complete, then we
-- re-lookup the current elementData (fresh from the new provider) and
-- open its Button.
function MF:FocusRowCell(dataIndex, cell)
    if not self.scrollBox or not self.dataProvider then return end
    local size = self.dataProvider:GetSize()
    if size == 0 or dataIndex < 1 or dataIndex > size then return end

    -- Snapshot the itemID at request time so we can re-locate the row
    -- after any refresh that fires between now and the deferred open.
    -- Using itemID rather than the elementData table itself because the
    -- provider gets fully rebuilt across Refresh() calls.
    local seed = self.dataProvider:Find(dataIndex)
    if not seed then return end
    local wantItemID = seed.itemID

    -- Scroll the target index into view first. If it's already visible
    -- this is a no-op; if it isn't, we need this call BEFORE the defer
    -- so the ScrollView has a frame's worth of time to spawn the Button.
    --
    -- Blizzard signature: ScrollToElementDataIndex(dataIndex, alignment,
    -- offset, noInterpolation). We were previously passing
    -- ScrollBoxConstants.NoScrollInterpolation (a BOOLEAN) into the
    -- `offset` slot, which throws 'attempt to perform arithmetic on
    -- local offset (a boolean value)' inside ScrollBox.lua:850. Correct
    -- placement: nil offset, boolean in the fourth slot.
    self.scrollBox:ScrollToElementDataIndex(dataIndex,
        ScrollBoxConstants.AlignCenter,
        nil,
        ScrollBoxConstants.NoScrollInterpolation)

    C_Timer.After(0, function()
        if not (self.scrollBox and self.dataProvider) then return end
        -- Re-resolve the elementData by itemID against the CURRENT
        -- provider. The row might have moved in the sort order if
        -- something else refreshed the list, but the itemID is stable.
        local currentSize = self.dataProvider:GetSize()
        for i = 1, currentSize do
            local d = self.dataProvider:Find(i)
            if d and d.itemID == wantItemID then
                local frame = self.scrollBox:FindFrame(d)
                if frame then
                    OpenRowCellEditor(frame, cell)
                end
                return
            end
        end
    end)
end

-- Toolbar boundary jumps: Tab out of Price Cap -> first row's Need;
-- Shift+Tab out of Item -> last row's Price Cap. Return true if the
-- list has any rows and focus was moved, false to let the caller wrap.
function MF:TabToFirstRowCell()
    if not self.dataProvider or self.dataProvider:GetSize() == 0 then
        return false
    end
    self:FocusRowCell(1, "need")
    return true
end

function MF:TabToLastRowCell()
    if not self.dataProvider or self.dataProvider:GetSize() == 0 then
        return false
    end
    self:FocusRowCell(self.dataProvider:GetSize(), "price")
    return true
end

-- Tab handler called from a row's inline editor. `cell` is "need" or
-- "price" (which cell the user is currently in); `dir` is +1 for forward
-- Tab or -1 for Shift+Tab. Walks the row-major sequence: within a row,
-- need <-> price; at row boundaries, jump to the next/prev row (or wrap
-- through the toolbar).
function MF:TabFromCell(row, cell, dir)
    if not row or not row._itemID or not self.dataProvider then return end
    -- Find this row's data index. Rows carry ._index thanks to Refresh's
    -- provider inserts; fall back to a linear search if it's missing.
    local size = self.dataProvider:GetSize()
    local idx
    for i = 1, size do
        local d = self.dataProvider:Find(i)
        if d and d.itemID == row._itemID then idx = i; break end
    end
    if not idx then return end

    if dir > 0 then
        -- Forward Tab.
        if cell == "need" then
            self:FocusRowCell(idx, "price")
        else -- cell == "price": next row's need, or wrap to toolbar's first stop
            if idx < size then
                self:FocusRowCell(idx + 1, "need")
            else
                -- End of list wraps forward to addBox (start of the loop).
                if self.addBox then self.addBox:SetFocus() end
            end
        end
    else
        -- Backward Tab.
        if cell == "price" then
            self:FocusRowCell(idx, "need")
        else -- cell == "need": prev row's price, or wrap to Add button
            if idx > 1 then
                self:FocusRowCell(idx - 1, "price")
            else
                -- Top of list wraps backward to the Add button, which is
                -- the tab stop immediately before the row list.
                self:FocusAddButton()
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Show / Hide
-- ---------------------------------------------------------------------------
-- Show accepts an optional `fromAH` argument. Only overwrite openedByAH
-- when the caller explicitly tells us where the show came from -- calling
-- Show() with no arg (e.g. from a slash command or a Refresh after add)
-- must not clobber a flag Core.lua just set on our behalf.
function MF:Show(fromAH)
    self:Build()
    if fromAH ~= nil then
        self.openedByAH = fromAH and true or false
    end
    self.frame:Show()
    self:Refresh()
end

function MF:Hide()
    if self.frame then self.frame:Hide() end
end

function MF:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show(false)
    end
end
