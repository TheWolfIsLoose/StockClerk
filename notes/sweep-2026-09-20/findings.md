# 0.7 Housekeeping Sweep — Pre-Sweep Findings

Captured before the sweep begins so nothing is lost.

## Confirmed multi-source-of-truth / redundancies

### 1. BuyDialog modal vs Armed-Flyout confirmation (CRITICAL)
- **Symptom:** In preview16, an uncapped item triggered the legacy `UI/BuyDialog.lua` "no cap set / Buy anyway / Skip / Stop loop" modal, while the newer flyout armed-toast is the intended confirmation path.
- **Two code paths for the same decision:** cap-aware Buy confirmation.
- **Files:** `UI/BuyDialog.lua`, `RestockLoop.lua` (whichever branch calls BuyDialog:Show for no-cap), `UI/MainFrame.lua` (ShowArmedToast).
- **Resolution:** Consolidate to armed-flyout. Delete or gut BuyDialog.
- **Related:** Any StaticPopup registrations for "confirm buy" should also go.

### 2. Shortfall computation (already partially fixed in preview15, verify no stragglers)
- Was: Core.lua auto-restock, MainFrame Refresh button state, MainFrame status footer, and Loop:BuildQueue all computed shortfall independently.
- Now: `Loop:PreviewShortfallCount()` is single source. Verified by debug log — bags and effHave agree.
- **Sweep task:** grep for any remaining `INV:GetCount` sites that make a "should we restock" decision (as opposed to display). Those should route through PreviewShortfallCount.

### 3. Money-formatting fallback pattern
- Every call site currently reads: `(ADDON.MoneyText and ADDON.MoneyText(x) or GetCoinTextureString(x))`
- **Sweep task:** MoneyText is a hard dependency at this point; drop the `or GetCoinTextureString` fallbacks. Or move the fallback INSIDE MoneyText itself so callers just call `ADDON.MoneyText(x)`.

### 4. Refresh() call churn (from debug log)
- `MainFrame:Refresh()` fires multiple times back-to-back on many events.
- **Symptom:** Debug log shows the full 6-row `InitializeRow` dump 3+ times per user action.
- **Cost:** Not functional but wasteful. Also amplifies preview-log spam.
- **Sweep task:** Add refresh coalescing (schedule a next-frame refresh, cancel duplicates) OR audit callers to remove redundant triggers.

### 5. PreviewShortfallCount debug logging is too chatty
- Every call logs every short item, and the function is called 3+ times per refresh (button state, status footer, auto-restock check).
- **Sweep task:** Log only when the OUTCOME changes, or throttle to once per second, or only log from the auto-restock entrypoint.

## Column layout scars to clean
- The `-178 / -128 / -95 / -30` → `-212 / -160 / -100 / -30` migration left multiple comments referring to old coordinates in MainFrame.lua BuildRow header. Old comments (e.g. lines ~508-513 in the "v0.7 column pixel positions" block) still say `Have -178 / Need -128 / Cap -72 / LastSeen -30`.
- **Sweep task:** Refresh the block comments to reflect current -212 / -160 / -100 / -30 layout.

## Naming / version drift
- Files reference "v0.7", "v0.7-dev", "alpha5" in comments. Some talk about "v0.6", "v0.7 tightened right inset". Legacy signposts.
- **Sweep task:** Normalize inline version citations OR strip them (a git blame is more authoritative than a "v0.7 tightened" comment).

## Dead code / handler orphans to hunt
- **Sweep task:** grep for functions defined but never called, event registrations with no handler body, `--TODO` / `--XXX` / `--FIXME` markers.

## Positive confirmations (from testing tonight)
- Phantom-restock fix holds under stress (multi-item, mail-looted, ledger-stale scenarios)
- Accounting-column alignment renders correctly
- Currency letters render everywhere the eye can see
- 1px seam between frame and toast reads cleanly
- Ellipsis truncation on long item names works
- Summary toast fits single- and multi-item cases without overflow
- Close(Ns) countdown ticks correctly

## Roadmap to 1.0 (to be fleshed out at sweep start)
- [ ] BuyDialog consolidation (sweep task 1)
- [ ] Refresh coalescing (sweep task 4)
- [ ] Debug log de-noise (sweep task 5)
- [ ] Money-format simplification (sweep task 3)
- [ ] Comment refresh (sweep task, column scars)
- [ ] Dead-code sweep
- [ ] Then feature-freeze v0.7 for release; 1.0 targets AFTER 0.7 ships
