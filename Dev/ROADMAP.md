# Stock Clerk — Roadmap

Forward plan, one section per release. Dev-only (`Dev/` never ships).
Shipped work moves to `Dev/HISTORY.md`; the player-facing summary goes in
`CHANGELOG.md` when a release is cut (see README → Releasing).

Status key: **Decided**, **Default** (recommended; change it if you
disagree), **Open** (needs an answer before build).

---

## Next session: start here (paused 2026-09-26)

State: `dev` holds the tested efficiency pass (released as
`v1.1.2-alpha2`), `Data/Consumables.lua` (13 items, not loaded yet) and
this plan. `main` is still v1.1.1. No 1.2 feature code written yet.

First up, in one focused session with the player in-game: the bank-API
probe (task 2 below). **2026-09-26: probe built and pushed to `dev`**
(`Dev/BankProbe.lua`). **Warband results (12.1.0, 2026-09-26):** split to
an empty slot, split onto a partial stack and whole stack via
`UseContainerItem` all work for addons; no blocked actions. Banker
interaction type is `Banker` (8). Three moves in one frame: only 1 lands
(item locks), so the executor must go one move at a time, waiting for
each to land: 300-550ms per move, 3s timeout is ample. A whole-stack
`UseContainerItem` merged onto an existing bag stack by itself. Character
bank confirmed on the same client (13:53 run): splits, whole stack and
pacing identical (326-607ms per move). **Spike done: build Feature A as
planned.** First move of a run is slower (1.2-1.7s); per-move timeout 3s.

- **Run it:** `update.bat dev`, `/reload`, open the bank (open it *after*
  the reload), then `/clerk bankprobe <itemID> scan` (moves nothing),
  then `/clerk bankprobe <itemID>`. `/reload` afterwards saves the log to
  `StockClerkDB.bankProbe` in the SavedVariables file.
- **Step order in the probe:** char split 5 → empty, split 3 → partial,
  3-in-one-frame burst, 3 sequential single moves (latency), whole
  stack; then warband split 5, split 3, whole stack. ~20 per bank covers it.

- **Build:** dev-only `Dev/BankProbe.lua` (~80 lines) in the TOC's
  `#@debug@` block, so it loads from a git checkout (`update.bat dev`)
  and never ships. Command: `/clerk bankprobe <itemID>`. Push to `dev`
  without a CHANGELOG heading, so no release is cut.
- **Player prep:** ~20 of one stackable consumable in the character bank
  and ~20 in the warband bank; a few free bag slots plus one partial
  stack of the same item in bags; at a banker, out of combat.
- **Probe prints one line per step:**
  1. Banker interaction type(s) reported on bank open.
  2. Bank tab IDs (`C_Bank.FetchPurchasedBankTabIDs`, character and
     account) and the slots holding the item.
  3. Whole stack → bags (`C_Container.UseContainerItem`).
  4. Split 5 → empty bag slot; split 3 → existing partial stack
     (`SplitContainerItem` + `PickupContainerItem`).
  5. Same moves from the warband bank.
  6. A quick burst of small moves to find the throttle ("item is
     locked" / "object is busy") → sets the executor's pacing.
- **Player sends back:** the chat output (screenshot or copy) and
  anything that visibly didn't move.
- **Outcome:** all steps work → build Feature A as planned. Moves
  blocked → switch to the "highlight bank slots to click" fallback.

Feature B (Add Common Consumables) doesn't depend on the probe and can
ship as `v1.2.0-alpha1` in the same or a separate session.

---

## v1.2.0 — Efficiency pass + Restock from Bank + Common Consumables

**Decided:** there is no separate v1.1.2 stable. The next stable release
is v1.2.0, and it carries three things:

1. **Ponytail efficiency pass (done, on `dev`, tested in-game).** Shipped to testers as
   `v1.1.2-alpha1` and `v1.1.2-alpha2`; full notes in `Dev/HISTORY.md`.
   - All libraries removed (Ace3, LibStub); events, slash commands and
     saved settings handled natively.
   - Dead code and unused files removed; Need/Cap row editors merged;
     shared palette and style helpers.
   - AH performance: no list rebuild for other addons' item lookups or
     while the window is closed; Sidecar/log redraw only when needed;
     shortfall count without sorting; one fewer bag-count call.
   - `/clerk help` lists every command; README rewritten; CI
     auto-releases from CHANGELOG; `Dev/smoke.lua` added.
2. **Feature B: Add Common Consumables** (below).
3. **Feature A: Restock from Bank** (below).

Prerelease tags continue as `v1.2.0-alphaN` on `dev` (the `v1.1.2-alpha`
tags stay as history). Stable `v1.2.0` ships from `main`.

### Feature A: "Restock from Bank"

**Goal.** At a banker, one button moves exactly enough of each short item
from the character bank and warband bank into bags to reach its target.
No gold spent, nothing moved that isn't on the list, never more than the
shortfall.

**UX**
- New footer button **Restock from Bank**, beside **Restock at AH**.
  Enabled only while the bank is open *and* at least one short item has
  copies in the bank or warband bank; the disabled tooltip says which
  (same pattern as the AH button's disabled reason).
- Click → pulls run in the background (a few per second), then the footer
  shows a summary: "Pulled 3 items from the bank. 1 still short — restock
  at the AH." Each item pulled is logged (new `bank_pull` log kind, shown
  in the Sidecar feed).
- Rows update live as bags change (existing bag-event refresh).
- **Decided:** one click pulls everything; no per-item confirm. Moving
  your own items costs nothing and is reversible, unlike an AH buy.
- **Decided:** the main window auto-docks/opens at the bank the same way
  it does at the AH, behind a new Sidecar toggle "Auto-open at Bank"
  (default OFF). W2-B from the legacy backlog.

**Behavior rules**
- Target = `need − have`, where *have* is the same "effective have" the
  AH loop uses (bags + purchases still in the mail), so bank stock isn't
  pulled for items already on their way. **Decided.**
- **Decided:** character bank first, then warband bank
  (keeps warband stock available to alts).
- Partial stacks: split exactly the remainder; merge onto an existing
  non-full stack of the same item in bags when there is one, otherwise
  use an empty bag slot.
- Bag space: if bags fill up, stop, and report what's still short.
- Abort cleanly (status + log) if the bank closes, you enter combat, or a
  move doesn't land within a timeout. Never leave an item on the cursor:
  refuse to start if the cursor already holds something; `ClearCursor()`
  on any failure.
- Existing AH guardrail (amber "you have N in bank") stays; its hint text
  becomes "Restock from Bank first" when you're at a bank.

**Design**
- New `BankRestock.lua` (~200 lines), loaded after `RestockLoop.lua`.
  - `PlanPulls(shortfalls, sources, bagSlots)` — **pure** function: given
    what's short, what's in each bank slot and what bag room exists,
    returns an ordered list of moves `{ fromBag, fromSlot, count,
    toBag?, toSlot? }`. All the stack/split/space math lives here so the
    smoke test can cover it without WoW.
  - Scanner: bank tab bag IDs from `C_Bank.FetchPurchasedBankTabIDs` for
    the character and account bank types; slots via
    `C_Container.GetContainerNumSlots` / `GetContainerItemInfo`.
  - Executor: one move at a time. Whole stack →
    `C_Container.UseContainerItem`; partial → `SplitContainerItem` then
    `PickupContainerItem` on the target bag slot. Waits for the item lock
    to clear / `BAG_UPDATE_DELAYED` before the next move; timeout per move.
- Bank open/close: `PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE` with the
  banker interaction type (same pattern as the AH in `Core.lua`).
- `Inventory` already reports bank vs warband counts; no change.
- MainFrame: second footer button + enable/disable logic mirroring
  `RefreshRestockBtn`.

**Spike first (half a session, in-game):** confirm on the live client
that `UseContainerItem` / `SplitContainerItem` / `PickupContainerItem`
still move bank ↔ bag items for addons in Midnight (12.x), how fast
moves can be issued before the server throttles, and the exact banker
interaction type(s). The plan above assumes yes; if Blizzard has
restricted it, the fallback is a "highlight what to grab" mode that
lights up the right bank slots for you to click.

**Out of scope for 1.2:** depositing surplus (see v1.3 candidate below);
one-button "bank then AH" (the AH loop
already works off the bag count once the pull is done).

### Feature B: "Add Common Consumables"

**Goal.** One click in the Sidecar fills a fresh list (e.g. on an alt)
with the current expansion's standard consumables; the player removes
what they don't want and restocks from the AH or the bank.

**UX**
- Sidecar settings section: button **Add common consumables**.
- Click → adds every item on the curated list that isn't already tracked,
  with a target of 1. **Decided:** an item you already track is never
  touched (its target and cap stay as you set them). Footer: "Added 12 items. Remove any you don't need with
  the trash icon."
- One log entry for the batch (not one per item).

**Data**
- **Decided:** the list is `Data/Consumables.lua` (already in the repo):
  one itemID per line with its name as a comment, grouped by category in
  comments. Target is 1 for every item for now (may revisit). To change
  the list, edit that file.
- Replaces the debug-only `Dev/RecommendedLists.lua` and `/clerk seed`
  (same idea, now for everyone).
- New expansion or patch = edit that one file; no code change.

**Design**
- ~30 lines: the data file plus an `AddCommonConsumables()` function
  (merge loop, same as today's `RecommendedLists:Apply`) and the Sidecar
  button. Items still loading from the server show as `item:ID` and fill
  in by themselves (existing item-info refresh).

### Tasks (in order)

1. ~~In-game check of the efficiency pass (`v1.1.2-alpha2`).~~ **Done
   2026-09-26:** stable, feels as good or slightly better. It rides along
   in `v1.2.0-alpha1`.
2. In-game spike for Feature A's container calls (see above).
3. Load `Data/Consumables.lua` from the TOC; Sidecar button; retire
   `Dev/RecommendedLists.lua` and `/clerk seed` → `v1.2.0-alpha1`.
4. `BankRestock.lua` planner + smoke tests for the move math.
5. Executor, bank open/close detection, footer button, log kind,
   Sidecar feed, "Auto-open at Bank" toggle → `v1.2.0-alpha2`.
6. AH guardrail hint text; README feature bullets; field test →
   `v1.2.0-beta1`.
7. Stable: CHANGELOG `## v1.2.0` (draft below), detailed entry at the
   top of `Dev/HISTORY.md`, merge `dev` → `main` → CI publishes.

### v1.2.0 player-facing CHANGELOG (draft)

Stable players are coming from v1.1.1, so the stable notes cover
everything since then, not just the last alpha. Keep to this shape and
trim to what actually shipped:

```
## v1.2.0

- New: Restock from Bank. At the bank, one click moves what you're short
  from your bank and warband bank into your bags.
- New: Add common consumables. One click in the side panel fills your
  list with this expansion's staples; remove what you don't need.
- Smoother at the Auction House, especially alongside scanning addons
  like Auctionator or TSM.
- Smaller download: Stock Clerk no longer bundles any libraries.
- `/clerk help` now lists every command.

Your list, caps and settings carry over unchanged.
```

### Open questions

- **Re-clicking "Add common consumables" (Decided):** re-adds any listed
  item you've since removed. The addon doesn't remember removals.

---

## v1.3 candidate — Deposit surplus (depends on 1.2 usage)

Only after Restock from Bank has proven reliable in the field.

- **Decided:** never automatic. Extra copies in your bags are your call;
  the addon doesn't move them unless you press a button.
- Candidate UX: a **Deposit Surplus** button at the bank that moves
  anything above target from bags to the bank, with a choice of
  character bank or warband bank (warband is shared by every character
  on the account; a character bank is only reachable by that character).
- Reuses the 1.2 planner/executor in the other direction.
- Open when scheduled: default destination, whether surplus of
  soulbound items (which can't go in the warband bank) falls back to the
  character bank.

---

## Later (unscheduled)

Carried from the legacy backlog; not committed to a release.

- Auto-loot mailbox attachments for tracked items (warn if Postal or a
  similar addon is loaded).
- Vendor auto-buy for tracked items a merchant sells.
- Per-item "count bank toward Have" mode; warband shopper/quartermaster
  (cross-character restocking).
- Gold/silver/copper cap input; "no cap" as an explicit checkbox.

The full pre-1.0 backlog text is in git history (`Dev/NOTES.md`, removed
in the commit that added this roadmap).
