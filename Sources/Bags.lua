--[[
    Stock Clerk - Sources/Bags.lua
    Wave 1: minimal presence — future home for drag-from-bags into
    the list window and any bag-specific scanning we can't do via
    GetItemCount alone.

    Wave 2 will add:
      - drop-target frame that accepts CursorHasItem() drops
      - hook for shift-click-in-bags to quick-add
--]]

local addonName = ...
local ADDON     = _G[addonName]

ADDON.Bags = {}
