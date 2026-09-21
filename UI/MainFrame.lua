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
    -- Row separator: 1px muted dark gray line drawn along each row's
    -- bottom edge. Distinct from Palette.border (pure black, used for
    -- window/cell chrome) so it reads as a between-rows divider rather
    -- than a hard boundary.
    rowSeparator  = { 0.15, 0.15, 0.15, 1.00 },
}

local BORDER_SIZE = 1
local ANIM_DUR    = 0.15

-- No WHITE_TEX path in this file: all solid fills and borders use
-- SetColorTexture. The White8x8+SetVertexColor atlas idiom renders
-- transparent on retail Midnight (v0.3 changelog) and mixed-path
-- remnants were stripped in the code-review cleanup.
local TRASH_TEX = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"   -- red X, native asset
local QUESTION_ICON = 134400

-- ---------------------------------------------------------------------------
-- Helpers (atrocity-style theming primitives)
-- ---------------------------------------------------------------------------

-- PixelSnap: turn off texel snapping / bias so 1px borders don't smear across
-- two physical pixel rows when the UI scale is off-grid. Verbatim from atrocity's
-- AE:PixelSnapRegions (Core/AddonTheme.lua). Every border texture goes through
-- this or you get the classic "1px line looks 2px thick and blurry" bug.
-- Local alias to the ADDON-wide money helper (defined in Core.lua at
-- load time, so it's available before this file's functions execute).
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
    -- SetColorTexture, not SetTexture(WHITE_TEX)+SetVertexColor: the
    -- White8x8 atlas path is the documented transparency trap on retail
    -- Midnight (see v0.3 changelog), and the mixed path contradicts the
    -- convention this codebase adopted.
    frame._bg:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
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
        PixelSnap(frame._band)
    end
    frame._band:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
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
        -- The EditBox sits on top of the
        -- container and eats mouse enter/leave for the interior. Without
        -- this mirror, moving the cursor across the editbox proper leaves
        -- the border un-lit, and only the ~3px exposed strip between the
        -- editbox edge and the container edge triggers container.OnEnter.
        -- Cursor drifting off the editbox onto that strip and back would
        -- flash the mint border in-and-out repeatedly -- exactly what
        -- users reported as "border highlight behavior is still weird".
        -- Hooking OnEnter/OnLeave on the editBox too collapses the two
        -- surfaces into one logical hover region: mint on entering either,
        -- fade only on leaving both (guarded by container:IsMouseOver()
        -- and editBox:IsMouseOver() so crossing the boundary stays lit).
        editBox:HookScript("OnEnter", toBrand)
        editBox:HookScript("OnLeave", function()
            if editBox:HasFocus() then return end
            if container:IsMouseOver() or editBox:IsMouseOver() then return end
            container._borderAnim.AnimateTo(Palette.border)
        end)
    end
end

-- Row hover wash: on-demand rectangle we manage without wash-registration
-- (we're driving it from RowEnter/RowLeave directly so it works even though
-- the row uses non-HookScript SetScript handlers).
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
-- StockClerk does not touch item
-- tooltips. They're native WoW territory, further shaped by whichever
-- tooltip addon the user runs -- not ours to arbitrate.
--
-- StockClerk paints exactly four tooltips, all of which describe our
-- own affordances: grip ("Drag to reorder"), cap cell ("Max Xg"),
-- need cell ("Target: N"), last-seen dot ("Last seen at AH"). All four
-- anchor at ANCHOR_TOP for consistent placement, and each cell paints
-- inline on OnEnter / hides on OnLeave -- no dispatcher, no state.
-- ---------------------------------------------------------------------------

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

    -- 2px vertical accent bar on the row's
    -- left edge that encodes short/ok/unknown state. Replaces the
    -- dedicated Status column (dropped in v0.7 but the old row.pill
    -- FontString was still leaking 'ok'/'-N' text at the row's right
    -- edge because InitializeRow was force-showing the stub). This bar
    -- is a robust position-anchored signal that works alongside the
    -- red/mint coloring of the Have text (dual-channel encoding for
    -- colorblind resilience). Sits BEFORE the grip in the mouse-hit
    -- stack; grip stays clickable because the accent is a texture, not
    -- a mouse-enabled frame.
    row.accent = row:CreateTexture(nil, "OVERLAY")
    row.accent:SetWidth(2)
    row.accent:SetPoint("TOPLEFT",    row, "TOPLEFT",     0, -1)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT",  0,  1)
    row.accent:Hide()  -- shown only when we have a definite short/ok call

    -- Row separator: 1px muted gray line along the row's bottom edge,
    -- full width. Gives the shopping list visual rhythm between rows
    -- without needing per-row backgrounds or heavy dividers. Drawn on
    -- BACKGROUND sublevel 0 so hover washes and cell fills paint over
    -- it cleanly.
    row.separator = row:CreateTexture(nil, "BACKGROUND", nil, 0)
    row.separator:SetColorTexture(unpack(Palette.rowSeparator))
    row.separator:SetHeight(1)
    row.separator:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    row.separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

    -- Grip handle (v0.4). Three dim horizontal lines, EnableMouse'd for
    -- the drag-to-reorder path. Sits at the far left; icon & name shift
    -- right by GRIP_W to make room. Rendered with three FontString
    -- em-dashes rather than a texture asset so it needs no atlas file
    -- and stays crisp at any UI scale.
    local GRIP_W = 14
    row.grip = CreateFrame("Button", nil, row)
    row.grip:SetSize(GRIP_W, ROW_HEIGHT - 6)
    row.grip:SetPoint("LEFT", 2, 0)
    row.grip:RegisterForDrag("LeftButton")
    row.grip:RegisterForClicks("LeftButtonUp")
    -- Three little bars, drawn as color-textures so we don't ship an
    -- atlas asset. 8px wide, 1px tall, spaced 3px vertically.
    row.grip._bars = {}
    for i = 1, 3 do
        local t = row.grip:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0.55, 0.55, 0.55, 0.85)
        t:SetSize(8, 1)
        t:SetPoint("CENTER", row.grip, "CENTER", 0, (i - 2) * 3)
        row.grip._bars[i] = t
    end
    row.grip:SetScript("OnEnter", function(self)
        for _, b in ipairs(self._bars) do
            b:SetColorTexture(Palette.brand[1], Palette.brand[2], Palette.brand[3], 1)
        end
        -- ANCHOR_TOP for consistency.
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Drag to reorder", 1, 1, 1)
        GameTooltip:AddLine("List order sets restock priority.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    row.grip:SetScript("OnLeave", function(self)
        for _, b in ipairs(self._bars) do
            b:SetColorTexture(0.55, 0.55, 0.55, 0.85)
        end
        -- Hide unconditionally. If the
        -- pointer is still on the row body, row's OnEnter will re-fire
        -- and paint the native item tooltip.
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

    -- The row-selection ring (soft-select) is
    -- gone. It was the source of every keyboard-nav bug we hit in
    -- alpha5, and the grip handle already communicates "drag to reorder"
    -- intuitively. Tab walks editors (Need, Cap) only; row order changes
    -- via mouse drag on the grip.

    -- Icon (shifted right by GRIP_W to clear the grip handle).
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", GRIP_W + 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim default 5% border

    -- Colored quality frame around the icon,
    -- matching WoW bags / Baganator convention. Players identify items by
    -- the quality chit at a glance, and it doubles as a mitigation for
    -- names that ellipsize (the quality color is normally at the end of
    -- the name -- e.g. "[Foo Potion]" in green -- so truncating the name
    -- loses that signal). Using WhiteIconFrame (a stock Blizzard 1px
    -- outline atlas) tinted with C_Item.GetItemQualityColor.
    row.iconBorder = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
    row.iconBorder:SetSize(26, 26)  -- slightly larger than the 22x22 icon so the frame reads clearly
    row.iconBorder:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.iconBorder:Hide()  -- shown by SetText path when quality is known and >= common

    -- Name (fills leftmost region up to the Have column). The right edge
    -- stops at -220 to leave room for four right-aligned columns (Have,
    -- Need, Cap, Last Seen) plus trash. Status column dropped in v0.7 --
    -- short/ok state is now signaled by coloring row.have (see below).
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    -- Tightened right inset (-400 -> -220) so item names get enough
    -- room at the new 420px main-frame width. Long names ellipsize; no
    -- word wrap (SetWordWrap(false) below).
    row.name:SetPoint("RIGHT", row, "RIGHT", -250, 0)  -- clears widened Have column
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Have column: pure display of the bags-only count, with a dim
    -- (+N bank/warband/reagent) suffix if the stash is non-empty. No
    -- cell chrome and no click affordance — this value only comes from
    -- inventory, the user never edits it here.
    --
    -- status-via-color: row.have text is colored red when have<need
    -- ("you're short") and mint when have>=need ("stocked"). This
    -- replaces the dedicated Status pill from earlier versions. See
    -- InitializeRow further down for the coloring logic.
    --
    -- Column layout (v0.7 accounting-style: each numeric column right-
    -- aligns on its own right edge; headers right-align above matching
    -- that edge. 14px gutters between columns so the labels can't
    -- visually collide even at narrow widths):
    --   Have   right edge -212 (Have text right-aligned)
    --   Need   cell right -160, width 42, text right-inset -6
    --   Cap    cell right -100, width 50, text right-inset -6
    --   Seen   right edge  -30, width 60 (Seen text right-aligned)
    --   trash  right edge   -6, width 18
    -- Status column dropped in v0.7 (short/ok signalled by Have text
    -- color plus the left-edge accent bar).
    -- Have column: read-only display of bags count with an optional dim
    -- (+N) suffix when the item has stashed copies in bank/warband. The
    -- suffix is intentionally quantity-only; the storage-source breakdown
    -- (which container has how many) moves to the cell's hover tooltip so
    -- the row itself stays compact and can't overflow into the Item name
    -- column at narrow widths.
    --
    -- Cell chrome matches Need/Cap for visual unity: same fill idle/hover,
    -- same border animator, same tooltip anchor. Difference: haveCell has
    -- NO OnClick handler because Have is derived from inventory, not user
    -- input. Users hover to inspect, they don't click to edit.
    row.haveCell = CreateFrame("Button", nil, row)
    row.haveCell:SetSize(50, 20)  -- slightly wider than needCell (42) to
                                  -- comfortably fit "999 (+9999)" worst case
    row.haveCell:SetPoint("RIGHT", row, "RIGHT", -212, 0)
    row.haveCell:SetFrameLevel(row:GetFrameLevel() + 2)

    local HAVE_FILL_IDLE   = { 0, 0, 0, 0.35 }
    local HAVE_FILL_HOVER  = { Palette.bgMedium[1], Palette.bgMedium[2], Palette.bgMedium[3], 1 }
    local HAVE_BORDER_IDLE = Palette.border

    ApplyFill(row.haveCell, HAVE_FILL_IDLE)
    AddBlackBorder(row.haveCell, HAVE_BORDER_IDLE)
    AttachBorderAnimator(row.haveCell)
    row.haveCell._fillIdle   = HAVE_FILL_IDLE
    row.haveCell._fillHover  = HAVE_FILL_HOVER
    row.haveCell._borderIdle = HAVE_BORDER_IDLE

    row.have = row.haveCell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.have:SetPoint("RIGHT", row.haveCell, "RIGHT", -6, 0)
    row.have:SetJustifyH("RIGHT")

    -- Have cell hover: same ANCHOR_TOP tooltip idiom as Need/Cap, but the
    -- content is inventory-derived instead of a CTA. Title line is the
    -- bags count; storage-source lines follow only when that source has
    -- >0. Reagent bank is folded into bank on retail 11.2+ (see
    -- Inventory.lua header) so we present them as one "bank" line.
    row.haveCell:SetScript("OnEnter", function(self)
        local r = self:GetParent()
        r:GetScript("OnEnter")(r)
        self._borderAnim.AnimateTo(Palette.brand)
        if self._bg then self._bg:SetVertexColor(unpack(self._fillHover)) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local bd = r._breakdown
        local bags = (bd and bd.bags) or (r._have or 0)
        GameTooltip:SetText(("Have: %d in bags"):format(bags), 1, 1, 1)
        if bd then
            local bankTotal = (bd.bank or 0) + (bd.reagent or 0)
            if bankTotal > 0 then
                GameTooltip:AddLine(("+%d in bank (this character)"):format(bankTotal), 0.78, 0.78, 0.78)
            end
            if (bd.warband or 0) > 0 then
                GameTooltip:AddLine(("+%d in warband bank (account-wide)"):format(bd.warband), 0.78, 0.78, 0.78)
            end
        end
        GameTooltip:Show()
    end)
    row.haveCell:SetScript("OnLeave", function(self)
        self._borderAnim.AnimateTo(self._borderIdle)
        if self._bg then self._bg:SetVertexColor(unpack(self._fillIdle)) end
        GameTooltip:Hide()
        local r = self:GetParent()
        r:GetScript("OnLeave")(r)
    end)

    -- Need column: dedicated editable cell for the target count. Styled
    -- exactly like the Price Cap cell — transparent at rest, dark fill +
    -- brand border fade in on hover, click opens an inline editor in place.
    row.needCell = CreateFrame("Button", nil, row)
    row.needCell:SetSize(42, 20)  -- v0.7: 56 -> 42 for compressed layout
    row.needCell:SetPoint("RIGHT", row, "RIGHT", -160, 0)  -- accounting-columns edge
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
    -- Right-align inside the cell (accounting style). SetPoint anchors
    -- the FontString's RIGHT edge at the cell's RIGHT edge -6px inset
    -- so the digit doesn't touch the cell border.
    row.need = row.needCell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.need:SetPoint("RIGHT", row.needCell, "RIGHT", -6, 0)
    row.need:SetJustifyH("RIGHT")

    -- Price Cap column: dedicated cell for the max price / unit. Click to
    -- edit. Always visible so the user can see (and change) the cap without
    -- hunting for it inside the count string. Wider than the Need cell (72
    -- vs 56) to comfortably hold 4-digit gold values like "9999g".
    row.capCell = CreateFrame("Button", nil, row)
    row.capCell:SetSize(50, 20)  -- v0.7: 72 -> 50 for compressed layout
    row.capCell:SetPoint("RIGHT", row, "RIGHT", -100, 0)  -- accounting-columns edge
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
    -- Right-align inside cell (accounting style, matches Need cell).
    row.cap = row.capCell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.cap:SetPoint("RIGHT", row.capCell, "RIGHT", -6, 0)
    row.cap:SetJustifyH("RIGHT")

    -- Inline Need editor (hidden until needCell is clicked). Anchored to
    -- the needCell so it lands exactly where the value was. The needCell
    -- carries the border animation; the editor just needs a slightly
    -- darker fill so the caret has enough contrast.
    -- SetColorTexture (not WHITE_TEX+SetVertexColor) so the editor bg
    -- actually paints on retail Midnight -- see LogFrame's ApplyFill
    -- comment for the atlas-alpha gotcha.
    row.needEditBg = row:CreateTexture(nil, "BACKGROUND")
    row.needEditBg:SetColorTexture(Palette.bgDark[1], Palette.bgDark[2], Palette.bgDark[3], 1)
    row.needEditBg:Hide()

    row.needEdit = CreateFrame("EditBox", nil, row)
    row.needEdit:SetFontObject("GameFontHighlight")
    row.needEdit:SetAutoFocus(false)
    row.needEdit:SetNumeric(true)
    row.needEdit:SetMaxLetters(5)
    row.needEdit:SetJustifyH("CENTER")
    row.needEdit:SetSize(42, 20)  -- v0.7: matches compressed needCell
    row.needEdit:SetPoint("CENTER", row.needCell, "CENTER")
    -- Explicitly single-line so Enter routes to OnEnterPressed rather
    -- than being consumed as a newline. Do NOT call EnableKeyboard(true)
    -- here: an EditBox already handles keystrokes when it has focus,
    -- and EnableKeyboard(true) on a hidden EditBox that never releases
    -- keyboard capture causes the addon to swallow ALL keys game-wide
    -- (chat, hotbars, movement) until /reload.
    row.needEdit:SetMultiLine(false)
    row.needEditBg:SetPoint("TOPLEFT",     row.needEdit, "TOPLEFT",     -4, 2)
    row.needEditBg:SetPoint("BOTTOMRIGHT", row.needEdit, "BOTTOMRIGHT",  4, -2)
    row.needEdit:SetFrameLevel(row.needCell:GetFrameLevel() + 1)
    -- KBD-FIX (H4): belt-and-suspenders. Any Hide of a focused
    -- EditBox must ClearFocus first, or WoW keeps routing keystrokes to
    -- the now-invisible field. Guards the case where the row itself is
    -- Hidden (row pool release, parent Hide) while this editor was open.
    row.needEdit:HookScript("OnHide", function(self)
        if self:HasFocus() then self:ClearFocus() end
    end)
    row.needEdit:Hide()

    -- Price cap inline editor (hidden until the cap cell is clicked).
    -- Anchored TO the cap cell so it lands exactly where the value was.
    -- The cap cell already carries the flat black border and brand-mint
    -- focus animation — the editor just needs a slightly darker fill so
    -- the caret has enough contrast.
    -- See row.needEditBg above for why SetColorTexture rather than the
    -- WHITE_TEX+SetVertexColor atlas path.
    row.priceEditBg = row:CreateTexture(nil, "BACKGROUND")
    row.priceEditBg:SetColorTexture(Palette.bgDark[1], Palette.bgDark[2], Palette.bgDark[3], 1)
    row.priceEditBg:Hide()

    row.priceEdit = CreateFrame("EditBox", nil, row)
    row.priceEdit:SetFontObject("GameFontHighlight")
    row.priceEdit:SetAutoFocus(false)
    -- Whole-gold integers only. SetNumeric strips any non-digit keystroke,
    -- which is exactly the constraint we want -- the storage is copper
    -- internally, but callers only ever type gold.
    row.priceEdit:SetNumeric(true)
    -- See row.needEdit above for why single-line and why we deliberately
    -- do NOT call EnableKeyboard(true) here.
    row.priceEdit:SetMultiLine(false)
    row.priceEdit:SetMaxLetters(7)  -- 9,999,999g cap on the input field
    row.priceEdit:SetJustifyH("CENTER")
    row.priceEdit:SetSize(50, 20)  -- v0.7: matches compressed capCell
    row.priceEdit:SetPoint("CENTER", row.capCell, "CENTER")
    row.priceEditBg:SetPoint("TOPLEFT",     row.priceEdit, "TOPLEFT",     -4, 2)
    row.priceEditBg:SetPoint("BOTTOMRIGHT", row.priceEdit, "BOTTOMRIGHT",  4, -2)
    row.priceEdit:SetFrameLevel(row.capCell:GetFrameLevel() + 1)
    -- KBD-FIX (H4): see needEdit OnHide above.
    row.priceEdit:HookScript("OnHide", function(self)
        if self:HasFocus() then self:ClearFocus() end
    end)
    row.priceEdit:Hide()

    -- Last Seen column (QA-11): dim display of the most recently observed
    -- unit price, or an em-dash if we've never seen it. Not clickable --
    -- the value updates automatically on every AH search (row-click or
    -- restock loop). Tooltip on hover: "1250g -- 2h ago via loop".
    row.lastSeen = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.lastSeen:SetPoint("RIGHT", row, "RIGHT", -30, 0)  -- v0.7: shifted right of trash
    row.lastSeen:SetWidth(60)  -- widened for #g#s (was 38)
    row.lastSeen:SetJustifyH("RIGHT")
    -- Invisible mouse target sized to the column so tooltips still work.
    row.lastSeenHit = CreateFrame("Frame", nil, row)
    row.lastSeenHit:SetSize(60, 20)  -- widened to match lastSeen
    row.lastSeenHit:SetPoint("RIGHT", row, "RIGHT", -30, 0)
    row.lastSeenHit:EnableMouse(true)
    row.lastSeenHit:SetScript("OnEnter", function(self)
        -- Paint at ANCHOR_TOP for
        -- consistency across the addon. If this row has no last-seen
        -- price, we intentionally show nothing here -- row's OnEnter
        -- already put the native item tooltip up when the mouse entered
        -- the row cluster, and we don't want to steal it.
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
        GameTooltip:AddLine(agoText .. " \194\183 via " .. (lp.source or "?"), 0.7, 0.7, 0.7)
        local staleCutoff = (ADDON.DB:Settings() and ADDON.DB:Settings().lastPriceTTL) or 86400
        if ago > staleCutoff then
            GameTooltip:AddLine("Price is stale -- re-search to refresh", 0.9, 0.6, 0.2)
        end
        GameTooltip:Show()
    end)
    row.lastSeenHit:SetScript("OnLeave", function(self)
        -- If we painted a tooltip, hide
        -- it. If the pointer is still on the row body, row's OnEnter
        -- re-fires and paints the native item tooltip. If the row has
        -- no lastPrice, we never painted anything -- Hide is a safe
        -- no-op in that case.
        local r = self:GetParent()
        if not r or not r._lastPrice then return end
        GameTooltip:Hide()
    end)

    -- The row.pill stub was intended to be a
    -- hidden 1x1 no-op after v0.7 dropped the Status column, but
    -- InitializeRow unconditionally called row.pill:Show() on every
    -- row init, and its FontString's text was still being SetText'd
    -- with 'ok' / '-N' -- so the pill's centered text (anchored at
    -- the row's right edge) was leaking through as the visible 'o' /
    -- 'o!' the screenshot showed. Keep the stub table so any lingering
    -- caller doesn't nil-error, but back it with no-op methods that
    -- can't paint anything. The full status signal now lives in
    -- row.accent (left-edge bar) + row.have color.
    row.pill = { text = { SetText = function() end } }
    row.pill.Show = function() end
    row.pill.Hide = function() end

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
        -- StockClerk does NOT paint an
        -- item tooltip on row hover. Item tooltips are the user's
        -- domain -- native WoW handles them, and users typically have
        -- their own tooltip addon further shaping that behavior. Row
        -- hover here is just visual (wash + trash button); the four
        -- StockClerk-generated tooltips (grip, cap, need, last-seen)
        -- live on their respective cells.
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
            -- "click" source tag lets QA-11 attribute this lastPrice stamp
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
                    -- QA-11: row list refresh so the Last Seen column
                    -- picks up the new stamp immediately.
                    MF:Refresh()
                else
                    MF:SetStatus("No auctions found")
                end
            end, "click")
        end
    end)
    row:RegisterForClicks("LeftButtonUp")

    -- Cap cell hover + click: opens the inline price editor. Prefills
    -- with the current cap in whole gold so the user can edit it in
    -- place instead of retyping.
    local function OpenPriceEdit(r)
        -- Mirror of the guard in
        -- OpenNeedEdit -- see comment there. Close the sibling Need
        -- editor synchronously before opening Cap so the two editors
        -- can never be visible together on the same row.
        if r.needEdit and r.needEdit:IsShown() then
            r.needEdit:ClearFocus()
            r.needEdit:Hide()
            if r.needEditBg then r.needEditBg:Hide() end
            if r.need then r.need:Show() end
            if r.needCell then
                r.needCell._needEditActive = false
                if r.needCell._borderAnim then
                    r.needCell._borderAnim.AnimateTo(r.needCell._borderIdle)
                end
                if r.needCell._bg and r.needCell._fillIdle then
                    r.needCell._bg:SetVertexColor(unpack(r.needCell._fillIdle))
                end
            end
        end
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
        -- Paint cap tooltip at ANCHOR_TOP.
        -- Also fires row-level hover so trash + wash still appear.
        r:GetScript("OnEnter")(r)
        -- Border animates to brand mint -- the "this opens something" signal.
        self._borderAnim.AnimateTo(Palette.brand)
        if self._bg then self._bg:SetVertexColor(unpack(self._fillHover)) end
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
        -- Hide unconditionally. If mouse
        -- is still on the row body, RowEnter re-fires and paints native
        -- item tooltip. If truly off, RowLeave's deferred check applies.
        GameTooltip:Hide()
        local r = self:GetParent()
        r:GetScript("OnLeave")(r)
    end)

    -- Need cell hover + click: opens the inline target editor. Mirrors the
    -- capCell wiring exactly so both editable cells behave identically.
    local function OpenNeedEdit(r)
        -- Force-close the sibling Cap
        -- editor on this row before we open Need. The within-row Tab
        -- path (need <-> cap) relied on the source editor's
        -- OnEditFocusLost to run before the destination editor showed,
        -- but priceEdit:SetFocus() in OpenPriceEdit can outrace the
        -- deferred focus-lost dispatch -- so briefly BOTH editors were
        -- visible on the same row. Snap the sibling cell state to
        -- closed synchronously.
        if r.priceEdit and r.priceEdit:IsShown() then
            r.priceEdit:ClearFocus()
            r.priceEdit:Hide()
            if r.priceEditBg then r.priceEditBg:Hide() end
            if r.cap then r.cap:Show() end
            if r.capCell then
                r.capCell._priceEditActive = false
                if r.capCell._borderAnim then
                    r.capCell._borderAnim.AnimateTo(r.capCell._borderIdle)
                end
                if r.capCell._bg and r.capCell._fillIdle then
                    r.capCell._bg:SetVertexColor(unpack(r.capCell._fillIdle))
                end
            end
        end
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
        -- Paint need tooltip at ANCHOR_TOP.
        r:GetScript("OnEnter")(r)
        self._borderAnim.AnimateTo(Palette.brand)
        if self._bg then self._bg:SetVertexColor(unpack(self._fillHover)) end
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
        -- Mirror of capCell OnLeave.
        GameTooltip:Hide()
        local r = self:GetParent()
        r:GetScript("OnLeave")(r)
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
            local oldNeed = r._need
            ADDON.DB:SetItem(r._itemID, newNeed)
            r._need = newNeed
            -- Update the inline fontstring immediately so the user sees
            -- the new value even though we skip the full Refresh.
            if r.need then r.need:SetText(tostring(newNeed)) end
            if ADDON.Log then
                ADDON.Log:Emit("target_change", r._itemID, {
                    from = oldNeed, to = newNeed,
                })
            end
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
        local r = self:GetParent()
        CloseNeedEdit(r)
        self._escaping = false
        -- Escape from cell edit closes the
        -- editor and yields keyboard focus. No ring stage.
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
    -- Alpha4's ROW-FOCUS grey-wash hooks are
    -- removed. The mint ring (row.selRing, painted by SetRowSelection)
    -- is now the singular focus indicator; the cell's own border-brand
    -- animation shows which cell is being edited. Two overlays on the
    -- same row was noisy and doubled up the "you are here" signal.

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
            -- Whole-gold input only. tonumber handles the numeric parse
            -- (SetNumeric already prevented non-digit keystrokes); we
            -- convert gold to copper for storage since the rest of the
            -- codebase (RestockLoop, AH:BuyUpTo, DB) works in copper.
            local priceGold = tonumber(raw)
            local maxPriceCopper = (priceGold and priceGold > 0) and (priceGold * 10000) or nil
            if maxPriceCopper ~= r._maxPrice then
                local oldMax = r._maxPrice
                ADDON.DB:SetItemMaxPrice(r._itemID, maxPriceCopper, "user")
                r._maxPrice = maxPriceCopper
                local name = r.name:GetText() or ("item:" .. r._itemID)
                if maxPriceCopper then
                    MF:SetStatus(("Cap for %s set to %dg"):format(name, priceGold))
                else
                    MF:SetStatus(("Cap cleared for %s"):format(name))
                end
                if ADDON.Log then
                    ADDON.Log:Emit("cap_change", r._itemID, {
                        fromCopper = oldMax, toCopper = maxPriceCopper,
                    })
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
        -- Escape from cell edit closes the
        -- editor and yields keyboard focus. No ring stage.
        self._escaping = true
        local r = self:GetParent()
        ClosePriceEdit(r)
        self._escaping = false
    end)
    row.priceEdit:SetScript("OnEnterPressed", function(self)
        CommitPriceEdit(self:GetParent())
    end)
    -- Alpha4's ROW-FOCUS grey-wash hook for
    -- the price cell removed for the same reason as the need cell above.

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

    -- KBD-FIX (H4): CRITICAL keyboard-capture defense. ScrollView
    -- recycles the pooled row Button when the underlying DataProvider
    -- changes (BAG_UPDATE refresh, scroll, filter chip toggle, etc.).
    -- If a row had its inline needEdit/priceEdit open with focus when the
    -- pool rebound this frame to a different item, the EditBox stayed
    -- Shown() and Focused() -- often scrolled offscreen -- and silently
    -- captured every keystroke game-wide until /reload. This is the
    -- "addon ate my keyboard" class of bug. Force-reset editor state
    -- BEFORE binding the new data so we never inherit stale focus into a
    -- frame the user can no longer see.
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

    -- Tint the border with quality color.
    -- Hide entirely for quality nil (cold cache) or 0/1 (poor/common) --
    -- WoW's own bag UI treats those as no-frame, matching player expectation.
    -- A GET_ITEM_INFO_RECEIVED refresh will re-run this row once quality
    -- resolves; no explicit event handler needed here because Refresh()
    -- already re-runs on that event via ItemResolver's callback path.
    --
    -- C_Item.GetItemQualityColor returns
    -- MULTIPLE VALUES (r, g, b, hex) as plain numbers -- NOT a ColorMixin
    -- table. The alpha5-preview build tried to index qc.r on the first
    -- return value (a number 0.0-1.0), which threw
    --   "attempt to index local 'qc' (a number value)"
    -- three times on launch (once per broken row init) and left the
    -- shopping list broken with only one row visible. Destructure the
    -- return values instead. Defensive default to white on nil in the
    -- unlikely event Blizzard ever returns nothing for a valid quality.
    if row.iconBorder then
        if quality and quality >= 2 and C_Item and C_Item.GetItemQualityColor then
            local r, g, b = C_Item.GetItemQualityColor(quality)
            row.iconBorder:SetVertexColor(r or 1, g or 1, b or 1, 1)
            row.iconBorder:Show()
        else
            row.iconBorder:Hide()
        end
    end
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

    -- Have column: bags-only count with optional dim suffix that names
    -- where any stashed copies live. Bags stays the primary metric; the
    -- suffix is context, not a total.
    --
    -- status-via-color: the primary bags-count gets a semantic
    -- color prefix based on have-vs-need (red when short, mint when
    -- stocked, default when no target). This replaces the dedicated
    -- Status pill from earlier versions. The (+N stash: bank/reagent)
    -- suffix stays gray -- it's ancillary info that shouldn't compete
    -- with the short/stocked signal.
    local haveColor = ""
    local haveColorEnd = ""
    if data.need and data.need > 0 then
        local short = data.need - have
        if short > 0 then
            haveColor    = "|cffe5624a"  -- muted red, was Status pill's short color
            haveColorEnd = "|r"
        else
            haveColor    = "|cff98FF98"  -- brand mint, "stocked"
            haveColorEnd = "|r"
        end
    end
    -- Suffix is quantity-only: "N (+M)". Storage-source detail (which
    -- container has how many) lives in the haveCell hover tooltip so the
    -- row itself stays compact and can't overflow into the Item column
    -- at narrow widths. Simplified in v0.8.0 (was
    -- "(+M: X bank, Y reagent, Z warband)" inline).
    local haveText = haveColor .. tostring(have) .. haveColorEnd
    if stashed > 0 then
        haveText = haveText .. ("  |cff888888(+%d)|r"):format(stashed)
    end
    row.have:SetText(haveText)

    -- Need column: the plain target number (secondary text tint so it
    -- doesn't compete with the mint cap value or the semantic status pill).
    row.need:SetText(("|cffCCCCCC%d|r"):format(data.need))

    -- Cap column value. Dim '--' when no cap; brand-mint when set. The
    -- number is the emphasized element in the row (per atrocity's rule:
    -- accent color goes on the value, not on the chrome).
    --
    -- When auto-purchase is ON but this item has no cap set, we swap the
    -- em-dash for a dim "skip" so the user can at-a-glance see which
    -- rows an auto run will pass over (QA-10 visual affordance).
    -- Plain text, not a glyph: WoW's stock fonts lack U+263D (moon),
    -- which was used here first and rendered as a placeholder box --
    -- the same bug class the v0.3 glyph fixes addressed for cog/log.
    --
    -- PT-1 v0.5: cap tint reflects the last-seen price when both are
    -- known. Above cap = pink (a buy would be rejected), at-or-below =
    -- simplified from the alpha4 three-state
    -- (pink / mint / muted-mint gated on TTL) to a binary pass/fail per
    -- user spec: cap is inclusive, so `seen > cap` is the ONLY fail state.
    -- Red text when we're priced out (seen > cap). Normal text otherwise
    -- (seen <= cap, or no seen data at all). TTL/staleness gating removed
    -- from this column -- the Last Seen column below has its own stale-
    -- dimming, so "this data is old" is communicated there instead.
    -- Rationale: if we haven't seen fresher data, the last known market
    -- signal is the best signal we have; hiding a priced-out state behind
    -- "data is stale" masks a real actionable UX signal.
    -- auto-purchase / defaultMaxCopper are gone.
    -- Cap cell has exactly two states: capped (mint "Ng", red "Ng"
    -- if last-seen exceeds cap) or unset (em-dash). No cap set means
    -- the row will buy at market price; the armed-flyout's amber
    -- 'No cap set' badge is the soft warning at buy time.
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

    -- Last Seen column (QA-11): read char.items[id].lastPrice off the
    -- flattened row entry (DB:GetSortedItems includes it; the provider
    -- Insert in Refresh must carry it through or this column can never
    -- paint -- code-review v0.2.0..HEAD finding 1).
    -- TTL dimming: entries older than settings.lastPriceTTL (default 24h)
    -- paint in a mid-gray between fresh (CCCCCC) and unset (555555) so
    -- a stale number doesn't read as current market at a glance.
    row._lastPrice = data.lastPrice
    if data.lastPrice and data.lastPrice.copper then
        local age = time() - (data.lastPrice.seenAt or 0)
        local staleCutoff = (ADDON.DB:Settings() and ADDON.DB:Settings().lastPriceTTL) or 86400
        local color = (age > staleCutoff) and "777777" or "CCCCCC"
        -- #g#s precision (silver-drop for column space). Copper is
        -- available in the hover tooltip for exact values. Row's tight
        -- column budget can't fit "1219g 80s 66c" so we truncate to
        -- silver here; the toast (which has room) shows copper too.
        row.lastSeen:SetText(("|cff%s%s|r"):format(color, MoneyText(data.lastPrice.copper, "silver")))
    else
        row.lastSeen:SetText("|cff555555\226\128\148|r")
    end

    -- Debug log only on state change per item (bags/stashed/need). Reduces
    -- the log flood -- a single user action was previously printing every
    -- row's snapshot 3+ times. Now each row logs once when its numbers move.
    if ADDON.debug then
        MF._initRowLast = MF._initRowLast or {}
        local sig = ("%d/%d/%d"):format(have, stashed, data.need)
        if MF._initRowLast[data.itemID] ~= sig then
            MF._initRowLast[data.itemID] = sig
            print(("|cff98FF98[SC:debug]|r InitializeRow: id=%d bags=%d stashed=%d need=%d"):format(
                data.itemID, have, stashed, data.need))
        end
    end

    -- Short/ok state encoded on the left-edge accent bar. Colors
    -- match the semantic palette: muted-red for short, mint-green
    -- for stocked.
    local short = data.need - have
    if short > 0 then
        -- Palette.short (muted red used throughout the v0.7 palette)
        row.accent:SetColorTexture(0xe5/255, 0x62/255, 0x4a/255, 1)
    else
        -- Mint green -- matches the Have-column stocked color
        row.accent:SetColorTexture(0x4a/255, 0xde/255, 0x80/255, 1)
    end
    row.accent:Show()

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
    -- No-op Show on the stub; kept for parity
    -- with the surrounding cell-visibility resets.
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
    -- KBD-FIX (H4): every EditBox in the addon ClearsFocus on Hide
    -- so a hidden focused field never captures game-wide keys. Applies to
    -- the toolbar's addBox/countBox/priceBox equally.
    eb:HookScript("OnHide", function(self)
        if self:HasFocus() then self:ClearFocus() end
    end)
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
    f:SetSize(420, 400)  -- v0.7: shopping-list shape, down from 680x500
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    -- Resize bounds: hard floor at 420x400 (the default), no ceiling.
    -- Rationale: the compressed layout was designed at exactly 420x400 so
    -- shrinking below that would clip columns; growing above it just
    -- gives the item list more headroom, which is always fine. Removing
    -- the ceiling (previously 1200x1200) lets 4K users pull the window
    -- as tall as they want without hitting an arbitrary cap.
    if f.SetResizeBounds then
        f:SetResizeBounds(420, 400)  -- min-only; no max args = unbounded
    else
        f:SetMinResize(420, 400)
        -- SetMaxResize on legacy clients: pass huge values as a soft cap
        f:SetMaxResize(4096, 4096)
    end
    f:EnableMouse(true)
    -- Re-enable keyboard on the root frame. VERIFIED NEEDED, do not remove:
    -- (a) previous experiment (v0.3) broke typing into toolbar EditBoxes
    --     entirely when this was removed;
    -- (b) the OnKeyDown handler below (soft-select nav) needs the root
    --     frame to receive raw keystrokes when no editbox has focus.
    -- The known-bad interaction was the OnKeyDown handler leaving
    -- SetPropagateKeyboardInput(false) sticky on error paths, which
    -- fixes at the OnKeyDown level (single exit point + pcall).
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

    -- ESCAPE-SIDECAR-FIX (was here): sidecar cascade now
    -- lives inside the SetScript("OnHide", ...) below. The earlier attempt
    -- registered a HookScript here, but the SetScript further down in
    -- Build() then REPLACES the OnHide handler entirely (HookScript chains,
    -- SetScript overwrites), silently killing this hook. Reprise fix folds
    -- the Sidecar+SettingsDropdown Hide() calls into the SetScript body so
    -- every close path -- imperative MF:Hide(), X button, Close button,
    -- /clerk toggle, and Escape via UISpecialFrames -- runs the same
    -- cleanup atomically.
    -- KBD-FIX (H1): SetPropagateKeyboardInput is sticky per-frame,
    -- so every OnKeyDown MUST end with an explicit propagate call in
    -- BOTH branches. The previous shape used early `return`s after
    -- SetPropagateKeyboardInput(false), which meant any Lua error in the
    -- handled action (Stop, MoveSelectedItem, FocusRowCell) would leave
    -- propagate=false stuck -- swallowing every subsequent key game-wide.
    -- New shape: decide (consumed / not consumed), do the action inside a
    -- pcall, then set propagate exactly ONCE at the end via a single exit
    -- path. No `return` allowed inside this handler before the final line.
    f:SetScript("OnKeyDown", function(self, key)
        local consumed = false

        -- QA-10 kill-switch: Escape stops an active auto-purchase loop.
        if key == "ESCAPE" and ADDON.RestockLoop and ADDON.RestockLoop:IsActive() then
            consumed = true
            pcall(function() ADDON.RestockLoop:Stop("user_esc") end)

        -- Soft-select navigation (UP/DOWN/
        -- ENTER/ESCAPE while a row was ring-selected) is gone. Row
        -- reorder is mouse-only via the grip handle. Tab walks editors
        -- only. No arrow-key hierarchy.
        end

        -- SINGLE exit point. propagate=false if we handled the key (so the
        -- game's default binding for that key doesn't ALSO fire), else
        -- propagate=true so B opens bags, Enter opens chat, macros fire,
        -- etc. Never leaves the frame in a stuck-false state.
        self:SetPropagateKeyboardInput(not consumed)
    end)

    -- Keyboard hygiene on close. Two capture leaks exist if the window
    -- hides while something holds keyboard focus:
    --   1) A focused-but-hidden EditBox keeps capturing game-wide
    --      keystrokes -- typed text routes into an invisible field, so
    --      chat/hotbars/movement all go dead.
    --   2) A focused Add button leaves EnableKeyboard(true) +
    --      SetPropagateKeyboardInput(false) sticky on a hidden frame -
    --      same silent swallow class.
    -- This handler is the single choke point: Escape via UISpecialFrames,
    -- the X button, and /clerk toggle all end in frame:Hide(), so
    -- OnHide fires for every close path. Catches anything the normal
    -- blur paths missed (e.g. user clicks the X mid-edit).
    -- NOTE: MF:BlurAddButton is defined later in Build(); the closure
    -- resolves at call time, after Build has completed.
    f:SetScript("OnHide", function()
        -- Cascade close to Sidecar and
        -- SettingsDropdown FIRST, before any propagate/focus/edit cleanup,
        -- so those UIParent-parented panels never orphan when Escape hides
        -- the main frame. Both :Hide methods are idempotent no-ops when
        -- the panel isn't shown.
        if ADDON.SettingsDropdown and ADDON.SettingsDropdown.Hide then
            pcall(function() ADDON.SettingsDropdown:Hide() end)
        end
        if ADDON.Sidecar and ADDON.Sidecar.Hide then
            pcall(function() ADDON.Sidecar:Hide() end)
        end

        -- KBD-FIX (H1): force propagate back to true on close. The
        -- root frame keeps EnableKeyboard(true) even while hidden; if any
        -- OnKeyDown left propagate=false and the window was closed before
        -- the next keystroke could restore it, the frame becomes a silent
        -- keyboard sink for the whole game session. Explicit reset here
        -- guarantees the steady-state is propagate=true across every
        -- close path (X button, /clerk toggle, Escape via UISpecialFrames,
        -- addon reload). Idempotent -- safe on every OnHide.
        f:SetPropagateKeyboardInput(true)

        local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focused and focused.ClearFocus then focused:ClearFocus() end
        -- KBD-FIX (H2): call BlurAddButton UNCONDITIONALLY, not just
        -- when the focused flag is set. If the flag ever desynced from the
        -- actual EnableKeyboard/PropagateKeyboardInput state (Lua error in
        -- FocusAddButton, taint interruption, etc.), a guarded call would
        -- leak the sticky-false propagate state past close. BlurAddButton
        -- is idempotent -- safe to call when already blurred.
        if MF.BlurAddButton then MF:BlurAddButton() end

        -- V0.4: soft-select and drag must not survive across window
        -- close. Selection would repaint the wrong pooled row when
        -- reshown; a live drag ticker would keep polling the cursor
        -- forever with no visible marker.
        if MF._dragTicker then
            MF._dragTicker:Cancel(); MF._dragTicker = nil
        end
        MF._dragItemID = nil
        MF._dropIndex  = nil
        if MF._dragMarker then MF._dragMarker:Hide() end
        -- Reset any in-progress row inline editor. ScrollView rows are
        -- pooled and InitializeRow does NOT reset editor visibility, so
        -- without this a row closed mid-edit would reappear on next open
        -- with a stale empty editor floating over whichever item the
        -- pooled row now serves. The edit itself is discarded (focus was
        -- already cleared, so no blur-commit fires) -- consistent with
        -- closing a dialog mid-edit.
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
    headerSep:SetColorTexture(Palette.border[1], Palette.border[2], Palette.border[3], 1)
    headerSep:SetHeight(BORDER_SIZE)
    headerSep:SetPoint("BOTTOMLEFT", 0, 0)
    headerSep:SetPoint("BOTTOMRIGHT", 0, 0)
    PixelSnap(headerSep)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", header, "LEFT", 12, 0)
    title:SetText("|cff98FF98Stock|r|cffFFFFFFClerk|r")
    title:SetShadowOffset(0, 0)

    -- Version string (v0.7). Sits immediately to the right of the title,
    -- baseline-aligned, in a smaller/muted font so it reads as metadata
    -- rather than part of the wordmark. Pre-release builds (-alpha, -beta)
    -- get an amber tint so the tester can see at a glance they're not on
    -- a stable build.
    --
    -- Version comes from the .toc "Version:" line via GetAddOnMetadata so
    -- it auto-updates on every version bump. Falls back to empty string
    -- if metadata is missing (never should happen -- addon can't load).
    -- guard against unsubstituted packager
    -- keywords. If the addon is installed from raw source (git clone,
    -- GitHub "Download ZIP") instead of a packaged CurseForge release,
    -- the .toc still contains the literal string "@project-version@"
    -- because only the BigWigsMods packager substitutes it at build
    -- time. Detect the raw keyword and show "dev" in muted grey rather
    -- than leaking packager syntax to the header.
    local rawVersion = C_AddOns and C_AddOns.GetAddOnMetadata
                       and C_AddOns.GetAddOnMetadata("StockClerk", "Version") or ""
    local isUnsubstituted = rawVersion == "" or rawVersion:sub(1, 1) == "@"
    local versionText, versionColor
    if isUnsubstituted then
        versionText = "dev"
        versionColor = "|cff888888"
    else
        -- The packager substitutes @project-version@
        -- with the git tag verbatim, and our tags already start with "v"
        -- (e.g. "v0.7.0"). Prepending another "v" would produce
        -- "vv0.7.0". Only prepend if the raw version doesn't already
        -- lead with "v".
        if rawVersion:sub(1, 1) == "v" or rawVersion:sub(1, 1) == "V" then
            versionText = rawVersion
        else
            versionText = "v" .. rawVersion
        end
        local isPrerelease = rawVersion:match("%-alpha") or rawVersion:match("%-beta")
        versionColor = isPrerelease and "|cffFFAA00" or "|cff888888"
    end
    local versionLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionLabel:SetPoint("LEFT", title, "RIGHT", 6, -1)  -- -1 to baseline-align vs the Large title
    versionLabel:SetText(versionColor .. versionText .. "|r")
    versionLabel:SetShadowOffset(0, 0)

    -- Close X button in the header (atrocity's aesClose recipe, WoW-adapted).
    -- Uses a font-string "×" since we don't have the atrocity texture; the
    -- shape is functionally the same and it snaps to pixels cleanly.
    local closeX = CreateFrame("Button", nil, header)
    closeX:SetSize(36, 28)  -- v0.7: enlarged from 28x22 for easier click targeting
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

    -- V0.7: single hamburger button replaces the previous cog + log button
    -- pair. It toggles the merged Sidecar (Settings + Activity in one
    -- flyout panel; see UI/Sidecar.lua, Phase C). Until Sidecar lands the
    -- click is a no-op stub -- the button is still drawn so header
    -- proportions are already correct when Sidecar wiring goes in.
    --
    -- Sizing bumped 22 -> 26 for parity with the enlarged close X target.
    -- Glyph is three drawn mint bars (WoW's stock fonts don't include
    -- U+2261, and SetColorTexture rectangles tint cleanly on hover).
    local hamburgerBtn = CreateFrame("Button", nil, header)
    hamburgerBtn:SetSize(26, 24)
    hamburgerBtn:SetPoint("RIGHT", closeX, "LEFT", -2, 0)
    local hamburgerGlyph = {}
    for i = 1, 3 do
        local bar = hamburgerBtn:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(0.85, 0.85, 0.85, 1)
        bar:SetSize(14, 2)
        bar:SetPoint("CENTER", 0, 4 - (i - 1) * 4)
        hamburgerGlyph[i] = bar
    end
    hamburgerBtn:SetScript("OnEnter", function(self)
        for _, b in ipairs(hamburgerGlyph) do
            b:SetColorTexture(Palette.brand[1], Palette.brand[2], Palette.brand[3], 1)
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Settings & Activity")
        GameTooltip:Show()
    end)
    hamburgerBtn:SetScript("OnLeave", function()
        for _, b in ipairs(hamburgerGlyph) do
            b:SetColorTexture(0.85, 0.85, 0.85, 1)
        end
        GameTooltip:Hide()
    end)
    hamburgerBtn:SetScript("OnClick", function(self)
        -- Stub: log to chat so the tester can confirm the button
        -- wires. Phase C replaces with ADDON.Sidecar:Toggle(self).
        if ADDON.Sidecar and ADDON.Sidecar.Toggle then
            ADDON.Sidecar:Toggle(self)
        elseif ADDON.SettingsDropdown and ADDON.SettingsDropdown.Toggle then
            -- Fallback during phased build: hamburger opens the old
            -- Settings dropdown until Sidecar (Phase C) is in place.
            ADDON.SettingsDropdown:Toggle(self)
        end
    end)
    MF._hamburgerBtn = hamburgerBtn
    -- Back-compat aliases so existing code that pokes at _cogBtn / _logBtn
    -- still finds a real frame during the phased v0.7 rollout.
    MF._cogBtn = hamburgerBtn
    MF._logBtn = hamburgerBtn

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
    -- scope: itemID-only. Item name resolution is deferred to a
    -- future release (see Dev/NOTES QA-2 backlog) because Blizzard's API
    -- returns non-deterministic matches when a name maps to multiple
    -- itemIDs (rank 1/2/3 craft variants, event duplicates), and there's
    -- no addon-facing enumerate-by-name endpoint to disambiguate.
    -- Numeric-only input avoids the ambiguity entirely.
    -- v0.7: compact widths for the 420px main-frame layout. Item ID box
    -- shrunk 240 -> 130 (item IDs are 5-7 digits; 130 comfortably fits
    -- 8-digit input and the placeholder "e.g. 212283"). Target 100 -> 60,
    -- Price Cap 120 -> 80. "Price Cap / Unit" label shortened to "Cap"
    -- (the /unit context is documented in the tooltip and the CHANGELOG).
    local addEB   = MakeEditBox(toolbar, "Item ID", 130, true, 8, "e.g. 212283")
    local countEB = MakeEditBox(toolbar, "Target",   60, true, 5, "20")
    local priceEB = MakeEditBox(toolbar, "Cap",      80, true, 7, "none")
    local addBox   = addEB.editBox
    local countBox = countEB.editBox
    local priceBox = priceEB.editBox

    addEB:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 12, -4)
    countEB:SetPoint("LEFT", addEB, "RIGHT", 12, 0)
    priceEB:SetPoint("LEFT", countEB, "RIGHT", 12, 0)

    local addBtn = CreateFrame("Button", nil, toolbar)
    addBtn:SetSize(72, 22)  -- v0.7: 96 -> 72 for compressed toolbar
    addBtn:SetPoint("LEFT", priceEB, "RIGHT", 10, -6)
    StyleButton(addBtn)
    local addBtnText = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addBtnText:SetPoint("CENTER")
    addBtnText:SetText(L.BTN_ADD_ITEM or "Add Item")
    addBtnText:SetTextColor(1, 1, 1, 1)

    local function DoAdd()
        local raw = addBox:GetText()
        if not raw or raw == "" then return end
        -- ItemID-only path. Strict validation: reject anything that isn't
        -- a positive integer, including item links (users can still
        -- Shift-click into chat, extract the numeric id, and paste it).
        -- Full 'paste an item link and extract the id' UX is v0.3 work.
        local itemID = tonumber(raw)
        if not itemID or itemID <= 0 or math.floor(itemID) ~= itemID then
            MF:SetStatus("|cffff8888Item ID must be a number (e.g. 212283)|r")
            return
        end
        local need = tonumber(countBox:GetText()) or 20
        -- Whole-gold input only. SetNumeric in MakeEditBox already
        -- prevented non-digit keystrokes; convert to copper here since
        -- storage is in copper.
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
            ADDON.DB:SetItem(resolvedID, need, maxPriceCopper, "user")
            ADDON.Inventory:Invalidate()
            if ADDON.Log then
                ADDON.Log:Emit("add", resolvedID, {
                    name       = name,
                    need       = need,
                    capCopper  = maxPriceCopper,
                })
            end
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

    -- KBD-FIX (H2): same single-exit shape as the root frame's
    -- OnKeyDown. Previous shape had early `return`s that could leave
    -- SetPropagateKeyboardInput(false) sticky if DoAdd() or the deferred
    -- Tab callback threw. Wrap all actions in pcall and set propagate
    -- exactly once at the end. If the focused-flag ever desyncs from
    -- the real EnableKeyboard state, force-blur so we recover cleanly
    -- instead of silently eating keystrokes.
    addBtn:SetScript("OnKeyDown", function(self, key)
        if not MF._addBtnFocused then
            -- Desync recovery: the flag is off but we're still receiving
            -- key events, which means EnableKeyboard(true) is stuck on.
            -- Force-blur to restore steady state, then let this key
            -- propagate to game bindings normally.
            pcall(function() MF:BlurAddButton() end)
            self:SetPropagateKeyboardInput(true)
            return
        end

        local consumed = (key == "TAB" or key == "ENTER" or key == "SPACE" or key == "ESCAPE")

        if key == "TAB" then
            -- Defer BOTH the blur and the focus transfer by one frame
            -- so the current Tab keystroke is fully consumed by this
            -- OnKeyDown and doesn't double-hop into the newly-focused
            -- control.
            local shift = IsShiftKeyDown()
            C_Timer.After(0, function()
                pcall(function()
                    MF:BlurAddButton()
                    if shift then
                        if priceBox then priceBox:SetFocus() end
                    else
                        -- Forward from Add button goes into the list;
                        -- wrap back to addBox if the list is empty.
                        if not MF:TabToFirstRowCell() then
                            if addBox then addBox:SetFocus() end
                        end
                    end
                end)
            end)
        elseif key == "ENTER" or key == "SPACE" then
            pcall(function() DoAdd() end)
            -- DoAdd clears the editbox focuses on success. Keyboard
            -- focus stays on the Add button (so Shift+Tab back to Price
            -- Cap works) -- safe now that unhandled keys propagate.
        elseif key == "ESCAPE" then
            pcall(function() MF:BlurAddButton() end)
        end

        -- SINGLE exit point. Same discipline as the root OnKeyDown.
        self:SetPropagateKeyboardInput(not consumed)
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

    -- =====================================================================
    -- quick-add via shift-click / drag-and-drop / focused link
    -- =====================================================================
    -- Three entry points, all landing on the same "fill the box with the
    -- item ID and let the user press Enter" path. Zero conflict with
    -- chat link insertion because each hook is scoped to the addBox
    -- itself, never global:
    --
    --   1. Shift-click ON addBox      : OnMouseUp checks cursor for a held
    --                                    item, drops its ID in the box.
    --   2. Drag-and-drop onto addBox  : OnReceiveDrag reads the same cursor,
    --                                    identical behavior.
    --   3. Shift-click any item link  : addBox opts into WoW's focused-
    --      while addBox is focused      editbox link-insertion routing via
    --                                    :SetHyperlinksEnabled + the hook
    --                                    below. Chat's own link routing is
    --                                    unaffected because when addBox is
    --                                    focused it OWNS the insertion.
    --
    -- All three deliberately do NOT commit -- they only fill the field.
    -- Commit remains the user pressing Enter, matching the addon's
    -- commit-on-Enter/Tab pattern (see Dev/NOTES 3.4a for the revisit
    -- checkpoint on this UX choice).
    -- =====================================================================

    -- Extract an itemID from whatever WoW says the cursor currently holds.
    -- Returns nil if the cursor holds nothing item-shaped. Item link path
    -- reuses the resolver's parsing so cursor-provided links and typed
    -- links go through the same regex.
    local function CursorItemID()
        local kind, arg1, arg2 = GetCursorInfo()
        if kind == "item" then
            -- Blizzard's cursor API returns ("item", itemID, itemLink).
            -- On some 11.x betas arg1 was a link string instead of an ID;
            -- handle both to be robust across builds.
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

    -- Drop an itemID into addBox and steer focus so the user's next Enter
    -- commits. Also clears the cursor so a held item doesn't linger
    -- (mirrors what happens when you drop an item into any Blizzard box).
    local function StampAddBox(itemID)
        if not itemID then return end
        addBox:SetText(tostring(itemID))
        addBox:SetFocus()
        -- Defer HighlightText by one frame: SetFocus queues a focus
        -- transfer, and on some clients calling HighlightText in the
        -- same tick as SetFocus hits before focus actually lands and
        -- becomes a no-op. C_Timer.After(0, ...) is the standard
        -- "next frame" idiom in the WoW client.
        C_Timer.After(0, function()
            if addBox:HasFocus() then addBox:HighlightText() end
        end)
        if ClearCursor then ClearCursor() end
        MF:SetStatus(("Quick-add: item %d (press Enter to add)"):format(itemID))
    end

    -- Shift-click quick-add on the Add box
    -- has been retired. It had unresolved edge cases (fired at wrong
    -- times, interacted poorly with other WoW UI's shift-click handling)
    -- and drag-and-drop covers the same intent more reliably. Container
    -- OnMouseUp now only does the focus fallthrough; the shift-click
    -- cursor-stamp branch is removed.
    --
    -- Drop-target enablement stays: EnableMouse + RegisterForDrag so the
    -- container and the editbox itself accept dropped items.
    -- IMPORTANT: use HookScript, not SetScript, on the container.
    -- StyleEditBoxContainer (above) already installs HookScripts on
    -- OnEnter/OnLeave for the border hover animation; a SetScript would
    -- blow them away. HookScript is additive.
    local dropTarget = addEB.container or addBox
    dropTarget:EnableMouse(true)
    dropTarget:RegisterForDrag("LeftButton")
    dropTarget:HookScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        -- Click on the box (or its container padding) focuses the input.
        -- No modifier branches: shift-click quick-add is retired.
        addBox:SetFocus()
    end)
    dropTarget:HookScript("OnReceiveDrag", function()
        local id = CursorItemID()
        if id then StampAddBox(id) end
    end)

    -- The container's OnReceiveDrag never fires
    -- because the EditBox itself sits on top of the container in the
    -- mouse-hit stack; when the user drops an item on the visual box,
    -- WoW routes OnReceiveDrag to the topmost mouse-enabled frame
    -- (addBox, the EditBox), NOT the container underneath. StyleEditBox-
    -- Container calls container:EnableMouse(true), but the EditBox is
    -- always mouse-enabled by default and paints in front. Register the
    -- drop handler directly on the EditBox so drops actually stamp.
    --
    -- Keep the container handler too so drops on the 1-2px border ring
    -- outside the EditBox's hitbox still work.
    addBox:RegisterForDrag("LeftButton")
    addBox:HookScript("OnReceiveDrag", function()
        local id = CursorItemID()
        if id then StampAddBox(id) end
    end)

    -- The ChatEdit_InsertLink hook that
    -- allowed shift-clicking an item link into a focused addBox is also
    -- retired. Same rationale as the container hook above: unreliable in
    -- practice, drag-and-drop covers the same intent, and typing/pasting
    -- an item ID still works. Removing the hook entirely (rather than
    -- leaving it wired but silent) avoids polluting other addons'
    -- shift-click link flows when Stock Clerk's add box happens to be
    -- focused in the background.

    -- Drop-zone visual affordance (Option A from grill): 1px mint outline
    -- that thickens (2px) when the cursor holds an item, signalling
    -- "you can drop here". CURSOR_CHANGED fires on every cursor state
    -- transition (pickup, drop, hover-target change) so it covers what
    -- we need without polling OnUpdate every frame.
    -- NOTE: CURSOR_UPDATE is NOT a real WoW event on retail Midnight.
    -- Early alpha builds registered it defensively and threw at Show()
    -- time; only CURSOR_CHANGED exists.
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

    -- Tooltip on the addBox container so first-time users discover the
    -- drag path without a wall of on-screen text. Shift-click was retired
    -- in alpha5 (see SHIFT-CLICK-KILL above), so the copy now names the
    -- surviving entry points only.
    --
    -- the container's OnEnter only fired
    -- when the cursor was over the ~3-6px gap between the editbox's edge
    -- and the container's edge, because the EditBox sitting on top of
    -- the container ate the mouse hover event for the entire interior.
    -- Users experienced this as a tooltip that only appeared on a
    -- "very precise edge" of the input. Mirror the same handler onto
    -- the EditBox itself so the tooltip fires no matter which region
    -- of the input rectangle the cursor is over. The tooltip is still
    -- anchored to dropTarget (the container) so its screen position
    -- doesn't jump around depending on where inside the box the cursor
    -- entered.
    -- HookScript (not SetScript) preserves the border-hover animation
    -- that StyleEditBoxContainer already installed on OnEnter/OnLeave.
    -- ANCHOR_TOP places the tooltip
    -- flush against the top edge of dropTarget. On very tight vertical
    -- layouts (or when the user's cursor drifts upward slightly), the
    -- rendered tooltip rectangle overlaps the top edge of the addBox
    -- container -- so the cursor hits the tooltip surface instead of
    -- addBox, which registers as "left addBox" and fires the OnLeave
    -- hide. The tooltip then vanishes, cursor is over addBox again,
    -- OnEnter fires, tooltip reappears -- classic show/hide flicker
    -- loop. Fix: anchor the tooltip manually with a 4px vertical gap so
    -- there's no overlap between the tooltip rectangle and dropTarget.
    local function showAddBoxTooltip()
        GameTooltip:SetOwner(dropTarget, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOM", dropTarget, "TOP", 0, 4)
        GameTooltip:SetText(L.ADDBOX_TOOLTIP or
            "Type an item ID or drag an item from your bags.",
            1, 1, 1, 1, true)
        GameTooltip:Show()
    end
    local function hideAddBoxTooltip()
        -- Only hide if the cursor has left BOTH the container and the
        -- editbox -- otherwise moving the mouse from the border area
        -- onto the input surface would blink the tooltip out and back.
        if not dropTarget:IsMouseOver() and not addBox:IsMouseOver() then
            GameTooltip:Hide()
        end
    end
    dropTarget:HookScript("OnEnter", showAddBoxTooltip)
    dropTarget:HookScript("OnLeave", hideAddBoxTooltip)
    addBox:HookScript("OnEnter", showAddBoxTooltip)
    addBox:HookScript("OnLeave", hideAddBoxTooltip)

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
    -- v0.7: shortened for the 420px layout. "Click 'x' to remove" dropped
    -- since trash-on-hover is a discovered affordance, not something the
    -- hint needs to spell out. "Click a value to edit" tightened.
    -- shift-click quick-add on the Add box is
    -- retired (SHIFT-CLICK-KILL above). "Shift+Click to link" here still
    -- refers to shift-clicking a ROW to paste an item link into chat --
    -- that path is untouched -- but rewording to name the concrete
    -- gesture rather than lean on the raw modifier name.
    hint:SetText("|cff6a6a6aShift+Click a row to link \194\183 Click a value to edit \194\183 Row-click (AH open) to search|r")

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
    -- -- Every numeric column right-aligns on its own right edge; headers
    -- match. See row layout above for the -212/-160/-100/-30 edges.
    -- Need cell has a -6 internal inset for the value, so its header sits
    -- at (cell_right - 6) to line up perfectly above the digits.
    MakeHeader("Item", "left",    36)     -- left edge + 24 (icon + 12 pad)
    MakeHeader("Have", "right",   -212)   -- right-edge with Have text
    MakeHeader("Need", "right",   -166)   -- cell right -160 - 6 inset
    MakeHeader("Cap",  "right",   -106)   -- cell right -100 - 6 inset
    MakeHeader("Seen", "right",   -30)    -- Seen text right edge

    -- V0.7: "stuck above cap" filter chip — now ICON-ONLY (was a 150w text
    -- pill in v0.6). At the compressed 420 width there isn't room for a
    -- 150-pixel text chip in the headers strip; the funnel glyph is a
    -- universal filter affordance and hover-tooltip carries the meaning.
    --
    -- Icon: three thin mint bars stacked in a funnel shape (top widest,
    -- bottom narrowest). Same construction pattern as the hamburger button
    -- above -- WoW's stock fonts don't reliably ship a funnel glyph, and
    -- drawn rectangles tint cleanly on hover / ON state.
    --
    -- Position: tucked to the right of the "Item" header label on the
    -- LEFT side of the headers strip. Anchored to headers.LEFT + 62 so
    -- the icon stays put regardless of window width.
    local filterChip = CreateFrame("Button", nil, headers)
    filterChip:SetSize(18, 16)
    filterChip:SetPoint("LEFT", headers, "LEFT", 62, 0)
    filterChip:EnableMouse(true)

    local chipMint = { 0x98/255, 0xFF/255, 0x98/255 }

    -- Funnel glyph: three horizontal bars, widths 12/8/4, stacked vertically.
    local chipBars = {}
    local barWidths = { 12, 8, 4 }
    for i = 1, 3 do
        local bar = filterChip:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(chipMint[1], chipMint[2], chipMint[3], 0.55)
        bar:SetSize(barWidths[i], 2)
        bar:SetPoint("CENTER", 0, 4 - (i - 1) * 4)
        chipBars[i] = bar
    end

    -- Applies the current DB state to the chip's visuals: OFF = dim mint
    -- outline ("filter available"), ON = solid bright mint ("filter active").
    local function paintChip()
        local on = ADDON.DB:GetStuckOnly()
        local alpha = on and 1.0 or 0.55
        for _, b in ipairs(chipBars) do
            b:SetColorTexture(chipMint[1], chipMint[2], chipMint[3], alpha)
        end
    end

    filterChip:SetScript("OnClick", function()
        ADDON.DB:SetStuckOnly(not ADDON.DB:GetStuckOnly())
        paintChip()
        MF:Refresh()
    end)
    filterChip:SetScript("OnEnter", function(self)
        -- Brighten to full mint on hover regardless of ON/OFF state so
        -- the icon reads as "clickable".
        for _, b in ipairs(chipBars) do
            b:SetColorTexture(chipMint[1], chipMint[2], chipMint[3], 1)
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local on = ADDON.DB:GetStuckOnly()
        GameTooltip:SetText((on and "|cff98FF98Filter ON|r  " or "") ..
            (L.FILTER_STUCK_ONLY or "Show only: stuck above cap"), 1, 1, 1)
        GameTooltip:AddLine(L.FILTER_STUCK_TOOLTIP or
            "Hide items whose most recent seen price is at or under your cap.",
            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    filterChip:SetScript("OnLeave", function()
        paintChip()  -- return to persisted ON/OFF alpha
        GameTooltip:Hide()
    end)

    self.filterChip     = filterChip
    self._paintFilterChip = paintChip

    -- Paint immediately so the chip matches persisted state on first show,
    -- not just after the first refresh. Safe: DB is initialized in
    -- Core.lua's OnInitialize which fires strictly before MainFrame:Build.
    paintChip()

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
    footerSep:SetColorTexture(Palette.border[1], Palette.border[2], Palette.border[3], 1)
    footerSep:SetHeight(BORDER_SIZE)
    footerSep:SetPoint("TOPLEFT", 0, 0)
    footerSep:SetPoint("TOPRIGHT", 0, 0)
    PixelSnap(footerSep)

    -- Status bar spans from left inset to just before the Restock button
    -- (leftmost of the two footer buttons). Previous impl stopped at
    -- -100 which cleared Close but NOT the 140px Restock button, so
    -- longer status text (e.g. "Ready: 30 x Thalassian Phoenix Oil...")
    -- flowed BEHIND the buttons. Anchoring to the Restock button's left
    -- edge means the status never overlaps regardless of how long it is.
    local statusBar = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusBar:SetPoint("LEFT", 14, 0)
    statusBar:SetJustifyH("LEFT")
    statusBar:SetWordWrap(false)  -- one line; oversized text truncates instead of stacking
    self.statusBar = statusBar
    self._statusBarNeedsAnchor = true  -- deferred: restockBtn not built yet

    local closeBtn = CreateFrame("Button", nil, footer)
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("RIGHT", -12, 0)
    StyleButton(closeBtn)
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeBtnText:SetPoint("CENTER")
    closeBtnText:SetText(L.BTN_CLOSE or "Close")
    closeBtnText:SetTextColor(1, 1, 1, 1)
    closeBtn:SetScript("OnClick", function() MF:Hide() end)

    -- Phase B post-feedback rework: two-state button.
    --   idle    -> "Restock at AH"  (left-click Start; disabled if no AH open,
    --                                nothing short, or loop running elsewhere)
    --   active  -> "Stop restock"    (left-click Stop)
    -- The purchase-confirm UI is a separate flyout (self.confirmToast) that
    -- appears above this button when a plan is armed. Keeping BUY out of
    -- this button prevents accidental confirms from rapid double-clicks on
    -- "Restock at AH" during arm.
    local restockBtn = CreateFrame("Button", nil, footer)
    restockBtn:SetSize(140, 22)
    restockBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)

    -- Now that restockBtn exists, anchor statusBar's right edge to its
    -- left edge minus a small gap. This is the deferred setup flagged
    -- above; status text now cleanly stops before the button row.
    if self._statusBarNeedsAnchor then
        statusBar:SetPoint("RIGHT", restockBtn, "LEFT", -8, 0)
        self._statusBarNeedsAnchor = nil
    end
    StyleButton(restockBtn)
    local restockBtnText = restockBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    restockBtnText:SetPoint("CENTER")
    restockBtnText:SetTextColor(1, 1, 1, 1)
    restockBtn._label = restockBtnText
    restockBtnText:SetText("Restock at AH")

    restockBtn:SetScript("OnClick", function()
        local loop = ADDON.RestockLoop
        if not loop then return end
        if loop:IsActive() then
            loop:Stop("user_stop")
        else
            loop:Start()
        end
    end)

    restockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local loop = ADDON.RestockLoop
        if loop and loop:IsActive() then
            GameTooltip:SetText("Stop restock", 1, 1, 1)
            GameTooltip:AddLine("Ends the current walk. Any armed buy is discarded.", 0.7, 0.7, 0.7, true)
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
    restockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Motion scripts must be enabled explicitly for OnEnter/OnLeave to fire
    -- while the button is Disabled(). Without this, hovering the greyed
    -- Restock button silently does nothing -- no tooltip, no reason line.
    restockBtn:SetMotionScriptsWhileDisabled(true)

    self.restockBtn = restockBtn

    -- ---- Confirm/Summary flyout (above the restock button) ---------------
    -- The core of the post-feedback Phase B rework. This is a compact
    -- horizontal flyout that appears above the restock button in two
    -- distinct modes:
    --
    --   armed   -> plan info on the left, [Skip] + [Buy (Ns)] on the right
    --   summary -> loop-end recap in the middle, [Close] on the right
    --
    -- Buy has a 3s countdown before it accepts clicks so the pattern
    -- matches other WoW confirmations (release spirit, in-combat res).
    -- The button label reads "Buy (3s)" -> "Buy (2s)" -> "Buy (1s)" ->
    -- "Buy" (mint accent). Skip is always live -- it's the safe action.
    -- Right-click on the flyout body stops the whole loop.
    -- Anchor: BELOW the main frame's bottom edge (not above the restock
    -- button). Above-the-button placement overlapped the last list rows
    -- and the status bar. Below the frame keeps the flyout out of the
    -- shopping list entirely and puts the Buy button far from any row
    -- click surface, which is safer against misclicks too.
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
    -- Full 1px mint border, four edges
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
    local titleFS = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFS:SetPoint("TOPLEFT", 10, -6)
    titleFS:SetPoint("RIGHT", -160, 0)  -- leave room for two buttons
    titleFS:SetJustifyH("LEFT")
    titleFS:SetTextColor(1, 1, 1, 1)
    titleFS:SetWordWrap(false)   -- truncate long titles, don't wrap into sub

    local subFS = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
    local skipText = skipBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    skipText:SetPoint("CENTER")
    skipText:SetText("Skip")
    skipBtn:SetScript("OnClick", function()
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
    local primaryText = primaryBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
                MF._toastHandlers.onBuy()
            end
        elseif MF._toastMode == "summary" then
            MF:HideToast()
        end
    end)

    -- Right-click anywhere on the toast body = stop the loop. Backup for
    -- the button's own stop -- if the user's mouse is already up here they
    -- don't need to travel back down.
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
    self._toastSkip       = skipBtn
    self._toastPrimary    = primaryBtn
    self._toastPrimaryTxt = primaryText
    self._toastPrimaryFill= primaryFill
    self._toastMode       = nil
    self._toastHandlers   = nil
    self._toastArmReady   = false

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
-- Public entrypoint: coalesces refreshes so multiple triggers in the
-- same frame collapse into a single row-list rebuild. Every module
-- calls MainFrame:Refresh() freely; this schedules ONE _RefreshNow on
-- the next frame tick if one isn't already pending.
--
-- Why: pre-v0.7.0 debug traces showed Refresh() firing 3+ times per
-- user action (bag update + inventory recompute + AH callback + a
-- Sidecar checkbox toggle would all pile on). Each Refresh rebuilds
-- the DataProvider and re-InitializeRows every visible row. Cheap in
-- isolation, wasteful in aggregate. Coalescing preserves the
-- "any change refreshes" contract while collapsing the cost.
function MF:Refresh()
    if self._refreshPending then return end
    if not self.frame or not self.scrollBox then return end
    self._refreshPending = true
    C_Timer.After(0, function()
        self._refreshPending = false
        self:_RefreshNow()
    end)
end

-- Internal, non-coalesced refresh. Called by the coalescer above, and
-- available for the rare synchronous case where the caller has already
-- committed a state change and MUST see the row list reflect it
-- immediately (e.g. inline-editor commit before focusing the next cell).
function MF:_RefreshNow()
    if not self.frame or not self.scrollBox then return end

    if ADDON.debug then
        print("|cff98FF98[SC:debug]|r MainFrame:_RefreshNow() (frame shown: " .. tostring(self.frame:IsShown()) .. ")")
    end

    local items = ADDON.DB:GetSortedItems()

    -- (PT-3): apply the "stuck above cap" filter if the chip is on.
    -- Definition of "stuck": item has a cap AND a fresh (non-stale)
    -- lastPrice that EXCEEDS the cap. Items without a cap, without any
    -- lastPrice, or with only stale prices are excluded from the filtered
    -- view -- the user is explicitly asking "what's currently priced out",
    -- not "what's unknown or unpriced".
    local stuckOnly = ADDON.DB.GetStuckOnly and ADDON.DB:GetStuckOnly() or false
    if stuckOnly then
        local staleCutoff = (ADDON.DB:Settings() and ADDON.DB:Settings().lastPriceTTL) or 86400
        local nowT = time()
        local filtered = {}
        for _, it in ipairs(items) do
            if it.maxPrice and it.lastPrice and it.lastPrice.copper
               and it.lastPrice.seenAt
               and (nowT - it.lastPrice.seenAt) <= staleCutoff
               and it.lastPrice.copper > it.maxPrice then
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
        -- SkipLog = true: Refresh-generated state summaries (this and
        -- the two below) are not events. Without the guard, every list
        -- repaint would flood the activity log's status history with
        -- "N items tracked" lines and bury the buy/expense entries the
        -- log exists to preserve (code-review v0.2.0..HEAD finding 3).
        -- v0.6: friendlier empty-state copy when the list is non-empty
        -- but the filter has hidden everything.
        if stuckOnly then
            self.emptyText:SetText("|cff888888No items currently priced above cap. Click the filter chip to see the full list.|r")
            self.emptyText:Show()
            self:SetStatus("0 stuck items (filter active)", true)
        else
            self.emptyText:SetText(L.EMPTY_LIST)
            self.emptyText:Show()
            self:SetStatus("0 items tracked", true)
        end
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
            itemID      = it.itemID,
            name        = it.name,
            need        = it.need,
            maxPrice    = it.maxPrice,
            priceSource = it.priceSource, -- PT-1: "user"/"vendor"/"template" or nil; reserved for row-level UI in Wave 2
            lastPrice   = it.lastPrice,   -- { copper, seenAt, source }; feeds the Last Seen column
            _index      = i,
        })
    end

    -- Swap the provider. Passing RetainScrollPosition keeps the user's
    -- scroll offset stable across refreshes so restocking updates don't
    -- yank the list back to the top.
    self.scrollBox:SetDataProvider(newProvider, ScrollBoxConstants.RetainScrollPosition)
    self.dataProvider = newProvider

    if shortCount > 0 then
        self:SetStatus(("|cff98FF98%d items tracked|r  |cff888888|||r  |cfff87171%d short|r"):format(#items, shortCount), true)
    else
        self:SetStatus(("|cff98FF98%d items tracked|r  |cff888888|||r  |cff4ade80all stocked|r"):format(#items), true)
    end

    -- Pass nil so the button routes through Loop:PreviewShortfallCount
    -- (effective-have) instead of reusing this raw-bags count. Two
    -- shortCounts (display-vs-behavior) may disagree when the ledger
    -- holds unlooted purchases; that's the whole point of unifying the
    -- button's decision with the loop's.
    self:RefreshRestockBtn()
end

-- Post-feedback rework: two states on the button itself
-- (buy/skip live in the confirm flyout, see ShowArmedToast).
--   idle   -> "Restock at AH", enabled if AH open + something short + not looping
--   active -> "Stop restock",  always enabled
-- Hover on the disabled idle state gets a reason line -- see the OnEnter
-- handler which calls _RestockDisabledReason.
function MF:RefreshRestockBtn(shortCount)
    if not self.restockBtn then return end
    -- Route through Loop:PreviewShortfallCount so the button's enabled
    -- state uses the SAME math as Loop:BuildQueue. Historical bug:
    -- button was greyed (raw bags said 'stocked'), user clicked Restock
    -- Loop's BuildQueue used _EffectiveHave (ledger + bags) and saw
    -- '1 short' from a stale ledger entry, so the loop fired anyway.
    -- Now the button state and the loop's decision agree by construction.
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
        btn._label:SetText("Restock at AH")
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

-- Dock the main frame to the right edge of the AH frame IF the AH is
-- currently shown. No-op if the AH isn't up or the frame isn't shown.
-- Callable from OnAuctionHouseShow (auto-open path) or from a manual
-- /clerk-open-while-AH-is-already-up path, so the behavior is symmetric.
function MF:DockToAHIfOpen()
    local f  = self.frame
    local ah = _G.AuctionHouseFrame
    if not (f and ah and ah:IsShown()) then return end
    if self._docked then return end -- already docked, don't overwrite _preDockPos
    local point, _, _, x, y = f:GetPoint()
    self._preDockPos = { point = point, x = x, y = y }
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", ah, "TOPRIGHT", 1, 0)
    self._docked = true
    if ADDON.Sidecar and ADDON.Sidecar:IsShown() then
        ADDON.Sidecar:Toggle()  -- hide
        ADDON.Sidecar:Toggle()  -- show at new anchor
    end
end

-- ---------------------------------------------------------------------------
-- ConfirmToast API. Called from RestockLoop.
--   ShowArmedToast(plan, handlers)      arm confirm with countdown
--   ShowSummaryToast(summaryText)       loop-end recap with [Close]
--   HideToast()                          dismiss
--
-- handlers table: onBuy, onSkip, onStop -- all optional.
-- ---------------------------------------------------------------------------
local COUNTDOWN_SECONDS = 3  -- 3s buy-arm delay per feedback (release-spirit
                             -- Pattern). Skip is live immediately.

function MF:_StopToastCountdown()
    if self._toastTicker then
        self._toastTicker:Cancel()
        self._toastTicker = nil
    end
end

function MF:ShowArmedToast(plan, handlers)
    if not self.confirmToast then return end
    self:_StopToastCountdown()
    self._toastMode     = "armed"
    self._toastHandlers = handlers or {}
    self._toastArmReady = false

    -- Reset text bounds for armed mode (summary mode expands them; must
    -- return to 2-button layout width here so title/sub don't sit under
    -- the Skip button).
    self._toastTitle:ClearAllPoints()
    self._toastTitle:SetPoint("TOPLEFT", 10, -6)
    self._toastTitle:SetPoint("RIGHT", -160, 0)
    self._toastSub:ClearAllPoints()
    self._toastSub:SetPoint("TOPLEFT", self._toastTitle, "BOTTOMLEFT", 0, -1)
    self._toastSub:SetPoint("RIGHT", -160, 0)

    -- Title line: qty x item name (truncated to 22 chars for horizontal fit).
    -- Total spend on the sub line alongside the cap so both money values
    -- share a row -- keeps the first line dedicated to WHAT you're buying.
    local nm = plan.name or "?"
    if #nm > 22 then nm = nm:sub(1, 21) .. "\226\128\166" end  -- ellipsis
    self._toastTitle:SetText(("%d x |cffffffff%s|r"):format(plan.planQuantity or 0, nm))

    -- Sub line: total spend + cap. 'worst unit' was dropped -- cap is
    -- the actionable gate. No cap set gets amber tint so the user knows
    -- they're firing blind. Middle dot separator matches the Sidecar log.
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

    -- Buy button starts in countdown mode: disabled, mint fill off, label
    -- shows the remaining seconds. Ticker updates every 1s and unlocks
    -- when the countdown reaches 0.
    self._toastPrimary:Disable()
    self._toastPrimaryFill:Hide()
    self._toastPrimaryTxt:SetTextColor(0.78, 0.78, 0.78, 1)

    local remaining = COUNTDOWN_SECONDS
    self._toastPrimaryTxt:SetText(("Buy (%ds)"):format(remaining))

    self.confirmToast:Show()

    self._toastTicker = C_Timer.NewTicker(1.0, function()
        if self._toastMode ~= "armed" then return end
        remaining = remaining - 1
        if remaining > 0 then
            self._toastPrimaryTxt:SetText(("Buy (%ds)"):format(remaining))
        else
            -- Arm complete: enable, mint-fill on, brighten label.
            self._toastArmReady = true
            self._toastPrimaryTxt:SetText("Buy")
            self._toastPrimaryTxt:SetTextColor(0.95, 1.0, 0.95, 1)
            self._toastPrimary:Enable()
            self._toastPrimaryFill:Show()
            self:_StopToastCountdown()
        end
    end, COUNTDOWN_SECONDS)
end

function MF:ShowSummaryToast(summary)
    if not self.confirmToast then return end
    self:_StopToastCountdown()
    self._toastMode     = "summary"
    self._toastHandlers = nil
    self._toastArmReady = false

    local title = summary.title or "Restock done"
    local sub   = summary.sub or ""
    self._toastTitle:SetText(title)
    self._toastTitle:SetTextColor(1, 1, 1, 1)
    self._toastSub:SetText(sub)
    self._toastSub:SetTextColor(0.78, 0.78, 0.78, 1)

    -- Summary mode has only ONE button (Close, ~90w) instead of two.
    -- Grow the text region to fill the reclaimed space so long summary
    -- messages (like 'Restock complete - bought 30 for 1219g 50s') don't
    -- wrap under the button. The armed layout resets these on next
    -- ShowArmedToast via its title/sub setup.
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

    -- Close countdown: 6s, ticks each second. Matches the Buy countdown
    -- pattern so the summary toast feels part of the same UI vocabulary.
    local SUMMARY_CLOSE_SECONDS = 6
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
    if self._summaryAutoHide then
        self._summaryAutoHide:Cancel(); self._summaryAutoHide = nil
    end
    self._toastMode     = nil
    self._toastHandlers = nil
    self._toastArmReady = false
    if self._toastSkip then self._toastSkip:Show() end
    if self.confirmToast then self.confirmToast:Hide() end
end

-- Set the footer status text. Also mirrors the message into the activity
-- log so the sidecar reads as a persistent history of the same status
-- stream the footer shows -- "Searching AH for...", "Cheapest: 100g",
-- "Cap for X set to 50g", loop tick messages, etc. This is intentional:
-- the log is meant to be the durable record of the same human-readable
-- feedback that used to only exist for a fraction of a second in the
-- footer before the next status overwrote it. Empty strings are still
-- passed to the footer (to clear it) but skipped in the log.
function MF:SetStatus(text, skipLog)
    if self.statusBar then self.statusBar:SetText(text or "") end
    if not skipLog and text and text ~= "" and ADDON.Log and ADDON.Log.Emit then
        ADDON.Log:Emit("status", nil, { text = text })
    end
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
-- ---------------------------------------------------------------------------
-- Reorder
--
-- Shopping list order = restock walk order (see DB.lua GetSortedItems).
-- Reorder is mouse-only: drag the grip handle on the row's far left. On
-- drop, compute the target index from the cursor Y against visible rows
-- and call DB:ReorderItems.
--
-- the previous keyboard soft-select model (Tab
-- into a 1px mint ring, UP/DOWN to reorder, Enter to drop into Need,
-- Escape to clear) is gone. It was the root cause of every alpha5
-- keyboard-nav bug. The grip handle already communicates drag-to-reorder
-- intuitively; Tab walks editors (Need, Cap) only.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Drag-to-reorder (mouse)
--
-- OnDragStart on the grip captures the itemID and shows a thin mint
-- insertion-line texture. OnUpdate polls cursor Y each frame, compares
-- against each visible row's midpoint, and repositions the line at the
-- nearest gap. OnDragStop resolves the gap to a target index, calls
-- DB:ReorderItems with the full permutation, Refreshes, and hides the
-- line. Dragging over empty space above/below the visible rows resolves
-- to top / bottom respectively.
-- ---------------------------------------------------------------------------

local function EnsureInsertionMarker(self)
    if self._dragMarker then return self._dragMarker end
    local m = self.scrollBox:CreateTexture(nil, "OVERLAY", nil, 7)
    m:SetColorTexture(Palette.brand[1], Palette.brand[2], Palette.brand[3], 1)
    m:SetHeight(2)
    m:Hide()
    self._dragMarker = m
    return m
end

-- Walk the visible rows and find the gap closest to cursorY. Returns
-- targetDataIndex in [1, size+1]: 1 = before first row, size+1 = after
-- last row. Uses row midpoints so drops slightly above a row's midline
-- insert before it, slightly below insert after.
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

-- Move the insertion marker to the gap at targetIndex. Marker sits at
-- the top edge of the row currently at targetIndex, or the bottom edge
-- of the last row if targetIndex == size+1.
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
    -- Poll cursor each frame while dragging. UIParent's effective scale
    -- converts raw cursor coords (which come back in native pixels) to
    -- the UI's coordinate space.
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

    -- Build the new order: current provider order with movedID removed,
    -- reinserted at target. target was resolved against the pre-move
    -- provider, so if the row moves DOWN we adjust the insert point by
    -- one (the removal shifted everything after it up).
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
-- tab semantics: forward Tab into the list from the toolbar lands
-- on soft-select of the first row (NOT its Need cell). From there:
--   Tab again -> Need cell of row 1 (existing per-row Need/Price chain)
--   Up/Down   -> reorder
--   Enter     -> Need cell
--   Escape    -> clear selection
-- Reverse Tab (Shift+Tab) from the toolbar lands on the last row's
-- price cap as before, so keyboard users who already know the flow
-- aren't slowed down.
-- forward wrap from the toolbar's
-- Add button lands on row 1's Need editor directly. No ring detour.
function MF:TabToFirstRowCell()
    if not self.dataProvider or self.dataProvider:GetSize() == 0 then
        return false
    end
    self:FocusRowCell(1, "need")
    return true
end

-- Reverse Tab from Item field lands
-- on the last row's Cap editor directly. No ring, no scroll-then-paint
-- dance -- ScrollToElementDataIndex followed by FocusRowCell is enough
-- because FocusRowCell uses scrollBox:FindFrame(elementData) which
-- resolves reliably by data reference (unlike EnumerateFrames-based
-- ring painting, which raced with row materialization).
function MF:TabToLastRowCell()
    if not self.dataProvider or self.dataProvider:GetSize() == 0 then
        return false
    end
    local size = self.dataProvider:GetSize()
    self:FocusRowCell(size, "price")
    return true
end

-- Tab handler called from a row's inline editor. `cell` is "need" or
-- "price" (which cell the user is currently in); `dir` is +1 for forward
-- Tab or -1 for Shift+Tab. Walks the row-major sequence.
--
-- two stops per row (Need, Cap). Row
-- boundaries jump straight to the neighbor row's editor -- no ring
-- detour. This matches how every commercial row-editable UI works
-- (Excel, Sheets, Airtable, Linear): Tab walks editable inputs; the
-- selection indicator is a mouse/arrow-key concept, not a Tab concept.
function MF:TabFromCell(row, cell, dir)
    if not row or not row._itemID or not self.dataProvider then return end
    -- Find this row's data index.
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
        else -- cell == "price"
            if idx < size then
                self:FocusRowCell(idx + 1, "need")
            else
                -- End of list wraps forward to addBox.
                if row.priceEdit and row.priceEdit:HasFocus() then row.priceEdit:ClearFocus() end
                if self.addBox then self.addBox:SetFocus() end
            end
        end
    else
        -- Backward Tab.
        if cell == "price" then
            self:FocusRowCell(idx, "need")
        else -- cell == "need"
            if idx > 1 then
                self:FocusRowCell(idx - 1, "price")
            else
                -- Top of list wraps backward to the Add button.
                if row.needEdit and row.needEdit:HasFocus() then row.needEdit:ClearFocus() end
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
    -- If the AH is already up (user turned Auto-Open off, then hit /clerk
    -- while at the AH), dock now. OnAuctionHouseShow already fired before
    -- this call so it can't dock us -- we have to do it from the Show path.
    self:DockToAHIfOpen()
end

function MF:Hide()
    -- Cleanup for SettingsDropdown
    -- and Sidecar (both UIParent-parented, so they don't inherit our
    -- Hide) now lives on the frame's OnHide hook. That way EVERY
    -- close path -- imperative (this method), Escape (UISpecialFrames),
    -- X button, Close button, /clerk toggle -- runs the same cleanup.
    -- This method just triggers the frame's Hide; the hook does the rest.
    if self.frame then self.frame:Hide() end
end

function MF:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show(false)
    end
end
