# Stock Clerk — version history

Full notes for every release, newest first. Dev-only (the `Dev/` folder
never ships); the player-facing summary for the release being cut lives in
CHANGELOG.md. Add each release's detailed notes here when you cut it.

Entries up to v1.1.2-alpha2 come from the old cumulative CHANGELOG.md,
or, where it had no entry, from that version's GitHub release notes.

> There is no v1.1.2 stable: the v1.1.2 alphas are the start of v1.2.0
> (efficiency pass). v1.2.0 plan: `Dev/ROADMAP.md`.

## v1.2.0-beta1 (2026-09-26)

Feature-complete v1.2. Goes straight from alpha1 to beta: every feature
worked first time in-game (no v1.2.0-alpha2).

### New: Restock from Bank

- `BankRestock.lua`. At a banker the footer button reads "Restock from
  Bank (N)" (N = short items with copies in the bank or warband bank).
- Pulls exactly the shortfall, using the AH loop's "have" (bags + mail in
  flight). Character bank first, then warband. Tops up existing bag
  stacks of the item, then empty slots in regular bags (profession bags
  and the reagent bag are skipped); stops when bags are full.
- Executor re-plans from live state before every move and does one move
  at a time: whole stack = pickup + place, partial = split + place, each
  onto a slot the planner sized exactly. 3s per-move timeout. Aborts on
  bank close, combat or timeout; clears the cursor on any stop.
- Footer summary ("Pulled 3 items from the bank. 1 still short, restock
  at the AH."), one `bank_pull` log entry per item (Sidecar feed, log
  popup), and a bank-open footer hint when something can be pulled.
- `PlanPulls` is pure and covered by the smoke test.
- Untested in-game: nearly full bags, and the bank closing mid-pull (see
  the caveat in `Dev/ROADMAP.md`).

### New: Auto-open at Bank

- Sidecar toggle, default ON. Opens on the `Banker` interaction (type 8,
  confirmed by the probe for both banks); closes with the bank only if it
  opened itself. No docking at the bank: bag addons (Baganator etc.)
  replace the bank window, so the list floats where the user left it.
  AH docking unchanged (`MF:Undock` now shared).

### Changed

- Filter chip shows only short items (bags below target). Was "stuck
  above cap"; saved on/off state carries over.
- Footer is feedback only: the last action message stays until the next
  one. The "N tracked | N short" summary is gone (it overwrote feedback on
  every redraw); the short count moved onto the Restock button.
- Bulk-import "+" is a 22x22 square with a drawn plus. It and the Restock
  button keep the shared hover highlight (their tooltip scripts now hook
  instead of replacing it).

### Dev

- Probe results and decisions recorded in `Dev/ROADMAP.md`.
- Smoke tests: bank auto-open/close, footer survives redraws, button
  count, short-items filter, bank planner.

## v1.2.0-alpha1 (2026-09-26)

First v1.2 prerelease: the v1.1.2 efficiency pass plus Feature B.

### New: Add common consumables

- Side panel button (under the AH toggles) adds every item in
  `Data/Consumables.lua` that isn't already tracked, target 1. Tracked
  items keep their target and cap. Re-clicking re-adds anything removed
  since (removals aren't remembered, by design). Footer reports the count;
  one `status` log entry for the batch.
- `Data/Consumables.lua` is now loaded from the TOC (13 Midnight items).
  Edit that file to change the list; no code change needed.

### Removed

- Dev-only `Dev/RecommendedLists.lua` and `/clerk seed` (replaced by the
  button). The `debugSeeded` setting default is gone; old saved values
  are ignored.

### Dev

- `Dev/BankProbe.lua` (`/clerk bankprobe <itemID> [scan]`, debug builds
  only): bank-API spike for Feature A. Results in `Dev/ROADMAP.md`.
- `Dev/update.bat` self-heals a zip/CurseForge install into a git
  checkout, runs from a temp copy, syncs via fetch + reset.
- Smoke test covers the consumables merge.

## v1.1.2-alpha2 (2026-09-26)

Second cleanup pass. Stock Clerk now has no library dependencies.
Your list, settings and activity log carry over unchanged.

### No more libraries

- Removed the last of Ace3 (AceAddon, AceEvent, AceConsole, AceDB,
  CallbackHandler, LibStub). Events, slash commands and saved settings
  are now handled directly in about 40 lines.

### Faster at the Auction House

- The list no longer rebuilds every time the game loads info for an
  item that isn't on your list, or while the window is closed. AH
  scanning addons trigger this thousands of times.
- The side panel no longer redraws for status messages it doesn't show.
- The activity log popup redraws once per new entry instead of twice.
- The Restock button's shortfall count no longer sorts the list.
- One fewer item-count call per stashed item (the reagent bank is gone
  since 11.2; any legacy reagent count now shows as bank).

### Fixes

- `/clerk help` lists every command.
- Removed a "remember side panel open" setting that never took effect.

### Repo

- README rewritten for players, with a Releasing section; unused images,
  a duplicate logo and stale design docs removed; `Dev/update.bat dev`
  tracks alpha builds; `Dev/smoke.lua` added as a runnable check.

## v1.1.2-alpha1 (2026-09-26)

Cleanup release. No new features; everything the player sees should
behave exactly as in v1.1.1. Please report anything that doesn't.

### Smaller package

- Removed six embedded libraries the addon never used or no longer
  needs: AceGUI-3.0, AceConfig-3.0, AceHook-3.0, AceLocale-3.0,
  AceBucket-3.0 and AceTimer-3.0 (about 11,600 lines). This also drops
  a broken include: AceConfig referenced an AceConfigDropdown file that
  was never in the repo.
- Bag/bank change events are now debounced with `C_Timer.After(0.25)`
  instead of AceBucket. Same 0.25s collapse window.

### Dead code removed

- `UI/SettingsDropdown.lua` (replaced by the Sidecar since v0.7) and the
  hamburger button's fallback to it.
- `Sources/Bags.lua` placeholder, saved-list templates
  (`DB:ApplyTemplate` / `DB:SaveTemplate`), `DB:MoveItem`,
  `Log:Aggregate`, and `RestockLoop` getters nothing called.
- The no-op `row.pill` stub left over from the old Status column.

### Consolidated

- The row Need and Cap inline editors now share one implementation.
  Click to open, Escape to cancel, Enter/Tab/click-away to commit, and
  opening one closes the other without saving it -- same as before.
- Sidecar, Activity Log and Bulk Import reuse the main window's palette
  and fill/border helpers instead of their own copies. The Sidecar and
  log panels' darkest fill moves from 0.04 to 0.031 grey (the main
  window's value); otherwise colors are unchanged.
- AH commodity and mail events route straight to their handlers; one
  shared debug printer replaces two copies.

## v1.1.1 (2026-09-23)

Point release. Two layout / lifecycle fixes.

### Item name overflowed into Have column

At narrow-window widths, a row's item name would render on top of the
Have column when the Have text was wide (e.g. a `20 (+134)` stash
suffix). Root cause: `row.have` right-aligns inside a fixed-width
`haveCell`, but WoW FontStrings extend LEFTWARD past their parent's
left edge as the string grows -- so the rendered Have text bled into
the item name lane. The item name FontString's static `SetPoint(RIGHT,
row, RIGHT, -250)` didn't account for that.

Fix: re-anchor `row.name`'s RIGHT edge to `row.have`'s LEFT edge with
an 8px gutter. WoW FontStrings support anchoring to another
FontString's edges, so `row.name` now shrinks and ellipsizes
automatically whenever the Have text changes width.

### Orphan tooltip on window auto-close

Hovering the Add box (or any other tooltip-owning widget in the main
frame -- row grip, Have cell, Last Seen hit-target) and then walking
away from the Auction House would leave a GameTooltip rectangle
stranded on screen. The main frame auto-hides on Express-Restock's
AH-close path, but Blizzard's `GameTooltip` doesn't get an `OnLeave`
from its owning widget when the widget just disappears without the
cursor moving -- so the tooltip lingers until the cursor crosses
another tooltip surface.

Fix: `OnHide` hook on the main frame that walks the current
`GameTooltip:GetOwner()` chain and calls `GameTooltip:Hide()` if any
ancestor is the main frame. Cheap (only runs when the frame hides),
covers every tooltip in the addon (not just the Add box), and doesn't
require touching any individual widget's `OnEnter`/`OnLeave`.

## v1.1.0 (2026-09-23)

First post-1.0 release. Ships a batch of ten small refinements and
tightening passes. No new gameplay systems; every change is either
an onboarding polish, a friction-reduction, a code-hygiene cut, or a
licensing addition.

### Bulk import (paste multiple item IDs)

A new compact `+` button next to Add opens a paste dialog for
bulk item entry. Format is one item per line:

* `212283`             — id only (silent default target 1, no cap)
* `212283 20`          — id + target
* `212283 20 500`      — id + target + cap in gold

Blank lines and `#` / `//` comment lines are skipped. Invalid lines
surface an inline error and don't block the rest of the batch. A
single Refresh runs at the end.

### Empty-list onboarding copy

The empty-state message on a fresh install now spells out the four
add paths (toolbar quick-add, bulk paste, drag-and-drop, and
`/clerk add <id-or-name>`) instead of showing a bare title.

### Add cluster default target is 1

With the count field blank, the Add cluster (and `/clerk add` slash
command and bulk-import lines that omit a target) now stocks 1 copy
instead of 20. Zero-friction quick-add without a magic number.

### Row-body Tab excised

The shopping list is now click-to-edit only (mouse). Tab / Shift+Tab
now cycles inside the Add cluster only — Item ID → Target → Price
Cap → Add Item → wrap. This removes an entire class of focus-
capture bugs the row-tab traversal was prone to, and the keyboard
watchdog module that shipped for those bugs is retired.

### Halved countdown timers

Buy-arm delay on the confirmation flyout drops from 3 seconds to
1.5. The post-buy summary auto-dismiss drops from 6 seconds to 3.
Skip is still live-immediate; the summary close button remains
clickable throughout.

### Auto-Restock renamed Express-Restock

The AH-open toggle in Settings and the sidecar dropdown is now
labelled "Express-Restock on AH open" to better match its
semantics: it kicks the restock flow when the AH opens, but every
buy is still user-confirmed via the flyout. Internal identifier
(DB field `autoRestock`) is unchanged for compatibility.

### MIT license

Added LICENSE at the repo root. Bundled libraries retain their own
upstream licenses.

### Layout hotfixes

Status footer clamps to a single line with ellipsis so it stops
vertically pushing the border at min-width. The empty-list message
font region wraps and left-aligns correctly at 420px.

## v1.0.0 (2026-09-21)

First stable release. Consolidates the v0.8.0 cleanup pass with the
v1.0.0 launch polish. No new features versus late v0.8 alphas —
Stock Clerk 1.0 is v0.7.0 hardened, refined, and stamped stable.

### Bank/warband guardrail on Restock at AH

Before committing gold on an item you already own copies of in bank
or warband bank, the buy flyout now says so. When the restock loop
queues an item with a non-empty stash, the flyout displays:

* `You have N in bank (this character)` — shown when the character
  bank (including reagent bank) has any copies
* `You have N in warband bank (account-wide)` — shown when the
  account warband bank has any copies

Both lines are amber-tinted to match the existing "No cap set"
warning idiom. The flyout's border also pulses amber-to-mint on a
0.5s cadence while the stash warning is active, drawing your eye to
the warning before the Buy button unlocks.

The 3-second Buy arm delay is unchanged. Skip advances to the next
item exactly as it did before; there's no third option for retrieving
from the bank — that's on you.

Items with no stashed copies show the flyout exactly the same as
prior versions (no stash lines, no pulse).

### Shopping list row separator

Each row in the shopping list is now separated from the next by a
1px muted-gray line spanning the full row width. Gives the list
visual rhythm without competing with row content.

### Have column simplified; hover for storage detail

The Have column no longer inlines the storage-source breakdown.
Rows now show either `N` or `N (+M)` where `M` is the total stashed
in bank/warband — no more `(+M: X bank, Y warband)` overflowing
into the Item column at narrow widths.

Hover the Have cell to see where the stash lives: a tooltip anchored
above the row lists `+N in bank (this character)` and
`+N in warband bank (account-wide)`, matching the visual idiom of
the Need and Cap tooltips. The cell itself stays visually plain on
hover — no border box, no fill change; the cursor arrow and the
tooltip appearing are sufficient signal.

### Addon-list icon

Stock Clerk now ships with a proper icon that shows in the in-game
addon list and the addon compartment dropdown, replacing the
placeholder Blizzard note glyph used through the v0.8 alphas.

### LogFrame surface removed

`UI/LogFrame.lua` (the v0.6 log surface, replaced by LogPopup in v0.7)
has been deleted. It was carried through v0.7 as a compatibility shim
and is no longer referenced by any caller. `/clerk log` continues to
open the LogPopup exactly as before.

### Bag/warband-open hitch eliminated

Opening bags or the warband bank no longer triggers a visible hitch
when Stock Clerk is closed. Two changes:

- Inventory-change events still invalidate the item-count cache (so
  the next open reads fresh data), but they no longer rebuild the
  row list while the window is hidden. Reopening the window repaints
  as before.
- `GetBreakdown` uses a fast path for items with nothing stashed
  outside bags: two `C_Item.GetItemCount` calls instead of four. The
  expensive account-bank decomposition only runs when a row actually
  needs to show a `(+N: bank/reagent/warband)` suffix.

### Cleanup

- `notes/` moved out of the public tree (was published in v0.8.0-alpha1).
- Alpha-era scar comments stripped from every source file (v0.8.0-alpha1).
- Pre-1.0 CHANGELOG history collapsed to a git-history pointer
  (v0.8.0-alpha1).
- CI wired to auto-create GitHub Releases on tag push, so the
  CurseForge webhook fires without a manual `gh release create`
  step (v0.8.0-alpha1).

## v0.8.0-alpha3 (2026-09-21)

v0.8.0: bank/warband guardrail in restock flyout

Adds a soft warning to the buy flyout when the queued item has copies
in bank and/or warband bank. The user still can buy without any extra
click (Skip is unchanged), but they see the stash before they commit.

RestockLoop:
- Advance() now attaches stashBank / stashWarband / hasStash to the
  plan before calling _Arm(plan). Bank + reagent are folded together
  per retail 11.2+ (single storage volume; see Inventory.lua header).

ShowArmedToast:
- New _toastStashBank / _toastStashWarband fontstrings, amber-tinted,
  hidden by default. Shown between title and sub line when the plan
  carries stash > 0 for that source. Copy:
    'You have N in bank (this character)'
    'You have N in warband bank (account-wide)'
- Sub line re-anchors below the last visible stash line
- Toast height grows 13px per shown stash line (base 44 -> 44/57/70)

Pulse animation:
- New _StartToastPulse / _StopToastPulse retint the 4 border textures
  from mint to amber and back on a 0.5s C_Timer.NewTicker cadence
- Pulses on the guardrail path only (plan.hasStash)
- Stopped by Buy click, Skip click, HideToast, ShowSummaryToast
- Border restored to resting mint on stop so next arm doesn't inherit

ShowSummaryToast:
- Hides stash lines, restores toast to 44px, stops pulse (belt-and-
  braces vs relying on the caller having already run HideToast)

3-second Buy arm delay is unchanged. No third button for 'retrieve
from bank' -- user handles bank retrieval themselves.

## v0.8.0-alpha2 (2026-09-21)

v0.8.0 perf: guard MainFrame refresh + lazy stash decomposition

Fixes the bag/warband-open hitch reported during v0.7.0 dogfooding.
Opening bags or the warband bank fires BAG_UPDATE_DELAYED /
PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED, which trips the inventory
bucket. Two problems compounded:

1. The bucket always called MainFrame:Refresh, even when the window
   was closed. A hidden refresh rebuilds the whole DataProvider and
   re-initializes every row, which in turn calls GetBreakdown per
   item -- pure waste.
2. GetBreakdown always did 4 C_Item.GetItemCount calls per item,
   including the expensive includeAccount=true variant, even for
   items with nothing stashed outside bags.

Fix 1: gate the Refresh call in INV:OnInventoryChanged behind
frame:IsShown(). Cache invalidation still runs so the next open
reads fresh data; MF:Show() explicitly re-Refreshes on open.

Fix 2: fast path in GetBreakdown. Fetch bagsOnly and the full-
warband total first (2 calls). If they match, no stash exists and
we skip the two decomposition calls entirely. Only items actually
stashed elsewhere pay the full 4-call cost. Return shape is
unchanged so both existing callers (MainFrame row init, /clerk
dump in Core.lua) see identical results.

## v0.8.0-alpha1 (2026-09-20)

Cleanup pass ahead of the v0.8.0 stable. No user-visible feature or behavior change vs v0.7.0.

**What changed:**
- Alpha-era scar comments stripped from the source (78 automatic + 6 hand edits + comment capitalizations). Substantive content preserved; only the iteration-era tags removed.
- `CHANGELOG.md` pre-1.0 history collapsed to a one-paragraph pointer at git history.
- `notes/` directory removed from public tracking.
- Module-header design docs rewritten as timeless documentation.

**Verified:**
- Lua syntax passes on all modified files
- No identity leaks (grep clean)
- Zero remaining scar markers in-tree

Marked as prerelease. If you're on the default CurseForge filter, you won't see this build in-client. Direct-download only.

## v0.7.0 (2026-09-20)

First stable release on the v0.7 track. Consolidates six months of
iteration across five alphas and seventeen preview builds into a
coherent single-window restock addon with confirmed-buy automation,
keyboard-first entry, and per-character shopping lists.

### Compressed main window

Main frame shrunk from 680x500 to 420x400 so Stock Clerk fits
comfortably alongside the Auction House and the game world without
eating half the screen. Every column, header, and inline editor was
rebuilt for the tighter footprint. Numeric columns now right-align
on their own edges (accounting-style) with headers matching, so
values like `41g` / `34g` and counts like `30` / `314` stack cleanly
for at-a-glance scanning.

### Sidecar panel: settings + activity log

Right-docked panel replaces the old settings dropdown. Contains:

- **Auto-open at Auction House** toggle — pops the shopping list open
  when you visit the AH.
- **Auto-Restock on AH open** toggle — starts the restock loop
  automatically when the AH opens if anything is short.
- **Recent Activity** log with a `/clerk log` link that opens a
  larger scrollable popup for full session review.

Sidecar hides with the main window (previously it orphaned).

### Restock loop with armed-flyout confirmation

A `Restock at AH` button runs a batched restock pass across every
short item on your list, respecting each item's price cap. Each buy
surfaces an armed flyout below the main window showing:

- What's about to be bought (`30 x Thalassian Phoenix Oil`)
- Total cost and per-unit cap (`1219g 80s · Cap 41g / unit`), OR
  amber `No cap set` warning for uncapped items
- `Buy` / `Skip` buttons with a 3-second arm delay so accidental
  clicks are impossible during the arming animation

The old StaticPopup confirmation modal is retired: the flyout's
amber `No cap set` badge IS the soft warning for uncapped buys.
Capped-out rows (cheapest listing above your cap) auto-skip
silently. When the loop finishes, a summary flyout shows what was
bought, total spend, mail-pending count, and a `Close (Ns)`
countdown.

### Currency letter suffixes (g/s/c)

Gold amounts render as `1219g 80s 66c` throughout the addon instead
of Blizzard's coin icon textures. Users who swap coin textures with
alternative art still see consistent price rendering. Precision
adapts to context: whole gold in tight columns, silver in the Seen
column, full copper in tooltips.

### Full keyboard-only entry

Tab / Shift+Tab walks the entire editable surface in row-major
order: Item ID → Target → Price Cap → Add Item → row 1 Need → row 1
Cap → row 2 Need → wrap. Inline edits commit on Enter, Tab, or
click-away. Escape cancels without committing.

*(Note: v1.1.0 excised the row-body portion of this Tab chain.
The row surface is now click-to-edit only. See the v1.1 entry
above.)*

### Left-edge status bar + Have text color

Each row shows a 2px vertical accent bar on its left edge (mint
when stocked, red when short) plus color-coded Have text. Dual-
channel encoding means colorblind users get a reliable positional
signal, everyone else gets redundant color across two spots.

### Mail-pending ledger (repeat-press safety)

Every successful purchase is tracked in a per-character ledger
that folds mailed-but-unlooted purchases into the effective have
count. So if you buy 30 items, close the AH, don't loot the mail,
and reopen the AH, the loop correctly sees you're stocked and
doesn't re-buy. The ledger reconciles against actual mail
contents on `MAIL_INBOX_UPDATE` and garbage-collects entries older
than 30 days.

### Auction House integration

Open the AH, click a row in Stock Clerk, and it searches for that
item. Search results feed a Last Seen column showing the cheapest
unit price and how long ago it was recorded. Stale prices dim
after the configured TTL (24h default).

### Bank / warband / reagent bank visibility

Items sitting in bank, warband, or reagent bank appear as a dim
`(+N)` annotation next to the primary bags-only Have count, so you
always know where your stock actually lives.

### Two-tier activity log

Every loop event (start, stop, buy attempt, buy result) is logged
both to the Sidecar's condensed Recent Activity feed and to a
full popup accessible via `/clerk log`.

### Commands

- `/clerk` — open the main window (aliases: `/sc`, `/stock`)
- `/clerk help` — command list
- `/clerk reset` — wipe this character's list
- `/clerk dump` — print current list to chat
- `/clerk log` — open the full activity popup
- `/clerk debug on|off` — toggle diagnostic chat output (log only
  emits on state changes to avoid spam)

### Under the hood

- Single-source-of-truth shortfall computation via
  `RestockLoop:PreviewShortfallCount()` — button state, footer
  status, and Core's auto-restock trigger all route through the
  same effective-have math that BuildQueue uses. Fixes an early
  alpha bug where three independent shortfall calcs could disagree
  and cause a phantom restock of already-stocked items.
- MainFrame:Refresh coalesces multiple triggers in the same frame
  into a single row-list rebuild.
- LibSharedMedia-free, LibStub-only dependency stack. No external
  library requirements at install time.


## v0.7.0-alpha4 (2026-09-18)

Field-testing feedback pass on alpha3. Five bug fixes plus a status-column redesign.

### Fixed

#### Drag-and-drop into the Item ID field silently no-op'd
The container's `OnReceiveDrag` never fired because the EditBox on top of it caught the drop first. Registered the handler directly on the EditBox in addition to the container. The mint drop-zone outline was already correct; only the drop consumption was broken.

#### Header showed literal `v@project-version@`
`## Version: @project-version@` is a BigWigsMods packager keyword that only gets substituted at CurseForge packaging time. If the addon is installed from raw source (`git clone`, or GitHub's "Download ZIP" button which bundles source not the packaged release), the literal survives and leaks to the header. Added a runtime guard: if the version starts with `@`, the header shows a muted grey `dev`. **Packaged installs still show the real version.**

#### Sidecar orphaned when main window closed
Sidecar (Settings + Recent Activity right-docked panel) was UIParent-parented rather than a child of `StockClerkFrame`, so hiding the main window via X, Close, or Escape left it floating. Extended `MF:Hide()` to cascade to it, same pattern as the pre-existing SettingsDropdown cascade.

#### Status column leaked `o`/`o!` text at every row's right edge
v0.7 was supposed to drop the Status column entirely, but the pill stub was still force-shown and populated with `ok` / `-N` text on every `InitializeRow`. Replaced the stub with a true no-op so nothing paints.

### Changed

#### Status column redesign — left-edge accent bar
Each row now shows a 2px vertical accent bar on its left edge:
- **Mint green** = stocked (Have >= Need)
- **Muted red** = short (Have < Need)

Dual-channel encoding (bar position + Have text color) means colorblind users get a reliable signal from the bar's absence/presence at a fixed position. Have/Need column order preserved (matches the game's `X/Y` progress convention).

#### Tab-focused row now highlights
Tabbing between row cells (Need <-> Cap <-> next row's Need) now triggers the same hover-wash a mouse-over would. Without it, keyboard-driven users lost their place in the list because the focused cell got a border-brand fade but the row around it stayed visually inert. Hooked via `OnEditFocusGained`/`OnEditFocusLost` on both cell editors, with a one-frame defer on Lost to avoid Tab-to-adjacent-cell flicker.

### Deferred

- Have-tooltip with bag / bank / warbank breakdown (needs per-location count queries + the warbank lazy-load quirk) — alpha5+
- Recent Activity panel polish

Full changelog: [CHANGELOG.md](https://github.com/TheWolfIsLoose/StockClerk/blob/v0.7.0-alpha4/CHANGELOG.md)

## v0.7.0-alpha3 (2026-09-18)

Republish of v0.7 alpha with the [v0.6.2](https://github.com/TheWolfIsLoose/StockClerk/releases/tag/v0.6.2) `CURSOR_UPDATE` Lua error fix back-merged in.

**No new v0.7 features vs alpha2.** Bumped so CurseForge's Alpha channel shows a v0.7 build newer than the current Stable (v0.6.2) and remains visible to alpha subscribers.

### Fixed

The drop-zone watcher registered a non-existent `CURSOR_UPDATE` event alongside `CURSOR_CHANGED`. Retail Midnight 12.1 does not expose `CURSOR_UPDATE`, causing every window open to throw `Frame:RegisterEvent(): Attempt to register unknown event` mid-`Build()`.

Full fix write-up in the [v0.6.2 release notes](https://github.com/TheWolfIsLoose/StockClerk/releases/tag/v0.6.2).

Full changelog: [CHANGELOG.md](https://github.com/TheWolfIsLoose/StockClerk/blob/v0.7.0-alpha3/CHANGELOG.md)

## v0.7.0-alpha2 (2026-09-18)

Republish of the v0.7 redesign with the v0.6.1 keyboard-capture hotfixes back-merged in.

**No new v0.7 features vs alpha1.** This release exists because CurseForge's Alpha channel hides an alpha build once a newer Stable ships — v0.6.1 shipped as Stable the day after alpha1, which made alpha1 invisible to alpha subscribers. Bumping to alpha2 restores visibility on the Alpha channel with the hotfixes included.

### Included from v0.6.1 hotfix

- Row-editor pool reset on rebind (primary cause of the keyboard-eating bug).
- Single-exit-point + pcall discipline on both keyboard handlers.
- Force propagation restore on window close.
- Add-button focus-flag desync recovery.
- New KeyboardWatchdog module that logs `[KBD]` entries to `/clerk log` if it detects a suspicious keyboard state.

See [v0.6.1 release notes](https://github.com/TheWolfIsLoose/StockClerk/releases/tag/v0.6.1) for the full hotfix write-up, and [v0.7.0-alpha1 release notes](https://github.com/TheWolfIsLoose/StockClerk/releases/tag/v0.7.0-alpha1) for the unchanged v0.7 feature list.

Full changelog: [CHANGELOG.md](https://github.com/TheWolfIsLoose/StockClerk/blob/v0.7.0-alpha2/CHANGELOG.md)

## v0.7.0-alpha1 (2026-09-18)

First preview of the v0.7 redesign. Marked **alpha** in CurseForge so normal Stable subscribers keep running v0.6.0; testers who opt into Alpha in the CurseForge app's Release Type filter pick this up.

See [CHANGELOG.md](https://github.com/TheWolfIsLoose/StockClerk/blob/v0.7.0-alpha1/CHANGELOG.md) for the full entry. Highlights:

- **Compact main window** — 420x400, Have column colors itself red when short and mint when stocked, icon-only filter chip
- **Sidecar panel** — new right-docked flyout merging Settings + Recent Activity, opened from the header hamburger. Persists open per character.
- **/clerk log popup** — 500x400 copy-friendly dump, pre-selects for Ctrl+C, tagged entries `[BUY]` `[CAP]` `[AUTO-BLOCK]` etc.
- **Auction House docking** — auto-dock to the AH's right edge on show, restore to your floating position on close
- Old `UI/LogFrame.lua` ships as a fallback and is scheduled for removal in v0.8

Known alpha caveats: new UI strings are English-only.

## v0.6.2 (2026-09-18)

Hotfix for a Lua error thrown on `/clerk` open.

### Fixed

The drop-zone watcher (shipped in v0.6.0) registered a non-existent `CURSOR_UPDATE` event alongside `CURSOR_CHANGED`. Retail Midnight 12.1 does not expose `CURSOR_UPDATE`, causing every window open to throw `Frame:RegisterEvent(): Attempt to register unknown event` mid-`Build()`.

Default `/console scriptErrors 0` hid this from most users; testers with scriptErrors turned on caught it.

Removed the invalid registration. `CURSOR_CHANGED` alone covers all cursor state transitions needed for the mint-outline drop-zone highlight, so no behavior change to the affordance itself.

**Bug was present since v0.6.0** — the drop-zone code shipped that way and just went unreported until now. If you had `scriptErrors` off, the addon worked; if you had it on, every window open threw.

Full changelog: [CHANGELOG.md](https://github.com/TheWolfIsLoose/StockClerk/blob/v0.6.2/CHANGELOG.md)

## v0.6.1 (2026-09-18)

Critical hotfix for a keyboard-capture bug that could leave the game unresponsive to input.

### Fixed

Under some conditions — editing target counts, using filter chips, or after inventory refreshes — Stock Clerk could silently swallow every keystroke game-wide: chat, movement, hotbars, even Escape were dead until an alt-tab out of the game and back in.

Four separate defensive fixes:

- **Row-editor pool reset (primary cause).** The list's row frames are pooled and recycled by WoW's ScrollView when the underlying data changes. If you had an inline Need or Price editor open with focus when the pool re-bound that row to a different item, the editor stayed alive and focused — often scrolled offscreen — and captured every keystroke silently. Row init now force-closes any open editor before binding new data.
- **Single-exit keyboard handlers.** The main-window and Add-button keyboard handlers previously had early returns after telling WoW to stop propagating a key. If any code inside those branches errored, propagation stayed off. Both handlers now run their actions inside a protected call and restore propagation exactly once at the end.
- **Force propagation restore on window close.** Explicit safety net on the main window's OnHide.
- **Add-button focus recovery.** If the Add button's internal focused flag ever drifts from its actual keyboard-capture state, the next keypress force-clears the state.

### Added

**Keyboard-capture watchdog.** A diagnostic sampler runs once per second while the window is open and logs a red `[KBD]` entry to `/clerk log` if it detects a suspicious state. If the bug recurs despite the fixes, `/clerk log` will give a timestamped incident report to share.

Full changelog: [CHANGELOG.md](https://github.com/TheWolfIsLoose/StockClerk/blob/v0.6.1/CHANGELOG.md)

## v0.6.0 (2026-09-18)

Quick-add gestures on the Add box, and a filter to focus the list on
items currently priced above your cap.

#### Quick-add via drag, shift-click, and item links (PT-2)

- **Drag any item onto the Add box.** Drop an item from your bags
  or from a Blizzard item slot onto Stock Clerk's Add box and its
  itemID appears in the field, ready for you to review Target and
  Price Cap and press Enter to commit.
- **Shift-click the Add box while holding an item on the cursor.**
  Same result as drag-and-drop; pick whichever gesture fits your
  hand.
- **Shift-click any item link while the Add box has focus.** With
  the Add box focused, shift-clicking an item in chat, in a
  tooltip, in the Auction House browse pane, or anywhere else
  routes the itemID into the Add box instead of into chat. Your
  chat's own "shift-click to link" behavior is untouched when the
  Add box isn't focused.
- **Mint drop-zone hint.** The Add box outline lights up mint
  whenever you're holding an item on the cursor, so you can see
  where the drop will land.
- **The gestures fill the box; they don't commit.** Enter still
  commits, matching the rest of the addon's edit model. This
  keeps a stray drag from adding an unwanted item; we'll revisit
  based on how the gestures actually get used in practice.

#### "Stuck above cap" filter (PT-3)

- **New filter chip in the column-header strip.** Toggle it on to
  hide every item except the ones whose most recent seen AH price
  exceeds your price cap -- i.e. the items you're currently
  waiting out. Toggle off to see the full list again.
- **Filter state is per character** and persists across sessions,
  so your alt with lots of enchanting mats doesn't inherit your
  main's filter state.
- **Cap column tri-state coloring.** The Cap value paints:
  - Mint when the last seen price is at or under the cap (ready)
  - Pink when the last seen price exceeds the cap (stuck)
  - Muted gray-mint when a cap is set but there is no fresh price
    data yet, so you can tell "unknown" from "known and healthy".

#### Under the hood

- New DB getters `GetStuckOnly` / `SetStuckOnly` and a
  `char.ui.stuckOnly` field, backfilled for existing saves.
- Refresh path now applies the filter before building the data
  provider, and paints the filter chip on every refresh so the
  chip and the visible list stay in sync.

## v0.5.0

_No release notes were published for this tag; see the git history._

## v0.4.0 (2026-09-17)

Priority ordering + daily budget.

#### List order is the priority

- **Drag rows to reorder.** Each row has a grip handle on its far
  left (three horizontal bars, mint on hover). Drag it up or down
  and drop to insert; a mint insertion line shows where the row
  will land.
- **Keyboard reorder.** Tab from the toolbar's Price Cap into the
  list now soft-selects the first row (1px mint ring, no cell
  focus). While selected: Up / Down move the row, Enter or Tab
  drop into the Need cell, Shift+Tab climbs back to Add, first
  Escape clears the selection, second Escape closes the window.
- **The restock loop walks the list top-down.** Whatever order you
  arrange is the order Restock at AH tries. Replaces the old
  biggest-shortfall-first sort.

#### Daily auto budget

- **Budget is now a daily allowance**, aligned to the realm's daily
  reset (server-local: currently 7 AM PT for NA realms, morning
  reset for EU, etc.).
  Pressing Restock at AH multiple times in a day draws from the same
  allowance. When exhausted, auto stops and waits for reset.
- **Manual buys are never counted and never blocked.** Budgets are
  guardrails against the autopilot spending on you; a human-confirmed
  click needs no such guardrail.
- **Settings dropdown shows a live readout**: "auto spent today:
  Xg / Yg (resets in Zh)".
- **Loop status appends the remaining allowance** on auto runs
  ("Loop done. Bought N, spent Xg. Yg left today.").

#### Repeat-press safety (backported to v0.3.x behavior)

- **Session purchase ledger** tracks commodities bought this session
  that haven't yet been looted from the mail. Hammering Restock at
  AH no longer re-buys the same items; the ledger decays as you
  loot mail.

#### Keyboard hygiene

- **Fixed keyboard-eating** after focusing the Add button. Unhandled
  keys now propagate correctly, so B / hotbars / Escape work while
  the addon window is open.

#### Slash commands

- **/clerk budget** — prints the current daily auto-spend, budget,
  and time until reset.
- **/clerk budget reset** — zeros today's counter and rearms the
  reset clock. For testing without waiting for realm reset.

## v0.2.0 (2026-09-17)

First public release. See CHANGELOG.md for the full change list.

### Highlights

- Auction House integration with left-click-to-search and batched restock loop
- Per-item price cap with editable Price Cap column
- Editable Need / Target column
- Have column with bag / bank / warband breakdown
- Full flat-dark UI with mint accent (SharedMedia_Tones organic green)
- Full keyboard-only entry: Tab / Shift+Tab walks toolbar -> Add Item -> row list in row-major order
- Inline edits commit on Enter, Tab, or blur; Escape cancels
- Resizable window with persistent size + position per character
- Item ID-only add (name resolution deferred; see backlog)
- Retail 12.1 (Midnight) interface
