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
C_AddOns = { GetAddOnMetadata = function() return "1.1.2" end, IsAddOnLoaded = function() return true end, LoadAddOn = function() end }
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
IsLoggedIn = function() return false end
print = function(...) end
UISpecialFrames = {}
SlashCmdList = {}
Enum = { PlayerInteractionType = { Auctioneer = 21 } }

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
assert(#ADDON.DB.global.log == 1 and ADDON.DB.char.items[111].need == 5, "saved data lost")
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
local printed
print = function(s) printed = s end
ADDON.Debug("AH", "x", 1); assert(printed == "|cff98FF98[SC:AH]|r x 1", tostring(printed))
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
local okRow, errRow = pcall(capturedInit, row, { itemID = 42, need = 20, maxPrice = 500000 })
io.stdout:write("InitializeRow " .. (okRow and "OK" or ("ERR " .. tostring(errRow))) .. "\n")
assert(okRow, tostring(errRow))
for _, k in ipairs({ "capCell", "needCell", "priceEdit", "needEdit", "priceEditBg", "needEditBg", "cap", "need" }) do
  assert(row[k], "row." .. k .. " missing")
end
row.capCell.scripts.OnEnter(row.capCell); row.capCell.scripts.OnLeave(row.capCell)
row.needCell.scripts.OnEnter(row.needCell); row.needCell.scripts.OnLeave(row.needCell)
-- Cap: open prefills 50g, Enter with 75 commits 750000 copper
row.capCell.scripts.OnClick(row.capCell)
assert(row.priceEdit:IsShown() and row.priceEdit._text == "50", "cap prefill: " .. tostring(row.priceEdit._text))
assert(row.capCell._priceEditActive == true)
row.priceEdit._text = "75"
row.priceEdit.scripts.OnEnterPressed(row.priceEdit)
assert(#calls == 1 and calls[1][1] == "cap" and calls[1][3] == 750000 and calls[1][4] == "user", "cap commit")
assert(not row.priceEdit:IsShown() and row.cap:IsShown() and refreshes == 1 and emits[#emits] == "cap_change")
-- Same value again: no DB write, no refresh
row.capCell.scripts.OnClick(row.capCell); row.priceEdit.scripts.OnEnterPressed(row.priceEdit)
assert(#calls == 1 and refreshes == 1, "no-op commit should not write")
-- Blank clears the cap
row.capCell.scripts.OnClick(row.capCell); row.priceEdit._text = ""
row.priceEdit.scripts.OnEnterPressed(row.priceEdit)
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
assert(not row.needEdit:IsShown() and row.needCell._needEditActive == false and row.priceEdit:IsShown())
assert(#calls == 3, "switching editors must not commit the sibling")
-- Invalid need (0) ignored
row.needCell.scripts.OnClick(row.needCell); row.needEdit._text = "0"; row.needEdit.scripts.OnEnterPressed(row.needEdit)
assert(#calls == 3, "zero need must be ignored")
io.stdout:write("row editors OK\n")

-- Inventory: bags 3, bank 4, legacy reagent 1 (folds into bank), warband 2
C_Item = C_Item ~= Stub and C_Item or {}
C_Item.GetItemCount = function(id, bank, _, reagent, account)
  return 3 + (bank and 4 or 0) + (reagent and 1 or 0) + (account and 2 or 0)
end
ADDON.Inventory.GetBreakdown = realBreakdown
ADDON.Inventory:Invalidate()
local bd = ADDON.Inventory:GetBreakdown(111)
assert(bd.bags == 3 and bd.bank == 5 and bd.warband == 2 and bd.total == 10 and bd.reagent == nil,
  ("breakdown %d/%d/%d/%d"):format(bd.bags, bd.bank, bd.warband, bd.total))
C_Item.GetItemCount = function() return 7 end
ADDON.Inventory:Invalidate()
bd = ADDON.Inventory:GetBreakdown(111)
assert(bd.bags == 7 and bd.bank == 0 and bd.warband == 0, "fast path")
-- Shortfall count ignores order: items 111 (need 5, have 7) and 42 (need 30, have 7)
ADDON.DB.char.items[42] = ADDON.DB.char.items[42] or { need = 30, sortOrder = 20 }
ADDON.DB.char.pendingBuys = {}
assert(ADDON.RestockLoop:PreviewShortfallCount() == 1, "shortfall count")
-- Item-info refresh only for our items while shown
local rf = 0
MF.Refresh = function() rf = rf + 1 end
MF.frame._shown = false; fire("GET_ITEM_INFO_RECEIVED", 42, true); assert(rf == 0, "refreshed while hidden")
MF.frame._shown = true;  fire("GET_ITEM_INFO_RECEIVED", 999, true); assert(rf == 0, "refreshed for foreign item")
fire("GET_ITEM_INFO_RECEIVED", 42, true); assert(rf == 1, "did not refresh for our item")
-- Sidecar repaints only for feed kinds; LogPopup once per emit
local sc, lp = 0, 0
ADDON.Sidecar.Refresh = function() sc = sc + 1 end
ADDON.LogPopup.Refresh = function() lp = lp + 1 end
ADDON.Sidecar.frame._shown = true
if ADDON.LogPopup.frame then ADDON.LogPopup.frame._shown = true end
ADDON.Log.Emit = hookedEmit
ADDON.Log:Emit("status", nil, { text = "x" })
assert(sc == 0 and lp == 1, ("status: sidecar %d, logpopup %d"):format(sc, lp))
ADDON.Log:Emit("buy_success", 42, { qty = 1 })
assert(sc == 1 and lp == 2, ("buy: sidecar %d, logpopup %d"):format(sc, lp))
io.stdout:write("perf/inventory OK\n")
