# Stock Clerk

Per-character consumable restock lists for World of Warcraft (Midnight, 12.1+).

Private dev repo. See `StockClerk.toc` for interface version.

## Dev-only files (never ship)

These files exist for local iteration and are excluded from packaged
releases via `.pkgmeta`:

- `update.bat` — Windows one-click git-pull helper
- `Dev/RecommendedLists.lua` — dev seed data (also gated by `@debug@`)
- `README.md`, `.pkgmeta`, `.gitignore`, `.github/`

## Layout
- `Core.lua` — AceAddon object, event routing, slash commands (/clerk, /sc, /stock)
- `DB.lua` — AceDB schema (per-character items, global templates, settings)
- `ItemResolver.lua` — async name↔itemID resolution
- `Inventory.lua` — cached GetItemCount wrapper (bags + bank + reagent + warband)
- `UI/MainFrame.lua` — native PortraitFrame + ScrollBox UI
- `Sources/` — Wave 2 auto-collection sources (mail, bank, vendor, AH)
- `Dev/RecommendedLists.lua` — dev seed data (stripped from release builds)
- `Libs/` — vendored Ace3

## Commands
- `/clerk` — open main window
- `/sc`, `/stock` — aliases
- `/clerk help` — command list
- `/clerk reset` — wipe this character's list
- `/clerk dump` — print current list to chat
- `/clerk seed` — apply dev recommended lists (debug builds only)
