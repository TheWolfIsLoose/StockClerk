--[[
    Stock Clerk - ItemResolver.lua
    Resolves user input (item name OR itemID) to a canonical itemID.

    Why this exists:
      C_Item.GetItemInfo(name) only works if the item has been in the
      player's inventory this session. C_Item.GetItemInfo(itemID) works
      for any known ID but returns nil until the client caches it, then
      fires GET_ITEM_INFO_RECEIVED when ready.

    Public API:
      ItemResolver:Resolve(input, callback)
        input    - string (name or "itemID:N" or plain digits) or number
        callback - function(itemID, itemName, itemLink) called when resolved,
                   or function(nil, errMsg) on failure.
--]]

local addonName = ...
local ADDON     = _G[addonName]
local IR = { pending = {} }
ADDON.ItemResolver = IR

-- ---------------------------------------------------------------------------
-- Input parsing
-- ---------------------------------------------------------------------------
local function extractItemID(input)
    if type(input) == "number" then return input end
    if type(input) ~= "string" then return nil end

    -- Bare digits
    local id = tonumber(input)
    if id then return id end

    -- item:12345 or item:12345:...  (partial or full itemString / link)
    id = tonumber(input:match("item:(%d+)"))
    if id then return id end

    -- Full item link with |Hitem:...|
    id = tonumber(input:match("|Hitem:(%d+)"))
    if id then return id end

    return nil
end

-- ---------------------------------------------------------------------------
-- Resolve
-- ---------------------------------------------------------------------------
function IR:Resolve(input, callback)
    if not input or input == "" then
        callback(nil, "empty input")
        return
    end

    local itemID = extractItemID(input)

    -- Path 1: we already have an itemID — try to fetch cached info,
    -- otherwise queue and wait for GET_ITEM_INFO_RECEIVED.
    if itemID then
        local name, link = C_Item.GetItemInfo(itemID)
        if name then
            callback(itemID, name, link)
        else
            -- Force the client to request info from the server.
            -- Calling GetItemInfo(id) is what triggers the cache fetch.
            self.pending[itemID] = self.pending[itemID] or {}
            table.insert(self.pending[itemID], callback)
        end
        return
    end

    -- Path 2: user typed a name.
    -- GetItemInfo(name) only works if the item has been in the player's
    -- session inventory. If it succeeds, extract the itemID from the link.
    local name, link = C_Item.GetItemInfo(input)
    if name and link then
        local id = tonumber(link:match("item:(%d+)"))
        if id then
            callback(id, name, link)
            return
        end
    end

    -- We can't resolve names we've never seen. Blizzard doesn't expose an
    -- item name -> ID search API to addons. Guide the user.
    callback(nil, _G[addonName .. "_L"].ITEM_NOT_FOUND)
end

-- ---------------------------------------------------------------------------
-- Event handler (wired by Core.lua)
-- ---------------------------------------------------------------------------
function IR:OnItemInfoReceived(itemID, success)
    local queue = self.pending[itemID]
    if not queue then return end
    self.pending[itemID] = nil
    if not success then
        for _, cb in ipairs(queue) do cb(nil, "item load failed") end
        return
    end
    local name, link = C_Item.GetItemInfo(itemID)
    for _, cb in ipairs(queue) do cb(itemID, name, link) end
end
