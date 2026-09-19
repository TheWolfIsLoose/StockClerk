# Stock Clerk — Roadmap to 1.0

Locked scope for the remaining pre-1.0 releases. Anything not on this
list is deferred to post-1.0. See "Post-1.0 backlog" at the bottom.

## Standing design principle

**Stock Clerk arbitrates only its own affordances.** We defer to the
user's WoW / UI / addon choices for anything outside our own
controls. Kill switches default to preserving the user's existing
setup rather than overriding it. Item tooltips render as the user's
tooltip stack dictates (Blizzard default, TipTac, ElvUI, etc.); we
only control anchor position and when we open them.

## v0.7.0-alpha5 (next release)

Big-drop release. Fixes the alpha4 regressions plus a batch of small
UX polish. Total budget: ~$56.

| # | Item | Cost | Category |
|---|---|---|---|
| 1 | Escape → Sidecar cascade fix | $3 | Bug |
| 2 | Tab nav rewrite (three-stop-per-row) + kill grey wash | $20 | Bug + UX |
| 3 | `vv0.7.0-alpha4` double-`v` header | $2 | Bug |
| 4 | Restock button stuck on "Stop restock" | $5 | Bug |
| 5 | Kill shift-click gestures + rewrite hint text | $5 | Simplification |
| 6 | Cap column: red text when `seen > cap` (inclusive) | $5 | UX |
| 7 | Tooltip hit-target fix (MVP — cover the whole input, not the border) | $8 | Bug |
| 10 | Quality frame overlay on item icons | $8 | UX |

**Cut from alpha5, deferred to v0.8:** full tooltip overhaul, hints
kill switch.

**Cut from 1.0 entirely, moved to post-1.0 backlog:** sound feedback
system.

## v0.8.0

Polish release. Total budget: ~$75.

| Item | Cost | Note |
|---|---|---|
| Tooltip overhaul (Baganator anchor: BR corner at TL corner of hovered element, screen-edge fallbacks, central helper) | $25 | Foundation for future tooltip work |
| Hints kill switch (Sidecar UI + wiring through the tooltip helper) | $10 | `settings.showHints` boolean, defaults `true` |
| Have-tooltip breakdown (bag / bank / warbank counts on hover) | $25 | Deferred from alpha4 |
| Recent Activity panel polish | $15 | Layout, spacing, entry legibility |

## 1.0.0 launch prep

Documentation and store-page work. Total budget: ~$31.

| Item | Cost | Note |
|---|---|---|
| CurseForge page: description, feature list, tags, screenshots | $10 | Sells the addon |
| GitHub README polish | $8 | Install instructions, feature list, screenshots |
| Hero screenshot + caption | $2 | You take, I write copy |
| Final changelog reconciliation for 1.0 | $8 | Coherent narrative across all pre-1.0 work |
| Version bump `v0.8.x` → `v1.0.0`, mechanical | $3 | Tag + release |

## Post-1.0 backlog (parked, revisit only if organic demand)

- **Sound feedback system.** Vanity feature; users will ignore or
  mute. Not shipping in the 1.0 window.
- **Localization.** ~$80+ scope; benefits few users at launch.
  Revisit after 1.0 if translation contributors surface.
- **WoW Classic support.** ~$200+ (Classic AH API is different).
  Revisit only if there's demand.
- **Per-event sound toggles in Sidecar UI.** Depends on sound
  feedback system existing.

## Spend estimate

| Milestone | Cost |
|---|---|
| Alpha5 | ~$56 |
| Alpha6 / beta (contingency for bugs found in testing) | ~$20–30 |
| v0.8.0 | ~$75 |
| 1.0.0 launch prep | ~$31 |
| **Total remaining to 1.0** | **~$180–200** |

Sunk cost to date: ~$300. Remaining is well under that — the biggest
cost is behind us, not ahead.

## Working discipline (adopted for the rest of pre-1.0)

- Batch feedback into single implementation passes. No mid-implementation
  "one more thing."
- Prefer targeted `edit` calls over full-file rewrites when changing
  MainFrame.lua.
- Skip verification screenshots the agent can predict. Trust the
  client.
- Punch list lives in one persistent place (see chat for current
  choice — GitHub issue, workspace file, etc.); no more per-alpha
  checklist files.
- Agent flags any request estimated over ~$15 with an explicit cost
  note before implementing.
- Agent pushes back on out-of-scope requests using the cost estimate
  as the shared metric.
