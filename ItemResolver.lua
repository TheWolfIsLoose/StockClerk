--[[
    StockClerk - ItemResolver.lua
    Turns user input (item ID, link, or the name of an item seen this
    session) into an itemID, waiting for the item cache when needed.

    IR:Resolve(input, callback)
      callback(itemID, name, link) once resolved, or callback(nil, errMsg).
    Names only resolve for items the client already knows; addons have no
    name-to-ID search.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local IR = { pending = {} }
ADDON.ItemResolver = IR

function IR:Resolve(input, callback)
    if not input or input == "" then return callback(nil, "empty input") end
    local itemID = tonumber(input) or (type(input) == "string" and tonumber(input:match("item:(%d+)")))
    if itemID then
        local name, link = C_Item.GetItemInfo(itemID)
        if name then return callback(itemID, name, link) end
        -- Not cached: GetItemInfo above requested it; wait for GET_ITEM_INFO_RECEIVED.
        self.pending[itemID] = self.pending[itemID] or {}
        table.insert(self.pending[itemID], callback)
        return
    end
    local name, link = C_Item.GetItemInfo(input)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then return callback(id, name, link) end
    callback(nil, "That item hasn't loaded yet. Hover it in game first, then add it again.")
end

function IR:OnItemInfoReceived(itemID, success)
    local queue = self.pending[itemID]
    if not queue then return end
    self.pending[itemID] = nil
    local name, link = C_Item.GetItemInfo(itemID)
    for _, cb in ipairs(queue) do
        if success then cb(itemID, name, link) else cb(nil, "item load failed") end
    end
end
