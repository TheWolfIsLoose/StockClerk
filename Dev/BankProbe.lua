--[[
    Stock Clerk - Dev/BankProbe.lua   [DEV ONLY, never ships: #@debug@ in TOC]

    One-off spike for v1.2 "Restock from Bank": do the container calls still
    move bank -> bag items for addons on the live client, and how fast?

        /clerk bankprobe <itemID>        scan, then run every move test
        /clerk bankprobe <itemID> scan   scan only (moves nothing)

    Prep: ~20 of one stackable item in the character bank and ~20 in the
    warband bank, a few free bag slots plus one partial stack of the same
    item in bags. At a banker, out of combat.

    Every line is printed to chat AND saved to StockClerkDB.bankProbe, so
    after a /reload it can be read from WTF\...\SavedVariables\StockClerk.lua.
--]]

local addonName = ...
local ADDON     = _G[addonName]
local C         = C_Container

local out, stepErrors, bankOpen = {}, {}, false
local seenTypes = {}                         -- interaction types since load

local function P(fmt, ...)
    local line = select("#", ...) > 0 and fmt:format(...) or fmt
    out[#out + 1] = line
    print("|cffff9933[probe]|r " .. line)
end

local function enumName(enum, v)
    for k, x in pairs(enum or {}) do if x == v then return k end end
    return "?"
end

-- Events: bank open/close, interaction types, UI errors, blocked actions.
local f = CreateFrame("Frame")
for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "UI_ERROR_MESSAGE",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do f:RegisterEvent(e) end
f:SetScript("OnEvent", function(_, e, a, b)
    if e == "BANKFRAME_OPENED" then bankOpen = true
    elseif e == "BANKFRAME_CLOSED" then bankOpen = false
    elseif e == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        table.insert(seenTypes, ("show %s(%s)"):format(enumName(Enum.PlayerInteractionType, a), tostring(a)))
        if #seenTypes > 8 then table.remove(seenTypes, 1) end
    elseif e == "UI_ERROR_MESSAGE" then stepErrors[#stepErrors + 1] = tostring(b)
    elseif (e == "ADDON_ACTION_BLOCKED" or e == "ADDON_ACTION_FORBIDDEN") and a == addonName then
        stepErrors[#stepErrors + 1] = e .. ": " .. tostring(b)
    end
end)

-- Coroutine helpers ---------------------------------------------------------
local co
local function sleep(s)
    local me = coroutine.running()
    C_Timer.After(s, function()
        local ok, err = coroutine.resume(me)
        if not ok then P("|cffff4444LUA ERROR|r %s", tostring(err)); ClearCursor() end
    end)
    coroutine.yield()
end

-- Scanning ------------------------------------------------------------------
local function bankBags(kind)
    if not (C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum.BankType) then return {} end
    return C_Bank.FetchPurchasedBankTabIDs(Enum.BankType[kind]) or {}
end

local function info(bag, slot) return C.GetContainerItemInfo(bag, slot) end

local function slotsWith(bags, itemID)            -- { {bag, slot, count}, ... } biggest first
    local r = {}
    for _, bag in ipairs(bags) do
        for slot = 1, C.GetContainerNumSlots(bag) do
            local i = info(bag, slot)
            if i and i.itemID == itemID then r[#r + 1] = { bag, slot, i.stackCount } end
        end
    end
    table.sort(r, function(x, y) return x[3] > y[3] end)
    return r
end

local BAGS = { 0, 1, 2, 3, 4 }                    -- backpack + 4 bags (reagent bag excluded)
local function emptyBagSlot()
    for _, bag in ipairs(BAGS) do
        for slot = 1, C.GetContainerNumSlots(bag) do
            if not info(bag, slot) then return bag, slot end
        end
    end
end

local function maxStack(itemID)
    return (C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID))
        or select(8, C_Item.GetItemInfo(itemID)) or 1
end

local function partialBagSlot(itemID, room)
    for _, s in ipairs(slotsWith(BAGS, itemID)) do
        if s[3] + room <= maxStack(itemID) then return s[1], s[2] end
    end
end

-- One move, then wait until the bag count rises by `n` (or timeout). -------
local function settle(itemID, before, n, timeout)
    local t0 = GetTimePreciseSec()
    repeat
        sleep(0.03)
        if C_Item.GetItemCount(itemID) >= before + n and not GetCursorInfo() then
            return true, (GetTimePreciseSec() - t0) * 1000
        end
    until GetTimePreciseSec() - t0 > timeout
    return false, timeout * 1000
end

local function report(label, ok, ms, itemID, before)
    local got = C_Item.GetItemCount(itemID) - before
    P("%s %s: %s in %dms, bags +%d%s", ok and "|cff4ade80OK|r" or "|cffff4444FAIL|r", label,
        ok and "landed" or "timed out", ms, got,
        #stepErrors > 0 and ("  errors: " .. table.concat(stepErrors, " | ")) or "")
    if GetCursorInfo() then P("  cursor still held an item -> ClearCursor()"); ClearCursor() end
end

local function guard()
    if InCombatLockdown() then P("ABORT: entered combat"); return false end
    if not bankOpen then P("ABORT: bank not open (after a /reload, close and reopen the bank)"); return false end
    return true
end

-- split n from the biggest stack in `bags` onto (toBag, toSlot)
local function splitMove(label, itemID, bags, n, toBag, toSlot)
    if not guard() then return false end
    local src = slotsWith(bags, itemID)[1]
    if not src or src[3] < n then P("SKIP %s: not enough in source", label); return true end
    if not toBag then P("SKIP %s: no suitable bag slot", label); return true end
    wipe(stepErrors)
    local before = C_Item.GetItemCount(itemID)
    C.SplitContainerItem(src[1], src[2], n)
    if GetCursorInfo() then C.PickupContainerItem(toBag, toSlot)
    else stepErrors[#stepErrors + 1] = "split put nothing on cursor" end
    report(("%s (%d.%d x%d -> %d.%d)"):format(label, src[1], src[2], n, toBag, toSlot),
        settle(itemID, before, n, 3), itemID, before)
    return true
end

local function wholeMove(label, itemID, bags)
    if not guard() then return false end
    local src = slotsWith(bags, itemID)[1]
    if not src then P("SKIP %s: nothing left in source", label); return true end
    wipe(stepErrors)
    local before = C_Item.GetItemCount(itemID)
    C.UseContainerItem(src[1], src[2])
    report(("%s (UseContainerItem %d.%d x%d)"):format(label, src[1], src[2], src[3]),
        settle(itemID, before, src[3], 3), itemID, before)
    local where = {}
    for _, s in ipairs(slotsWith(BAGS, itemID)) do where[#where + 1] = ("%d.%d=%d"):format(s[1], s[2], s[3]) end
    P("  bag stacks now: %s", table.concat(where, " "))
    return true
end

-- The probe -----------------------------------------------------------------
local function run(itemID, scanOnly)
    local build, _, _, iface = GetBuildInfo()
    P("StockClerk bank probe  item %d (%s)  client %s / %s  %s",
        itemID, C_Item.GetItemInfo(itemID) or "?", build, iface, date("%Y-%m-%d %H:%M"))

    P("1. bankOpen=%s  interactions seen: %s", tostring(bankOpen),
        #seenTypes > 0 and table.concat(seenTypes, ", ") or "none")
    if C_Bank and C_Bank.CanViewBank and Enum.BankType then
        P("   CanViewBank character=%s account=%s",
            tostring(C_Bank.CanViewBank(Enum.BankType.Character)), tostring(C_Bank.CanViewBank(Enum.BankType.Account)))
    end

    local charBags, acctBags = bankBags("Character"), bankBags("Account")
    local function fmt(list) local t = {}
        for _, s in ipairs(list) do t[#t + 1] = ("%d.%d=%d"):format(s[1], s[2], s[3]) end
        return #t > 0 and table.concat(t, " ") or "none" end
    P("2. character tabs {%s}: %s", table.concat(charBags, ","), fmt(slotsWith(charBags, itemID)))
    P("   warband tabs {%s}: %s", table.concat(acctBags, ","), fmt(slotsWith(acctBags, itemID)))
    local eb, es = emptyBagSlot()
    P("   bags: %s  first empty slot %s  max stack %d", fmt(slotsWith(BAGS, itemID)),
        eb and (eb .. "." .. es) or "NONE", maxStack(itemID))
    if scanOnly then P("scan only; nothing moved."); return end

    if GetCursorInfo() then P("ABORT: cursor already holds something"); return end
    if not guard() then return end
    local start = C_Item.GetItemCount(itemID)

    -- Character bank. Splits and throttle tests first, whole stack last,
    -- so ~20 in the bank covers every step (5 + 3 + 3 + 3 + remainder).
    if not splitMove("4a char split -> empty", itemID, charBags, 5, emptyBagSlot()) then return end
    if not splitMove("4b char split -> partial", itemID, charBags, 3, partialBagSlot(itemID, 3)) then return end

    -- 6a: three split+place pairs in the same frame (no waiting).
    if not guard() then return end
    wipe(stepErrors)
    local before, issued = C_Item.GetItemCount(itemID), 0
    for _ = 1, 3 do
        local src, tb, ts = slotsWith(charBags, itemID)[1], partialBagSlot(itemID, 1)
        if src and tb then
            C.SplitContainerItem(src[1], src[2], 1)
            if GetCursorInfo() then C.PickupContainerItem(tb, ts); issued = issued + 1 end
            if GetCursorInfo() then ClearCursor() end
        end
    end
    local ok, ms = settle(itemID, before, 3, 3)
    P("6a burst: 3 moves in one frame, %d placed", issued)
    report("6a burst", ok, ms, itemID, before)

    -- 6b: three moves back to back, each as soon as the last one landed.
    local times = {}
    for n = 1, 3 do
        if not guard() then return end
        local src, tb, ts = slotsWith(charBags, itemID)[1], partialBagSlot(itemID, 1)
        if not (src and tb) then break end
        wipe(stepErrors)
        before = C_Item.GetItemCount(itemID)
        C.SplitContainerItem(src[1], src[2], 1)
        if GetCursorInfo() then C.PickupContainerItem(tb, ts) end
        ok, ms = settle(itemID, before, 1, 3)
        times[#times + 1] = ok and ("%dms"):format(ms) or "timeout"
        if not ok then report("6b move " .. n, ok, ms, itemID, before) end
    end
    P("6b sequential single moves: %s", table.concat(times, ", "))

    if not wholeMove("3 char whole stack", itemID, charBags) then return end

    -- Warband bank.
    if not splitMove("5a warband split -> empty", itemID, acctBags, 5, emptyBagSlot()) then return end
    if not splitMove("5b warband split -> partial", itemID, acctBags, 3, partialBagSlot(itemID, 3)) then return end
    if not wholeMove("5c warband whole stack", itemID, acctBags) then return end

    P("DONE. bags %d -> %d. Now /reload so the log is saved.", start, C_Item.GetItemCount(itemID))
end

-- Hook /clerk bankprobe into Core's slash handler (Core loads first).
local orig = ADDON.OnSlashCommand
function ADDON:OnSlashCommand(msg)
    local id, mode = (msg or ""):lower():match("^bankprobe%s*(%d*)%s*(%a*)")
    if not id then return orig(self, msg) end
    if id == "" then P("usage: /clerk bankprobe <itemID> [scan]"); return end
    if co and coroutine.status(co) ~= "dead" then P("already running"); return end
    wipe(out)
    StockClerkDB.bankProbe = out
    co = coroutine.create(function() run(tonumber(id), mode == "scan") end)
    local ok, err = coroutine.resume(co)
    if not ok then P("|cffff4444LUA ERROR|r %s", tostring(err)); ClearCursor() end
end
