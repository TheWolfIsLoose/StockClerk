--[[
    StockClerk - Dev/BankProbe.lua   [DEV ONLY, never ships: #@debug@ in TOC]

    v1.3 spike: can addon code deposit bag stacks into the warband bank,
    do tab deposit filters block it, and how fast can deposits chain?
    (The v1.2 pull probe this replaces is in git history.)

        /clerk bankprobe <itemID>        scan, then run every deposit test
        /clerk bankprobe <itemID> scan   scan only (moves nothing)

    Prep: ~30 of one stackable item in bags, in 2+ stacks; one partial
    stack of it already in a warband tab; free slots in every warband tab.
    Optional: set one tab's deposit filter to exclude this item's type
    (step 7 places 1 into every tab and reports each). At a banker, out
    of combat.

    Every line is printed to chat AND saved to StockClerkDB.bankProbe; after
    a /reload it can be read from WTF\...\SavedVariables\StockClerk.lua.
--]]

local addonName = ...
local ADDON     = _G[addonName]
local C         = C_Container
local BAGS      = { 0, 1, 2, 3, 4 }

local out, errs, bankOpen, co = {}, {}, false, nil

local function P(fmt, ...)
    local line = select("#", ...) > 0 and fmt:format(...) or fmt
    out[#out + 1] = line
    print("|cffff9933[probe]|r " .. line)
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "UI_ERROR_MESSAGE",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do f:RegisterEvent(e) end
f:SetScript("OnEvent", function(_, e, a, b)
    if e == "BANKFRAME_OPENED" then bankOpen = true
    elseif e == "BANKFRAME_CLOSED" then bankOpen = false
    elseif e == "UI_ERROR_MESSAGE" then errs[#errs + 1] = tostring(b)
    elseif a == addonName then errs[#errs + 1] = e .. ": " .. tostring(b) end
end)

local function sleep(s)
    local me = coroutine.running()
    C_Timer.After(s, function()
        local ok, err = coroutine.resume(me)
        if not ok then P("|cffff4444LUA ERROR|r %s", tostring(err)); ClearCursor() end
    end)
    coroutine.yield()
end

-- Scanning ------------------------------------------------------------------
local function tabs() return C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account) or {} end
local function info(bag, slot) return C.GetContainerItemInfo(bag, slot) end
local function maxStack(id) return C_Item.GetItemMaxStackSizeByID(id) or 1 end

local function slotsWith(bags, id)                -- { {bag, slot, count}, ... } biggest first
    local r = {}
    for _, bag in ipairs(bags) do
        for slot = 1, C.GetContainerNumSlots(bag) do
            local i = info(bag, slot)
            if i and i.itemID == id then r[#r + 1] = { bag, slot, i.stackCount } end
        end
    end
    table.sort(r, function(x, y) return x[3] > y[3] end)
    return r
end

local function total(bags, id)
    local n = 0
    for _, s in ipairs(slotsWith(bags, id)) do n = n + s[3] end
    return n
end

local function emptySlot(bags)
    for _, bag in ipairs(bags) do
        for slot = 1, C.GetContainerNumSlots(bag) do
            if not info(bag, slot) then return bag, slot end
        end
    end
end

local function partialSlot(bags, id, room)
    for _, s in ipairs(slotsWith(bags, id)) do
        if s[3] + room <= maxStack(id) then return s[1], s[2] end
    end
end

local function fmt(list)
    local t = {}
    for _, s in ipairs(list) do t[#t + 1] = ("%d.%d=%d"):format(s[1], s[2], s[3]) end
    return #t > 0 and table.concat(t, " ") or "none"
end

local function allowed(bag, slot)
    local ok, r = pcall(C_Bank.IsItemAllowedInBankType, Enum.BankType.Account,
        ItemLocation:CreateFromBagAndSlot(bag, slot))
    return ok and tostring(r) or ("error: " .. tostring(r))
end

-- One deposit, then wait until the warband count rises by n (or timeout). -
local function guard()
    if InCombatLockdown() then P("ABORT: entered combat"); return false end
    if not bankOpen then P("ABORT: bank not open (after a /reload, close and reopen the bank)"); return false end
    return true
end

local function settle(bags, id, before, n)
    local t0 = GetTimePreciseSec()
    repeat
        sleep(0.03)
        if total(bags, id) >= before + n and not GetCursorInfo() then
            return true, (GetTimePreciseSec() - t0) * 1000
        end
    until GetTimePreciseSec() - t0 > 3
    return false, 3000
end

local function report(label, ok, ms, bags, id, before)
    P("%s %s: %s in %dms, warband +%d, GetItemCount(account) %d%s",
        ok and "|cff4ade80OK|r" or "|cffff4444FAIL|r", label, ok and "landed" or "timed out", ms,
        total(bags, id) - before, C_Item.GetItemCount(id, true, false, true, true) - C_Item.GetItemCount(id, true, false, true),
        #errs > 0 and ("  errors: " .. table.concat(errs, " | ")) or "")
    if GetCursorInfo() then P("  cursor still held an item -> ClearCursor()"); ClearCursor() end
end

-- Split n off the biggest bag stack (or pick it up whole if n == its size)
-- into `bags`: onto a partial stack with room unless into == "empty".
local function deposit(label, id, n, bags, into)
    if not guard() then return false end
    local src = slotsWith(BAGS, id)[1]
    if not src or src[3] < n then P("SKIP %s: not enough in bags", label); return true end
    local toBag, toSlot
    if into ~= "empty" then toBag, toSlot = partialSlot(bags, id, n) end
    if not toBag then toBag, toSlot = emptySlot(bags) end
    if not toBag then P("SKIP %s: no target slot", label); return true end
    wipe(errs)
    local before = total(bags, id)
    if n == src[3] then C.PickupContainerItem(src[1], src[2]) else C.SplitContainerItem(src[1], src[2], n) end
    if GetCursorInfo() then C.PickupContainerItem(toBag, toSlot)
    else errs[#errs + 1] = "nothing on cursor after pickup" end
    local ok, ms = settle(bags, id, before, n)
    report(("%s (%d.%d x%d -> %d.%d)"):format(label, src[1], src[2], n, toBag, toSlot), ok, ms, bags, id, before)
    return true
end

-- The probe -----------------------------------------------------------------
local function run(id, scanOnly)
    local build, _, _, iface = GetBuildInfo()
    P("StockClerk DEPOSIT probe  item %d (%s)  client %s / %s  %s",
        id, C_Item.GetItemInfo(id) or "?", build, iface, date("%Y-%m-%d %H:%M"))
    local acct = tabs()
    P("1. bankOpen=%s  CanViewBank(account)=%s", tostring(bankOpen),
        tostring(C_Bank.CanViewBank(Enum.BankType.Account)))
    for _, t in ipairs(C_Bank.FetchPurchasedBankTabData(Enum.BankType.Account) or {}) do
        P("   tab %s \"%s\" depositFlags=%s", tostring(t.ID), tostring(t.name), tostring(t.depositFlags))
    end
    P("2. warband {%s}: %s", table.concat(acct, ","), fmt(slotsWith(acct, id)))
    local bagSlots = slotsWith(BAGS, id)
    P("   bags: %s  max stack %d", fmt(bagSlots), maxStack(id))
    if bagSlots[1] then P("   IsItemAllowedInBankType(account) for this item: %s", allowed(bagSlots[1][1], bagSlots[1][2])) end
    local refused = {}
    for _, bag in ipairs(BAGS) do
        for slot = 1, C.GetContainerNumSlots(bag) do
            local i = info(bag, slot)
            local a = i and allowed(bag, slot)
            if a and a ~= "true" then refused[#refused + 1] = ("%s(%s)"):format(i.itemID, a) end
        end
    end
    P("   bag items the warband bank refuses: %s", #refused > 0 and table.concat(refused, " ", 1, math.min(#refused, 12)) or "none")
    if scanOnly then P("scan only; nothing moved."); return end
    if GetCursorInfo() then P("ABORT: cursor already holds something"); return end

    -- 4: split to an empty slot, split onto a partial stack.
    if not deposit("4a split -> empty", id, 5, acct, "empty") then return end
    if not deposit("4b split -> partial", id, 3, acct) then return end

    -- 5a: three split+place pairs in one frame (expect the lock to refuse 2 of them).
    if not guard() then return end
    wipe(errs)
    local before, issued = total(acct, id), 0
    for _ = 1, 3 do
        local src, tb, ts = slotsWith(BAGS, id)[1], partialSlot(acct, id, 1)
        if src and tb then
            C.SplitContainerItem(src[1], src[2], 1)
            if GetCursorInfo() then C.PickupContainerItem(tb, ts); issued = issued + 1 end
            if GetCursorInfo() then ClearCursor() end
        end
    end
    local ok, ms = settle(acct, id, before, 3)
    P("5a burst: 3 deposits in one frame, %d placed", issued)
    report("5a burst", ok, ms, acct, id, before)

    -- 5b: three single deposits back to back, each once the last landed.
    local times = {}
    for n = 1, 3 do
        if not guard() then return end
        local src, tb, ts = slotsWith(BAGS, id)[1], partialSlot(acct, id, 1)
        if not (src and tb) then break end
        wipe(errs)
        before = total(acct, id)
        C.SplitContainerItem(src[1], src[2], 1)
        if GetCursorInfo() then C.PickupContainerItem(tb, ts) end
        ok, ms = settle(acct, id, before, 1)
        times[#times + 1] = ok and ("%dms"):format(ms) or "timeout"
        if not ok then report("5b deposit " .. n, ok, ms, acct, id, before) end
    end
    P("5b sequential single deposits: %s", table.concat(times, ", "))

    -- 6: whole stack (pickup, no split) onto a partial with room, else empty.
    local src = slotsWith(BAGS, id)[#slotsWith(BAGS, id)]   -- smallest stack
    if src then
        local tb, ts = partialSlot(acct, id, src[3])
        if not tb then tb, ts = emptySlot(acct) end
        if not guard() then return end
        wipe(errs)
        before = total(acct, id)
        C.PickupContainerItem(src[1], src[2])
        if GetCursorInfo() then C.PickupContainerItem(tb, ts) end
        ok, ms = settle(acct, id, before, src[3])
        report(("6 whole stack (%d.%d x%d -> %s.%s)"):format(src[1], src[2], src[3], tostring(tb), tostring(ts)),
            ok, ms, acct, id, before)
    end

    -- 7: one into every tab (deposit filters vs addon placement).
    for _, tab in ipairs(acct) do
        if not deposit("7 tab " .. tab, id, 1, { tab }) then return end
    end

    P("DONE. warband %s. Now /reload so the log is saved.", fmt(slotsWith(acct, id)))
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
