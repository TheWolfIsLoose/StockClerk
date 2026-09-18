# Post-v0.6.0 testing queue

Live testing checklist for the v0.6.0 release. Work through these
in-game, capture repro steps + severity for anything that fails,
then feed the surviving list into a v0.6.1 patch cycle.

Format per item: **check**, **what to do**, **expected**, **watch for**.
Severity codes: **B** blocking (blocks release), **M** major (fix
before next tag), **P** polish (backlog).

---

## PT-2 — Quick-add gestures on the Add Item box

### PT-2.1 Shift-click ON the Add box with cursor item _(M)_
- Pick up an item from bags so it's on the cursor
- Shift-click directly on the Add Item box
- **Expected:** Add box fills with the item's numeric ID, cursor
  clears, box gets focus, ID is highlighted so a keystroke replaces
- **Watch for:** duplicate stamping if you shift-click twice; box
  losing focus; ID not highlighting on some clients (that's the
  `C_Timer.After(0, ...)` deferred highlight — should work but
  worth verifying)

### PT-2.2 Drag-and-drop onto the Add box _(M)_
- Pick up an item, drag it onto the Add box, release
- **Expected:** same as PT-2.1 — box fills, cursor clears
- **Watch for:** drop landing anywhere else on the frame that
  produces a bad state (e.g. dropping on the row list vs. the box)

### PT-2.3 Shift-click item link while Add box focused _(M)_
- Click into the Add box to give it focus
- Shift-click an item in chat, in a bag tooltip, in the AH pane,
  in the mail attachment area
- **Expected:** the itemID (numeric, not the full link) lands in
  the Add box; chat is NOT populated with a link
- **Watch for:** chat capturing the link when it shouldn't (i.e.
  `addBox:HasFocus()` guard misfires); non-item hyperlinks
  (spells, quests, achievements) trying to be stamped

### PT-2.4 Chat link-to-chat NOT broken when Add box unfocused _(B)_
- Click elsewhere so the Add box is NOT focused
- Shift-click an item in chat, a tooltip, wherever
- **Expected:** normal Blizzard behavior — link goes to the chat
  edit box, or opens the item link, whatever you're used to
- **Watch for:** the `hooksecurefunc` on `ChatEdit_InsertLink`
  leaking into general chat behavior. This is the highest-risk
  hook in v0.6.

### PT-2.5 Mint drop-zone hint _(P)_
- Move your cursor over an item, pick it up
- **Expected:** the Add box outline lights up mint. Drop or clear
  the cursor and the outline dims back.
- **Watch for:** outline stuck on after the cursor clears (event
  wiring on CURSOR_UPDATE / CURSOR_CHANGED); outline showing
  even without an item on cursor

### PT-2.6 Hover tooltip on the Add box _(P)_
- Mouse over the Add box (empty cursor)
- **Expected:** tooltip shows the three gestures. Existing border
  hover animation still fires.
- **Watch for:** border-hover animation broken (the HookScript vs
  SetScript fix from v0.6 is exactly what this tests)

### PT-2.7 Enter still commits, gestures don't _(B)_
- Use any gesture to fill the box
- Do NOT press Enter — click elsewhere to defocus
- **Expected:** nothing gets added. Only Enter commits.
- **Watch for:** an unintended commit path (implicit blur = add)

---

## PT-3 — Stuck-above-cap filter chip

### PT-3.1 Chip toggles filter _(M)_
- Populate a few rows: some with lastPrice > cap, some ≤ cap,
  some with no lastPrice at all
- Click the filter chip
- **Expected:** only rows where fresh lastPrice > cap remain
  visible. Click again — everything returns.
- **Watch for:** rows with STALE lastPrice appearing (they
  shouldn't; TTL is 24h)

### PT-3.2 Filter persists per character _(M)_
- Toggle filter ON, `/reload`
- **Expected:** filter still ON on same character
- Log to a different character
- **Expected:** filter state on the alt is independent

### PT-3.3 Empty-state copy under active filter _(P)_
- Toggle filter ON when nothing is stuck
- **Expected:** custom empty message ("No items currently priced
  above cap...") + status bar reads "0 stuck items (filter active)"
- **Watch for:** the default `EMPTY_LIST` copy leaking through

### PT-3.4 Chip visual states _(P)_
- OFF: hollow with mint outline + mint text
- ON: solid mint fill + dark text
- Hover: tooltip explains what it filters
- **Watch for:** paint out of sync with actual state after
  `/reload` or after adding new items

### PT-3.5 Cap column tri-state coloring _(M)_
- Set caps on three rows: one with fresh lastPrice ≤ cap, one with
  fresh lastPrice > cap, one with cap set but no lastPrice yet
- **Expected:**
  - mint value → ready (last price at/under cap)
  - pink value → stuck (last price above cap)
  - muted gray-mint value → unknown (no fresh data)
- **Watch for:** old two-state behavior (just mint + pink)
  leaking through

### PT-3.6 Chip position under window resize _(P)_
- Drag the window wider / narrower
- **Expected:** chip stays anchored on the right side of the
  headers strip, doesn't clip or collide with column headers

---

## Regression sweep (pre-v0.6 features still work)

### R.1 Inline row edit still works _(B)_
- Click a row's cap value, edit, press Enter/Tab
- **Expected:** unchanged from v0.5

### R.2 Manual restock still works _(B)_
- At AH, hit Restock
- **Expected:** unchanged from v0.5

### R.3 Auto restock still works _(B)_
- Enable auto, visit AH
- **Expected:** unchanged from v0.5, including the pendingBuys
  mail-delivery gate from v0.5

### R.4 `/clerk` commands still respond _(M)_
- Try `/clerk`, `/clerk pending`, `/clerk budget`
- **Expected:** each prints something coherent, no Lua errors

### R.5 Activity log still records buys/expenses _(M)_
- Do a manual buy from AH
- **Expected:** entry lands in the log, no "N items tracked"
  status-history spam from v0.6 filter-driven refreshes

### R.6 Saved variables migration is silent _(B)_
- Load with pre-v0.6 saved variables (i.e. no `char.ui`)
- **Expected:** no Lua error; `char.ui.stuckOnly` gets defaulted
  to false, everything else untouched

---

## Meta / release health

### RH.1 No Lua errors on fresh load _(B)_
- With BugSack or `/console scriptErrors 1`
- Load into game, open Stock Clerk, close it, `/reload`
- **Expected:** zero errors

### RH.2 CurseForge v0.6.0 clears approval _(B)_
- Check https://www.curseforge.com/wow/addons/stock-clerk/files
  in the morning
- **Expected:** v0.6.0 status = Approved

### RH.3 GitHub release visible _(P)_
- https://github.com/TheWolfIsLoose/StockClerk/releases
- **Expected:** v0.6.0 shown with the full changelog notes

---

## After the sweep

- File any B/M failures as v0.6.1 patch scope
- Any P items go to Dev/NOTES.md polish section
- If everything passes, PT-2 and PT-3 revisit checkpoints in
  section 3.4a start their observation window from today
