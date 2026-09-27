# Stock Clerk — Roadmap

Forward plan, one section per release. Dev-only (`Dev/` never ships).
Shipped work moves to `Dev/HISTORY.md`; the player-facing summary goes in
`CHANGELOG.md` when a release is cut (see README → Releasing).

Status key: **Decided**, **Default** (recommended; change it if you
disagree), **Open** (needs an answer before build).

---

## Next session: start here

**2026-09-27:** `v1.2.0-beta2` released. `dev` now holds the full Ponytail
pass for `v1.2.0-beta3` (see that section): needs the player's in-game
check, then swap in the beta3 CHANGELOG and push to cut it. After that:
play on it, then stable `v1.2.0` (stable notes cover everything since
v1.1.1; merge `dev` into `main`).

State: `main` is still v1.1.1 plus the `update.bat` fix.

Session setup: player syncs with `Dev\update.bat dev` and `/reload`;
Claude reads `WTF\Account\SAVAGEFEARLESS\SavedVariables\StockClerk.lua`
via the connected `_retail_` folder (after a `/reload`) for logs. Local
smoke: `lua5.1 Dev/smoke.lua .` (Lua 5.1 builds from github.com/lua/lua
tag v5.1 when no package manager is reachable).

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
- **Decided (2026-09-26):** the main window opens at the bank the same
  way it does at the AH, behind a new Sidecar toggle "Auto-open at Bank",
  **default ON** for now. Without it the only way in at the bank is the
  slash command. Build it right after Feature B (before the executor).
- **Decided:** progress and the summary go in the footer + Sidecar log
  only. No center-screen text (many players hide it with UI addons) and
  no separate popup (the window is open whenever the button is).

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
3. ~~Load `Data/Consumables.lua` from the TOC; Sidecar button; retire
   `Dev/RecommendedLists.lua` and `/clerk seed` → `v1.2.0-alpha1`.~~
   **Done 2026-09-26.**
3b. ~~"Auto-open at Bank" Sidecar toggle (default ON) + bank open/close
   detection (`Banker` interaction type 8, confirmed by the probe).~~
   **Done 2026-09-26:** docks to `BankFrame` when it's showing (stays put
   if a bag addon replaced it); closes with the bank only if it opened
   itself; `ADDON.bankOpen` tracks the banker. Shared `MF:DockTo/Undock`.
4. ~~`BankRestock.lua` planner + smoke tests for the move math.~~ Done.
5. ~~Executor, bank open/close detection, footer button, log kind,
   Sidecar feed, "Auto-open at Bank" toggle~~ **Done 2026-09-26**, shipped
   as `v1.2.0-beta1` (straight from alpha1; no alpha2). Built differently from the plan:
   - One footer button that switches by location ("Restock from Bank (N)"
     at a banker, "Restock at AH (N)" elsewhere) instead of two buttons.
   - The executor re-plans from live bag/bank state before every move
     (no stale plan to drift); whole stacks move by pickup + place, partial
     ones by split + place, always onto a slot the planner sized exactly.
   - No docking at the bank (Baganator and similar replace the bank
     window); the list floats where the user left it.
6. ~~README feature bullets~~ done; field test of `v1.2.0-beta1`.

   **Caveat, not yet tested in-game (2026-09-26):** Restock from Bank with
   bags nearly full, and the bank closing (or any unexpected exit) while a
   pull is running. Expected: the planner stops when no bag slot fits and
   reports "bags are full"; `OnBankClosed` stops the run with "bank
   closed", clears the cursor, and the item mid-move either lands or stays
   in the bank. If a report comes in about items left on the cursor, a
   pull that never ends, or split stacks in odd places, start with
   `BankRestock:_Step` / `Stop` and the per-move timeout.
   Deferred: the AH guardrail "Restock from Bank first" hint (see Later:
   AH and bank open together).
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

### Circle back (noted 2026-09-26)

- ~~Filter chip should show only items you're short on.~~ **Done
  2026-09-26:** replaced "stuck above cap" outright (bags below target).
- **Footer redesign (Decided + done 2026-09-26):** the footer is
  feedback only; the last action message stays until the next one (no
  more "N tracked | N short" summary, which duplicated the red rows and
  kept overwriting feedback). The short count moved onto the button:
  "Restock at AH (3)". Feature A's button follows suit ("Restock from
  Bank (2)"), and when nothing has happened yet at a banker the footer
  shows a hint: "2 short items can come from your bank."

### Open questions

- **Re-clicking "Add common consumables" (Decided):** re-adds any listed
  item you've since removed. The addon doesn't remember removals.

---

## v1.2.0-beta3 — Full Ponytail pass (built on `dev`, awaiting in-game check)

Goal: code a human reviewer reads as deliberate. Whole-repo audit
(2026-09-27), all 22 findings applied; behaviour unchanged unless noted.
Lua: ~5,650 → ~3,330 lines (-41%), one file fewer.

- Every file rewritten or tightened: AH 328→150, Core 441→240,
  RestockLoop 526→248, MainFrame 2,390→1,370, DB, Log, Inventory,
  ItemResolver, panels. Guards for modules that always exist removed;
  dead fields, params and functions removed; stale headers rewritten.
- **Fixed:** the 7 font objects copied themselves (a bulk rename hit the
  table meant to point at Blizzard's fonts). Now 3 white fonts + a grey
  disabled font; same look.
- Caught before shipping: the RestockLoop rewrite briefly let a restock
  stopped mid-search arm the flyout when the search came back; the new
  smoke check found it (old code didn't have this bug).
- Locale.lua inlined and removed (no localization planned; easy to bring
  back). `/clerk dump` and `/clerk pending` removed: the `/clerk log`
  report now lists the items (bags/target, cap) and purchases waiting in
  the mail.
- Log window: the redundant Close button went (× and Escape close it).
- Smoke now covers AH buy planning and confirm-or-cancel, a full restock
  run (arm, double-click, mail ledger, stop), the report, and the flyout,
  drag and dock paths. The AH and restock checks pass on old and new code.

**Player-facing CHANGELOG (draft):**
```
## v1.2.0-beta3

- Under the hood: Stock Clerk's code was tightened throughout (about 40% smaller) with no change to how it works.
- `/clerk log` now also lists your items and anything still waiting in the mail, so a bug report has everything in one paste. `/clerk dump` and `/clerk pending` are gone.

Your list, caps and settings carry over unchanged.
```

---

## v1.2.0-beta2 — Ponytail sweep + UI/UX consistency pass

### Reconciled list (2026-09-26, late session)

**Built on `dev`, awaiting the in-game look:**
- U1 rows 30 → 24px, icons 18px; row text one size smaller; no `[ ]`
  around item names.
- 1px quality border on icons (Baganator style): quality colour for every
  quality (grey poor, white common...), black while the item loads.
- U2 toolbar 48 → 30px: no labels, the placeholder names each box, hover
  tooltips explain. **Cap box removed** (caps are set per row after
  seeing AH prices; Seen stays as the price reference). Item ID stretches.
- The grey hint line moved into the row grip's (≡) tooltip.
- Add → drawn **+** icon button. Bulk import moved to the side panel.
- Side panel (U4): auto-open hints dropped (labels say it); Express-Restock
  explained in tooltips; tooltips on "Add common consumables" and "Bulk
  import item IDs"; labels are clickable; same button style as the main
  window.
- **Express-Restock at Bank** (new setting `autoRestockBank`, default off):
  opening the bank with something short and pullable starts the bank
  pull. Bag space is planned per move (tops up stacks, then empty
  slots); if nothing fits the footer says "Not enough bag space."
  **Known unknown (Decided):** ships without the nearly-full-bags /
  bank-closed-mid-pull test.
- U3 footer Close button removed (× and Escape close); footer 38 → 30px.
- U5 header 32 → 26px; the × is drawn like the other header icons.
- U6 fonts: StockClerk's own font objects (same sizes/colours as the
  Blizzard ones it borrowed). Face = Expressway when LibSharedMedia has
  it (ElvUI, EllesmereUI...), else bundled Barlow Semi Condensed (SIL
  OFL, `Media/`). Expressway can't ship: its free license forbids
  embedding in software.
- U6 wording: no internal terms in player-facing text (Seen tooltip,
  restock-stopped toast, `/clerk pending`).

**Log rework (pulled in from v1.3, Decided 2026-09-27; built on `dev`):**
- One plain-language formatter (`Log:Format`) for the side panel feed and
  `/clerk log`. Levels: **activity** (feed), **detail** (AH searches,
  purchase attempts, footer messages, settings, updates, bank-run
  summaries with stop reason), **trace** (recorded only while
  `/clerk debug` is on; off again after /reload).
- New entries: `bank_run`, `setting`, `version` (once per version
  change), `error` (event-handler errors, logged then passed on to
  BugSack), `trace`. Buffer 500 → 1,000.
- `/clerk log` = support report: version, WoW build, locale, character,
  list size, settings, relevant addons, recording state, then every
  entry (details marked `.`, recorded steps `>`, item IDs included).
  Snapshot, pre-selected for Ctrl+C.
- Help tooltip on "Recent Activity"; the "/clerk log" label is a link.
- **Known limit:** errors raised outside event handlers (button clicks,
  timers) reach BugSack but not the log. Extend if reports show gaps.

**Done 2026-09-27 (on `dev`):** flat checkboxes; C1 comment diet (code
verified unchanged; ~6.8k → ~5.6k lines total); C2 legacy AH events
dropped; C3 `DrawGlyph` / `HeaderIcon` / one Need-Cap cell helper; C4 row
keyboard navigation was already gone; `Dev/STYLE.md` written.

**Before cutting beta2:**
- Player's in-game look at the whole pass.
- ~~C2 AH check~~ **Done:** docking works with Auctionator (it's a tab in the AH window).
- **Decided 2026-09-27:** Enter adds from either box, so the + button
  became **bulk import** (drawn "list +" icon) and left the side panel;
  the Add Tab stop and its keyboard guards are gone (Tab switches boxes).
  Item ID placeholder: "Item ID or drag an item, Enter to add".
- **Fixed:** row hover could stick (leaving through the grip or Seen
  column never cleared it). A hovered row now clears itself once the
  cursor is outside it.
- Bulk import docks beside the main window like the side panel (one open
  at a time), restyled to STYLE.md.
- Bulk import: drop items onto the paste area to add their IDs one per
  line (duplicates skipped; mint border while holding an item).
- Then replace CHANGELOG.md with the beta2 notes below and push to `dev`
  (the push cuts the release).

**v1.2.0-beta2 CHANGELOG (draft; current version only, player-facing):**
```
## v1.2.0-beta2

- New look: a slimmer, tidier window. Smaller rows fit more items, item icons get a clean quality-coloured border, and help text moved into tooltips.
- New: **Express-Restock at Bank.** Turn it on in the side panel and opening your bank pulls anything you're short on. If your bags are full, Stock Clerk tells you.
- The add bar is just Item ID and Target: press Enter to add. Set a price cap on the row after checking the AH.
- The button next to them opens bulk import: drag items from your bags into it one after another (or paste a list of item IDs), then add them all at once.
- Stock Clerk uses Expressway when your UI provides it (ElvUI, EllesmereUI and others), and a similar built-in font otherwise.
- Recent Activity now reads like a receipt: "Bought 20 [Light's Potential] for 412g", with item names in their quality colour.
- Something not working? Hover **Recent Activity**: `/clerk log` gives you a report to paste into a bug report, and `/clerk debug` records extra detail while you repeat the problem.

Your list, caps and settings carry over unchanged.
```

### Audit (2026-09-26)

Baseline: 13 Lua files, ~6.8k lines. `UI/MainFrame.lua` is 3.36k lines,
of which ~1.1k are comments (vs ~2.0k code). The window spends 138px of
its 400px minimum height on chrome (header 32, toolbar 48, column
headers 20, footer 38), leaving ~8.7 rows of 30px.

**UI / real estate** (ranked by space won; each needs an in-game look):
- U1. **Row height 30 → 24** (icon 22 → 18). About 25% more rows in the
  same window; the biggest single gain.
- U2. **Toolbar 48 → ~28px:** drop the labels above Item ID / Target /
  Cap; the placeholders ("e.g. 212283", "e.g. 20", "none") already say
  what goes where. Tooltips carry the rest.
- U3. **Footer Close button → remove** (the header × and Escape already
  close). Gives the footer message ~90px more room; footer 38 → ~30.
- U4. **Side panel hints → tooltips.** Each checkbox carries a 1-2 line
  grey hint (~22px each, 3 of them); moving them into hover tooltips
  gives the activity feed ~65px. Consider 260 → ~230 width.
- U5. **Header 32 → ~26px** (title, version, filter/hamburger/× icons fit).
- U6. **Consistency rules:** one button recipe (StyleButton; tooltips must
  HookScript, never SetScript, or the hover highlight dies: fixed for +
  and Restock in beta1, check the rest), one drawn-icon recipe
  (hamburger, funnel, plus; the header × is still a font glyph), one
  spacing scale, fewer fonts (7 GameFont variants in use today), one
  voice for tooltips/footer text (sentence case, no internal terms like
  "loop", "ledger", "stuck").
- U7. **Decided:** Cap box leaves the toolbar; Last Seen column stays.

**Code** (Ponytail; keep behaviour identical, smoke must stay green):
- C1. **Comment diet in `UI/MainFrame.lua`** (~-500 to -700 lines): version
  history ("v0.4", "V0.7", "QA-11", "PT-1", "KBD-FIX (H1)"...), repeated
  rationale, and narration of what the next line does. Keep the few
  "do not remove, here's why" notes. Same treatment, smaller, for
  RestockLoop.lua (170 comment lines) and DB.lua.
- C2. **Duplicate AH open/close events** (`Core.lua`): both
  `PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE` and
  `AUCTION_HOUSE_SHOW/CLOSED` call the same handlers, so every AH visit
  runs them twice. Delete the legacy pair, but check in-game that the
  window still opens/docks with Auctionator/TSM (the comment says the
  pair was kept "for coverage").
- C3. **`MF:Build` is ~1,350 lines and `BuildRow` ~600.** Not a split for
  its own sake; look for repeated widget recipes (edit-box cells, drawn
  icons, toast lines) that collapse into one helper each.
- C4. **Keyboard soft-select / Tab navigation** carries a lot of guard code
  (8 "KBD-FIX" blocks). Decide whether keyboard row navigation earns its
  keep for a pocket shopping list; if not, removing it deletes the
  guards with it.

Goal: less code and more usable space before stable v1.2.0. No new
features.

**Design intent (Decided):** Stock Clerk should feel like a real-life
shopping list: efficient, "pocket-sized", minimal without being
brutalist. Every pixel and every control has to earn its place.

1. **Ponytail sweep of the whole addon.** Run `/ponytail-audit` over the
   repo, then work the ranked list: dead code, reinvented stdlib, one-use
   abstractions, over-long comments, leftover v0.x scaffolding.
   `UI/MainFrame.lua` (~3.3k lines) is the main target. Keep behaviour
   identical; the smoke test must stay green.
2. **UI/UX consistency audit.** Every control, font, spacing value,
   colour, hover state and tooltip checked against one set of rules:
   - Same button style everywhere (fill, border, hover highlight,
     pressed state); icon buttons drawn the same way (hamburger, funnel,
     plus, close).
   - One spacing scale and one font scale; consistent label casing and
     tone in tooltips and footer messages.
   - Look for real-estate gains: default window size, toolbar (Item ID /
     Target / Cap / Add / +), column widths, the side panel's settings
     block and feed, header height, footer.
3. Write the rules down (short section in the README or a `Dev/STYLE.md`)
   so later features follow them.
4. In-game review → `v1.2.0-beta2`, then stable `v1.2.0`.

---

## v1.3.0 — Activity log

Pulled into v1.2.0-beta2 (see the beta2 section). Left for later, only
if support reports call for it: cover errors from button clicks and
timers too.

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
- Minimap icon to open Stock Clerk, with a settings option to hide it.
- **AH and bank open at the same time** (fringe cases may allow it,
  e.g. a mobile/portable banker next to an auctioneer). Today the footer
  button prefers the bank whenever `ADDON.bankOpen` is true and no AH walk
  is running; decide the priority (or offer both), and revisit the AH
  confirm step's "Restock from Bank first" hint for that case.
- Footer hint at the AH: "3 short, about 1,240g at last seen prices"
  (estimated restock cost; skip stale prices).

The full pre-1.0 backlog text is in git history (`Dev/NOTES.md`, removed
in the commit that added this roadmap).
