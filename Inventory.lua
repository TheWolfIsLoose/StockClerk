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

    Metric choice:
      The visible row count is BAG COUNT ONLY. Rationale: bag<->bank and
      bank<->warband self-moves don't change the all-storage total, so a
      "total" row looks broken to a user who just moved things around.
      Bags-only reacts to every transaction the user makes on the fly,
      matching how they think about "do I have enough to raid tonight?"

      GetBreakdown() exposes bags / bank / reagent / warband separately
      for the row's `(+N in bank)` annotation and for the tooltip. It's
      four C_Item.GetItemCount calls, still O(1) per item, cached.

    Caching:
      We memoize breakdowns per itemID and invalidate on BAG_UPDATE_DELAYED,
      PLAYERBANKSLOTS_CHANGED, PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED,
      BANK_TABS_CHANGED and BANKFRAME_OPENED. The last one guarantees a
      fresh scan the first time the user opens the bank in a session.
--]]

local addonName = ...
local ADDON     = _G[addonName]
local INV = { cache = {} }
ADDON.Inventory = INV

function INV:Invalidate()
    wipe(self.cache)
end

-- Returns a fully-populated breakdown for the item:
--   { bags = N, bank = N, reagent = N, warband = N, total = N }
-- All fields are "just this container," not cumulative, so the caller
-- can decide how to display them.
function INV:GetBreakdown(itemID)
    if not itemID then
        return { bags = 0, bank = 0, reagent = 0, warband = 0, total = 0 }
    end

    local cached = self.cache[itemID]
    if cached ~= nil then return cached end

    -- C_Item.GetItemCount(id, includeBank, includeUses, includeReagent, includeAccount)
    -- returns cumulative totals; subtract to derive per-container values.
    local bagsOnly    = C_Item.GetItemCount(itemID) or 0
    local plusBank    = C_Item.GetItemCount(itemID, true) or 0
    local plusReagent = C_Item.GetItemCount(itemID, true, false, true) or 0
    local plusWarband = C_Item.GetItemCount(itemID, true, false, true, true) or 0

    local breakdown = {
        bags    = bagsOnly,
        bank    = plusBank    - bagsOnly,
        reagent = plusReagent - plusBank,
        warband = plusWarband - plusReagent,
        total   = plusWarband,
    }
    self.cache[itemID] = breakdown

    if ADDON.debug then
        print(("|cff98FF98[SC:debug]|r GetBreakdown(%d): bags=%d bank=%d reagent=%d warband=%d ⇒ total=%d"):format(
            itemID, breakdown.bags, breakdown.bank,
            breakdown.reagent, breakdown.warband, breakdown.total))
    end

    return breakdown
end

-- Back-compat: returns the primary "have" number (bags only).
-- Callers that want the breakdown should use GetBreakdown(itemID).
function INV:GetCount(itemID)
    return self:GetBreakdown(itemID).bags
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
