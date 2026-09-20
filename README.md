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
  a dim `(+N: 5 bank, 2 warband)` annotation so you always know where
  your stock actually lives.
- **Per-item price cap.** Set an optional maximum gold-per-unit for
  any item. The restock loop will never buy above that price.
  Uncapped items are visible in the list but excluded from any
  automation until you set a cap for them.
- **Auction House integration.** Open the AH, click a row in the
  Stock Clerk window, and it searches for that item. Or use the
  "Restock at AH" button to run a batched restock pass across every
  short item on your list, respecting each item's price cap.
- **Full keyboard-only entry.** Tab / Shift+Tab walks the entire
  editable surface in row-major order: Item ID → Target → Price Cap
  → Add Item → row 1 Need → row 1 Cap → row 2 Need → ... and wraps.
  Inline edits commit on Enter, Tab, or clicking away. Escape
  cancels without committing.
- **Flat, out-of-the-way UI.** Single-window, resizable, mint-accented
  chrome that stays out of your face. Position and size persist per
  character.

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

## Roadmap

Stock Clerk hit v0.7.0 (first stable release) with per-character
shopping lists, the restock loop, confirmed-buy automation, and the
sidecar activity log. Planned work for v0.8 includes a tooltip
overhaul, a hints kill switch, and a bag / bank / warband breakdown
tooltip on the Have column. v1.0 will focus on documentation and
store-page polish.

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

Not yet declared. Treat as all-rights-reserved for now; a permissive
license will be added before v1.0.
