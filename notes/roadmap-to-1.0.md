# Stock Clerk — Roadmap to 1.0

Locked scope for the remaining pre-1.0 releases. v0.7.0 landed
tonight and, in the user's words, "*felt* like a 1.0." The rest of
the path is repo hygiene and documentation, not new features.

## Standing design principle

**Stock Clerk arbitrates only its own affordances.** We defer to the
user's WoW / UI / addon choices for anything outside our own
controls. Kill switches default to preserving the user's existing
setup rather than overriding it.

## v0.7.1 — Bugfix contingency (as needed)

Reserved for hotfixes to anything preview17 didn't smoke-test. Not
tagged in advance. Zero budget unless triggered.

Likely triggers:
- Refresh coalescing edge case (a call site depending on sync refresh)
- Uncapped-item flow regression from BuyDialog removal
- Debug memoization false-negative (state transition doesn't log)

## v0.8.0 — Cleanup pass

Not a feature release. Goal: get the dirty laundry out of the
public repo, tighten what ships in the packaged zip, and reduce the
"shows a lot of churn" surface a new user sees when browsing.

| Item | Note |
|---|---|
| Move `notes/` out of the public repo | Roadmap, sweep docs, alpha checklists, session artifacts. Options: local-only (`.gitignore` + leave on disk), separate private repo, or GitHub Wiki. Whatever the choice, they stop being browsable on the public GitHub project. |
| Strip in-code scar comments | `v0.7.0-alpha5 PILL-KILL`, `RING-NUKE`, `TOOLTIP-SIMPLIFY`, `SIBLING-EDITOR-FIX`, `QUALITY-BORDER`, `BORDER-BLINK-FIX`, `LOG-ESCAPE-FIX`, and similar version-tagged breadcrumbs. Keep the code they annotate; drop the alpha-era markers. Diff will look larger than the actual behavior change. |
| Collapse CHANGELOG pre-1.0 history | Trim the per-alpha entries below the v0.7.0 divider down to a one-paragraph "development history: v0.7.0 consolidated seventeen preview builds across five alphas; see git history for details" or delete outright. |
| **One open core-feature slot** | Undefined; reserved for something you notice missing during dogfooding of v0.7.x. Not committing to fill it. If nothing surfaces, the slot stays empty and v0.8 is pure cleanup. |
| Ship the cleanup as v0.8.0 | Not v0.7.2 — a cleanup pass of this scope deserves its own minor. |

**Optional additions to consider:**
- `.pkgmeta` audit: what else is in the tracked tree that shouldn't
  ship in the zip? (Currently ignored: `README.md`, `Dev/`,
  `notes/`, `.assets`, `.github`, `.gitignore`, `.gitattributes`,
  `.pkgmeta`. Anything else?)
- README slim-down: remove anything that reads like a dev diary.
  README should be for users, not agents or future maintainers.

## v1.0.0 — Launch prep

Docs and store page. No new code.

| Item | Note |
|---|---|
| CurseForge page: description, feature list, tags, screenshots | Draft in `notes/sweep-2026-09-20/curseforge-description.md`; still needs screenshots. |
| GitHub README polish | Users, not devs. Install instructions, feature list, screenshots. |
| Hero screenshot + caption | You take, I write copy. |
| Final CHANGELOG for 1.0 | Short entry: "First stable release." Point at v0.7.0 for the substance. |
| Version bump `v0.8.x` → `v1.0.0`, mechanical | Tag + release. |

## Post-1.0 backlog (parked; ship only on organic demand)

Everything that was in the pre-1.0 roadmap and is not on the list
above got moved here. Do not build unless a real user asks.

- **Tooltip overhaul** (Baganator-style anchor helper). The current
  tooltip behavior works.
- **Hints kill switch.** No user has asked for one. Ship if asked.
- **Have-column breakdown tooltip.** The dim `(+N)` annotation on
  Have already conveys the information without a tooltip.
- **Recent Activity panel polish.** Current sidecar log is functional.
- **Sound feedback system.** Vanity; users mute or ignore.
- **Localization.** ~$80+ scope; wait for a translation contributor.
- **WoW Classic support.** ~$200+ (Classic AH API differs). Retail
  Midnight is the target.
- **Per-item historical price sparklines.** Requires a price-history
  schema and rendering layer. Nice-to-have, not core.
- **Cross-character shopping list sharing / account-wide view.**
  Large SavedVariables schema change; wait for demand.

## Discipline lessons from v0.7.0 (self-imposed, going forward)

The v0.7 track spent significantly more than its original alpha5
budget of ~$56 because scope grew mid-track. Rules adopted so v0.8
doesn't repeat that:

- **Feature freeze on v0.8.** The core-feature slot is *one* slot,
  and only fills if a genuine gap surfaces. Everything else parks.
- **Multi-source-of-truth is the #1 budget killer.** BuyDialog +
  armed-flyout, three shortfall calcs, the MoneyText fallback
  pattern — each cost 1–3 preview builds. Refactor before writing
  a second function that computes the same thing.
- **Debug prints memoize from day one.** No "log every row every
  refresh" patterns.
- **Comment coordinates lie.** Any comment with a hard-coded
  offset (`-178`, `-128`) is a magic number and drifts. Refresh
  when the coordinate moves, or drop the coordinate.
- **Batch feedback into single implementation passes.** No mid-
  implementation "one more thing."
- **Prefer targeted `edit` calls** over full-file rewrites of
  large files (MainFrame.lua is 3500 lines).
- **Trust the client.** Skip verification screenshots the agent
  can predict.
- **Confirm before pushing tagged releases.** Public, hard to
  retract. Confirmation catches "wait, one more thing."
