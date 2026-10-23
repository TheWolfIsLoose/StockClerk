# StockClerk — Releasing

Dev-only (`Dev/` never ships).

Releases are cut by CI from the `## vX.Y.Z` heading in
[CHANGELOG.md](../CHANGELOG.md), which holds only the release being cut
(short, player-facing bullets). Detailed notes for every version,
including this one, go in [HISTORY.md](HISTORY.md). Planned work lives in [ROADMAP.md](ROADMAP.md).

**Policy (2026-09-28, after v1.3.0):** work lands on `dev` and is tested
internally (Claude installs the changed files straight into the game, the
player plays and `/reload`s, Claude reads the log). `CHANGELOG.md` keeps the last stable heading meanwhile, so
`dev` pushes publish nothing. Public prereleases only for a big new feature
or a significant redesign. Otherwise the next public build is a stable
tag.

**Cadence (2026-10-13, all of the player's addons):** feature releases go
out every Tuesday at 9 AM ET (from 2026-10-20), bundling whatever
is tested on `dev`; the "Addon releases" scheduled task cuts them and skips
any addon with nothing new. Hotfixes still ship as soon as they're needed.
Why: fewer update prompts for players, less Claude usage per release.
**Patch days** (a Retail patch goes live, or the live interface number is
above our TOCs) move that Tuesday's release to ~5 PM ET, whether or not it's
a release week: the 9 AM run only tells the player to fitness-test, and the
"Patch day addon releases" task ships the TOC bump plus any fixes landed on
`dev` that day. The day matters more than the time.

- Push to `dev` with a new `-alphaN` / `-betaN` version heading to
  publish a prerelease (CurseForge Alpha/Beta).
- Merge to `main` with a new stable `vX.Y.Z` heading to publish a release.

The workflow tags the commit, packages it and creates the GitHub
release, which CurseForge picks up. Don't create releases by hand.
Testers pull alpha / beta builds from Git. Before pushing, run the smoke test: `lua5.1 Dev/smoke.lua .`

## Patch day: Retail TOC bump

Every Retail patch, check the live interface number and bump `## Interface`
in the TOC if it changed (keep older numbers in a comma list only where the
addon still supports them; Tones also lists Classic flavors).

Cross-reference at least two of:
- Warcraft Wiki, Public client builds (Interface column):
  https://warcraft.wiki.gg/wiki/Public_client_builds
- Blizzard's UI source mirror, `live` branch (the latest commit message names
  the patch, e.g. "12.1.0 (69933)" = 120100):
  https://github.com/Gethe/wow-ui-source/tree/live
- In game: `/dump select(4, GetBuildInfo())`

A TOC-only bump is a patch release (vX.Y.Z+1) with a one-line CHANGELOG
("Up to date for patch 12.x.y."). Last checked: 2026-10-13, 12.1.5 = 120105.
