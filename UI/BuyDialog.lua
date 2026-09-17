--[[
    Stock Clerk - UI/BuyDialog.lua
    Per-item purchase confirmation for the restock loop.

    Uses StaticPopupDialogs, which:
      * Auto-manages queueing if two dialogs would show simultaneously
      * Handles Escape / clicking off-screen
      * Uses Blizzard's built-in confirm styling (fits the addon's
        native-template UI direction)

    The dialog shows:
      * Item name + icon
      * "Buy N of M needed" summary (N may be < M if listings ran out
        under the price cap)
      * Total planned spend and worst unit price
      * Warning line if maxPrice is unset or the worst unit is exactly
        at cap (so the user knows the search barely fit)

    Buttons: Confirm | Skip | Stop
--]]

local addonName = ...
local ADDON     = _G[addonName]

local BuyDialog = {}
ADDON.BuyDialog = BuyDialog

local POPUP_NAME = "STOCKCLERK_BUY_CONFIRM"

-- Registered once. We rewrite the .text field each Show() call because
-- StaticPopups don't natively support dynamic per-instance parameters.
StaticPopupDialogs[POPUP_NAME] = {
    text         = "Stock Clerk: confirm purchase",
    button1      = "Buy",
    button2      = "Skip",
    button3      = "Stop loop",
    OnAccept     = function() end,
    OnCancel     = function() end,
    OnAlt        = function() end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 3, -- avoid taint per Blizzard docs
    hasEditBox   = false,
    showAlert    = false,
    -- 3-button variant: OnButton3 acts as "Stop loop"
    -- Blizzard's StaticPopup supports button3 out of the box on retail.
}

local function FormatPlanText(plan)
    -- plan fields: itemID, name, planQuantity, requestedQty, plannedSpend,
    --              worstUnitPrice, shortfall, maxPrice, have, need
    local lines = {}
    lines[#lines+1] = ("|cffffd200%s|r"):format(plan.name or "?")
    lines[#lines+1] = ("Bags: %d / %d  \194\183  Need to buy: %d"):format(
        plan.have or 0, plan.need or 0, plan.requestedQty or 0)

    if plan.planQuantity < plan.requestedQty then
        lines[#lines+1] = ("|cffff8888Only %d available under cap|r"):format(plan.planQuantity)
    end

    lines[#lines+1] = ""
    lines[#lines+1] = ("Total: |cffffffff%s|r"):format(GetCoinTextureString(plan.plannedSpend))
    lines[#lines+1] = ("Worst unit price: %s"):format(GetCoinTextureString(plan.worstUnitPrice))

    if not plan.maxPrice then
        lines[#lines+1] = "|cffff8888No price cap set for this item|r"
    elseif plan.worstUnitPrice >= plan.maxPrice then
        lines[#lines+1] = "|cffffaa00Worst unit is at your cap|r"
    end

    return table.concat(lines, "\n")
end

function BuyDialog:Show(plan, handlers)
    handlers = handlers or {}

    -- Rewrite the dialog callbacks per-show to close over the current
    -- handlers. Safe because only one popup of this name is ever visible.
    StaticPopupDialogs[POPUP_NAME].OnAccept = function()
        if handlers.onConfirm then handlers.onConfirm() end
    end
    StaticPopupDialogs[POPUP_NAME].OnCancel = function()
        if handlers.onSkip then handlers.onSkip() end
    end
    StaticPopupDialogs[POPUP_NAME].OnAlt = function()
        if handlers.onStop then handlers.onStop() end
    end
    StaticPopupDialogs[POPUP_NAME].text = FormatPlanText(plan)

    -- StaticPopup_Show clears any existing instance of the same name
    -- before showing, so rapid Advance() calls don't stack popups.
    StaticPopup_Hide(POPUP_NAME)
    StaticPopup_Show(POPUP_NAME)
end

function BuyDialog:Hide()
    StaticPopup_Hide(POPUP_NAME)
end
