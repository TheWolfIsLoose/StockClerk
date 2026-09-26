# Stock Clerk — Backlog

Dev-only (the `Dev/` folder never ships). Release process lives in the
README's "Releasing" section; shipped work is on the GitHub Releases page.

This backlog predates v1.0 and some entries have since shipped; check
the Releases page before picking one up.

---

## Section 3: Prioritized backlog (ordered by user-value / effort)

Ordering rule: fill out existing features before opening new ones.
Anything that hardens or extends already-shipped code beats a brand-new
subsystem, all else equal.

### 3.1 — Fill out already-shipped features

**PT-4: Mail-delivery gate on auto-buy** (hardens v0.4 pendingBuys ledger)

Current v0.4 behavior is that pendingBuys is session-only and decays
passively as bags catch up. That already prevents re-buying the same
item, but the loop still *runs* on subsequent presses — which can
draw the daily budget against stale bag numbers on OTHER items and
doesn't force a natural checkpoint before the next auto pass.

Sharper contract (user-approved 2026-09-17): once auto has bought
anything, the next auto pass is **blocked** until the ledger is
empty, and the ledger only empties by **actual on-hand confirmation**
of items in bags (not just mailbox visit).

- **Persist ledger to `char.pendingBuys`** with `{ qty, baseHave,
  boughtAt }` per item. Restored on load.
- **`MAIL_INBOX_UPDATE` reconciliation** — mailbox is authoritative.
  On update, walk `GetInboxItem` for every attachment, sum counts by
  itemID. Any ledger entry not present in mail = looted or expired
  (delete). Any ledger entry whose mailbox count is less than qty =
  partially looted (clamp qty down).
- **Passive bag-count decay in `_EffectiveHave` unchanged** — items
  landing in bags still absorb ledger entries the same way.
- **Gate `Loop:Start`** when `s.autoPurchase and next(pendingBuys)`:
  refuse with a status message naming what's still pending. Manual
  mode is NOT gated (per standing rule: manual is full user
  discretion).
- **30-day GC on load** — auction mail expires server-side at 30
  days; any ledger entry with `boughtAt` older than that is garbage.
  Prevents a ledger entry that was never reconciled from staying
  immortal.
- **`/clerk pending`** prints current ledger; **`/clerk pending
  clear`** wipes it (test helper, parallel to `/clerk budget reset`).
- **Loop-end status enhancement**: append "Check mail before next
  auto pass" when the pass ended with the ledger non-empty.

Storage scope: **per-character** (auction mail is delivered to the
buying character, not the warband). Lives on `char.pendingBuys`.

Cross-session behavior: on a fresh login with a non-empty persisted
ledger, gate stays CLOSED until the user visits a mailbox and
reconciliation runs. Handles the "buy, log out, log back in" case
the passive-decay-only ledger couldn't.

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

**MUST be opt-in (user-approved 2026-09-17).** Several established
addons already do mail auto-collect (Postal, MailCollector, etc.) and
users may already have one running. Stock Clerk's mail auto-collect
ships **off by default** with an explicit toggle in the settings
dropdown ("Auto-loot mailbox attachments for tracked items").
Enabling it should also warn the user if a known mail-automation
addon is loaded (`IsAddOnLoaded("Postal")` etc.) so they can avoid
two addons fighting over the same inbox.

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

### 3.4a — UX review checkpoints (revisit with usage data)

**PT-2 quick-add commit model.** Shipped in v0.6 as **review-and-commit**:
shift-click, drag, or focused-editbox link insertion all just fill the
Add Item box with the item ID; the user still reviews target/cap and
presses Enter to actually add the item. This matches the rest of the
addon's commit-on-Enter/Tab pattern (inline row edits work the same
way) and prevents an unwanted item from landing with no undo path.

**Revisit trigger:** if real-world usage shows the review step is
pure friction (i.e. we’re always defaulting target=1, always keeping
the suggested cap, always mashing Enter without changing anything),
switch to **immediate-add-with-defaults** and rely on a per-row
delete affordance as the safety net. Do NOT flip this preemptively.
Wait for at least a couple of weeks of daily usage to build a
reliable read on how the gesture is actually being used. User-approved
2026-09-17.

**PT-3 filter chip design.** Shipped in v0.6 as a **single toggle
chip** labeled "Show only: stuck above cap". Matches the flat,
out-of-the-way UI aesthetic and keeps the top-of-window surface
quiet.

**Revisit trigger:** if usage shows a real appetite for slicing the
list by other states (e.g. wanting a "no price data yet" pass to go
hit the AH for pricing, or a "ready to buy" preview before pressing
Restock), expand to a **multi-chip row** (All / Stuck above cap / No
price data / Ready to buy, pick one). User doesn't have strong
feelings either way today (2026-09-17); revisit after real usage
shapes the intuition.

**Sidecar unification model (v0.7).** Shipping in v0.7 as a **single
merged sidecar panel** containing BOTH a compact activity feed AND
the settings controls, stacked in one view. Not tabs, not two panels
sharing a slot -- one panel, one purpose ("the sidecar"). One
toolbar button toggles it; the cog and log buttons collapse into
that single button.

Design principle: **function drives form.** The sidecar's size is an
output of its content, not a fixed input. Ship a reasonable initial
size based on what's inside; expect it to change as content changes.

Content scope for v0.7:
- **Settings** (TOP of panel, always visible): the current
  SettingsDropdown controls -- auto-purchase, default cap, daily
  budget, auto-open-at-AH. Same shape, just relocated. Anchored to
  the top because rare-use controls must not get buried when the
  sidecar grows.
- **Activity feed** (BOTTOM of panel, growable region): bounded
  "last few outcomes" feed. When the sidecar gains a resize handle,
  activity is what expands.

**Two-tier activity model (critical distinction).**
- **Underlying log** (saved-vars, comprehensive): every internal
  addon event, same as today. Not directly visible in-game;
  developer-focused; the source of truth for diagnosis.
- **Sidecar feed view** (user-facing, opinionated filter): shows
  only user-meaningful outcomes derived from the underlying log.
  Purpose: let the user self-diagnose "what did the addon just do,
  and why isn't it doing what I expected." Cadence-based, not
  event-based -- the user sees the last N outcomes that mattered
  to them, not the last N things the addon did.

Sidecar feed inclusion rules (v0.7):
- INCLUDE: purchases (manual and auto), cap changes (row-level
  and global-default), auto-purchase blocks ("skipped Silk Cloth:
  last price 1g 80s over cap", "auto blocked: mail pending").
- EXCLUDE: mail-arrival events (not addon-initiated), session
  boundaries, config-changes-other-than-cap, refresh cycles,
  every-tick internal state, any external-world event the addon
  merely observed. If the addon didn't cause it, it doesn't
  belong in the feed.

Sidecar feed entry shape: `[HH:MM] <verb> <qty>x <item> -- <gold>`
(action-first, absolute HH:MM timestamp, plain English, single line).

Sidecar feed grouping axes (future scope, decision-recorded):
v0.7 ships **session-only** (no selector) to avoid shipping tiny
chips nobody clicks before we know which axes matter. Add a
time-horizon selector (session / today / all-time, or whatever
subset proves useful) once real usage tells us what users
reach for. Data tier already supports arbitrary time filters --
this is UI-only when we're ready. Revisit trigger: user
explicitly wants historical activity, or reports "I lost context
after relogging."

**LogFrame deprecation:** the standalone Activity window
(UI/LogFrame.lua) is retired in v0.7. `/clerk log` is repurposed:
instead of opening LogFrame, it opens a **new dedicated copy-paste
popup** that dumps the VERBOSE underlying log (user outcomes AND
developer events) into a selectable, scrollable text box the user
can copy from. Purpose: shareable diagnostics for bug reports. This
popup is NOT the sidecar feed; the two views serve different
purposes and different audiences.

The `/clerk log` dump popup must NEVER print to the default chat
frame. Chat is precious real estate and a verbose dump would
spam it into unusability.

Cap-change entries in feed use a **10-second debounce**: rapid
edits to the same item's cap coalesce into a single "final value"
entry, logged once the cap has been stable for 10 seconds. Prevents
noise while the user is dialing in a price.

Header polish (v0.7):
- **Version string in title bar.** Read from TOC's `## Version:`
  metadata via `C_AddOns.GetAddOnMetadata`. Format: `Stock Clerk  v0.7.0`
  baseline-aligned, two-space gap, version in a smaller darker-gray
  font. One-line header, not stacked.
- **Bigger close X.** Current close is 28x22; needs to be larger and
  easier to hit. Target ~36x28 or thereabouts, tuned in prototype.
- **Sidecar toggle** (single hamburger button, replaces cog + log)
  sits in the top-right corner alongside the close X. Same slot the
  log button occupies today.

Compression scope (v0.7):
- **Main frame default size**: shopping-list feel, taller than wide,
  ~50% of current area. Prototype starting point ~420x400. Row model
  and column layout unchanged.
- **Resize behavior**: keep the bottom-right resize grip, but enforce
  a hard minimum size at the new compact default. User can grow beyond
  the default freely; can never shrink below it. This is the "floor,
  no ceiling" model.
- **Trash icon on row hover only** -- removes visual noise from rows
  the user isn't actively touching.
- **Filter chip becomes icon-only** -- a small filter glyph in the
  headers strip, tooltip on hover explains "Show only: stuck above
  cap." Frees ~100px of horizontal space in a now-tighter header row.
  Same click behavior, same persistence.
- **Sidecar resize handle deferred to v0.8+.** Sidecar height tracks
  main-frame height (existing behavior); width TBD in prototype but
  fixed for v0.7. Revisit once we know if users actually want to
  expand the activity feed area beyond the default.

AH-dock behavior (v0.7):
- **Dock position**: right of AH, 1px gap between AH's right edge
  and Stock Clerk's left edge. Anchor TOPLEFT of Stock Clerk to
  TOPRIGHT of `AuctionHouseFrame`.
- **Float position**: when AH is closed, Stock Clerk uses its
  remembered per-character float position. AH-open snaps to dock;
  AH-close snaps back to float. `char.ui.floatPos = { x, y }`.
- **`autoOpenAtAH` governs opening only, not docking.** Once Stock
  Clerk is open, it always docks while AH is up regardless of the
  auto-open setting. Different concerns.
- **Overflow at small screen widths** (dock would push sidecar
  off-screen) is not handled in v0.7. User is on 4K; deferred until
  a real report from a low-res tester surfaces.

**Revisit trigger:** if the sidecar accumulates enough content types
that the stacked layout becomes hard to scan (e.g. we add an item
detail pane, prices-over-time, warband view), reshape as **tabs**.
At that point the sidecar has enough content to justify tab UI --
today it doesn't. User approved single-merged-sidecar 2026-09-18
replacing the earlier A+future-C plan.

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
