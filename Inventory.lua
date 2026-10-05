--[[
    StockClerk - Inventory.lua
    How many of an item this character has: bags, bank, warband bank.

    The row count is bags only: moving items between bags and bank would
    otherwise look like nothing happened. Bank and warband copies show as
    the dim (+N) and in the tooltip. Since 11.2 the reagent bank folds into
    the bank count. Breakdowns are cached until the next inventory event.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local INV = { cache = {} }
ADDON.Inventory = INV

function INV:Invalidate()
    wipe(self.cache)
end

-- { bags, bank, warband }, each for that container only. GetItemCount's
-- totals are cumulative, so subtract; items with nothing stashed (the common
-- case) cost two calls instead of three.
function INV:GetBreakdown(itemID)
    local bd = self.cache[itemID]
    if bd then return bd end
    local bags = C_Item.GetItemCount(itemID) or 0
    local all  = C_Item.GetItemCount(itemID, true, false, true, true) or 0
    local bank = all == bags and bags or (C_Item.GetItemCount(itemID, true, false, true) or 0)
    bd = { bags = bags, bank = bank - bags, warband = all - bank }
    self.cache[itemID] = bd
    return bd
end

-- Inventory changed: forget cached counts; repaint only if the window shows
-- (MF:Show repaints on open anyway).
function INV:OnInventoryChanged()
    self:Invalidate()
    ADDON.RestockLoop:Sweep()
    local mf = ADDON.MainFrame
    if mf.frame and mf.frame:IsShown() then mf:Refresh() end
end
