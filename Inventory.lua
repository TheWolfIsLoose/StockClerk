--[[
    Stock Clerk - Inventory.lua
    Answers "how many of item X does this character have?" cheaply.

    Backing API: C_Item.GetItemCount(itemInfo, includeBank, includeUses, includeReagentBank)
    That single call rolls up bags + (optionally) bank + reagent bank.

    Warband bank note:
      As of TWW, warband bank items count toward GetItemCount when the
      includeBank flag is true (Blizzard folded warband into the "bank"
      bucket for count queries). We keep the flag on by default so the
      user's "have" number reflects everything reachable to that character.

    Caching:
      We memoize counts per itemID and invalidate on BAG_UPDATE_DELAYED
      (fires once after a burst of BAG_UPDATE), PLAYERBANKSLOTS_CHANGED,
      PLAYERREAGENTBANKSLOTS_CHANGED, and the warband bank change event.
      This keeps the UI cheap when the list is long.
--]]

local addonName = ...
local ADDON     = _G[addonName]
local INV = { cache = {} }
ADDON.Inventory = INV

-- Options that describe what counts as "have". Users may eventually
-- want to exclude bank items from the "have" number to only see what's
-- immediately equipped in bags — expose a toggle later.
INV.opts = {
    includeBank        = true,
    includeReagentBank = true,
}

function INV:Invalidate()
    wipe(self.cache)
end

function INV:GetCount(itemID)
    if not itemID then return 0 end
    local cached = self.cache[itemID]
    if cached ~= nil then return cached end

    local count = C_Item.GetItemCount(
        itemID,
        self.opts.includeBank,
        false, -- includeUses (charges) — not what a stack count means for us
        self.opts.includeReagentBank
    ) or 0

    self.cache[itemID] = count
    return count
end

-- Called by Core.lua on inventory-change events.
function INV:OnInventoryChanged()
    self:Invalidate()
    -- Notify UI (fire a lightweight callback the MainFrame listens for).
    if ADDON.MainFrame and ADDON.MainFrame.Refresh then
        ADDON.MainFrame:Refresh()
    end
end
