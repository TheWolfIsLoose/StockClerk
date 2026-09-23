<p align="center">
  <img src=".assets/logo-256.png" alt="Stock Clerk" width="180" height="180">
</p>

<h1 align="center">Stock Clerk</h1>

<p align="center">
  <a href="https://www.curseforge.com/wow/addons/stock-clerk">CurseForge</a>
  ·
  <a href="https://github.com/TheWolfIsLoose/StockClerk/releases">GitHub Releases</a>
</p>

A lightweight, per-character consumable restock tracker for World of
Warcraft. Set a target count for every consumable you want to keep on
hand, and Stock Clerk shows you at a glance which ones you're short on
and helps you top them up from the Auction House.

Retail only. Interface 12.1 (Midnight).

## What it does

Stock Clerk is built around one simple loop: *"I want to always have N
of this consumable on me. How many am I short? What's the cheapest way
to get more?"*

- **Per-character shopping list.** Each character keeps its own list of
  items and target counts. Add an item by ID, set a target, and it
  shows up in your restock window with a live count.
- **Have / Need / Price Cap columns.** The primary Have count is your
  bags; anything sitting in bank, reagent bank, or warband appears as
  a compact `(+N)` suffix. Hover the Have cell to fan out the full
  breakdown — `+N in bank (this character)` and `+N in warband bank
  (account-wide)` — so you always know where your stock actually
  lives.
- **Per-item price cap.** Set an optional maximum gold-per-unit for
  any item. The restock loop will never buy above that price.
  Uncapped items are visible in the list but excluded from any
  automation until you set a cap for them.
- **Auction House integration.** Open the AH, click a row in the
  Stock Clerk window, and it searches for that item. Or use the
  "Restock at AH" button to run a batched restock pass across every
  short item on your list, respecting each item's price cap.
- **Keyboard-friendly quick add.** Tab / Shift+Tab cycles the Add
  cluster (Item ID → Target → Price Cap → Add Item → wrap). Inline
  row edits commit on Enter, Tab, or clicking away. Escape cancels
  without committing. Row cells themselves are click-to-edit (mouse)
  — the row body is no longer part of the Tab chain, which removes a
  whole class of focus-capture bugs.
- **Bank/warband guardrail.** When the restock loop queues an item
  you already own copies of in bank or warband bank, the buy flyout
  says so in amber before you commit gold. No third "withdraw from
  bank" option — that's still on you — but you'll never spend a
  thousand gold on flasks you forgot were in the warband bank.
- **Flat, out-of-the-way UI.** Single-window, resizable, mint-accented
  chrome that stays out of your face. Position and size persist per
  character.

## Screenshots

<p align="center">
  <img src=".assets/screenshots/hero.jpg" alt="Stock Clerk main window with restock flyout and sidecar" width="900">
  <br>
  <em>Main window: four-item shopping list showing at-target, over-target,
  under-target, and stashed rows side by side. Bottom-center: the Skip/Buy
  flyout for the next queued item. Right sidecar: settings toggles and
  the recent-activity log.</em>
</p>

<p align="center">
  <img src=".assets/screenshots/have-tooltip.jpg" alt="Have cell tooltip showing storage breakdown" width="900">
  <br>
  <em>Hover the Have cell to fan out where a consumable actually lives —
  bags, bank, warband bank — without cluttering the row itself.</em>
</p>

## Commands

- `/clerk` — open the main window
- `/sc`, `/stock` — aliases
- `/clerk help` — command list
- `/clerk reset` — wipe this character's list
- `/clerk dump` — print current list to chat
- `/clerk log` — open the full activity log popup
- `/clerk debug on|off` — toggle diagnostic chat output

## Installation

**CurseForge:** install [Stock Clerk on
CurseForge](https://www.curseforge.com/wow/addons/stock-clerk) via
the CurseForge desktop app or your addon manager of choice.

**Manual:** download the packaged zip from the
[Releases page](https://github.com/TheWolfIsLoose/StockClerk/releases)
and unzip into your `Interface/AddOns/` folder.

## Status

Stock Clerk v1.0.0 is the first stable public release. New features
after 1.0 will land on organic demand; the addon considers its
restock loop, keyboard-first entry, per-character lists, sidecar
activity log, and bank/warband guardrail feature-complete.

## Credits and inspiration

Stock Clerk stands squarely on the shoulders of some very good addon
work by other people. Specifically:

- **[atrocityEssentials](https://www.curseforge.com/wow/addons/atrocityessentials)**
  and **[NorskenUI](https://github.com/Nrsken/NorskenUI)** — the
  flat-dark, minimalist aesthetic of Stock Clerk's window (single
  near-black fill, 1px pure-black section separators, no per-row
  backgrounds, hover-only mint accents) is directly inspired by these
  two UI kits.
- **[plusmouse](https://github.com/plusmouse)** — several of Stock
  Clerk's functional patterns are inspired by plusmouse's addons:
  the DataProvider-replaced-on-each-refresh row list pattern (from
  [Auctionator](https://www.curseforge.com/wow/addons/auctionator)),
  the item-count-across-all-storage-locations model (from
  [Baganator](https://www.curseforge.com/wow/addons/baganator) and
  [Syndicator](https://www.curseforge.com/wow/addons/syndicator)),
  and generally the "quiet, well-behaved AH addon" reference bar
  that Auctionator sets. Any resemblance is admiration, not theft;
  no code is copied.

## A note on how this was built

Stock Clerk was lovingly constructed with heavy AI assistance,
iterating on design and implementation through conversation and
in-game testing. The audio-processing sibling project
(SharedMedia_Tones) uses the same workflow. Every design decision,
every QA pass, and every commit went through a human reviewer before
shipping, but the drafting speed and comment thoroughness you'll see
in the source is what happens when a patient human works alongside a
patient model.

## License

MIT. See [LICENSE](LICENSE) for the full text. The embedded
LibSharedMedia-3.0 and other bundled libraries retain their own
upstream licenses.
