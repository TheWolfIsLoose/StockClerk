--[[
    StockClerk - Merchant.lua
    "Restock at vendor": the AH restock at a merchant. Same list, targets and
    caps (an item above its cap is marked and passed over), list order is the
    priority, and nothing is bought without the player's click. A vendor's
    price is fixed and its goods land in bags, so one click buys the lot: no
    per-item Buy, no mail ledger. Gold-priced items only.
--]]

local addonName = ...
local ADDON     = _G[addonName]

local V = {}
ADDON.Merchant = V

-- itemID -> { index, price (per batch), batch (items per purchase), unit, avail (batches; -1 = unlimited) }
function V:Stock()
    local out = {}
    for i = 1, GetMerchantNumItems() do
        local id, info = GetMerchantItemID(i), C_MerchantFrame.GetItemInfo(i)
        if id and not out[id] and info.isPurchasable and not info.hasExtendedCost and info.price > 0 then
            local batch = math.max(1, info.stackCount)
            out[id] = { index = i, price = info.price, batch = batch, unit = info.price / batch, avail = info.numAvailable }
        end
    end
    return out
end

-- Listed items this vendor sells that you're short, in list order:
-- { item, s (its Stock entry), batches, overCap }.
function V:Plan()
    local plan, stock, loop = {}, self:Stock(), ADDON.RestockLoop
    for _, it in ipairs(ADDON.DB:GetSortedItems()) do
        local s, short = stock[it.itemID], loop:Short("mine", it.itemID, it.need)
        if s and short > 0 then
            local batches = math.ceil(short / s.batch)
            if s.avail >= 0 then batches = math.min(batches, s.avail) end
            if batches > 0 then
                plan[#plan + 1] = { item = it, s = s, batches = batches, overCap = it.maxPrice and s.unit > it.maxPrice }
            end
        end
    end
    return plan
end

-- For the button: items a click would buy, and what they cost.
function V:Preview()
    local n, cost = 0, 0
    for _, p in ipairs(self:Plan()) do
        if not p.overCap then n, cost = n + 1, cost + p.batches * p.s.price end
    end
    return n, cost
end

-- ponytail: free slots in plain bags only (no reagent bag, no topping up a
-- partial stack), so a nearly full bag may buy a little less than it could.
local function FreeSlots()
    local n = 0
    for bag = 0, 4 do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if family == 0 then n = n + free end
    end
    return n
end

-- Bags update a moment after a buy; until then a second click would buy it all again.
local LOCK = 1.5

function V:Restock()
    if GetTime() < (self.lockUntil or 0) then return end
    self.lockUntil = GetTime() + LOCK
    local mf, money, free = ADDON.MainFrame, GetMoney(), FreeSlots()
    local bought, spent, over, short = 0, 0, 0, nil
    mf:ClearMarks()
    for _, p in ipairs(self:Plan()) do
        local id, s = p.item.itemID, p.s
        if p.overCap then
            over = over + 1
            mf:Mark(id, "over", "Over your cap: " .. ADDON.MoneyText(s.unit, "silver") .. " each here")
            ADDON.Log:Emit("buy_skip", id, { reason = "over cap" })
        else
            local perSlot = math.max(1, math.floor((C_Item.GetItemMaxStackSizeByID(id) or 1) / s.batch))
            local canPay, canFit = math.floor(money / s.price), free * perSlot
            local n = math.min(p.batches, canPay, canFit)
            if n < p.batches then short = short or (canPay < canFit and "Not enough gold." or "Not enough bag space.") end
            if n > 0 then
                local left, perCall = n * s.batch, math.max(s.batch, GetMerchantItemMaxStack(s.index))
                while left > 0 do
                    local q = math.min(left, perCall)
                    BuyMerchantItem(s.index, q)
                    left = left - q
                end
                local cost = n * s.price
                money, free = money - cost, free - math.ceil(n / perSlot)
                bought, spent = bought + 1, spent + cost
                mf:Mark(id, "done", ("Bought %d for %s"):format(n * s.batch, ADDON.MoneyText(cost)))
                ADDON.Log:Emit("buy_success", id, { qty = n * s.batch, spentCopper = cost, lane = "mine" })
            end
        end
    end
    local parts = { bought > 0 and ("bought %d for %s"):format(bought, ADDON.MoneyText(spent)) or "nothing bought" }
    if over > 0 then parts[#parts + 1] = over .. " over cap" end
    mf:SetStatus("Vendor: " .. table.concat(parts, " \194\183 ") .. (short and (" \194\183 |cffff6666" .. short .. "|r") or ""))
end
