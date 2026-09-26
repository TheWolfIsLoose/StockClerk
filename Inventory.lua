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
    warband/account bank. Retail 11.2 removed the reagent bank, so
    "bank" below means bank + any legacy reagent-bank count.

    Metric choice:
      The visible row count is BAG COUNT ONLY. Rationale: bag<->bank and
      bank<->warband self-moves don't change the all-storage total, so a
      "total" row looks broken to a user who just moved things around.
      Bags-only reacts to every transaction the user makes on the fly,
      matching how they think about "do I have enough to raid tonight?"

      GetBreakdown() exposes bags / bank / warband separately for the
      row's `(+N)` annotation and the tooltip: at most three
      C_Item.GetItemCount calls, cached.

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
--   { bags = N, bank = N, warband = N, total = N }
-- All fields are "just this container," not cumulative, so the caller
-- can decide how to display them.
function INV:GetBreakdown(itemID)
    if not itemID then
        return { bags = 0, bank = 0, warband = 0, total = 0 }
    end

    local cached = self.cache[itemID]
    if cached ~= nil then return cached end

    -- C_Item.GetItemCount(id, includeBank, includeUses, includeReagent, includeAccount)
    -- returns cumulative totals; subtract to derive per-container values.
    --
    -- Fast path: two calls answer the common question "does this item
    -- live anywhere besides bags?" If total == bags there's no stash,
    -- and we skip the extra call that splits the stash into bank vs
    -- warband. Rows without stashed copies (the common case for actively
    -- consumed items) do 2 calls instead of 3.
    local bagsOnly    = C_Item.GetItemCount(itemID) or 0
    local plusWarband = C_Item.GetItemCount(itemID, true, false, true, true) or 0

    local breakdown
    if plusWarband == bagsOnly then
        breakdown = {
            bags    = bagsOnly,
            bank    = 0,
            warband = 0,
            total   = bagsOnly,
        }
    else
        local plusBank = C_Item.GetItemCount(itemID, true, false, true) or 0
        breakdown = {
            bags    = bagsOnly,
            bank    = plusBank    - bagsOnly,
            warband = plusWarband - plusBank,
            total   = plusWarband,
        }
    end
    self.cache[itemID] = breakdown

    if ADDON.debug then
        print(("|cff98FF98[SC:debug]|r GetBreakdown(%d): bags=%d bank=%d warband=%d ⇒ total=%d"):format(
            itemID, breakdown.bags, breakdown.bank, breakdown.warband, breakdown.total))
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
