--[[
    Stock Clerk - Data/Consumables.lua
    "Add common consumables" list (Sidecar button, v1.2). Edit freely:
    one line per item, itemID first. Every entry is added with a target
    of 1; items already on the player's list are left untouched.
    The itemID fixes the quality; the "(Rank N)" notes are just labels
    (commodities are Rank 1 or Rank 2).

    Not loaded yet: add to StockClerk.toc when the v1.2 feature is built
    (see Dev/ROADMAP.md).
--]]

local addonName = ...
local ADDON     = _G[addonName]

ADDON.CommonConsumables = {
    -- Combat potions
    241308, -- Light's Potential (Rank 2)
    271887, -- Liquid Luster (Rank 2)
    241302, -- Void-Shrouded Tincture (Rank 2)
    241288, -- Potion of Recklessness (Rank 2)

    -- Healing potions
    271884, -- Concentrated Silvermoon Health Potion (Rank 2)
    241304, -- Silvermoon Health Potion (Rank 2)

    -- Flasks
    241326, -- Flask of the Shattered Sun
    241322, -- Flask of the Magisters
    241324, -- Flask of the Blood Knights

    -- Weapon oils
    243734, -- Thalassian Phoenix Oil (Rank 2)

    -- Utility
    132514, -- Auto-Hammer

    -- Food
    255847, -- Royal Roast
    242274, -- Champion's Bento
}
