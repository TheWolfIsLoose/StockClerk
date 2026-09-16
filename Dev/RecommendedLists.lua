--[[
    Stock Clerk - Dev/RecommendedLists.lua
    DEV-ONLY seed data. Stripped from release builds by the BigWigsMods
    packager (the file is only referenced inside a #@debug@..#@end-debug@
    block in the TOC).

    Seed matches Jake's Midnight (12.1) live consumable kit — the items
    already tracked on his character as of the first working v0.1.0 build.

    Categories seeded (all itemIDs are rank 3, the crafted top-quality
    variant that WoW shows with a gold star in the bag icon):
      - DPS Potions   (Light's Potential)
      - Healing Potions (Concentrated Silvermoon, plain Silvermoon)
      - Flasks        (Flask of the Shattered Sun)
      - Weapon Oils   (Thalassian Phoenix Oil)

    itemID sources: wowhead.com item pages, cross-checked against the
    Midnight Alchemy / Enchanting recipe lists.
        Concentrated Silvermoon Health Potion (r3) - 271883
        Silvermoon Health Potion (r3)              - 241305
        Flask of the Shattered Sun (r3)            - 241326
        Light's Potential (r3)                     - 241308
        Thalassian Phoenix Oil (r3)                - 243734
--]]

local addonName = ...
local ADDON     = _G[addonName]

local RL = {}
ADDON.RecommendedLists = RL

RL.categories = {
    ["DPS Potions"] = {
        [241308] = 20,  -- Light's Potential
    },
    ["Healing Potions"] = {
        [271883] = 20,  -- Concentrated Silvermoon Health Potion
        [241305] = 20,  -- Silvermoon Health Potion (fallback / bulk)
    },
    ["Flasks"] = {
        [241326] = 20,  -- Flask of the Shattered Sun
    },
    ["Weapon Oils"] = {
        [243734] = 20,  -- Thalassian Phoenix Oil
    },
}

-- Apply all recommended categories to the current character's list.
-- Uses merge semantics (won't clobber user-modified needs).
-- Returns (itemsAdded, categoriesApplied).
function RL:Apply()
    local added, catCount = 0, 0
    local items = ADDON.DB:GetItems()
    for cat, entries in pairs(self.categories) do
        catCount = catCount + 1
        for itemID, need in pairs(entries) do
            if items[itemID] == nil then
                ADDON.DB:SetItem(itemID, need)
                added = added + 1
            end
        end
    end
    ADDON.Inventory:Invalidate()
    ADDON.DB:Settings().debugSeeded = true
    return added, catCount
end
