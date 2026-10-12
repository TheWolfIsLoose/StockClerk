--[[
    StockClerk - ItemResolver.lua
    Turns user input (item ID, link, or the name of an item seen this
    session) into an itemID, waiting for the item cache when needed
    (Blizzard's Item mixin does the waiting).

    IR:Resolve(input, callback)
      callback(itemID, name, link) once resolved, or callback(nil, errMsg).
    Names only resolve for items the client already knows; addons have no
    name-to-ID search.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local IR = {}
ADDON.ItemResolver = IR

function IR:Resolve(input, callback)
    local itemID = tonumber(input) or tonumber(tostring(input or ""):match("item:(%d+)"))
    if not itemID then
        local _, link = C_Item.GetItemInfo(input or "")
        itemID = link and tonumber(link:match("item:(%d+)"))
        if not itemID then return callback(nil, "That item hasn't loaded yet. Hover it in game first, then add it again.") end
    end
    if not C_Item.DoesItemExistByID(itemID) then return callback(nil, "no such item") end
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function() callback(itemID, item:GetItemName(), item:GetItemLink()) end)
end
