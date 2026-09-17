# Stock Clerk changelog

## v0.2.0

First public release. Consolidates all Wave 1 / Wave 1.5 work plus a
full visual reskin.

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
