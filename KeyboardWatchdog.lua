-- ---------------------------------------------------------------------------
-- KeyboardWatchdog.lua                                                 v0.6.1
--
-- Belt-and-suspenders diagnostic for the "addon ate my keyboard" bug class.
-- Every 1s while StockClerkFrame is shown, sample two things:
--
--   1) GetCurrentKeyBoardFocus() -- if it returns an EditBox that belongs to
--      StockClerk AND that EditBox is NOT :IsVisible(), the addon has a
--      hidden focused field that will silently swallow keystrokes.
--
--   2) StockClerkFrame's SetPropagateKeyboardInput sticky state -- WoW
--      doesn't expose a getter, so we track it indirectly: if we set
--      propagate=true in the last emit-cycle but a subsequent OnKeyDown
--      returned early without re-arming it, we can spot the leak by
--      checking that a "dead-man" test key routes through normally.
--      (In practice we can only detect case (1) at runtime; case (2) is
--      diagnosed post-mortem from the emit sequence in /clerk log.)
--
-- When a suspicious state is detected, emits a `kbd_stuck` log entry with a
-- short reason string. The tester can `/clerk log`, copy the resulting text,
-- and paste it into the issue -- turning "keyboard just stopped working"
-- into "at 14:32:07 my needEdit for Rousing Fire was focused and hidden."
--
-- This does NOT try to auto-fix. The v0.6.1 code changes are the fix; this
-- module only observes and reports. Auto-fixing here would mask whether the
-- primary defenses are actually holding.
-- ---------------------------------------------------------------------------

local ADDON_NAME, ADDON = ...

local Watchdog = {}
ADDON.KeyboardWatchdog = Watchdog

-- Sampling cadence. 1s is fine: the bug traps input for seconds-to-minutes,
-- not sub-second bursts, and a slower tick keeps the module invisible in
-- WoW's per-frame profiler.
local SAMPLE_INTERVAL = 1.0

-- Deduplication: don't spam the log with the same finding every second while
-- the state persists. Only emit again after this many seconds of continuous
-- suspicious state, and only re-emit the SAME reason after this cooldown.
local DEDUP_COOLDOWN = 10.0

local _ticker
local _lastEmit = {}   -- reason -> last-emit timestamp

-- Best-effort detection of "this frame belongs to StockClerk". EditBoxes
-- created by StockClerk are all anonymous (CreateFrame("EditBox", nil, ...))
-- so we can't match on frame name. Walk the parent chain looking for
-- StockClerkFrame instead. If we hit the top without finding it, treat as
-- "not ours" and don't emit -- another addon's leak isn't our problem.
local function OwnedByStockClerk(frame)
    if not frame or not frame.GetParent then return false end
    local root = _G.StockClerkFrame
    if not root then return false end
    local cur = frame
    for _ = 1, 20 do
        if cur == root then return true end
        if not cur.GetParent then return false end
        cur = cur:GetParent()
        if not cur then return false end
    end
    return false
end

local function Emit(reason, detail)
    local now = GetTime and GetTime() or 0
    local prev = _lastEmit[reason]
    if prev and (now - prev) < DEDUP_COOLDOWN then return end
    _lastEmit[reason] = now
    if ADDON.Log and ADDON.Log.Emit then
        ADDON.Log:Emit("kbd_stuck", nil, { reason = reason, detail = detail })
    end
end

local function Sample()
    -- Only run while our window is shown -- when it's closed the addon
    -- should not be holding keyboard state anyway, and other addons'
    -- focus states are none of our business.
    local root = _G.StockClerkFrame
    if not root or not root:IsShown() then return end

    -- Case 1: hidden focused EditBox that belongs to us.
    local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focused and OwnedByStockClerk(focused) then
        if focused.IsVisible and not focused:IsVisible() then
            -- Try to identify which editbox -- helps triage. Anonymous
            -- frames don't have names, but we can report their debug
            -- string if the API is available.
            local kind = "unknown"
            if focused.GetDebugName then
                local dbg = focused:GetDebugName()
                if dbg and dbg ~= "" then kind = dbg end
            end
            Emit("hidden_focused_editbox",
                ("EditBox %s owned by StockClerk has focus but is not visible -- keystrokes are being captured silently"):format(kind))
        end
    end

    -- Case 2: Add button focus flag desync. MF._addBtnFocused should only
    -- be true while the Add button visibly has the ring. If the addon
    -- window is hidden but the flag is still true, we leaked focus state.
    local MF = ADDON.MainFrame
    if MF and MF._addBtnFocused and not root:IsShown() then
        Emit("addbtn_focused_while_hidden",
            "Add button focus flag is true but StockClerkFrame is hidden -- EnableKeyboard(true) may be stuck on")
    end
end

function Watchdog:Start()
    if _ticker then return end
    if not C_Timer or not C_Timer.NewTicker then return end
    _ticker = C_Timer.NewTicker(SAMPLE_INTERVAL, Sample)
end

function Watchdog:Stop()
    if _ticker then
        _ticker:Cancel()
        _ticker = nil
    end
end

-- Auto-start on PLAYER_LOGIN so we're sampling by the time the user opens
-- any StockClerk window. Failing to start (missing C_Timer, missing Log)
-- is silent -- diagnostic modules must never break the addon itself.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        Watchdog:Start()
    end)
end
