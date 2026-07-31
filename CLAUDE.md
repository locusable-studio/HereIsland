# CLAUDE.md

## Git

### Commit: bump build number

Before every code commit, increment `CURRENT_PROJECT_VERSION` (build number) by 1.

- Location: `HereIsland.xcodeproj/project.pbxproj`
- Bump both Debug and Release values in sync
- Include the build number change in the same commit as the functional changes
