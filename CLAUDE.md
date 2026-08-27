# CLAUDE.md

## Git

### Commit: bump build number

Before every code commit, increment `CURRENT_PROJECT_VERSION` (build number) by 1.

- Location: `HereIsland.xcodeproj/project.pbxproj`
- Bump both Debug and Release values in sync
- Include the build number change in the same commit as the functional changes

### Marketing version

`MARKETING_VERSION` in `HereIsland.xcodeproj/project.pbxproj` is CalVer `YYYY.M.D` with an optional same-day `.N`. No zero-padding.

- First ship of the day on `main`: `2026.8.27`
- Same-day hotfix on `main`: `2026.8.27.1`
- Do not write a `-beta.M` suffix into the project file
- Release CI stamps the archive from the tag (`agvtool` gets the tag with `-beta.M` stripped). `main` does not need to match a beta tag

### Tag / release

Git tags are `vYYYY.M.D` or `vYYYY.M.D.N`. Beta tags append `-beta.M`.

- Stable first ship of the day: `v2026.8.27`
- Stable same-day hotfix: `v2026.8.27.1`
- Beta: `v2026.8.27-beta.1` or `v2026.8.27.1-beta.1`
- Pushing a `v*` tag runs Release CI. Tags containing `-beta.` are prereleases
- Creating a tag does **not** require changing `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` on `main` just to “match” the tag
- `sparkle:version` is a single monotonic integer shared by both channels

### Update channels

- Menu Extra → Updates → Channel: Stable (default) or Beta
- Stable feed: `https://raw.githubusercontent.com/locusable-studio/HereIsland/main/Updates/appcast.xml`
- Beta feed: `https://raw.githubusercontent.com/locusable-studio/HereIsland/main/Updates/appcast-beta.xml`
- Stable Release CI writes both feeds (so Beta users can graduate). Beta CI writes only the beta feed
- Stable `generate_appcast` previous DMGs skip drafts and GitHub prereleases
- The beta feed has no Sparkle deltas, including stable items copied into it
- Beta releases must not update `/releases/latest`, `HereIsland.dmg`, or the Homebrew tap
- Switching Beta → Stable does not downgrade; wait for a higher `sparkle:version` on the stable feed

## Release notes

GitHub Release title and body follow this convention. Write for users, not for commit history.

### Scope

- Each release covers changes **since the previous `v*` tag** (e.g. `v2026.7.28` → next tag).
- Do not restate older releases. Exception: the first public release may summarize the full fork delta from Atoll when there is no prior Here Island tag.

### Title

```text
Here Island <MARKETING_VERSION>
```

Optional theme suffix when useful: `Here Island 2026.8.1 — …`

### Body

```markdown
## Highlights
- Up to 3 user-facing points for this release @github-username

## Changes
- Concrete changes, ordered by importance (not by commit type) @github-username
- Prefer product language over conventional-commit subjects @github-username

## Notes
- Optional: upgrade caveats, permissions, system requirements, feed URL
```

### Rules

- CI creates the Release with **title only** (empty body); fill in Highlights / Changes / Notes manually after the tag ships
- End every Highlights / Changes bullet with the commit author's GitHub `@username` (resolves from the commit author email → GitHub account). That drives the Release page Contributors avatar list.
- Keep it short; one screen is enough
- No download-link sections (GitHub Assets already list DMGs)
- Sparkle feed (stable): `https://raw.githubusercontent.com/locusable-studio/HereIsland/main/Updates/appcast.xml`
- Sparkle feed (beta): `https://raw.githubusercontent.com/locusable-studio/HereIsland/main/Updates/appcast-beta.xml`
- Release title uses the full tag without `v` (e.g. `Here Island 2026.8.27-beta.1`)
