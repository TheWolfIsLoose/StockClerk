# Stock Clerk — Releasing

Dev-only (`Dev/` never ships).

Releases are cut by CI from the `## vX.Y.Z` heading in
[CHANGELOG.md](../CHANGELOG.md), which holds only the release being cut
(short, player-facing bullets). Detailed notes for every version,
including this one, go in [HISTORY.md](HISTORY.md). Planned work lives in [ROADMAP.md](ROADMAP.md).

- Push to `dev` with a new `-alphaN` / `-betaN` version heading to
  publish a prerelease (CurseForge Alpha/Beta).
- Merge to `main` with a new stable `vX.Y.Z` heading to publish a release.

The workflow tags the commit, packages it and creates the GitHub
release, which CurseForge picks up. Don't create releases by hand.
Testers can track a branch with `Dev/update.bat` (`update.bat dev` for
alphas). Before pushing, run the smoke test: `lua5.1 Dev/smoke.lua .`
