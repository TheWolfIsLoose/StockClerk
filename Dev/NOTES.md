# Stock Clerk — Design Notes / Backlog

Living roadmap for pre-1.0. Not user-facing; excluded from packaged
releases via `.pkgmeta` (`Dev/` is ignored).

**Current tag:** v0.4.0 (baseline for tester feedback, Sept 17 2026).
**Release policy:** GitHub-only until 1.0 (see `.pkgmeta`). Tags are
free to bump between now and 1.0; CurseForge / Wago wiring is a
deliberate go-wide decision.

---

## Section 1: Shipped (what testers actually have on v0.4.0)

Cross-referenced against source files 2026-09-17. Each item lists the
version it landed in.

### Core (v0.1 → v0.2.0)

- Per-character DB schema (`char.items[itemID] = { need, maxPrice, sortOrder, lastPrice }`).
- Main list UI: resizable window (drag handle bottom-right, persists size + position).
- Full keyboard entry: Tab / Shift+Tab walks Item ID → Target → Price Cap → Add → row cells; commit on blur.
- Inline row editors for Need and Price Cap cells (Enter commits, Esc cancels, click-away commits).
- Item ID-only add (name-based deferred, see QA-2 backlog).
- Slash surface: `/clerk`, `/sc`, `/stock` aliases; `open`, `close`, `reset`, `dump`, `help`, `debug`, `auto`, `log`.

### Bags source + inventory rollup (v0.2.0)

- `Sources/Bags.lua` scans bag containers on `BAG_UPDATE_DELAYED`.
- `Inventory:GetBreakdown(itemID)` returns `{ bags, bank, reagent, warband }`.
- `Inventory:GetCount(itemID)` rolls up bags-only for the "have" number today.

### Per-item price cap (v0.2.0, foundation) — **fully shipped**

- `char.items[id].maxPrice` (copper, nil = no cap).
- `DB:SetItemMaxPrice(itemID, copper)` for programmatic edits.
- UI: dedicated Price Cap column on every row; click to open inline gold-input editor.
- Toolbar Add flow accepts an optional Price Cap value on first-add.
- Restock loop **enforces the cap on every AH auto-buy** — `AH:BuyUpTo` walks results unit-price-ascending and stops at the cap.
- Mid-purchase price drift: if the server re-prices upward between search and confirm, the buy aborts (`COMMODITY_PRICE_UPDATED` above cap → cancel).
- Settings modal counts uncapped items when enabling auto ("N tracked items have no price cap set. Those items will be SKIPPED.").
- BuyDialog warns when unset or when worst unit is exactly at cap.

### QA-10 opt-in auto-purchase (v0.3)

- Global master toggle (`autoPurchase`), off by default.
- Confirmation StaticPopup on first-enable via `SettingsDropdown:RequestAutoEnable` — the click-through path is the only enable path (slash `/clerk auto on` also routes through it).
- Row-level "auto-skipped" affordance (dim indicator on uncapped rows while auto is on).
- Esc kill-switch: pressing Esc while a purchase loop is active calls `RestockLoop:Stop("user_esc")` (see `UI/MainFrame.lua:1234`).
- Quantity delta sanity check inside the loop (refuses buys that would push have past 3× need).

### QA-11 last-known-price column (v0.3)

- `char.items[id].lastPrice = { copper, seenAt, source }`.
- Piggyback stamp on the click-to-search flow (every left-click on a row while AH is open updates the row's lastPrice).
- AH-open sweep + stale-only sweep (24h TTL, configurable).
- Column between Price Cap and Status, dim when stale.

### QA-13 sidecar activity log (v0.3)

- `Log:Emit(event, itemID, payload)` writes to a ring buffer in SavedVariables.
- Events: add / remove / target change / cap change / AH search / purchase attempt / purchase completion / skip / loop start / loop stop.
- LogFrame docked window with footer `/clerk log clear` reminder.
- `/clerk log` toggles the frame, `/clerk log clear` wipes the ring.

### v0.4.0 (this baseline)

- **List order = priority.** Grip handle on each row (14px, three mint bars, tooltip); OnDragStart→BeginRowDrag with a 2px mint insertion-line marker that follows the cursor; OnDragStop→ReorderItems.
- **Keyboard reorder.** Tab from toolbar Price Cap into the list soft-selects row 1 (1px mint ring, no cell focus). Up/Down move via `DB:MoveItem`; Enter/Tab drops into Need cell; first Escape clears selection, second Escape closes window; Shift+Tab climbs to Add.
- **Restock loop walks list top-down.** Replaces old biggest-shortfall-first sort. Priority is now tacit.
- **Daily auto budget.** `char.autoSpend = { copper, resetAt }`; realm-reset aligned via `C_DateAndTime.GetSecondsUntilDailyReset` + `GetServerTime`; fallback +86400. `DB:AddDailyAutoSpend`, `DB:GetDailyAutoSpend`, `DB:GetDailyAutoBudgetLeft`.
- **Manual buys neither counted nor blocked** (design contract).
- **Session `pendingBuys` ledger.** Loop tracks commodities bought this session that haven't looted from mail yet; `Loop:_EffectiveHave = bags + pendingBuys`. Fixes repeat-press double-buy.
- **Root OnKeyDown propagation fix.** Add button focus no longer eats keystrokes for hotbars / `B` / Escape.
- **`/clerk budget`** prints today's spend, remaining allowance, time until reset.
- **`/clerk budget reset`** test helper (zeros counter, rearms clock).

---

## Section 2: Reconciliation — what the old plan promised vs. what actually happened

**QA-10a (per-loop proportional + spillover budget allocation).**
Replaced by the v0.4 **daily-allowance model**. The two-pass allocator
was designed to prevent tail-starvation *within* a single Restock press;
the daily model instead makes each Restock press a normal top-down
attempt and defers unfulfilled items to tomorrow's fresh allowance.
User-approved 2026-09-17 as simpler and matching how they actually
budget gold. Considered CLOSED — do not re-open unless testers report
that a large-list character can't get past their high-priority items in
a reasonable number of realm-days.

**Wave 2 price threshold spec (from 2026-09-16 NOTES.md).**
The foundational per-item `maxPrice` field, DB API, UI cell, loop
enforcement, and price-drift handling are ALL SHIPPED. What remains
from that spec is polish, not foundation — see Section 3.

**Wave 1.5 vs. Wave 2 line.** The original plan bundled "AH auto-buy"
into Wave 2. That already shipped (v0.3, gated by QA-10 opt-in +
per-item cap + QA-10a→daily budget). The remaining Wave 2 bucket is
now specifically **mail / bank / vendor / paste-import** — no more
"AH auto-buy" work is pending in Wave 2.

---

## Section 3: Prioritized backlog (ordered by user-value / effort)

Ordering rule: fill out existing features before opening new ones.
Anything that hardens or extends already-shipped code beats a brand-new
subsystem, all else equal.

### 3.1 — Fill out already-shipped features

**PT-1: Price threshold polish** (extends v0.2.0 maxPrice foundation)

Extends the shipped per-item cap without touching the loop path.

- **Gold / silver / copper input** in the inline price editor. Today it's gold-only (integer, silently rounded), which is coarse for low-value consumables (e.g. spell reagents, silk cloth). Extend the popup to three-field input with clear conversion.
- **Global default cap** in Settings. Currently every item's cap is nil-by-default and the only way to set one is per-row. A "Default cap for new items" gold value in the cog dropdown would make bulk-add and paste-import (see 3.2) actually usable with auto.
- **`priceSource` field** (`"ah" | "vendor" | "any"`, from the original 2026-09-16 spec). Nil-safe migration; UI can wait — no user-visible surface required until we ship vendor auto-buy.
- **"Buy at any price" explicit toggle** on the editor popup. Currently "no cap" is inferred from an empty gold field, which is confusing. A checkbox that says "no cap (buy at any price)" makes the intent visible in the UI and in the tooltip.
- **Warning when cap has been unreachable for N days** (uses lastPrice history). Nice-to-have; skip if it stretches this branch.

**PT-2: QA-2 tier disambiguation for name-based adds**

Name-based adds are still disabled in the toolbar (item ID only). Ship
the shift-click shortcut so users can populate the Item ID field
without typing:

- Hook `OnMouseUp` on the addBox for `IsShiftKeyDown()` and inspect `GetCursorInfo()` / `ChatEdit_InsertLink` behavior to grab the linked item's ID.
- Extract itemID via `GetItemInfoFromHyperlink` and stamp the addBox with the numeric ID.
- Optional stretch: recent-encounters cache (log every `GetItemInfo` we resolve, so a typed name that maps to >1 known ID opens a chooser popup instead of picking blind).

**PT-3: `lastPrice`-driven UI hardening**

Uses the QA-11 data already being captured; costs nothing at the
storage layer:

- **"Waiting on price" filter chip.** Items whose lastPrice is above their cap sit here so users see what's stuck. Restock loop already skips them; UI just needs a badge.
- **Cap vs. lastPrice indicator.** Green if lastPrice < cap, red if above, dim if no lastPrice yet.

### 3.2 — Wave 2 automation (existing spec still valid)

Order below is dependency-sorted:

**W2-A: Mail auto-collect**

Simplest automation, biggest immediate win. `AutoLootMailItem` on
`MAIL_INBOX_UPDATE`, filtered to items on the tracked list AND below
target. Reuses the existing `pendingBuys` ledger — once mail is looted,
decrement the ledger (which we already track).

**W2-B: Bank auto-pull + bank auto-open/close**

Pair these together. Bank auto-open mirrors the AH auto-open+close
pattern already in Core.lua. Auto-pull uses `UseContainerItem` on
`BANKFRAME_OPENED` for items short in bags but present in bank.

**W2-C: Vendor auto-buy**

`BuyMerchantItem` on `MERCHANT_SHOW`, only for tracked items the
vendor sells (walk merchant slot list first). Low blast radius — vendor
items are cheap. Depends on `priceSource = "vendor"` from PT-1.

**W2-D: Paste-a-recipe / bulk import**

Multi-line EditBox modal with itemlink parsing. Blocked on nothing;
priority sits below Wave 2 automation because it's a data-entry
feature, not an automation feature. Ships naturally alongside a
**Groups** tag on items (`char.items[id].groups = {...}`).

**W2-E: Auctionator handoff for AH shopping-list**

Detect `_G.Auctionator` and hand off the tracked list via its
documented SavedVariables. Fallback: continue using our own
`C_AuctionHouse.SendSearchQuery` queue.

### 3.3 — Wave 3+ (deferred, cross-character work)

**W3-A: Storage-vs-cap split.**
`char.items[id].countMode = "bagsOnly" | "bagsAndBank" | "all"`.
Row shows `12 / 20 (+34 in warband)` when reserve > 0. Consumer
character sees restock=short even if warband has plenty.

**W3-B: Shopper role + warband quartermaster.**
Global `warband.settings.shopperCharacter`. Shopper aggregates all
consumer needs. Consumer characters don't auto-buy — they only
auto-pull. Depends on W3-A for count-mode semantics.

**W3-C: Syndicator integration.**
Delegate cross-character bag/bank/warband queries to Syndicator when
present (`Syndicator.API.GetInventoryInfoByItemID`). Falls back to
`C_Item.GetItemCount` when not present. Soft dependency — no TOC
change, no OptionalDeps entry.

### 3.4 — Watchlist (real-world reports only)

**QA-12: Post-release AH edge cases.** Do not preemptively harden.
Wait for reproducible reports from testers.
- Throttled queries (100/min backoff)
- Mid-purchase disconnect (partial confirmation state on relog)
- Partial fills (asked for 100, got 87, did we bank the balance?)
- Cross-realm auction house quirks

**QA-14: Historical expenditure charts.** Sparklines, "is now a good
time to buy" green/yellow/red. Depends on QA-11 accumulating enough
history. Feels post-1.0.

### 3.5 — Polish / low priority

**atrocityEssentials asset borrow.** Own version bump, own CHANGELOG
entry. Bundle a Palette toggle so users can fall back to Blizz-native.
License check before shipping any borrowed asset.

---

## Section 4: Suggested v0.5 branch — PT-1 (price threshold polish)

Concrete branch scope, in order of user-visible impact:

1. Global default cap in Settings (biggest usability jump — makes auto
   safe to turn on without per-row config).
2. Gold / silver / copper editor (fixes precision for cheap items).
3. "Buy at any price" explicit toggle (fixes "empty = ?" confusion).
4. `priceSource` field with nil-safe migration (invisible until vendor
   auto-buy needs it).
5. lastPrice vs. cap indicator (cheap, uses existing data).

Branch name: `wip/v0.5-price-threshold-polish`.

Explicitly deferred out of this branch: PT-2 (shift-click) and PT-3
(waiting-on-price filter). Ship those in v0.5.1 / v0.5.2 if v0.5
tester feedback is quiet.

---

## The receipts (an easter egg, buried here on purpose)

Not for the public README, not for the CurseForge page, not for the
Wago page. Just for whoever's poking around the source.

Stock Clerk v0.1.0 through v0.2.0 was built across five active build
days on the Perplexity Computer platform (Sept 11-15, 2026, UTC),
plus a v0.2.0 finalize/release day (Sept 16-17, still shaking out at
the time of writing).

Perplexity Computer's usage analytics for those five aggregated days,
scoped to this account, report:

- 2026-09-11: 2,820 credits  (Wave 1 scaffolding, DB, UI, first build)
- 2026-09-12:   184 credits  (small polish + user testing)
- 2026-09-13:   890 credits  (Wave 2 sources, AH search)
- 2026-09-14:   485 credits  (QA pass 1)
- 2026-09-15:   422 credits  (QA pass 2, packaging)

**Five-day total: 4,801 credits ≈ $48.01 USD.**

That figure excludes Sept 16-17 (v0.2.0 tag + release + this README),
which was still in flight when the snapshot was taken. Real total
through first-public-release is a little higher.

Caveat: the number is an *upper* bound for what Stock Clerk cost --
this account only did Stock Clerk work on those days, but the credit
counter doesn't itemize by session. If another project had piggy-
backed on the same day, that would be baked in too. On these five
days, nothing else was.

So: forty-eight dollars and one cent, in AI-assistance tokens, to get
a WoW addon from empty repo to first public release. The audio-
processing sibling project SharedMedia_Tones cost roughly similar over
its own build window. Cheaper than a raid tier's worth of consumables.
