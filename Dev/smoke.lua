-- Stock Clerk smoke test (dev only; Dev/ never ships).
-- Loads the addon in TOC order against stubbed WoW APIs, then checks the
-- lifecycle, saved-data carry-over, event routing, inventory math, the row
-- editors and the refresh guards. Needs a Lua 5.1 interpreter:
--   lua5.1 Dev/smoke.lua .
-- Prints a line per section; any failure raises with the reason.
-- Minimal WoW stub harness: load the addon in TOC order, run lifecycle,
-- fire a few events, and flush timers. Catches load-time/wiring errors.
local root = arg[1]
local timers, frames = {}, {}
local Stub
Stub = setmetatable({}, { __index = function() return Stub end, __call = function() return Stub end })
local function Frame(parent)
  local f = { scripts = {}, events = {}, _parent = parent, _text = "" }
  return setmetatable(f, { __index = function(t, k)
    if k == "Show" then return function(self) self._shown = true end end
    if k == "Hide" then return function(self) self._shown = false end end
    if k == "IsShown" then return function(self) return self._shown == true end end
    if k == "SetText" then return function(self, x) self._text = x end end
    if k == "GetText" then return function(self) return self._text end end
    if k == "GetParent" then return function(self) return self._parent end end
    if k == "SetFocus" then return function(self) self._focus = true end end
    if k == "ClearFocus" then return function(self)
      if self._focus then self._focus = false
        if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end end
    end end
    if k == "HookScript" then return function(self, n, fn)
      local old = self.scripts[n]
      self.scripts[n] = old and function(...) old(...); fn(...) end or fn
    end end
    if k == "SetScript" then return function(self, n, fn) self.scripts[n] = fn end end
    if k == "GetScript" then return function(self, n) return self.scripts[n] end end
    if k == "RegisterEvent" then return function(self, e) self.events[e] = true end end
    if k == "UnregisterEvent" then return function(self, e) self.events[e] = nil end end
    if k == "IsEventRegistered" then return function(self, e) return self.events[e] end end
    if not k:match("^[A-Z]") then return nil end
    if k == "GetName" then return function() return "Frame" end end
    if k:match("^Get") and (k:match("Texture$") or k:match("FontString$") or k:match("Region$")) then
      return function(self) return Frame(self) end end
    if k:match("^Get") then return function() return 0 end end
    if k:match("^Is") or k:match("^Has") then return function() return false end end
    if k:match("^Create") then return function(self) return Frame(self) end end
    return function() return Stub end
  end })
end
setmetatable(_G, { __index = function(_, k)
  if k == "LibStub" or k:match("^StockClerk") then return nil end
  if k:match("^[A-Z]") or k:match("^C_") then return Stub end
  return nil
end })
CreateFrame = function(_, _, parent) local f = Frame(parent); frames[#frames + 1] = f; return f end
C_Timer = { After = function(d, fn) timers[#timers + 1] = fn end,
            NewTimer = function(d, fn) timers[#timers + 1] = fn; return { Cancel = function() end } end,
            NewTicker = function() return { Cancel = function() end } end }
C_AddOns = { GetAddOnMetadata = function() return "1.1.2" end, IsAddOnLoaded = function() return true end, LoadAddOn = function() end,
             GetNumAddOns = function() return 2 end }
GetAddOnMetadata = C_AddOns.GetAddOnMetadata
securecallfunction = function(f, ...) return f(...) end
geterrorhandler = function() return function(e) error(e, 0) end end
GetTime = function() return 0 end
GetServerTime = os.time
time = os.time
date = os.date
CopyTable = function(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and CopyTable(v) or v end return o end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
strsplit = function(d, s) local o = {} for p in (s .. d):gmatch("(.-)" .. d) do o[#o + 1] = p end return unpack(o) end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
format = string.format
hooksecurefunc = function() end
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitRace = function() return "Human", "Human" end
UnitFactionGroup = function() return "Alliance" end
GetCurrentRegion = function() return 1 end
GetLocale = function() return "enUS" end
debugstack = function() return "file:1: in function\nfile:2" end
IsLoggedIn = function() return false end
print = function(...) end
UISpecialFrames = {}
SlashCmdList = {}
Enum = { PlayerInteractionType = { Auctioneer = 21, Banker = 8 } }

local ADDON_NAME = "StockClerk"
local function load(rel)
  local fn = assert(loadfile(root .. "/" .. rel:gsub("\\", "/")))
  fn(ADDON_NAME, {})
end
local function xml(rel)
  local dir = rel:match("^(.*)/") or ""
  local fh = io.open(root .. "/" .. rel); if not fh then io.stderr:write("missing xml: " .. rel .. "\n"); return end
  local txt = fh:read("*a")
  for kind, file in txt:gmatch('<(%a+) file="([^"]+)"') do
    local path = (dir ~= "" and dir .. "/" or "") .. file:gsub("\\", "/")
    if kind == "Script" then load(path) elseif kind == "Include" then xml(path) end
  end
end
-- SavedVariables in the pre-1.1.2 (AceDB) layout, to prove they carry over.
StockClerkDB = { global = { settings = { autoOpenAtAH = false }, log = { { ts = 1, kind = "status" } } },
                 profileKeys = { ["Tester - Realm"] = "Default" } }
StockClerkCharDB = { items = { [111] = { need = 5, sortOrder = 10 } } }
for line in io.lines(root .. "/StockClerk.toc") do
  line = line:gsub("\r", "")
  if not line:match("^#") and line:match("%S") then
    if line:match("%.xml$") then xml(line:gsub("\\", "/")) else load(line) end
  end
end
local ADDON = _G[ADDON_NAME]
local evFrame
for _, f in ipairs(frames) do if f.events.ADDON_LOADED then evFrame = f end end
assert(evFrame, "event frame not found")
local function fire(e, ...) evFrame.scripts.OnEvent(evFrame, e, ...) end
fire("ADDON_LOADED", "OtherAddon")
assert(not ADDON.DB.char, "must ignore other addons' ADDON_LOADED")
fire("ADDON_LOADED", ADDON_NAME)
fire("PLAYER_LOGIN")
assert(SlashCmdList.STOCKCLERK and SLASH_STOCKCLERK1 == "/clerk", "slash not registered")
local st = ADDON.DB:Settings()
assert(st.autoOpenAtAH == false, "saved setting lost")
assert(st.autoRestock == false and st.lastPriceTTL == 86400, "defaults not filled")
assert(#ADDON.DB.global.log == 2 and ADDON.DB.global.log[2].kind == "version", "saved log lost / no version entry")
assert(ADDON.DB.char.items[111].need == 5, "saved data lost")
assert(ADDON.DB.char.pendingBuys and ADDON.DB.char.ui, "char defaults not filled")
do -- "Add common consumables": adds the rest at target 1, never touches tracked items
  local items, list = ADDON.DB.char.items, ADDON.CommonConsumables
  local seen = {}; for _, id in ipairs(list) do assert(not seen[id], "duplicate consumable " .. id); seen[id] = true end
  items[list[1]] = { need = 7, maxPrice = 99, sortOrder = 5 }
  assert(ADDON.DB:AddCommonConsumables() == #list - 1, "common consumables count")
  assert(items[list[1]].need == 7 and items[list[1]].maxPrice == 99, "tracked item was overwritten")
  assert(items[list[2]].need == 1, "new item target")
  assert(ADDON.DB:AddCommonConsumables() == 0, "second click added duplicates")
  for _, id in ipairs(list) do items[id] = nil end
end
do local out = {}; local op = print; print = function(m) out[#out + 1] = m end
   SlashCmdList.STOCKCLERK("help"); print = op
   assert(out[1] and out[1]:find("StockClerk", 1, true), "slash /clerk help did not print") end
local origInv = ADDON.Inventory.OnInventoryChanged
do
assert(ADDON.MainFrame.Palette and ADDON.MainFrame.Palette.panelBg, "palette not published")
local invCalls = 0
ADDON.Inventory.OnInventoryChanged = function(...) invCalls = invCalls + 1 end
fire("BAG_UPDATE_DELAYED"); fire("BAG_UPDATE_DELAYED"); fire("BANKFRAME_OPENED")
assert(invCalls == 0, "debounce fired early")
local n = #timers
for i = 1, n do timers[i]() end
assert(invCalls == 1, "debounce should collapse to 1 call, got " .. invCalls)
fire("BAG_UPDATE_DELAYED"); for i = n + 1, #timers do timers[i]() end
assert(invCalls == 2, "debounce should re-arm, got " .. invCalls)
do -- AH: buy planning within the cap, and confirm only if the server total hasn't risen
  local AH, ahf, cah = ADDON.AH, AuctionHouseFrame, C_AuctionHouse
  local listings = { { unitPrice = 100, quantity = 5 }, { unitPrice = 200, quantity = 5 }, { unitPrice = 900, quantity = 50 } }
  local calls = {}
  AuctionHouseFrame = { IsShown = function() return true end }
  C_AuctionHouse = {
    MakeItemKey = function(id) return id end, SendSearchQuery = function() end,
    GetNumCommoditySearchResults = function() return #listings end,
    GetCommoditySearchResultInfo = function(_, i) return listings[i] end,
    StartCommoditiesPurchase   = function() calls[#calls + 1] = "start" end,
    ConfirmCommoditiesPurchase = function() calls[#calls + 1] = "confirm" end,
    CancelCommoditiesPurchase  = function() calls[#calls + 1] = "cancel" end,
  }
  local newTimer = C_Timer.NewTimer
  C_Timer.NewTimer = function() return { Cancel = function() end } end  -- timeouts never fire here
  local function run(fn) local mark = #timers; fn(); for i = mark + 1, #timers do timers[i]() end end
  local ok, res
  local function cb(o, r) ok, res = o, r end
  run(function() AH:BuyUpTo(7, 8, 250, cb); AH:OnCommoditySearchUpdated(7) end)
  assert(ok and res.planQuantity == 8 and res.plannedSpend == 1100 and res.worstUnitPrice == 200, "buy plan")
  run(function() AH:BuyUpTo(7, 8, 50, cb); AH:OnCommoditySearchUpdated(7) end)
  assert(not ok and res:find("above your 0g cap", 1, true), "cap refusal: " .. tostring(res))
  run(function() AH:ExecutePurchase(7, 8, 1100, cb); AH:OnCommodityPriceUpdated(137, 1100) end)
  assert(calls[#calls] == "confirm", "confirm at expected total")
  run(function() AH:OnCommodityPurchaseSucceeded() end)
  assert(ok, "purchase success")
  run(function() AH:ExecutePurchase(7, 8, 1100, cb); AH:OnCommodityPriceUpdated(150, 1200) end)
  assert(calls[#calls] == "cancel" and not ok and res:find("price rose"), "cancel when price rose")
  AuctionHouseFrame, C_AuctionHouse, C_Timer.NewTimer = ahf, cah, newTimer
end
local got = {}
for _, m in ipairs({ "OnCommoditySearchUpdated", "OnCommodityPriceUpdated", "OnCommodityPriceUnavailable",
                     "OnCommodityPurchaseSucceeded", "OnCommodityPurchaseFailed" }) do
  ADDON.AH[m] = function(self, ...) assert(self == ADDON.AH); got[m] = { ... } end
end
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 12345)
fire("COMMODITY_PRICE_UPDATED", 100, 500)
fire("COMMODITY_PRICE_UNAVAILABLE"); fire("COMMODITY_PURCHASE_SUCCEEDED"); fire("COMMODITY_PURCHASE_FAILED")
assert(got.OnCommoditySearchUpdated[1] == 12345, "search itemID not passed")
assert(got.OnCommodityPriceUpdated[1] == 100 and got.OnCommodityPriceUpdated[2] == 500, "price args not passed")
assert(got.OnCommodityPurchaseFailed, "purchase failed not routed")
local mail = 0
ADDON.RestockLoop._OnMailInboxUpdate = function() mail = mail + 1 end
fire("MAIL_INBOX_UPDATE"); assert(mail == 1, "mail not routed")
ADDON.debug = true
ADDON.Debug("AH", "x", 1)
local last = ADDON.DB.global.log[#ADDON.DB.global.log]
assert(last.kind == "trace" and last.payload.text == "x 1" and ADDON.Log:Format(last) == "[AH] x 1", "trace not recorded")
ADDON.debug = false
do -- Plain-language wording, report header, error capture
  local Log = ADDON.Log
  local F = function(kind, p, id) return Log:Format({ kind = kind, payload = p, itemID = id }) end
  assert(Log.Money(42550000) == "4,255g" and Log.Money(123400) == "12g 34s" and Log.Money(5000) == "50s", "money")
  assert(F("buy_success", { qty = 20, spentCopper = 4120000 }, 7) == "Bought 20 [item 7] for 412g", F("buy_success", { qty = 20, spentCopper = 4120000 }, 7))
  assert(F("cap_change", { toCopper = 1500000 }, 7) == "[item 7]: cap set to 150g", "cap set")
  assert(F("cap_change", { fromCopper = 1500000 }, 7) == "[item 7]: cap removed", "cap removed")
  assert(F("loop_stop", { reason = "user_stop", touched = 0 }) == "Restock stopped by you, nothing bought", "loop stop")
  assert(F("loop_stop", { reason = "done", touched = 3, spentCopper = 6120000, stillShort = 1 })
         == "Restock finished, bought 3 items for 612g, 1 still short", "loop done")
  assert(F("buy_skip", { reason = "cap out (silent)" }, 7) == "Skipped [item 7]: cheapest price is above your cap", "skip")
  assert(Log:Format({ kind = "bank_pull", payload = { qty = 5 }, itemID = 7 }, true) == "Pulled 5 [item 7] (#7) from your bank", "full ids")
  for kind in pairs(Log.LEVEL) do assert(type(F(kind, {}, 7)) == "string", "format " .. kind) end
  local gb = ADDON.Inventory.GetBreakdown
  ADDON.Inventory.GetBreakdown = function() return { bags = 2, bank = 0, warband = 0 } end
  ADDON.DB.char.pendingBuys[111] = { qty = 3, baseHave = 0, boughtAt = 0 }
  local report = Log:Report()
  ADDON.Inventory.GetBreakdown, ADDON.DB.char.pendingBuys[111] = gb, nil
  assert(report:find("(#111) 2/5", 1, true) and report:find("Waiting in the mail: item 111 (#111) x3", 1, true), "report list/mail")
  assert(report:find("StockClerk report", 1, true) and report:find("Settings: ", 1, true)
         and report:find("> [AH] x 1", 1, true), "report")
  assert(report:find("\n%-%- %a%a%a %d%d%d%d%-%d%d%-%d%d %-%-\n") and report:find("\n%[%d%d:%d%d:%d%d%] "), "report layout")
  -- Event handler errors land in the log, then reach the normal error handler
  local seen
  local geh = geterrorhandler
  geterrorhandler = function() return function(e) seen = e end end
  local hs = evFrame.scripts.OnEvent
  SlashCmdList = SlashCmdList or {}
  evFrame.events.SMOKE_BOOM = true
  -- inject a failing handler through the real dispatcher
  local ok = pcall(hs, evFrame, "SMOKE_BOOM")  -- no handler: indexing nil errors inside xpcall
  geterrorhandler = geh
  local e = ADDON.DB.global.log[#ADDON.DB.global.log]
  assert(ok and seen and e.kind == "error" and Log.LEVEL.error == "activity", "error not captured")
end
io.stdout:write("smoke OK\n")
end
local capturedInit
CreateScrollBoxListLinearView = function()
  return setmetatable({ SetElementInitializer = function(_, _, fn) capturedInit = fn end },
    { __index = function() return function() return Stub end end })
end
-- UI builds (stubbed frames): catches nil palette keys / missing helpers.
ADDON.Inventory.OnInventoryChanged = origInv
MF = ADDON.MainFrame
local ok, err = pcall(function() MF:Build() end)
io.stdout:write("MF:Build " .. (ok and "OK" or ("ERR " .. tostring(err))) .. "\n")
ok, err = pcall(function() ADDON.Sidecar:Toggle(Stub) end)
io.stdout:write("Sidecar " .. (ok and "OK" or ("ERR " .. tostring(err))) .. "\n")
ok, err = pcall(function() ADDON.LogPopup:Show() end)
io.stdout:write("LogPopup " .. (ok and "OK" or ("ERR " .. tostring(err))) .. "\n")
ok, err = pcall(function() ADDON.BulkImport:Open() end)
io.stdout:write("BulkImport " .. (ok and "OK" or ("ERR " .. tostring(err))) .. "\n")
do -- Cursor item: numeric id, or a link in either slot; nothing for non-items
  local gci = GetCursorInfo
  GetCursorInfo = function() return "item", 212283 end;                        assert(ADDON.MainFrame.CursorItemID() == 212283, "cursor id")
  GetCursorInfo = function() return "item", nil, "|Hitem:7:::|h[x]|h" end;     assert(ADDON.MainFrame.CursorItemID() == 7, "cursor link")
  GetCursorInfo = function() return "spell", 5 end;                            assert(ADDON.MainFrame.CursorItemID() == nil, "cursor non-item")
  GetCursorInfo = gci
end
do -- Bulk parser: id [target [cap]], comments skipped, bad lines reported
  local r = ADDON.BulkImport.ParseBulkText("212283\n7 20 500\n# note\nabc\n1 2 3 4\n5 0")
  assert(#r == 5, "bulk entries " .. #r)
  assert(r[1].ok and r[1].need == 1 and not r[1].maxPriceCopper, "bulk id only")
  assert(r[2].ok and r[2].need == 20 and r[2].maxPriceCopper == 5000000, "bulk id target cap")
  assert(not r[3].ok and not r[4].ok and not r[5].ok, "bulk bad lines")
end

-- Row editor behavior
ADDON.debug = false
local realBreakdown = ADDON.Inventory.GetBreakdown
ADDON.Inventory.GetBreakdown = function() return { bags = 5, bank = 0, reagent = 0, warband = 0, total = 5 } end
assert(capturedInit, "row initializer not captured")
local calls = {}
ADDON.DB.SetItemMaxPrice = function(_, id, c, src) calls[#calls + 1] = { "cap", id, c, src } end
ADDON.DB.SetItem = function(_, id, n) calls[#calls + 1] = { "need", id, n } end
local emits = {}
local hookedEmit = ADDON.Log.Emit
ADDON.Log.Emit = function(_, kind, id, p) emits[#emits + 1] = kind end
local refreshes = 0
MF.Refresh = function() refreshes = refreshes + 1 end
local row = Frame(nil)
row.scripts.OnEnter = function() end
row.scripts.OnLeave = function() end
local okRow, errRow = pcall(capturedInit, row, { itemID = 42, need = 20, maxPrice = 500000, name = "Test Potion", index = 1 })
io.stdout:write("InitializeRow " .. (okRow and "OK" or ("ERR " .. tostring(errRow))) .. "\n")
assert(okRow, tostring(errRow))
for _, k in ipairs({ "capCell", "needCell", "capEdit", "needEdit", "cap", "need" }) do
  assert(row[k], "row." .. k .. " missing")
end
row.capCell.scripts.OnEnter(row.capCell); row.capCell.scripts.OnLeave(row.capCell)
row.needCell.scripts.OnEnter(row.needCell); row.needCell.scripts.OnLeave(row.needCell)
-- Cap: open prefills 50g, Enter with 75 commits 750000 copper
row.capCell.scripts.OnClick(row.capCell)
assert(row.capEdit:IsShown() and row.capEdit._text == "50", "cap prefill: " .. tostring(row.capEdit._text))
assert(row.capCell.editing == true)
row.capEdit._text = "75"
row.capEdit.scripts.OnEnterPressed(row.capEdit)
assert(#calls == 1 and calls[1][1] == "cap" and calls[1][3] == 750000, "cap commit")
assert(not row.capEdit:IsShown() and row.cap:IsShown() and refreshes == 1 and emits[#emits] == "cap_change")
-- Same value again: no DB write, no refresh
row.capCell.scripts.OnClick(row.capCell); row.capEdit.scripts.OnEnterPressed(row.capEdit)
assert(#calls == 1 and refreshes == 1, "no-op commit should not write")
-- Blank clears the cap
row.capCell.scripts.OnClick(row.capCell); row.capEdit._text = ""
row.capEdit.scripts.OnEnterPressed(row.capEdit)
assert(calls[2][1] == "cap" and calls[2][3] == nil, "blank should clear cap")
-- Need: Escape aborts
row.needCell.scripts.OnClick(row.needCell); assert(row.needEdit._text == "20")
row.needEdit._text = "99"; row.needEdit.scripts.OnEscapePressed(row.needEdit)
assert(#calls == 2 and not row.needEdit:IsShown(), "escape must not commit")
-- Need: blur commits
row.needCell.scripts.OnClick(row.needCell); row.needEdit._text = "30"
row.needEdit:ClearFocus()
assert(calls[3][1] == "need" and calls[3][3] == 30 and emits[#emits] == "target_change", "blur should commit need")
-- Opening Cap while Need is open closes Need without committing it
row.needCell.scripts.OnClick(row.needCell); row.needEdit._text = "55"
row.needEdit._focus = false -- deferred focus-lost in WoW; sibling close must not commit
row.capCell.scripts.OnClick(row.capCell)
assert(not row.needEdit:IsShown() and row.needCell.editing == false and row.capEdit:IsShown())
assert(#calls == 3, "switching editors must not commit the sibling")
-- Invalid need (0) ignored
row.needCell.scripts.OnClick(row.needCell); row.needEdit._text = "0"; row.needEdit.scripts.OnEnterPressed(row.needEdit)
assert(#calls == 3, "zero need must be ignored")
io.stdout:write("row editors OK\n")

-- Inventory: bags 3, bank 4, legacy reagent 1 (folds into bank), warband 2
C_Item = C_Item ~= Stub and C_Item or {}
C_Item.GetItemInfo = function() end
C_Item.GetItemCount = function(id, bank, _, reagent, account)
  return 3 + (bank and 4 or 0) + (reagent and 1 or 0) + (account and 2 or 0)
end
ADDON.Inventory.GetBreakdown = realBreakdown
ADDON.Inventory:Invalidate()
local bd = ADDON.Inventory:GetBreakdown(111)
assert(bd.bags == 3 and bd.bank == 5 and bd.warband == 2 and bd.reagent == nil,
  ("breakdown %d/%d/%d"):format(bd.bags, bd.bank, bd.warband))
C_Item.GetItemCount = function() return 7 end
ADDON.Inventory:Invalidate()
bd = ADDON.Inventory:GetBreakdown(111)
assert(bd.bags == 7 and bd.bank == 0 and bd.warband == 0, "fast path")
-- Shortfall count ignores order: items 111 (need 5, have 7) and 42 (need 30, have 7)
ADDON.DB.char.items[42] = ADDON.DB.char.items[42] or { need = 30, sortOrder = 20 }
ADDON.DB.char.pendingBuys = {}
assert(ADDON.RestockLoop:PreviewShortfallCount() == 1, "shortfall count")
do -- Restock run: search -> arm -> Buy (double click buys once) -> mail ledger -> done; stop ignores late results
  local L, AH, mf = ADDON.RestockLoop, ADDON.AH, ADDON.MainFrame
  local saved = { AuctionHouseFrame, AH.BuyUpTo, AH.ExecutePurchase, mf.ShowArmedToast, mf.ShowSummaryToast, mf.HideToast }
  AuctionHouseFrame = { IsShown = function() return true end }
  local search, execs, armed, summary = nil, {}, nil, nil
  AH.BuyUpTo = function(_, id, qty, cap, cb) search = { id = id, qty = qty, cb = cb } end
  AH.ExecutePurchase = function(_, id, qty, spend, cb) execs[#execs + 1] = cb end
  mf.ShowArmedToast = function(_, plan, h) armed = { plan = plan, h = h } end
  mf.ShowSummaryToast = function(_, sm) summary = sm end
  mf.HideToast = function() end
  L:Start()
  assert(search and search.id == 42 and search.qty == 23, "loop searches the short item for its shortfall")
  search.cb(true, { itemID = 42, planQuantity = 23, plannedSpend = 2300, worstUnitPrice = 100 })
  assert(armed and armed.plan.name, "loop arms the flyout")
  armed.h.onBuy(); armed.h.onBuy()
  assert(#execs == 1, "double click must buy once")
  local mark = #timers
  execs[1](true)
  assert(ADDON.DB.char.pendingBuys[42].qty == 23 and L:PreviewShortfallCount() == 0, "mail ledger counts the buy")
  for i = mark + 1, #timers do timers[i]() end
  assert(summary and summary.title:find("Restock complete") and not L:IsActive(), "run finishes")
  ADDON.DB.char.pendingBuys = {}
  armed = nil
  L:Start()
  local late = search.cb
  L:Stop("user_stop")
  late(true, { itemID = 42, planQuantity = 23, plannedSpend = 2300, worstUnitPrice = 100 })
  assert(armed == nil and not L:IsActive(), "a search finishing after Stop must not arm")
  AuctionHouseFrame, AH.BuyUpTo, AH.ExecutePurchase, mf.ShowArmedToast, mf.ShowSummaryToast, mf.HideToast = unpack(saved, 1, 6)
end
-- Item-info refresh only for our items while shown
local rf = 0
MF.Refresh = function() rf = rf + 1 end
MF.frame._shown = false; fire("GET_ITEM_INFO_RECEIVED", 42, true); assert(rf == 0, "refreshed while hidden")
MF.frame._shown = true;  fire("GET_ITEM_INFO_RECEIVED", 999, true); assert(rf == 0, "refreshed for foreign item")
fire("GET_ITEM_INFO_RECEIVED", 42, true); assert(rf == 1, "did not refresh for our item")
-- Sidecar repaints only for activity-level entries
local sc = 0
ADDON.Sidecar.Refresh = function() sc = sc + 1 end
ADDON.Sidecar.frame._shown = true
ADDON.Log.Emit = hookedEmit
ADDON.Log:Emit("status", nil, { text = "x" })
assert(sc == 0, ("status repainted the feed %d"):format(sc))
ADDON.Log:Emit("buy_success", 42, { qty = 1 })
assert(sc == 1, ("buy: feed repaints %d"):format(sc))
do -- Footer keeps the last action through redraws; the short count is on the button
  local mf = ADDON.MainFrame
  local bar = { SetText = function(self, t) self.t = t end }
  local saved, sb, cdp, gii = mf.statusBar, mf.scrollBox, CreateDataProvider, C_Item.GetItemInfo
  mf.statusBar, mf.scrollBox = bar, { SetDataProvider = function() end }
  CreateDataProvider = function() return { Insert = function() end, GetSize = function() return 1 end } end
  C_Item.GetItemInfo = gii or function() end
  mf:SetStatus("Added 12 items"); mf:_RefreshNow()
  assert(bar.t == "Added 12 items", "redraw overwrote the footer: " .. tostring(bar.t))
  assert(mf.restockBtn:GetText() == "Restock at AH (1)", "button count: " .. tostring(mf.restockBtn:GetText()))
  mf.statusBar, mf.scrollBox, CreateDataProvider, C_Item.GetItemInfo = saved, sb, cdp, gii
end
do -- Flyout, drag and dock paths run without errors (layout itself needs the game)
  local mf = ADDON.MainFrame
  local plan = { itemID = 42, planQuantity = 5, plannedSpend = 50000, name = "Test Potion", maxPrice = nil, stashBank = 2, stashWarband = 0 }
  local bought
  mf:ShowArmedToast(plan, { onBuy = function() bought = true end, onSkip = function() end, onStop = function() end })
  mf:ShowSummaryToast({ title = "Restock complete", sub = "" })
  mf:HideToast()
  local ahf = AuctionHouseFrame
  AuctionHouseFrame = { IsShown = function() return true end }
  mf:DockToAHIfOpen(); mf:Undock()
  AuctionHouseFrame = ahf
  local row = Frame(nil); row._itemID = 42
  mf:BeginRowDrag(row); mf:EndRowDrag(true)
  assert(mf:RestockState().label, "restock state")
end
do -- Bank: auto-open when set, close only what we opened, track bankOpen
  local mf = ADDON.MainFrame
  assert(ADDON.DB:Settings().autoOpenAtBank == true, "autoOpenAtBank default")
  mf.frame._shown = false
  fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
  assert(mf.frame._shown and ADDON.bankOpen, "did not auto-open at bank")
  fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
  assert(not mf.frame._shown and not ADDON.bankOpen, "did not close with bank")
  mf:Show()                                          -- user opens it by hand
  fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8); fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
  assert(mf.frame._shown, "closed a window the user opened")
  mf.frame._shown = false
  ADDON.DB:Settings().autoOpenAtBank = false
  fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
  assert(not mf.frame._shown and ADDON.bankOpen, "opened with the setting off")
  fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
  ADDON.DB:Settings().autoOpenAtBank = true
end
do -- Filter chip: shows only short items (items 111 need 5, 42 need 30; bags hold 7)
  local mf, shown = ADDON.MainFrame, nil
  local sb = mf.scrollBox
  mf.scrollBox = { SetDataProvider = function(_, p) shown = p end }
  local origCDP = CreateDataProvider
  CreateDataProvider = function() local t = { n = {} }; function t:Insert(x) self.n[#self.n + 1] = x.itemID end; function t:GetSize() return #self.n end; return t end
  local gii = C_Item.GetItemInfo; C_Item.GetItemInfo = gii or function() end
  ADDON.DB:SetStuckOnly(true); mf:_RefreshNow()
  C_Item.GetItemInfo = gii
  assert(shown and #shown.n == 1 and shown.n[1] == 42, "filter should show only the short item: " .. (shown and table.concat(shown.n, ",") or "nothing shown"))
  ADDON.DB:SetStuckOnly(false); mf.scrollBox = sb; CreateDataProvider = origCDP
end
do -- Restock from Bank planner: exact amounts, char bank first, top up stacks, bag space
  local plan, max20 = ADDON.BankRestock.PlanPulls, function() return 20 end
  local sources = { { bag = 6, slot = 1, itemID = 1, count = 10 }, { bag = 7, slot = 1, itemID = 2, count = 50 },
                    { bag = 12, slot = 1, itemID = 1, count = 30 } }
  local bags = { { bag = 0, slot = 1, itemID = 1, count = 15 }, { bag = 0, slot = 2 } }
  local m, still = plan({ { itemID = 1, short = 12 } }, sources, bags, max20)
  local got = {}
  for _, x in ipairs(m) do got[#got + 1] = ("%d.%d>%d.%d x%d%s"):format(x.fromBag, x.fromSlot, x.toBag, x.toSlot, x.count, x.whole and "w" or "") end
  got = table.concat(got, " ")
  assert(got == "6.1>0.1 x5 6.1>0.2 x5w 12.1>0.2 x2" and still == 0, "plan: " .. got)
  assert(sources[1].count == 10 and bags[2].itemID == nil, "planner mutated its inputs")
  m, still = plan({ { itemID = 1, short = 3 } }, sources, { { bag = 0, slot = 1, itemID = 1, count = 20 } }, max20)
  assert(#m == 0 and still == 1, "full bags must plan nothing")
  m, still = plan({ { itemID = 3, short = 3 } }, sources, bags, max20)
  assert(#m == 0 and still == 1, "item not in bank must plan nothing")
end
io.stdout:write("perf/inventory OK\n")
