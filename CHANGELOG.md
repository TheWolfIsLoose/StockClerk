# Stock Clerk changelog

## v0.6.0

Quick-add gestures on the Add box, and a filter to focus the list on
items currently priced above your cap.

### Quick-add via drag, shift-click, and item links (PT-2)

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

### "Stuck above cap" filter (PT-3)

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

### Under the hood

- New DB getters `GetStuckOnly` / `SetStuckOnly` and a
  `char.ui.stuckOnly` field, backfilled for existing saves.
- Refresh path now applies the filter before building the data
  provider, and paints the filter chip on every refresh so the
  chip and the visible list stay in sync.

## v0.5.0

Safer auto mode: mail-delivery gate, price polish, default cap.

### Mail-delivery gate on auto-purchase

- **Auto no longer double-buys while your last order is still in
  the mail.** Purchases via the auto loop go onto a per-character
  "pending on-hand" ledger and count toward your effective bag
  total until you actually pick up the mail. Repeat-pressing
  Restock at AH before the mailbox arrives no longer piles orders.
- **`/clerk pending`** lists what auto has bought this session
  that hasn't landed in your bags yet. Old entries older than 30
  days are garbage-collected on load so a forgotten mail from a
  character you don't play doesn't skew the count forever.
- **Manual buys are unchanged.** The gate is auto-mode only —
  manual purchase is full user discretion.

### Price cap polish

- **Row cap turns pink when the last seen price is over your cap.**
  Within the 24h staleness window, if the AH last-seen exceeds your
  cap, the row's cap value paints pink so you can eyeball at a
  glance which items your caps are currently blocking. Mint if the
  last-seen is at or below your cap.
- **Cap entry is whole gold.** Row cap editor, the toolbar Add
  field, and the new Settings default cap all accept gold
  integers only. Sub-gold caps aren't a real workflow for
  consumables and the extra parsing surface wasn't earning its
  keep.

### Global default cap for auto mode

- **New Settings field: "Default cap per unit, gold (auto only)."**
  Set it once and auto mode uses it as a fallback for any item
  that doesn't have its own cap. Leave it blank to keep the v0.4
  behavior of skipping uncapped items outright.
- **Row display shows `(Ng)` in dim gray** on uncapped rows when
  auto is on and a default is set, so you can tell at a glance
  which rows will be bought at what price.
- **The auto-enable confirmation now tells the truth.** When a
  default cap is set, the popup no longer warns that "N uncapped
  items will be skipped" — it shows the default cap alongside the
  daily budget instead.
- **`/clerk auto`** readout adds the current default cap alongside
  the auto state and budget.

### Under the hood

- New per-item `priceSource` metadata ("user" / "vendor" /
  "template") on caps. Not surfaced in the UI yet; groundwork for a
  future "where did this cap come from" affordance.
- Restock plan now carries `capSource` ("item" / "default") so the
  activity log and future BuyDialog copy can distinguish per-item
  caps from default-cap purchases.
- Dev workflow: solo-dev, single-branch. All work lands on `main`
  and every push is tag-eligible. `Dev/update.bat` (moved from
  root) always tracks main.

## v0.4.0

Priority ordering + daily budget.

### List order is the priority

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

### Daily auto budget

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

### Repeat-press safety (backported to v0.3.x behavior)

- **Session purchase ledger** tracks commodities bought this session
  that haven't yet been looted from the mail. Hammering Restock at
  AH no longer re-buys the same items; the ledger decays as you
  loot mail.

### Keyboard hygiene

- **Fixed keyboard-eating** after focusing the Add button. Unhandled
  keys now propagate correctly, so B / hotbars / Escape work while
  the addon window is open.

### Slash commands

- **/clerk budget** — prints the current daily auto-spend, budget,
  and time until reset.
- **/clerk budget reset** — zeros today's counter and rearms the
  reset clock. For testing without waiting for realm reset.

## v0.2.0

First public release. Consolidates all Wave 1 / Wave 1.5 work plus a
full visual reskin.

### Pre-release polish

- **Resizable window** with a drag handle in the bottom-right corner
  (Blizzard-native SizeGrabber texture). Minimum width 640, maximum
  1200x1200. Size and position persist per character.
- **Full keyboard-only entry.** Tab / Shift+Tab walks the entire
  editable surface in row-major order: Item ID -> Target -> Price
  Cap -> Add Item button (mint focus ring, activates on Space or
  Enter) -> row 1 Need -> row 1 Price Cap -> row 2 Need -> ... and
  wraps. Off-screen rows auto-scroll into view before opening.
- **Inline edits commit on blur** as well as on Enter. Tabbing or
  clicking away no longer discards the pending value. Escape still
  cancels without committing.
- **Row cell values stay visible on hover.** Previously the cell fill
  occluded the value on hover; the FontStrings are now parented to
  the cell itself so they draw over the fill.
- **Placeholder hints** in all three toolbar fields; the fields
  clear back to their placeholders after a successful add.
- **Column-header band** stretches flush to the right edge of the
  window, matching the toolbar and footer bands.
- **Item ID-only add.** The Item field now accepts numeric item IDs
  only (e.g. `212283`). Name-based add is deferred to a future
  release because Blizzard's API returns non-deterministic matches
  when a display name maps to multiple item IDs (rank 1/2/3 craft
  variants, event duplicates).
- **Escape releases keyboard cleanly.** Pressing Escape out of an
  editbox no longer leaves the window holding keyboard input --
  bag hotkeys, chat toggle, and macro binds all fire immediately.

### New

- **Auction House integration.** With the AH open, left-click a tracked
  row to search for it; a "Restock at AH" button in the footer runs a
  batched restock loop against every item currently under its target
  count. The loop respects each item's price cap and stops
  automatically when the AH closes.
- **Per-item price cap.** Every tracked item has an optional maximum
  gold-per-unit. The restock loop will never buy above that price. Caps
  are shown in a dedicated **Price Cap** column and can be edited in
  place by clicking the cell (Enter to save, blank to clear, Escape
  to cancel).
- **Editable Need column.** The target count is now its own cell,
  edited the same way as the price cap.
- **Have column with source breakdown.** The primary count is your
  bags only; anything sitting in bank / reagent bank / warband appears
  as a dim `(+N: 5 bank, 2 warband)` annotation so the metric stays
  meaningful when items move between storage locations.
- **Slash command debug toggle.** `/sc debug` prints instrumentation
  for stale-count investigation.

### Redesigned

- **Full flat-dark UI.** New chrome inspired by atrocityEssentials:
  single near-black window fill, 1px pure-black borders separating
  sections, no per-row backgrounds. Rows use a translucent grey hover
  wash and every editable cell grows a mint-green border on hover.
- **Brand accent** is SharedMedia\_Tones organic mint green
  (#98FF98) applied to the title accent word, column headers, focus
  rings, price-cap values, and the tracked-count status text.
- **Column layout** is centered under labeled headers (Item / Have /
  Need / Price Cap / Status) with the item name column tightened to
  make room.

### Fixed

- Stale row counts after bag / bank moves (ScrollView was reusing
  frames without re-invoking the row initializer).
- Sticky tooltip when the mouse exited through the GameTooltip frame.
- Trash-icon clicks eating row clicks.
- Shift-click item link into chat now works from the row.
- AH close no longer leaves the frame in an inconsistent state.
- Warband and bank event handlers wired correctly so counts update
  when quartermaster or bank UIs open and close.

### Under the hood

- Modern ScrollBox + ScrollView + DataProvider list (Dragonflight
  pattern) with the DataProvider replaced on each refresh (Auctionator
  pattern) to avoid stale row reuse.
- LibSharedMedia-3.0 and other libs embedded so the addon remains
  standalone.

---

## v0.1.1 (internal)

- Initial working build (Wave 1, bags-only).
