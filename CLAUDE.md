# CLAUDE.md

## Git

### Commit: bump build number

Before every code commit, increment `CURRENT_PROJECT_VERSION` (build number) by 1.

- Location: `HereIsland.xcodeproj/project.pbxproj`
- Bump both Debug and Release values in sync
- Include the build number change in the same commit as the functional changes

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
- Up to 3 user-facing points for this release

## Changes
- Concrete changes, ordered by importance (not by commit type)
- Prefer product language over conventional-commit subjects

## Notes
- Optional: upgrade caveats, permissions, system requirements, feed URL
```

### Rules

- Keep it short; one screen is enough
- No download-link sections (GitHub Assets already list DMGs)
- Prefer editing the Release body after CI creates the tag if auto-generated notes are too thin
- Sparkle feed (stable): `https://raw.githubusercontent.com/locusable-studio/HereIsland/main/Updates/appcast.xml`
