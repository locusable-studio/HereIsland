# CLAUDE.md

## Git

### Commit: bump build number

Before every code commit, increment `CURRENT_PROJECT_VERSION` (build number) by 1.

- Location: `HereIsland.xcodeproj/project.pbxproj`
- Bump both Debug and Release values in sync
- Include the build number change in the same commit as the functional changes

### Marketing version: three-part CalVer only

`MARKETING_VERSION` in `HereIsland.xcodeproj/project.pbxproj` is always `YYYY.M.D` (no zero-padding, no hotfix suffix).

- Example: `2026.8.25`
- Never `2026.8.25.1` or any other four-part string
- Bump this in the project only when the calendar day of the product version changes (both Debug and Release, in sync)

### Tag / release

Git tags are `vYYYY.M.D`. Same-day hotfixes append `.N` **on the tag only**.

- First ship of the day: `v2026.8.25`
- Same-day hotfix: `v2026.8.25.1`, then `.2`, …
- Do **not** copy that `.N` into `MARKETING_VERSION`
- Creating a `v*` tag does **not** require changing `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` just to “match” the tag
- Pushing a `v*` tag runs Release CI (it may stamp the tag string into the archive; the project file on `main` still stays three-part)

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
