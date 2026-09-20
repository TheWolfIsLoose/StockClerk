# CurseForge project description — v0.7.0

Paste this into the CurseForge project's Description tab. Uses
CurseForge's Bbcode-flavored markdown; feel free to trim or
reformat.

---

# Stock Clerk

A lightweight, per-character consumable restock tracker for World of
Warcraft. Set a target count for every consumable you want to keep
on hand, and Stock Clerk shows you at a glance which ones you're
short on and helps you top them up from the Auction House.

**Retail only.** Interface 12.1 (Midnight).

## Why Stock Clerk

Stock Clerk is built around one simple loop:

> *"I want to always have N of this consumable on me. How many am I
> short? What's the cheapest way to get more?"*

Set a target of 30 for your favorite flask, 20 for your health
potions, 12 for your rune, and Stock Clerk keeps a running tally of
your shortfall. Visit the Auction House, click Restock at AH, and
each short item surfaces a confirm-to-buy flyout showing quantity,
total cost, and your per-unit price cap. One click per item, no
manual searching, no accidental impulse buys.

## What it does

- **Per-character shopping list.** Each character keeps its own
  list of items and target counts. Bags-only Have count plus a dim
  `(+N bank/warband/reagent)` annotation shows where your stock
  actually lives.
- **Per-item price cap.** Set a maximum gold-per-unit for any
  item. The restock loop refuses to buy above that price. Uncapped
  items show an amber "No cap set" warning at buy time so you know
  you're buying at market.
- **Auction House integration.** Click a row while the AH is open
  to search for that item. Cheapest listing feeds the Last Seen
  column. Optional auto-open when you visit the AH.
- **Confirmed-buy automation.** Restock at AH walks every short
  item in list order, surfacing an armed flyout for each with
  Buy / Skip / Stop controls. Capped-out items auto-skip silently.
  A 3-second arm delay on each Buy prevents accidental clicks.
- **Mail-pending safety.** Purchases sitting in mail count toward
  your effective have count, so you can't accidentally re-buy items
  you already own but haven't looted yet.
- **Full keyboard entry.** Tab / Shift+Tab walks Item ID → Target →
  Cap → Add → row 1 Need → row 1 Cap → row 2 Need → wrap. Enter
  commits, Escape cancels.
- **Sidecar activity log.** Right-docked panel with a Recent
  Activity feed plus a full popup accessible via `/clerk log`.
- **Flat, out-of-the-way UI.** Single-window, resizable, mint-
  accented chrome. Position and size persist per character.

## Commands

- `/clerk` — open the main window (aliases: `/sc`, `/stock`)
- `/clerk help` — command list
- `/clerk log` — full activity popup
- `/clerk reset` — wipe this character's list
- `/clerk debug on` — diagnostic chat output for bug reports

## Feedback

Bug reports and feature requests are welcome on the GitHub issue
tracker. Screenshots of the actual bug (`/clerk debug on` then
reproduce) speed up diagnosis significantly.

## Credits

Stock Clerk stands on the shoulders of great addon work by others:

- **atrocityEssentials** and **NorskenUI** — flat-dark aesthetic
  inspiration.
- **plusmouse** (**Auctionator**, **Baganator**, **Syndicator**) —
  the DataProvider-per-refresh row list pattern and the item-count-
  across-all-storage-locations model.
