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
        -- Break the total down by container to see whether bag<->bank
        -- moves actually change any component. If they don't, the metric
        -- itself is invariant (bags+bank+warband stays constant on a
        -- self-move) and "stale count" isn't a bug — it's math.
        local bagsOnly = C_Item.GetItemCount(itemID) or 0
        local plusBank = C_Item.GetItemCount(itemID, true) or 0
        local plusReagent = C_Item.GetItemCount(itemID, true, false, true) or 0
        local plusWarband = C_Item.GetItemCount(itemID, true, false, true, true) or 0
        print(("|cff98FF98[SC:debug]|r GetCount(%d): bags=%d +bank=%d(+%d) +reagent=%d(+%d) +warband=%d(+%d)  ⇒ total=%d"):format(
            itemID, bagsOnly, plusBank, plusBank - bagsOnly,
            plusReagent, plusReagent - plusBank,
            plusWarband, plusWarband - plusReagent, count))
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
