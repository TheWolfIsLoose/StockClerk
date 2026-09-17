# Stock Clerk — Design Notes / Backlog

Living list of Wave 2+ features and open design questions. Not user-facing;
excluded from packaged releases via `.pkgmeta` (`Dev/` is ignored).

---

## Wave 2 — Automation scope (already agreed)

- **Mail auto-collect** — `TakeInboxItem` / `AutoLootMailItem` on `MAIL_INBOX_UPDATE`, filtered to items that are on the tracked list AND below target.
- **Bank auto-pull** — `UseContainerItem` on `BANKFRAME_OPENED`, same filter, respects warband bank + reagent bank.
- **Vendor auto-buy** — `BuyMerchantItem` on `MERCHANT_SHOW`, only for items the vendor actually sells (walk merchant slot list first).
- **AH shopping-list queue** — detect Auctionator via `_G.Auctionator`, hand off short-list via its documented SavedVariables shape. Fallback: build our own C_AuctionHouse.SendSearchQuery queue (100/min rate limit; back off automatically).

---

## Wave 2 — Price thresholds (added 2026-09-16)

**User goal:** don't blindly buy from the AH at any cost. Let the user
set a max acceptable price per item, and skip that item from any
auto-buy pass when the current best offer exceeds it.

### Data model
Extend `DB.lua` per-item schema:

```lua
char.items[itemID] = {
    need         = 20,      -- existing
    maxPrice     = nil,     -- in copper; nil = no cap, buy at any price
    priceSource  = "ah",    -- "ah" (Auction House) | "vendor" | "any"
    lastSeenPrice = nil,    -- copper, updated when we observe an AH scan
}
```

Copper as the storage unit keeps math integer-safe. Display converts to
`g / s / c` in the UI.

### UI surface
Add a fourth interactive zone on each row, to the left of the trash
icon: a small gold-coin button showing `≤ 45g` (or "any" if unset).
Click → popup with three inputs (gold, silver, copper) + a
"buy at any price" checkbox. Save persists to `char.items[id].maxPrice`.

Alternate cheaper implementation for v1: right-click row → context menu
with "Set price threshold..." → same popup.

### Behavior
- **Vendor buy**: cheap enough that price checks are usually
  unnecessary. Only enforce threshold if vendor price actually
  exceeds it — most consumables from an NPC are pennies.
- **AH auto-buy** (once we get there): before purchase, compare best
  buyout against `maxPrice`. If exceeds, skip and surface in a
  "waiting on price" section of the UI with the last-seen price.
- **AH scan results caching**: whenever we run a search, write
  `lastSeenPrice` so users can see current market vs. their cap without
  reopening the AH.

### Open questions
- Per-item threshold vs. per-category threshold vs. a global default?
  Per-item is most flexible but tedious to set. Suggest a global
  default (e.g. "500g") that individual items can override.
- Warn user if threshold is unreachable (last-seen price has been
  above it for N days)? Feels like scope creep for v1.
- Percentile-based thresholds ("only buy in the bottom 20% of recent
  observations") — powerful but expensive. Defer to a later wave.

### Priority
Low-medium. Not blocking the initial Wave 2 (mail/bank/vendor
auto-collect ships without it), but must ship before any AH auto-buy.

---

## Wave 2 — Paste-a-recipe / bulk import (added 2026-09-16)

**User goal:** many consumables (esp. food) are crafted from several
component items — some AH-sourced, some vendor-only. User wants to
paste a whole recipe (or shopping list) into Stock Clerk in one shot
and have it tracked as a personal keep-stocked-for-crafting inventory,
rather than adding items one at a time.

### Sources to accept (in priority order)
1. **Whitespace-separated item links**  — the format WoW itself uses when
   you shift-click into chat. Trivial to parse: match every
   `|Hitem:<itemID>:...|h[Name]|h|r` occurrence, extract itemID.
2. **Bare itemIDs** — space/comma/newline separated, e.g.
   `241308 271883 241305`.
3. **`<qty>x<link>` or `<qty>x<itemID>`** — lets the user encode the
   target quantity per line, matching how recipes list reagents
   (e.g. `5xFlask of the Shattered Sun`, or crafting UI "5 Sacred Salt
   + 2 Dreaming Essence"). Default quantity when omitted: use the
   user's global default target, or 20 if none.
4. **Recipe / "crafts N of item X" header line** — optional. First
   line matching `^# ?(.+)$` becomes a group name (see Groups below).
5. **Wowhead-style dumps** (stretch) — they publish recipes as HTML
   with item links; if we can grab plaintext from clipboard we can
   parse it. Not a v1 requirement.

### UI surface
- New button in the header row: **"Paste List"** (or a `/clerk paste`
  slash subcommand).
- Opens a modal with a multi-line EditBox and a preview pane that
  parses as-you-type: "Will add 7 items: [icon] Silvermoon Flask x5,
  [icon] Dreaming Essence x10, ...".
- Buttons: "Add to list", "Replace list", "Cancel".

### Data model considerations
This pairs naturally with a **Groups** concept:

```lua
char.items[itemID] = {
    need         = 20,
    -- ... existing fields ...
    groups       = { "Feast of the Fishmonger", "Weekly Raid Prep" },
}
```

A group is just a tag; the UI can filter/collapse by group. Pasted
recipes auto-tag with the header line if present. Enables future
"cook this recipe now?" flow: check that every item in the group has
`have >= need`, then optionally trigger the crafting action.

### Open questions
- Do we dedupe on paste (item already tracked → bump target vs.
  overwrite vs. leave alone)? Suggest: default to `max(existing, pasted)`
  with a checkbox to override.
- Does pasting persist to the character or the warband/account?
  Depends on the shared-warband feature below.

### Priority
Medium. High user value for the crafting/food workflow, and unblocks
the cross-character quartermaster feature described next.

---

## Wave 3+ — Storage-vs-cap and warband quartermaster (added 2026-09-16)

**User goal (part 1):** currently `Inventory:GetCount` rolls up bags +
bank + reagent bank + warband bank as one number. The user wants to
distinguish between:

- **Immediately-usable stock** — items in bags on the current
  character. This is what counts toward the target for "am I ready
  to raid/cook right now?".
- **Reserve stock** — items sitting in bank / warband bank / on other
  characters. Visible in the UI so the user knows the item exists,
  but does *not* count toward the target and does not suppress
  restocking.

**User goal (part 2):** dedicate one character as the "shopper" —
that character does all AH buying and mail collection, then deposits
into the warband bank. Other characters withdraw from the warband
bank as they need supplies. Stock Clerk should be aware of this and
not double-count.

### Data model

```lua
-- Per-item settings (character-scoped)
char.items[itemID] = {
    need           = 20,
    countMode      = "bagsOnly",   -- "bagsOnly" | "bagsAndBank" | "all"
    reserveSources = { "warband" }, -- what to show as reserve
    -- ... existing fields ...
}

-- Global settings (warband-scoped, shared across chars)
warband.settings = {
    shopperCharacter = "Jakerator-Illidan",  -- who does the buying
    depositTo        = "warband",             -- where they drop items
}
```

### UI surface
- Row shows two numbers when reserve > 0:  
  `12 / 20  (+34 in warband)`
- The pill (short/OK indicator) is driven by the primary count only,
  so a bags-only character correctly shows "restock" even if warband
  has plenty.
- Right-click row → "Count mode" submenu: Bags only / Bags + bank /
  Everything.
- Character selector in the header shows role: `🛒 Shopper` /
  `📦 Consumer`.

### Behavior
- **Shopper character**: `countMode = "all"` by default. Auto-buy /
  mail-collect targets are the SUM of all consumer needs, not just
  the shopper's own need. When shopper deposits into warband, other
  characters see their reserve number tick up.
- **Consumer character**: `countMode = "bagsOnly"` by default. Their
  restock target is what they personally consume between raids. When
  they open the bank and pull from warband, their bag count catches
  up naturally; nothing extra to do.
- **Aggregation across characters**: warband bank items are the same
  across all characters, so `C_Item.GetItemCount(id, ..., true)`
  already returns the shared number. Bag counts are per-character; we
  already store per-character DBs so this Just Works if we scan on
  logout / login (`PLAYER_LOGOUT` → write bag counts to warband-scoped
  saved var so shopper can see "consumers need X").

### API notes
- `C_Item.GetItemCount(itemID, includeBank, includeUses,
   includeReagentBank, includeAccountBank)` — 5th arg (added 11.0) is
  the warband/account bank. Pass `true` for reserve, `false` for the
  bags-only mode.
- Bags-only is `C_Item.GetItemCount(id, false, false, false, false)`.
- Bags + bank + warband is `C_Item.GetItemCount(id, true, false, true, true)`
  (what we do today).

### Open questions
- Do we want to model **guild bank** as another reserve source? Adds
  a lot of scanning code; skip for v1.
- How does the shopper know what to buy for consumers who haven't
  logged in recently? Cache last-known bag counts per-character with a
  timestamp; show stale data with an age indicator ("2d ago").
- Do we auto-detect the shopper role, or is it a manual toggle? Manual
  is simpler and less surprising; auto-detect can wait.

### Priority
Medium-low for the count-mode split (nice quality-of-life, unlocks
accurate restocking on the consumer side). Higher for the shopper
role once Wave 2 auto-buy lands — without shopper awareness, every
character would try to buy the same items.

---

## Wave 2: bank / warband auto-open+close (2026-09-16)

AH auto-open+close now works via PLAYER_INTERACTION_MANAGER_FRAME_SHOW
/HIDE. Same treatment for the personal bank and warband bank is a
natural companion feature and pairs directly with the planned
"auto-pull from bank" automation.

Events to hook:
  - `BANKFRAME_OPENED` / `BANKFRAME_CLOSED` (personal bank)
  - `PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE` with
    Enum.PlayerInteractionType.BankBanker (or the warband equivalent
    -- verify against Interaction Manager enum in 12.1)

Same `openedByBank` / `openedByWarband` flag pattern as the AH path.
Only close if we opened it, so a user with SC pinned open doesn't
lose their window every time they visit the bank.

---

## Integration reference: Syndicator (added 2026-09-16)

Syndicator (by plusmouse; Interface 120100+) is the industry-standard
databasing addon that powers Baganator. It already solves the exact
sub-problem the shopper role needs: **cross-character bag / bank /
warband / mail counts, persisted even when the character is offline**.

Rather than write our own multi-character cache, detect Syndicator and
delegate — same pattern we already use for Auctionator on the AH side.

### Detection
```lua
local syn = _G.Syndicator
if syn and syn.API and syn.API.IsReady and syn.API.IsReady() then
    -- safe to call
end
```

### Key API calls (from `Syndicator/API/Main.lua`)
- `Syndicator.API.GetInventoryInfoByItemID(itemID, sameConnectedRealm, sameFaction)`  
  Returns a breakdown of which characters/guilds hold that item and how
  many. This is the whole shopper query in one call.
- `Syndicator.API.GetAllCharacters()` → list of `"Name-Realm"` keys.
- `Syndicator.API.GetByCharacterFullName(name)` → full character bag +
  bank data, offline-safe.
- `Syndicator.API.GetWarband(index)` → warband bank data (index 1 for
  the primary warband).
- `Syndicator.API.GetCurrentCharacter()` → the logged-in character's
  full-name key, so we can distinguish self vs. alts.
- `Syndicator.API.IsReady()` → handshake; wait for it before querying.

### SavedVariables (do NOT read directly — use the API)
- `SYNDICATOR_DATA` — `.Characters[name]`, `.Guilds[name]`, `.Warband[i]`
- `SYNDICATOR_SUMMARIES` — pre-aggregated by-realm rollups

### Implication for our design
- **Baseline** (no Syndicator): each character sees only its own bag +
  bank + warband count via `C_Item.GetItemCount`. Consumer stays in
  `bagsOnly`, shopper uses `all`.
- **With Syndicator**: shopper can display *every* consumer's bag count
  in real terms, with fresh timestamps, without needing us to write
  our own logout-scan-and-persist code. Big win for the "is anyone
  short?" view.

### Suggested code structure
```lua
-- Inventory.lua (or a new Inventory/Syndicator.lua module)
local function GetCrossCharacterCount(itemID)
    if _G.Syndicator and Syndicator.API.IsReady() then
        local info = Syndicator.API.GetInventoryInfoByItemID(itemID, true, true)
        -- info is a structured breakdown; sum characters + warband
        return SumInventoryInfo(info)
    end
    -- Fallback: only the current character is visible.
    return nil
end
```

Keeps the dependency **soft** — no TOC entry required, no OptionalDeps
needed, no breakage if the user doesn't have it installed.

### Related: Baganator
Baganator is Syndicator's UI consumer, not something we need to talk
to directly. But it's a good reference for how the Auctionator/
Syndicator/Baganator ecosystem chains data addons behind UI addons —
the same shape we're building (Stock Clerk = UI + logic, delegates to
Syndicator for cross-char data and Auctionator for AH queries).

---

## UI polish — borrow atrocityEssentials custom assets (added 2026-09-16)

**User ask (verbatim):** "AES ships with custom assets for GUI construction. Maybe we borrow some of those to make the aesthetic more cohesive."

**Context:** Current UI uses Blizzard-native textures for the resize grip
(`Interface\ChatFrame\UI-ChatIM-SizeGrabber-*`) plus a couple of solid-color
`WHITE8X8` fills, black 1px overlay borders, and `GameFontNormal/Highlight`
FontStrings. That reads as "well-behaved Blizzard addon" but not
distinctively AES-family. AES ships its own texture pack that unifies its
whole suite of addons visually.

### What AES ships (audit before pulling anything in)
The user's uploaded `atrocityEssentials.zip` should contain a
`Media/` (or `Assets/`) directory with things like:
- Corner / edge / grip pixels
- Button up/down/highlight states
- Section-divider hairlines
- Check/radio marks
- Slider thumbs / scroll thumbs
- Font atlas or a bundled TTF

Before borrowing: `unzip -l atrocityEssentials.zip` to list the media dir,
then look at how AES's own `.lua` references those paths so we know the
intended usage and any anchor conventions.

### Candidate swaps (once we know what's in the pack)
| Current                              | AES swap candidate                     |
|--------------------------------------|----------------------------------------|
| Blizz `SizeGrabber-*` (resize grip)  | AES corner-grip trio if bundled        |
| WHITE8X8 button fills                | AES flat button plate + hover state    |
| 1px `Palette.border` textures        | AES hairline / crisp-pixel border      |
| `GameFontDisableSmall` ghost text    | AES muted font style (if a font ships) |
| Custom scroll-thumb (if any)         | AES scroll thumb                       |

### Licensing / attribution
Before shipping any borrowed asset: check AES's license (README/LICENSE
in the zip). Most addon authors are permissive but explicit MIT/CC-BY
attribution may be required. If unclear, ask the AES author on
CurseForge before publishing v0.3+.

### Rollout strategy
Do this as a dedicated **UI-cohesion pass** (own version bump, own
CHANGELOG entry), not smuggled into a feature release — makes it easy
to revert if the aesthetic doesn't land or if we hit a licensing snag.
Keep the current Blizz-native fallbacks in the code path (e.g. via a
`Palette.assets = "atrocity" or "blizzard"` toggle) so users on
low-memory setups or with texture-pack conflicts have an escape hatch.

---

## Post-v0.2.0 QA-derived backlog (added 2026-09-17)

Compiled from the v0.2.0 pre-release QA sweep. Bugs QA-1/3/6/7/8 were
hotfixed for v0.2.0 (see CHANGELOG). QA-2 got a soft guardrail (status-
line hint on name-based adds); full fix is v0.3 work. The rest below
are features / longer-horizon watchlist items.

### QA-2 (v0.3 — proper quality-tier disambiguation)

Name-based adds are non-deterministic across items sharing a display
name (rank 1/2/3 craft variants especially). Blizzard doesn't expose
name -> multiple-itemIDs to addons, so we can't enumerate at resolve
time.

Options, ordered from cheapest to richest UX:

1. **Shift-click into add box shortcut.** User Shift-clicks an item in
   bags / recipe UI / AH; the linked item's exact ID is inserted into
   the Item field. This works today for chat edits; extend the addBox's
   OnHyperlinkClick or InsertLink hook. Zero ambiguity for anything the
   user can find in-game.
2. **Local recent-encounters cache.** Every time C_Item.GetItemInfo
   fires for an item, remember `{name -> {itemIDs...}}` in
   SavedVariables. When the user types a name that matches a cached
   set with >1 ID, refuse and show a small chooser popup listing the
   candidates with their quality tier indicator. Fills up naturally
   as the user plays.
3. **Auctionator / trade-skills scan piggyback.** If Auctionator is
   installed, borrow its item database (it maintains a name-index of
   everything it's ever seen at the AH). Fallback to option 2 when
   Auctionator isn't present.

Rec: ship (1) as a quick win, ship (2) alongside as the guardrail,
consider (3) only if it doesn't stretch scope.

### QA-10 (feature — opt-in full auto-purchase)

Single global toggle in a settings surface, no per-item override. The
per-item **price cap is the fail-safe**: auto-purchase only ever acts
on items with a set cap. Uncapped items are visible but never
auto-bought. Design contract that must be visible in the UI:

- Toggle sits in a settings panel (opens from a header cog icon).
  Tooltip on hover states the contract in plain English.
- One-time confirmation modal when enabling: "Auto-purchase is ON.
  Only capped items will be bought. N items have no cap set; they
  will be skipped. Continue?"
- Row-level indicator (dim moon glyph? crossed-out coin?) on items
  with no cap while auto is on, so it's obvious at a glance which
  rows are excluded.
- Esc kill-switch: pressing Esc while a purchase loop is active
  cancels it immediately (regardless of window focus).
- Qty delta sanity check: if a single BuyMerchantItem or AH bid would
  push have above `need + 2*need` (i.e. more than triple the target),
  refuse it and log to the sidecar activity log.
- Per-run spend ceiling — required, see QA-10a.

**v1 scope: commodities only.** Non-commodity auctions have quirks
(item-of-the-day, bind-on-account rules, buyout vs bid) that add too
much surface area for the first iteration.

### QA-10a (feature — per-session spend cap + budget allocation)

Spend cap is REQUIRED when auto is on, not optional. Naive top-down
iteration causes tail starvation: the first few short items eat the
whole budget and the rest of the list gets nothing. This is a real
problem for cheap-but-many vs expensive-but-few stockpiles.

Recommended v1 strategy: **two-pass proportional + spillover.**

- Pass 1 (allocation): for each short item, compute demand-value =
  `(need - have) * est_unit_price` where est_unit_price is the last
  known price (see QA-11). Scale each demand-value slice down
  proportionally so their sum fits under the budget. Convert each
  slice back into a target unit count.
- Pass 2 (spillover): after pass 1's target counts are executed, any
  budget left over redistributes to items still short, prioritizing
  those with the largest remaining shortfall. Repeat until either
  the budget is exhausted or no items are still short.

End-of-loop summary in the sidecar log (see QA-13):
`Spent Xg of Yg. N items still short: [names]. M items now at target.`

Open sub-question: **per-loop reset or rolling per-play-session cap?**
Argument for per-loop: user explicitly initiates each restock so
they'd expect the budget to reset. Argument for rolling: prevents
'run the loop 20 times to get around the cap' abuse of your own
guardrail. Rec: per-loop cap for v1, add a rolling cap toggle later
if the abuse pattern materializes.

Depends on QA-11 for reasonably accurate est_unit_price. Without it
pass 1 is effectively 'equal shares'.

### QA-11 (feature — last-known-price column)

New per-item schema field:
```lua
char.items[itemID].lastPrice = {
    copper = 12500,         -- copper per unit
    seenAt = 1758067200,    -- unix ts
    source = "click"|"scan" -- how we saw it
}
```

Population strategy, in order of user friction:

1. **Piggyback the left-click-to-search flow.** Every time the user
   left-clicks a row while AH is open, we already run a search. Grab
   the cheapest unit price from those results and stamp it. Free,
   no new UI, no rate-limit concerns.
2. **Optional AH-open sweep.** Setting: "Update all prices when the
   AH opens." Runs `C_AuctionHouse.SendSearchQuery` for each tracked
   item, rate-limited (100/min budget; back off automatically on
   throttle events). Cancellable via a small progress toast.
3. **Stale-only sweep.** Same as (2) but only re-queries items whose
   lastPrice.seenAt is older than a TTL (24h default, configurable).

Column: 'Last Seen' between Price Cap and Status. Dim the text when
older than the TTL. Empty state shows a dim em-dash.

Ship path 1 first (piggyback), then add the AH-open sweep with the
stale-only variant behind a toggle.

Powers QA-10a budget-allocation accuracy and QA-14 historical trend.

### QA-12 (watchlist — post-release AH edge cases)

Not v0.2.0 blocking. Broader user base is required to flush these
out because they need real-world timing / server load / cross-realm
config combinations:

- Throttled queries (C_AuctionHouse rate limit backoff behavior)
- Mid-purchase disconnect (partial confirmation state on relog)
- Partial fills (asked for 100, got 87, did we bank the balance?)
- Cross-realm auction house quirks (region-wide commodities market)
- BFA-era 'commodities queue' interactions if any legacy code path
  hits it

Track user reports post-soft-release and open concrete tickets from
them; don't preemptively harden without a reproducible case.

### QA-13 (feature — sidecar activity log window)

Extricate the statusBar into a docked sidecar frame. Statusbar today
is a single line that gets overwritten; a sidecar gives us proper
audit trail and enables analytics.

Log entries (timestamped, all persisted):

- add / remove item
- target change (from -> to)
- cap change (from -> to)
- AH search (item, cheapest, listings count)
- purchase attempt (item, qty, unit price, source)
- purchase completion (item, qty, spent)
- purchase skip (item, reason: over cap / no cap set / at target)
- loop start, loop stop (with duration, spent, items touched)

Storage: SavedVariables ring buffer, account-wide for cross-alt
auditing. Cap ~500 entries; oldest evicted first.

Header aggregation surface (top of the sidecar): total purchases,
total gold spent, per-item breakdown (units bought, gold spent,
avg unit price).

Filter chips: All | Purchases only | This session | Per-item (opens
a submenu of tracked items).

Toggle via a footer button (log icon), OR a slash command `/sc log`.

Makes the addon feel like a proper tool with an audit trail vs
fire-and-forget. Groundwork for QA-14.

### QA-14 (feature — historical expenditure mapping, v0.4-ish)

Extends QA-13 into per-item time-series. Sparkline drawn inline in
each row (right of the Status pill); right-click to open a full chart
in an overlay panel.

Enables:

- "Is now a good time to buy?" — current AH price vs trailing 30-day
  median (green if below, yellow if within 10%, red if above).
- "Am I getting ripped off?" — user's purchase history for this item
  vs current AH cheapest. Flags anomalies.
- Total holdings value ticker at window footer.

Data source: append every `lastPrice` observation (from QA-11) to a
per-item history array. Cap ~200 obs per item; downsample older
entries into daily/weekly buckets to keep SavedVariables size bounded.

Green/yellow/red color band vs the USER's own price history, not
some external oracle, so the addon stays fully self-contained.

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
