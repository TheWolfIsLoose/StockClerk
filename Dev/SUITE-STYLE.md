# Suite style guide

> Shared copy: the same file lives in each addon's `Dev/` folder. Edit the master, not this copy.

One visual and verbal language for **PickupGroup**, **StockClerk**, **SharedMedia: Tones**, **TalentKeeper** and any addon after them. Each repo's `Dev/STYLE.md` holds only that addon's specifics and points here. When this guide and an addon's notes disagree, this guide wins unless the addon's notes name the exception.

Reference for accessibility: WCAG 2.2 (https://www.w3.org/TR/WCAG22/).

## Principles

- **Pocket-sized and efficient.** Every pixel and control earns its place. Small windows (players run 4K), rows 24px, no decorative chrome.
- **Work with Blizzard's UI, don't replace it.** Sit inside or beside Blizzard's frames; leave their pieces working.
- **One footprint, no pop-ups.** Everything an addon does beside a Blizzard window lives in its own side panel. Anything that would open a new window to interact with (import, rename, new group, options, confirmations, alerts) morphs the side panel instead: the panel swaps its view, grows or slides to fit, and returns when done. Short, quiet transitions are welcome (they still stop within 5 s, 2.2.2). Separate windows stay only for long copyable text (the log) and things that must work without the host window open (see Prompt strips). Something the player must hear about while the panel is closed gets one chat line, with the full explanation and the choice waiting in the panel (see Clash prompt).
- **All controls together, at the top.** A panel's controls live in one place, never split between top and bottom. Order top to bottom: header, controls, the state (what's selected / what's live), then tabs and the list, which runs to the bottom. A form opened in the panel is the one exception: its buttons sit in the footer band.
- **A button does one thing, always,** whenever the action is allowed. No buttons whose meaning changes with state or a second press. The two-click guard on destructive actions doesn't break this: the button still does one thing, the first click only arms it.
- **Stable positions.** A set of items (specs, roles, views) keeps each item in the same spot and fills a fixed strip (width shared out), so the layout never shifts or leaves holes by class or state.
- **Monochrome, colour for meaning only.** Whites and grays carry the whole UI: on / off, focus, selection, success, identity. Colour appears only when something needs attention (`warn`, `bad`, `info`), when it's Blizzard's own, or when it identifies content.
- **Flat and quiet.** Flat fills, 1px lines.
- **Controls look like controls at rest**, not only on hover.
- **Help lives in tooltips**, never in standing lines of text. A short status or reason line is fine when it changes.
- **Standalone.** No dependency on other addons; optional pass-through from them (Raider.IO, LibSharedMedia) when present.

## Colour tokens

All text tokens pass 4.5:1 on the panel (0.06 grey) and the window (0.031 grey); monochrome palette.

### Surfaces and lines

| Token | Value | Use |
|---|---|---|
| `bgDark` | 0.031 grey, 97% | main windows |
| `panelBg` | 0.06 grey, 98% | side panels, sidecar, log / history windows |
| `bgMedium` | 0.055 grey, 95% | button base |
| `btnRest` | white 7% | button face at rest |
| `well` | white 8% | text boxes, checkboxes, slider tracks ("fill me") |
| `band` | white 3.5% | header / toolbar / footer strip |
| row stripe | white 5% | alternate rows |
| `hoverWash` / `pressFill` | 0.851 grey, 15% / 22% | hover, press |
| selection wash | white 12% | the row the player clicked |
| `border` | black | window edges, icon tiles, the footer band's rule (not controls) |
| `ringRest` | 0.4 grey (3.3:1) | every control's ring at rest (WCAG 1.4.11) |
| `ringHover` | 0.7 grey | control under the mouse |
| `ringOn` | white | focus (typing), "on" |

### Text and status

| Token | Hex | Contrast | Use |
|---|---|---|---|
| text | `FFFFFF` | 19:1 | body, values, names; also "on", live, hover, focus, success (with ✓), the first word of the title |
| `glyphRest` | `B3B3B3` (0.7) | 9.1:1 | header icons and secondary values at rest, the second word of the title |
| `soft` | `BDBDBD` (0.74) | 10:1 | tooltip bodies, explanations, instructions |
| `muted` | `8C8C8C` (0.55) | 5.7:1 | labels, column headings, placeholders, "off", hints in chat, release version label |
| faint | `666666` (0.4) | 3.3:1 | decoration only: an em-dash for "no value", separator dots. Never words. |
| `warn` | `FFD84A` yellow | 13.9:1 | warnings, untimed / over cap, dev / alpha / beta version label; mark ▲ |
| `bad` | `FF6666` red | 6.7:1 | errors, failures, shortages, destructive labels; mark ✕ |
| `info` | `5AA9FF` blue | 7.8:1 | something worth a look that isn't a problem (PickupGroup's leader view: fills a seat); also StockClerk's Warband view (its one mode colour). Never for "new" in a group list: Blizzard colours a group with a friend in it blue, so new groups get a white edge instead |
| `good` | `4ADE80` green | 11.0:1 | yours and in progress: PickupGroup's sign-ups while they're waiting or invited (name, dungeon, edge), a sign-up that got you in (added 2026-10-23) |

Rules:
- **Marks are drawn, not typed:** the bundled font has no ✓ ▲ ✕ (only × and !), so the check, triangle and cross are drawn glyphs like the header icons (Expressway may lack them too).
- Four meaning colours, far apart in hue: yellow (the bright one) and red (the dark one) for attention, blue for info, green for yours and in progress (yellow vs red 2.1:1, where the old amber vs red was 1.3:1). No near-duplicates, no fifth colour without a guide change. Green is not mint: a saturated mid green, kept to things that are the player's own and still going.
- No mint anywhere in the UI (Tones' Organic set colour is content, so it stays).
- Neutral feedback ("nothing to do") is muted, not red.
- **Colour is never the only cue (1.4.1):** pair it with a word, mark or shape (untimed key = yellow **and** a trailing x; `warn` always with ▲, `bad` with ✕ where there's room; friend vs guild = different glyphs).
- **Selection vs live state:** the selection wash marks what the player clicked; white text **and** a 2px edge bar mark what's live (TalentKeeper: the build actually committed in the tree). Never the same mark for both.
- **Blizzard's own colours stay Blizzard's:** class colours, item quality, raid difficulty, Battle.net friend blue, guild green, Raider.IO's colours. Don't recolour them to the palette.
- **Marks inside Blizzard's frames use Blizzard's art,** recoloured only where the game's own language already does it (TalentKeeper: the game's green glow for talents a build takes, the same glow in red for talents it drops). Our palette is for our own frames.
- **Content colours are allowed when they identify content,** not state: SharedMedia: Tones colours its sets (Organic mint, Classic pink `FF69B4`, Memes lime `32CD32`).

## Type

- Three sizes, all white by default: Small 10, Regular 12, Large 16 (`<Addon>FontSmall`, `<Addon>Font`, `<Addon>FontLarge`). Never `GameFont*`.
- Face: Expressway through LibSharedMedia when present, else bundled Barlow Semi Condensed (OFL, ships in `Media/`).
- Row text and button labels use Small. Long pasted text (log, bulk import) uses WoW's chat font.
- Colour via the tokens above, not new greys.

## Header

Every panel and window starts with the same header strip (`band`):

- **Left:** the addon icon (16px), the two-tone name in Regular (12, sized for the tightest panels), and the version in Small on its baseline (`warn` yellow for dev / alpha / beta, muted for releases). The icon is the monochrome mark; the name is two-tone: first word white, second word `glyphRest`.
- **Right:** header icons, close last. The options icon sits left of close.
- Name and version never move to the bottom of a panel.

## Controls

| Control | Look | Behaviour |
|---|---|---|
| Button | 20px tall, Small font; flat face (`btnRest`), grey rest ring, hover wash, press flash; label via `SetText`, muted when disabled | grayed buttons still show a tooltip saying why |
| Checkbox | 16px well + grey ring, white square when on; label is part of the click area (24px tall) | rows 24px apart |
| Slider | well track + grey ring, light gray thumb (white while dragging), value as % above it | applied on release, not while dragging |
| Text box | well + grey ring; lighter ring on hover; white ring while typing; placeholder names the field (muted) | clears focus when hidden; never `EnableKeyboard(true)` |
| Toggle / tab | muted text off; white text **and** a 2px white bottom bar on; the bar spans the word exactly | same mark for tabs and toggles (3.2.4) |
| Header icon | drawn glyph only (no game textures), `glyphRest` at rest, white on hover, one-line tooltip | 24px target |
| Options icon | the drawn three-bar glyph in the header, tooltip "Settings & Activity" (or "Settings") | opens the addon's options (and activity / log) as a view in its side panel; one per addon, nowhere else (no Options tab) |
| More... menu | a button labelled "More..." opening the suite's picker (headings, 24px check rows, plain rows) | for an item's less-used actions (rename, copy, group, delete); never for the addon's options. *On trial in TalentKeeper.* |
| Destructive action | label turns to "Sure?" in `bad` with a `bad` ring, flashing (the pulse, 3 x 1 s) for 3 s; second click acts | no confirm dialogs |
| Side panel / sidecar | docked to the window's edge, window height, one view at a time | opens where the player needs it (PickupGroup: with the search pane); forms and options open as a view inside it, never a separate window |
| Footer band | 36px, a black 1px rule over a `band` strip | holds a form's buttons when it opens in the panel |
| Clash prompt | a view in the side panel: Large title naming the choice ("Turn off <other addon>'s group finder?"), a `soft` note saying what overlaps, one 24px check row per clashing feature (ticked = theirs stays on), footer band with "Reload now" and "Later" | while a clash stands, our overlapping part is off. The view opens by itself the next time the panel opens; at login, one chat line points there. Unticking turns their feature off from the next reload: our addon writes that one setting in the other addon's saved settings, or turns the whole addon off when the clash is the whole addon; "Later" keeps ours off and asks again next login. Follows TalentKeeper's "Turn off the other talent addons?" view |
| Prompt strip | small strip outside the host window (TalentKeeper's zone-in bar and ready check strip); panel fill, grey ring | shift-drag to move; closes with the thing it's attached to; one at a time |
| Lists | rows 24px (18px in dense tables), 5% alternate shading; entries under a heading indent and hang from it on tree lines (1px 0.3 gray trunk from the heading, a short branch to each entry, the trunk ending at the last); no scroll bars in our own lists: a "more below" chevron pulses (see Motion) | long text windows (log, history) keep Blizzard's scroll bar |

- No Blizzard button / checkbox templates; build through each addon's kit helpers (`Kit.*` in PickupGroup, `MF.*` in StockClerk, `UI.*` in TalentKeeper).
- All fills use `SetColorTexture` (White8x8 + vertex colour renders transparent on retail); 1px lines turn off texel snapping.
- Tooltips: `HookScript`, never `SetScript`, on styled controls. Title in white, body in `soft`. Anchor so a tooltip can't cover its own trigger.
- **Hint tooltips** (how a control works) can be switched off by the player; **information tooltips** (groups, reasons, results) always show.

## Motion

The suite has two motions, and they mark **what just changed, never a standing state**: a shimmer says "this row is news", a pulse says "this control wants a click". Both stop within 5 s (2.2.2), neither is ever the only cue (the colour or word stays), and each addon has one switch that turns its motion off.

| Motion | Look | Used for |
|---|---|---|
| **Shimmer** | one 2 s white sweep (low alpha) across a row (a 90px band) | something new or just changed in a list: PickupGroup's new groups, a sign-up whose status changed, a new applicant when leading; TalentKeeper's saved / tagged / moved builds and the build that just went into the tree; StockClerk's rows that went short since the window last closed. Skipped when too many rows would shimmer at once (PickupGroup: 20). |
| **Pulse** | alpha pulse, 3 times, then holds | "more below" chevrons, the picker's attention mark, an armed "Sure?" (1 s pulses; it lapses after the third); a control that wants a click as it appears: StockClerk's Restock on arriving with something short, TalentKeeper's zone-in prompt button and the ready check strip's Switch on a wrong build |

- **Motion during a game hitch is invisible:** don't animate on events where the game freezes (a spec change landing). Animate before (a cast fill) or after.
- A new motion joins this table before it ships in any addon.

## Accessibility (WCAG 2.2, applied)

| Criterion | Rule here |
|---|---|
| 1.4.1 Use of Color | colour plus a word, mark or shape |
| 1.4.3 Contrast (AA) | text 4.5:1; use the tokens (all pass) |
| 1.4.11 Non-text contrast | control rings 3:1 (`ringRest` 0.4 grey) |
| 2.2.2 Pause, Stop, Hide | motion stops within 5 s; shimmer can be switched off |
| 2.4.7 Focus visible | white ring while typing |
| 2.5.8 Target size | 24px targets or 24px spacing |
| 3.2.4 Consistent identification | one look and one name per control across the suite |
| 3.3.2 Labels | placeholders / labels say what a field is; disabled controls say why |

Accepted exceptions: PickupGroup's apply-as role icons sit 17px apart. StockClerk's Restock button stays in its footer, because it turns into the checkout bar during a run. TalentKeeper's first-login "Bring your builds in" / turn-off-the-other-addons prompt stays its own window when the talent window isn't open: another talent addon's panel loads in the same spot as the pane, so a prompt in the pane couldn't be reached to resolve the clash (found in the 0.4.0 cycle, 2026-10-22).

Measure: WCAG relative luminance of each colour composited over its real background; ratio = (L1 + 0.05) / (L2 + 0.05). Re-measure after any palette change.

## Words

- **Names:** each addon goes by its display title everywhere a player reads it: PickupGroup, StockClerk, SharedMedia: Tones, TalentKeeper (folders, slash commands and saved data keep their code names).
- **American English**, matching the game's English client: color, gray, recognize, leveled.
- Sentence case everywhere: titles, buttons, labels, tooltips, feature names (Restock from bank, Recent activity). Blizzard's proper nouns keep their capitals (Auction House, Group Finder, Premade Groups).
- "AH" is fine on a tight button or label; spell out Auction House in sentences.
- No `--` in sentences: use a colon or a new sentence. Em dashes only in command help lists (`/cmd sub — what it does`).
- On / off in lowercase, in white when on, muted when off (never ON / OFF).
- Plain words a player uses. No dev terms (loop, ledger, queue, payload, schema, pending, staging), reason codes or bare `?`.
- A button's label names its one action (Apply applies, every time).
- Short. A tooltip body is one or two sentences.
- Item names in running text are `[Bracketed]` and quality-coloured where colour is allowed; plain where text gets copied (logs).
- Timestamps bracketed: `[14:24]` in feeds, `[14:24:10]` in logs.
- Numbers use the game's grouping (`BreakUpLargeNumbers`).
- **Tone:** helpful and dry by default. The fun corners (PickupGroup's sign-up history and `/pug stats`) are self-deprecating, ironic and silly, never mean or offensive, and never on screens where a player is making a decision (no jokes in the search pane).

Suite vocabulary (one word per idea across the addons):

| Word | Means | Not |
|---|---|---|
| Tags | what a build or entry is used for (raid, boss, dungeon) | For |
| Settings & Activity | the options view (with the log / recent activity) | Options tab, Config |
| More... | an item's less-used actions | Actions, Manage |

## Chat

- Prefix: the addon's two-tone name, then a colon: `|cffffffffPickup|r|cffb3b3b3Group|r: ...` (white + `glyphRest`, as in the header).
- One load line: `<Name>: v1.2.3 loaded. Type /cmd to <verb>.` The command in white. Git checkouts show `dev <commit>` instead of the version.
- Help lists: `/cmd sub` in white, ` - what it does` in muted.
- Errors in chat use `bad`; never spam (one line per event).
- Alerts the player must see with the panel closed (another addon clashing, say) are one chat line pointing at the panel, where the clash prompt waits. No alert windows.

## Docs and store pages

Every addon has the same README shape: centered title, one-line tagline, CurseForge · Releases links; a short intro paragraph; **Features** (bulleted, bold lead sentence, then one or two sentences); **Commands** (table); **Install** (game versions, dependencies, where to file bugs with the log); **Credits**; **License**. The CurseForge description lives in `Dev/CURSEFORGE.md` (the README without HTML, bold tagline first). The TOC `## Notes` matches the CurseForge summary line. CHANGELOG holds only the version being cut: short, player-facing bullets ("New:" for features).

## Logging and support

- Every addon keeps a saved log with a copyable report window (`/cmd log`), and a debug switch (`/cmd debug`) for detailed steps. Debug defaults off at 1.0.
- Log what a player or support would want: activity for players, detail for support.

## Per-addon colour

Monochrome for every addon. What each keeps:

| Addon | Colour it keeps | Notes |
|---|---|---|
| PickupGroup | none of its own | `warn` for untimed; Blizzard difficulty and friend colours pass through |
| StockClerk | `info` blue for the Warband view | the Mine view is plain white; the tab mark still says which list is on screen (colour isn't the only cue) |
| SharedMedia: Tones | set colours (content) | Organic mint, Classic pink, Memes lime in sound lists; names "T: Name" |
| TalentKeeper | none of its own | tree marks are Blizzard's green / red glow |

## Icons

One icon per addon, built from the in-game style guide so the icon looks like the addon: a 96px-grid square in window black (`#080808`), the 0.4 gray control ring, a faint 4% inner wash, the addon's mark as a flat **white** line drawing, and the 2px white "on" bar underneath (the suite tie). All four read as one family; the mark alone tells them apart. Marks: PickupGroup a portal swirl (instanced content: dungeons and raids alike), StockClerk a flask with a check, Tones sound bars, TalentKeeper a talent tree (1-2-3 nodes in a triangle, the bottom-center node joined to both middle nodes).

Files in every repo: `icon.png` (64 px, TOC `## IconTexture`), `.assets/logo-256.png` (README, shown at 128), `.assets/logo.png` (400 px, the CurseForge logo). `.assets/` never ships (`.pkgmeta` ignore). A new addon gets a new mark in the same frame; check it at 16 px before adopting it.

## Status

All four addons follow this guide as of 2026-10-22, tested in game: PickupGroup (dev 2572a6e), StockClerk (dev 7d5ccf2), TalentKeeper (dev 0ae5e89), SharedMedia: Tones (icon only). Monochrome palette, header and options pattern, clash prompt, white icons. Released 2026-10-22: PickupGroup v1.2.0, StockClerk v1.5.0, TalentKeeper v0.5.0, SharedMedia: Tones v2.7.4.
