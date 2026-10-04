# StockClerk — UI style rules

Suite-wide rules (colour tokens, controls, accessibility, words, chat) live in
the "Suite style guide" doc in the WoW Addons project; this file holds StockClerk
's specifics and wins only where it names an exception.

StockClerk should feel like a real shopping list: pocket-sized, efficient,
minimal without being brutalist. Every pixel and every control earns its
place. New UI follows these rules; the helpers named here already exist in
`UI/MainFrame.lua` (exported on `ADDON.MainFrame` where other files need them).

## Space
- Rows 24px, icons 18px with a 1px quality-coloured border (black while the
  item loads). Header 26px, toolbar 30px, column headers 20px, footer 30px.
- No labels above inputs: the placeholder names the field, a hover tooltip
  explains it. Help text lives in tooltips, never in a standing line.
- If a control is rarely used, it goes in the side panel, not the main window.

## Look
- One window fill (`Palette.bgDark`); regions are separated by 1px black
  borders and the faint `bandTint` strip, never by extra shades.
- Text and status colours: the suite tokens only (white, soft 0.74, muted
  `8C8C8C`, faint `666666` for decoration, amber `FFB84D`, red `FF8888`).
- Accent (`Palette.brand`): hover, focus, "on", marks. Mint `#98FF98` in the
  Mine view, warband blue `#5AA9FF` in the Warband view (`MF:SetView`
  recolours the table in place). Deposit marks are blue in either view. The
  mint "Stock" in the title never changes. Colour is never the only cue.
- Buttons: `StyleButton` only (flat fill, band, hover wash, press flash, black
  ring; label via `SetText`, grey when disabled). No Blizzard button or
  checkbox templates.
- Lines: `AddRule` (one edge) and `AddBlackBorder` (ring); never hand-built.
- Side panels: `MF.DockedPanel(name)` + `MF:ShowPanel(panel)` (right edge,
  window height, one at a time).
- Icons: drawn bars via `DrawGlyph`, never font glyphs. Header icons via
  `HeaderIcon` (grey at rest, mint on hover, one-line tooltip).
- Checkboxes: 16px flat well + black border, mint square when on, label is
  part of the click area.
- Editable spots show a faint sunken well (`Palette.fieldFill`); the border
  fades to mint on hover/focus (`AttachBorderAnimator`).
- All fills use `SetColorTexture` (White8x8 + vertex colour renders
  transparent on retail).

## Type
- Three font objects, all white: `StockClerkFontSmall` (10), `StockClerkFont`
  (12), `StockClerkFontLarge` (16), plus grey `StockClerkFontDisabled` for
  disabled buttons. Never `GameFont*`. Face: Expressway via LibSharedMedia
  when available, else bundled Barlow Semi Condensed. Any window's Build
  calls `MF.ApplyFontFace()` first.
- Row text uses the Small size. Exception: the multi-line boxes (`/clerk
  log`, bulk import) use WoW's chat font for long pasted text.

## Words
- Sentence case. Plain words a player uses: no "loop", "ledger", "stuck",
  "queue", "payload", reason codes or `?`.
- Item names in running text are `[Bracketed]` and quality-coloured where
  colour is allowed (the side panel), plain where text gets copied
  (`/clerk log`).
- Timestamps are bracketed: `[14:24]` in the feed, `[14:24:10]` in the log.
- Footer = feedback on the last action; it stays until the next one. No
  centre-screen alert text. During a restock it is the checkout bar (item
  and price over total and progress or amber warnings; Skip; Buy in the
  Restock button's place, same right edge) and the end-of-run receipt
  lands there. No flyouts or popups for a run.
- Run state lives in the list: a mark in the grip's slot (dot queued,
  mint chevron current, mint check done, grey/amber/red dash for skipped,
  over cap, not bought), its detail in the grip tooltip. Marks last until
  the AH or bank closes.

## Behaviour
- Tooltips: `HookScript` (never `SetScript`) on styled buttons, or the hover
  wash dies. Anchor so the tooltip can't cover its own trigger.
- Any EditBox clears focus when hidden, and never calls
  `EnableKeyboard(true)`: a hidden focused box swallows every key game-wide.
- Every `OnKeyDown` sets `SetPropagateKeyboardInput` exactly once, last.
- Log anything a player or support would want to see: activity for players,
  detail for support, trace only via `/clerk debug` (see `Log.lua`).
