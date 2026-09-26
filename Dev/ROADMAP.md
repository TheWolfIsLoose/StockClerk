# Stock Clerk — Roadmap

Forward plan, one section per release. Dev-only (`Dev/` never ships).
Shipped work moves to `Dev/HISTORY.md`; the player-facing summary goes in
`CHANGELOG.md` when a release is cut (see README → Releasing).

Status key: **Decided**, **Default** (recommended; change it if you
disagree), **Open** (needs an answer before build).

---

## v1.1.2 — stable (gate before any 1.2 work)

- Test `v1.1.2-alpha2` in-game (list/settings survive `/reload`, AH
  auto-open, row search, one Buy, bank tooltip numbers).
- Merge `dev` → `main` with a `## v1.1.2` CHANGELOG heading → CI
  publishes the stable release.
- 1.2 work then continues on `dev` as `v1.2.0-alphaN`.

---

## v1.2.0 — Restock from Bank + Common Consumables

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

1. In-game spike for Feature A's container calls (see above).
2. Load `Data/Consumables.lua` from the TOC; Sidecar button; retire
   `Dev/RecommendedLists.lua` and `/clerk seed` → `v1.2.0-alpha1`.
3. `BankRestock.lua` planner + smoke tests for the move math.
4. Executor, bank open/close detection, footer button, log kind,
   Sidecar feed, "Auto-open at Bank" toggle → `v1.2.0-alpha2`.
5. AH guardrail hint text; README feature bullets; field test →
   `v1.2.0-beta1`, then `v1.2.0` on `main`.

### Open questions

- **Consumables list (Open):** `241304` is listed as both Light's
  Potential and Silvermoon Healing Potion; one ID is wrong. The healing
  potion line is commented out in the file until confirmed.
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
