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
