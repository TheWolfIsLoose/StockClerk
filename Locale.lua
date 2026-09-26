--[[
    Stock Clerk - Locale.lua
    Minimal locale table so strings live in one place.
--]]

local addonName = ...
local L = {}
_G[addonName .. "_L"] = L

-- UI strings
L.ADDON_NAME             = "Stock Clerk"
L.SLASH_HEADER           = "|cff88ccffStock Clerk|r"
L.MAIN_TITLE             = "Stock Clerk"
L.BTN_ADD_ITEM           = "Add"
L.BTN_CLOSE              = "Close"
L.COL_ICON               = ""
L.COL_ITEM               = "Item"
L.COL_HAVE               = "Have"
L.COL_NEED               = "Need"
L.COL_DELTA              = "Short"
L.COL_ACTIONS            = ""
L.EMPTY_LIST             = "No items yet.\n\nAdd items by:\n |cffffffff1.|r Typing an item ID into the Item ID box and pressing Enter\n |cffffffff2.|r Clicking the |cffffffff+|r button to paste multiple item IDs at once\n |cffffffff3.|r Dragging an item from your bags into this window"
L.PROMPT_ADD_ITEM        = "Enter item name or itemID:"
L.PROMPT_ADD_COUNT       = "Target count:"
L.ITEM_NOT_FOUND         = "Item not found or not yet cached. Try opening its tooltip in-game first, then re-add."

-- Item ID input box hints
L.ADDBOX_TOOLTIP         = "Type an item ID, or drag an item from your bags onto this window."
L.ADDBOX_DROP_ACCEPTED   = "Drop to fill"

-- Shopping list filter chip
L.FILTER_STUCK_ONLY      = "Show only: items you're short on"
L.FILTER_STUCK_TOOLTIP   = "Hide items you already have enough of in your bags."

-- Slash command help
L.HELP_TITLE             = "|cff88ccffStock Clerk|r commands:"
L.HELP_OPEN              = "  /clerk  |cff888888— open the main window|r"
L.HELP_SHORT             = "  /sc, /stock |cff888888— aliases|r"
L.HELP_RESET             = "  /clerk reset |cffff8888— wipe this character's list|r"
L.HELP_DUMP              = "  /clerk dump |cff888888— print current list to chat|r"
L.HELP_LOG               = "  /clerk log [clear] |cff888888— open or clear the activity log|r"
L.HELP_DEBUG             = "  /clerk debug |cff888888— toggle diagnostic chat output|r"
L.HELP_ADD               = "  /clerk <item ID or link> |cff888888— add an item with target 1|r"
L.HELP_PENDING           = "  /clerk pending [clear] |cff888888— show items awaiting mail delivery; 'clear' resets the mail-in-flight ledger|r"
