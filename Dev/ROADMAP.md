# Stock Clerk — Roadmap

Forward plan, one section per release. Dev-only (`Dev/` never ships).
Shipped work moves to `Dev/HISTORY.md`; the player-facing summary goes in
`CHANGELOG.md` when a release is cut (see `Dev/RELEASING.md`).

Status key: **Decided**, **Default** (recommended; change it if you
disagree), **Open** (needs an answer before build).

---

## Next session: start here

**2026-09-28: stable v1.3.0 released** (`main` = `dev`). Warband list,
warband AH pass, deposit. Open follow-ups:
1. Not yet covered in-game: buy on one character, switch before
   depositing (transit: not short there); a soulbound listed item at
   Deposit (red mark, footer); a full warband bank.
2. Tab deposit-filter preference if the probe (`/clerk bankprobe
   <itemID>`) shows filters matter.
3. Player: paste the updated copy into CurseForge (same wording as the
   README intro and the two new feature bullets).

Pending on the player's side: paste the CurseForge description and the
GitHub "About" line (drafted in the 2026-09-27 session: pitch "A
pocket-sized shopping list for WoW consumables..."; README intro is the
same copy).

State: `main` = `dev` = v1.2.0.

Session setup: player syncs with `Dev\update.bat dev` and `/reload`;
Claude reads `WTF\Account\SAVAGEFEARLESS\SavedVariables\StockClerk.lua`
via the connected `_retail_` folder (after a `/reload`) for logs. Local
smoke: `lua5.1 Dev/smoke.lua .` (Lua 5.1 builds from github.com/lua/lua
tag v5.1 when no package manager is reachable). Pushing needs the repo
attached with push access (add_repo), then `git push origin dev`. Wait for
a release push's tag (`git ls-remote --tags origin`) before pushing again.

---

## Checkout mode (v1.2.0-beta4): replace the AH buy flyout (released 2026-09-27)

Every AH purchase needs a player click (hardware event), so the run is
always one click per item; this redesigns everything around that click.

**Problems with today's flyout** (below the window, `MF:BuildToast`):
out of the eye line (hangs under the window, can land on chat or off
screen); shows one item with no view of the queue, progress or total;
Buy moves ~6px when the stash lines grow it (breaks click rhythm); Stop
lives in three places (footer button, hidden right-click, Escape); the
1.5s lock on every Buy adds ~15s to a 10-item run and trains wait-then-
click (alarm fatigue); over-cap items skip silently; the summary auto-
closes after 3s (breaks the footer-keeps-feedback rule); the pulsing amber
border is animation noise.

**Design (Decided in principle):** the run happens in the list itself,
like ticking off a paper shopping list.
- **Footer becomes the checkout bar** while a run is active: line 1
  "16 x Flask of the Shattered Sun · 7,424g"; line 2 warnings (amber
  "You have 12 in your bank", "No cap set"); progress "2 of 4 · spent
  2,420g"; [Skip] [Buy], with **Buy exactly where the Restock button
  sits** so Restock, Buy, Buy... never moves the mouse and never shifts.
- **Rows show run state:** bought ✓, current ▶ (highlighted, scrolled
  into view), queued ·, over cap ⊘ (tooltip: cheapest price). An over-cap
  item is visible and its Cap cell is right there to edit; the next run
  uses it.
- **Friction only where there's risk:** Buy is live at once; the short
  lock applies only when there's no cap, copies in bank/warband, or a
  price well above Last Seen.
- **One Stop:** Escape or a small × in the checkout bar. Drop the right-
  click gesture.
- **End of run** stays in the footer ("Done: bought 3 for 1,219g · 1 over
  cap · check your mail"); row marks stay until the list changes or the
  AH closes. The log keeps the receipt.
- **Restock from Bank** uses the same pattern (rows tick as items pull).
- Expected to remove code: the flyout, its pulse ticker and layout
  juggling (~150 lines).
- Open detail: lock drag-reorder during a run (the queue is a snapshot);
  keep Cap editing live.

**As built (2026-09-27).** Smoke covers the run end to end (risk lock,
debounce, double click, marks, receipt, over cap, late results after Stop).
- The Restock button *is* Buy during a run: it narrows 160 → 100px with
  the same right edge, so it still covers where Restock was clicked. Skip
  (50px) sits left of it; the × is at the footer's far left, away from
  both. Footer stays 30px: line 1 "20 × Name", line 2 "4,880g" + grey
  "2 of 4 · spent 2,420g" or amber warnings.
- **Default:** Buy locks 1.5s (label "Buy (2)") only with a warning: copies
  in bank/warband, no cap, or average unit price > 125% of the Last Seen
  read *before* this search. Otherwise Buy is live, except within 0.5s of
  the player's last click (Restock, Buy, Skip), which stops a double-click
  on Restock from buying. Buy's tooltip repeats the warnings in full.
- Marks sit in the grip's slot (drawn: dot, chevron, check, dash); the
  current row gets a faint mint wash and mint accent and scrolls into view.
  Grip tooltip leads with the mark's detail ("Bought 20 for 4,880g, on its
  way by mail", "Over your cap: cheapest is 465g 98s"). Rows the run never
  reached lose their marks on Stop; the rest clear when the AH/bank closes.
- **Decided (open detail):** drag-reorder is locked during a run; Cap
  editing stays live (the next run uses it). Also: clicking a row to search
  is off during a run (it would cancel the run's own search).
- Receipt in the footer: "Done: bought 3 for 1,219g · 1 over cap · 1 not
  bought" (Stopped / AH closed variants). No "check your mail": it
  truncated even above min width, and the tick's tooltip says "on its way
  by mail" (Decided 2026-09-27; players keep the window small).
- Bank: same bar ("Pulling 20 × Name", "2 items pulled so far"), button
  reads "Pulling..." (disabled), × or Escape stops; rows tick as items land.
- Flyout, its countdown/pulse tickers and right-click stop removed:
  MainFrame 1,370 → 1,328 lines with the marks and checkout bar added.
- `AH:BuyUpTo` now returns the cheapest price as a third value when every
  listing is over the cap (replaces matching the error text).

**In-game checklist:** Restock at AH with 3+ short items (one capped
below market, one uncapped, one with bank copies): marks, current row
scrolls into view, Buy stays under the cursor, "Buy (2)" only on the
risky ones, Skip, × and Escape, receipt. Double-click Restock must not
buy. Restock from Bank: rows tick, × stops. Footer text legibility at
the 420px minimum width (two lines in 30px).

**v1.2.0-beta4 CHANGELOG (draft):**
```
## v1.2.0-beta4

- New: **checkout at the Auction House.** Restock at AH now works like ticking off a shopping list. The item and its price show at the bottom of the window, and **Buy** appears right where the Restock button was, so you can buy item after item without moving the mouse.
- Rows tick off as you go: bought, skipped, or over your cap (hover the mark to see the cheapest price, then set a new cap right there).
- Buy only waits a moment when something needs a second look: you have copies in your bank, the item has no cap, or the price is well above what you last saw.
- Stop any time with Escape or the x at the bottom left. The end-of-run receipt stays at the bottom of the window.
- Restock from Bank ticks rows off the same way.

Your list, caps and settings carry over unchanged.
```

**Rejected / shelved (Decided):**
- A third docked "restock" panel: duplicates the visible list, and at the
  AH (window docked to the AH's right edge) another 260px doesn't fit
  many screens.
- **Quote pass** (price every item before the first Buy): shelved. It
  adds addon-generated wait at AH open, which slows a quick restock
  between dungeons; a background version would compete with each Buy's
  own search (one search at a time).
- **Keybind for Buy:** shelved (player's call).

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

## v1.2.0-beta3 — Full Ponytail pass (released 2026-09-27)

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

## v1.3.0 — Warband list: shared stock in the warband bank (v1.3.0-beta1 built 2026-09-28)

**Goal.** Let players keep shared stock in the warband bank, bought by
whichever character is at the AH, and keep every character's own bags
topped up from it (v1.2 Restock from Bank).

**Why not a "supplier mode" (Decided 2026-09-28).** A per-character
switch assumed a character is either a buyer or a consumer. The player's
main is both: it keeps its own list and also buys in bulk for alts. The
role belongs to the list, not the character.

**Design (Decided 2026-09-28)**
- **Two lists, two lanes; scope is only items you've listed.**
  - **Personal list** (per character, as today): Target = keep N in my
    bags.
  - **Warband list** (new, account-wide, one target per item): keep **at
    least** N in the warband bank. It drives buying only. The same item
    can sit on both lists with different numbers.
- **Surplus is defined by the personal list**: anything above a listed
  item's personal target is surplus, because stock in one character's
  bags is useless to the others. Surplus belongs in the warband bank,
  whether it came from the AH, crafting or anywhere else. Deposits are
  not capped by the warband target (it's a floor for buying, not a cap).
  An item on the warband list but not this character's personal list
  counts as personal target 0 (all of it deposits: the pure buyer alt).
- **At the AH:** personal checkout first; then, if anything on the
  warband list is short, an optional continuation ("Warband: 3 short,
  ~12,400g"). A second pass, not a combined buy: **each list has its own
  caps** (Decided 2026-09-28: pay more for tonight's flasks, less for
  bulk), and skipping the warband step leaves the personal run intact.
- **At the bank, per listed item:** short in bags → pull from the warband
  (v1.2); over the personal target → deposit the extra to the warband.
  Never both for one item in one visit. The deposit is a continuation
  after the personal pull ("Warband: deposit 20 flasks"): still a click,
  never automatic (Express-Restock never deposits). Items the warband
  bank refuses (soulbound etc.) are skipped and named in the footer.
- **Pulls may drop the warband below its floor**: personal needs come
  first; the warband list then shows it short and the next AH trip
  refills it.
- **Per-character setting "Never ask this character to restock the
  warband"**: hides the AH continuation only. Deposits are never
  blocked (a crafter alt that never shops is exactly who makes surplus).
- **Superseded:** supplier mode, the "Warband" Have-header swap, the
  standalone surplus-deposit button, Copy list (bulk import covers list
  setup: `ID target cap` per line).

**Engine (Default):** `BR.PlanPulls` is direction-free; a deposit is
PlanPulls with bag slots as sources, warband tab slots as targets and the
surplus as amounts. "Landed" check: target slot grew and the cursor is
empty. Warband counts are readable anywhere (`GetItemCount` account
flag), so AH checkout knows warband stock without a bank visit.

**UI (Default, proposed 2026-09-28)**
- Header switch, text only: `Mine · Warband 3` between version and the
  icons; active word lit, the inactive side shows its short count. Last
  view remembered per character. The view changes what you see and where
  adds go (add box, drag, bulk import, Add common consumables); it never
  changes what Restock does.
- **Both cues in the Warband view (Decided):** Target header reads
  "Keep ≥", and the accent colour switches from mint to a warband blue.
  The accent follows the lane of whatever is happening: the warband AH
  continuation and bank deposit use blue for the current row, marks and
  bar. The "Stock" in the title stays mint (brand, not state). Colour is
  never the only cue (header word + "Keep ≥").

- **Warband blue = #5AA9FF (Decided 2026-09-28).** Separated from mint
  by lightness, not just hue (mint luminance 0.81, blue 0.38: 2.0:1 apart),
  so it holds under colour-deficiency correction filters and every CVD
  type (tritan included, where mint vs cyan would merge). 8.2:1 on the
  window background. WoW's own #00CCFF was rejected: only 1.5:1 from mint.

- **Opt-out (Decided copy):** side-panel checkbox, per character, on by
  default: "Shop for the warband on this character". Tooltip: "Offer to
  restock the warband list after your own shopping at the Auction House.
  Surplus is always deposited at the bank." **Check it fits the side
  panel at its current width; the panel must not get wider** (reword or
  wrap the label instead).
- **Bank continuation (Decided copy):** personal pull as today, then the
  footer reads "Warband: deposit 3 items" and the button turns blue,
  "Deposit". Rows tick blue. Receipt: "Done: pulled 2 · deposited 3 to
  the warband" (+ "· 1 can't go in the warband", hover for which).
  Nothing to pull → deposit offered at once; nothing to deposit → no
  step.

**More decisions (2026-09-28)**
- **Mail guardrail (Decided):** warband Have = warband bank + bags +
  purchases still in the mail, so a second AH trip before looting never
  rebuys. Never tell the player to buy what's already on its way. The bank
  step notes mail it can't deposit yet ("3 more waiting in your mail").
- **Deposit target (Decided):** top up an existing stack of the item →
  a tab whose deposit filter matches → any free slot. Warband full →
  footer "Warband bank is full". (Spike confirms whether filters bind.)
- **Header (Decided):** keep the version in the header, a size smaller if
  needed to fit `Mine · Warband 3` at 420px; move it to the side panel
  only if it truly can't fit.
- **Empty Warband view (Decided):** one line of guidance, e.g. "Keep at
  least this many in your warband bank, for all your characters.
  Anything above your own targets is deposited here." Final copy at build.
- **Shared price history (Decided):** Last Seen moves from each
  character's item entry (`StockClerkCharDB.items[id].lastPrice`) to
  account-wide `StockClerkDB.global.prices[id]`, recorded for items on
  either list; on first load fold existing per-character prices in
  (newest wins). Lives in DB.lua (it already owns both saved tables), so
  no new file unless it grows.
- **Activity log (Decided):** deposits and warband buys get their own
  lines, e.g. "Deposited 20 × Flask to warband (tab 2)", plus skips
  (refused, full).
- **Naming (Decided):** UI copy says "warband" / "warband bank" (the
  game's term), never "warbank".
- Storage: warband list in account-wide `StockClerkDB.global`.

**Open (UI)**
- None left; remaining details settle at build/in-game review.

**As built (v1.3.0-beta1)**, see `Dev/HISTORY.md`. Deviations and gaps:
- 2026-09-28 in-game fixes: bulk import title follows the accent; side
  panel ticks stay mint (settings aren't a list view); empty Warband copy
  rewritten in the same shape as the Mine list's; "Keep ≥" → "Keep".
- **Tab deposit-filter preference not built yet:** deposits fill existing
  stacks, then free slots in tab order. Mapping item types to tab filter
  flags can't be verified outside the game; waits on the probe.
- The warband pass is offered once your own list has nothing short (the
  button becomes "Restock warband (N)"), and the receipt says "warband: N
  short". Deposit marks are blue in either view; a deposit doesn't switch
  the view (its items can be on either list). A pull switches to Mine; a
  warband AH pass switches to Warband.
- Warband shopping is a second pass, not a combined buy (per-list caps).

**Built 2026-09-28 (`Loop:NextLane`):** at the AH the button offers
whichever list hasn't run yet this visit, yours first. Today the warband
pass is only offered when your own list has nothing short, so an over-cap,
skipped or failed item blocks it for the whole visit. New flow: open AH →
"Restock at AH (N)"; after that run ends (even with leftovers) → "Restock
warband (N)"; after the warband pass, back to "Restock at AH (N)" if still
short (a cap may have been raised); AH close resets.

**Bug (found in the 2026-09-28 AH + bank log; fixed the same day):** deposit
"a move didn't finish" (Phoenix Oil, twice; a third press finished). The
deposit "landed" check is "bag count dropped and cursor empty", which is
true the instant the client places the stack, before the server confirms.
The next move is planned at once and targets the same warband stack while
it's still locked; the drop fails and times out (the stalled stacks did
land later: Phoenix Oil reached 100, the log counted 20 short). (Pulls don't hit this:
their bag count only rises on server confirmation.) Fix, as the design
said: landed = target slot shows the new count, unlocked, cursor empty;
and never pick a locked warband slot as a target.

**In-game checklist (beta1)**
- Header at 420px: `StockClerk <version>  Mine · Warband N  ≡ ×` fits.
  (2026-09-28: fits. "≥" doesn't render in WoW's fonts: header is "Keep".)
- Side panel: "Shop for the warband on this character" fits without
  widening the panel; Recent Activity still lines up below it.
- Switch views: accent turns blue (hover borders, headers, filter, drop
  outline), title "Stock" stays mint, list and empty text change; adds,
  drag, bulk import and Add common consumables go to the visible list.
- AH: own list first; then "Restock warband (N)" (blue) with its caps;
  Buy has no "in your warband bank" warning on that pass; receipt.
  Untick the side-panel box: no warband offer.
- Mail guardrail: buy warband stock, don't loot, reopen the AH: not short
  again. Log onto another character before depositing: not short there
  either (transit).
- Bank: pull as before; then "Deposit (N)" (blue): rows tick blue, receipt
  "Done: deposited N to the warband"; a soulbound listed item gets the red
  mark "Can't go in the warband bank"; mail note when purchases are unlooted.

**v1.3.0-beta1 CHANGELOG (released 2026-09-28):**
```
## v1.3.0-beta1

- New: **Warband list.** Switch between **Mine** and **Warband** at the top of the window. The warband list says how many to keep, at least, in your warband bank for all your characters.
- After your own shopping at the Auction House, Stock Clerk offers to restock the warband list, with its own price caps. Turn this off per character in the side panel ("Shop for the warband on this character").
- New: **Deposit** at the bank. Anything above your own targets goes into the warband bank, where every character can restock from it. Always a button, never automatic.
- Purchases still in the mail, and warband buys your other characters haven't deposited yet, count as stock, so nothing gets bought twice.
- Last Seen prices are now shared by all your characters.

Your list, caps and settings carry over unchanged.
```

**Release (stable v1.3.0):** updated public copy (README, CurseForge) and
hero shots of the Warband Bank stock.

**Spike (short, in-game; probe on `dev`: `/clerk bankprobe <itemID>`):**
placing a bag stack into a warband tab slot from addon code; tab deposit
filters vs addon placement; how fast deposits chain.

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
