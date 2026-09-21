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
    --
    -- Fast path: two calls answer the common question "does this item
    -- live anywhere besides bags?" If total == bags there's no stash,
    -- and we can skip the two extra calls that decompose stash into
    -- bank/reagent/warband. Rows without stashed copies (the common
    -- case for actively-consumed items) do 2 calls instead of 4. The
    -- expensive account-bank variant is only hit on the slow path.
    local bagsOnly    = C_Item.GetItemCount(itemID) or 0
    local plusWarband = C_Item.GetItemCount(itemID, true, false, true, true) or 0

    local breakdown
    if plusWarband == bagsOnly then
        breakdown = {
            bags    = bagsOnly,
            bank    = 0,
            reagent = 0,
            warband = 0,
            total   = bagsOnly,
        }
    else
        -- Full decomposition needed for the (+N: bank/reagent/warband) suffix.
        local plusBank    = C_Item.GetItemCount(itemID, true) or 0
        local plusReagent = C_Item.GetItemCount(itemID, true, false, true) or 0
        breakdown = {
            bags    = bagsOnly,
            bank    = plusBank    - bagsOnly,
            reagent = plusReagent - plusBank,
            warband = plusWarband - plusReagent,
            total   = plusWarband,
        }
    end
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
    -- Only trigger a UI rebuild when the window is actually visible.
    -- Cache invalidation always runs so the next open reads fresh data,
    -- but rebuilding the row list is wasted work while we're closed --
    -- and each row does GetBreakdown() -> up to 4 GetItemCount calls,
    -- which is the hitch that surfaces when opening bags/warband bank.
    -- MF:Show() calls Refresh() explicitly, so the next open repaints.
    local mf = ADDON.MainFrame
    if mf and mf.Refresh and mf.frame and mf.frame:IsShown() then
        mf:Refresh()
    end
end
