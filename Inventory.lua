--[[
    Stock Clerk - Inventory.lua
    Answers "how many of item X does this character have?" cheaply.

    Backing API (retail 11.0+):
      C_Item.GetItemCount(itemInfo,
                          includeBank,
                          includeUses,
                          includeReagentBank,
                          includeAccountBank)

    That single call rolls up bags + (optionally) bank + reagent bank +
    warband/account bank. As of retail 11.2 the reagent bank was removed
    (items were folded into the main bank tabs), so includeReagentBank is
    a harmless no-op on live but we leave it on for pre-11.2 servers.

    Caching:
      We memoize counts per itemID and invalidate on BAG_UPDATE_DELAYED,
      PLAYERBANKSLOTS_CHANGED, PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED,
      BANK_TABS_CHANGED and BANKFRAME_OPENED. The last one guarantees a
      fresh scan the first time the user opens the bank in a session.
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
    includeReagentBank = true, -- vestigial post-11.2; kept for older clients
    includeAccountBank = true, -- warband bank
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
        self.opts.includeReagentBank,
        self.opts.includeAccountBank
    ) or 0

    self.cache[itemID] = count
    if ADDON.debug then
        print(("|cff98FF98[SC:debug]|r GetCount(%d) = %d (fresh from C_Item.GetItemCount)"):format(itemID, count))
    end
    return count
end

-- Called by Core.lua on inventory-change events.
function INV:OnInventoryChanged()
    if ADDON.debug then
        print("|cff98FF98[SC:debug]|r OnInventoryChanged fired, invalidating cache")
    end
    self:Invalidate()
    -- Notify UI (fire a lightweight callback the MainFrame listens for).
    if ADDON.MainFrame and ADDON.MainFrame.Refresh then
        ADDON.MainFrame:Refresh()
    end
end
