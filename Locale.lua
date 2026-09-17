--[[
    Stock Clerk - Locale.lua
    Minimal locale table. Expand later via AceLocale-3.0 if we localize.
    For now: a plain table so strings live in one place.
--]]

local addonName = ...
local L = {}
_G[addonName .. "_L"] = L

-- UI strings
L.ADDON_NAME             = "Stock Clerk"
L.SLASH_HEADER           = "|cff88ccffStock Clerk|r"
L.MAIN_TITLE             = "Stock Clerk"
L.BTN_ADD_ITEM           = "Add Item"
L.BTN_CLOSE              = "Close"
L.COL_ICON               = ""
L.COL_ITEM               = "Item"
L.COL_HAVE               = "Have"
L.COL_NEED               = "Need"
L.COL_DELTA              = "Short"
L.COL_ACTIONS            = ""
L.EMPTY_LIST             = "No consumables tracked for this character yet. Click \"Add Item\" to begin."
L.PROMPT_ADD_ITEM        = "Enter item name or itemID:"
L.PROMPT_ADD_COUNT       = "Target count:"
L.ITEM_NOT_FOUND         = "Item not found or not yet cached. Try opening its tooltip in-game first, then re-add."
L.SEED_APPLIED           = "Applied recommended lists: %d items across %d categories."

-- Slash command help
L.HELP_TITLE             = "|cff88ccffStock Clerk|r commands:"
L.HELP_OPEN              = "  /clerk  |cff888888— open the main window|r"
L.HELP_SHORT             = "  /sc, /stock |cff888888— aliases|r"
L.HELP_SEED              = "  /clerk seed |cff888888— apply dev recommended lists (debug builds only)|r"
L.HELP_RESET             = "  /clerk reset |cffff8888— wipe this character's list|r"
L.HELP_DUMP              = "  /clerk dump |cff888888— print current list to chat|r"
L.HELP_BUDGET            = "  /clerk budget [reset] |cff888888— show daily auto budget; 'reset' zeroes today's counter|r"
