# Stock Clerk changelog

## v1.0.0

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

## v0.7.0

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


---

## Earlier development

Stock Clerk went through five internal alpha cycles (v0.5 through
v0.7.0-alpha5) plus seventeen preview builds during v0.7.0's
development, all of which are captured in the git history if
anyone needs the detail. The v0.7.0 entry above is the coherent
narrative of what changed from a user's perspective.
