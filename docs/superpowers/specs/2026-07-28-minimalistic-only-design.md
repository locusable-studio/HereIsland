# Atoll Minimalistic-Only Cleanup — Design Spec

**Date:** 2026-07-28  
**Status:** Approved (user: approach 1 + scope A/A/B; “全部通过，不要再问”)

## Goal

Strip Atoll down to a always-on Minimalistic product: notch media player + core system HUDs. Physically delete standard-mode and adjacent feature domains. No Minimalistic UI toggle.

## Product Scope

### Keep

- Notch shell: open/close, hover/gesture open-close, minimalistic sizing/corners/shadow
- `MinimalisticMusicPlayerView` (+ optional battery indicator on that surface)
- All existing media controllers (Apple Music, Spotify, YouTube Music, Now Playing, etc.) and `MusicManager`
- Core system HUD / sneak peek: volume, brightness, keyboard backlight, battery
- App shell: menu bar, launch-at-login, slim permissions onboarding, Sparkle updates
- Minimal settings: General (no mode toggle), Media (sources/auth), Permissions-related, Updates; slim Appearance only if needed for media visuals still used by minimalistic player

### Delete (whole domains)

- Standard multi-tab home, calendar-in-notch, webcam, mirror
- Shelf, Notes, Terminal, Stats, Clipboard, Color Picker, Screen Assistant, Timer UI, Downloads live activities (non-media)
- Lock Screen stack (widgets, panels, managers)
- Extensions (AtollExtensionKit usage, RPC/XPC, extension settings, minimalistic overrides)
- Non-core live activities / HUDs: Bluetooth audio HUD, privacy, recording, Focus, CapsLock (unless later reinstated)
- Multi-profile onboarding → replace with single slim welcome/permissions if still required
- `enableMinimalisticUI` flag and all standard-mode branches

### Non-goals

- No rename of product / Bundle ID unless requested later
- No media protocol rewrite
- No new features

## Architecture After Cleanup

```
App (@main + AppDelegate)
  ├─ MenuBarExtra + Settings (slim)
  ├─ Notch window → always MinimalisticMusicPlayerView
  ├─ MusicManager + MediaControllers
  └─ System HUD managers (volume / brightness / backlight / battery sneak peek)
```

- Hardcode minimalistic layout sizes (remove `if enableMinimalisticUI` forks; delete standard sizing paths)
- Coordinator retains only sneak-peek types needed for kept HUDs + music
- Defaults keys for deleted features removed or left inert only if migration cost is high; prefer delete unused keys when touch sites are cleared

## Settings Surface

| Tab | Action |
|-----|--------|
| General | Keep slim (launch, displays, gestures for open/close, haptics). Remove UI Mode / Minimalistic toggles |
| Media | Keep media source + Spotify/YTM auth as needed |
| Updates | Keep Sparkle channel + check |
| Permissions / related | Keep only what media + HUD need |
| Appearance | Keep only knobs still used by minimalistic player (or fold into General); delete notch-width/standard-only |
| Timer, Stats, Clipboard, Screen Assistant, Color Picker, Shelf, Notes, Terminal, Lock Screen, Extensions, Battery extras beyond indicator | Delete |

## Deletion Inventory (directories / areas)

**components/** remove or gut: `Stats`, `Shelf`, `Clipboard`, `ColorPicker`, `ScreenAssistant`, `Timer`, `LockScreen`, `Extensions`, `Downloads`, `Focus`, `Privacy`, `Recording`, `Webcam`, `Calendar` (notch), standard `Music` player views not used by minimalistic, multi-tab chrome as needed.

**managers/** remove: LockScreen*, Extension*, Clipboard*, ColorPicker*, Stats*, Terminal*, Timer*, ScreenAssistant*, Download*, Privacy*, BluetoothAudio*, Webcam*, CapsLock*, DoNotDisturb*, Reminder*, Calendar*, LLMUsage*, LocalSend*, etc. Keep: Music*, SystemVolume*, System* brightness/backlight/HUD related, MacBattery*/Battery*, MediaKey*, SpotifyAuth*, notch window managers required for shell.

**services/Extensions/**, extension SPM dependency `AtollExtensionKit`: remove when no references remain.

**Onboarding:** collapse to slim path; delete profile matrix that toggles features.

## Verification

- `xcodebuild` (or Xcode) build of main app target succeeds
- App launches: notch opens to minimalistic music UI; volume/brightness HUD still work
- Settings opens without missing tabs/crash
- No link errors for deleted symbols; Package.resolved drops unused deps when cleaned

## Risks

- `DynamicIsland.xcodeproj/project.pbxproj` must drop file refs or build breaks
- AppDelegate / DynamicIslandApp bootstrap has many manager side-effects — strip carefully
- Shared helpers used by both kept and deleted features need retention audit before folder deletes
- LFS media for Bluetooth HUD may become unused; safe to leave assets or delete with HUD

## Spec Self-Review

- No TBD placeholders for scope decisions
- Keep/delete lists match user choices A (product) / A (settings) / B (all media backends) / approach 1
- Bluetooth/privacy/recording/Focus/CapsLock explicitly out of scope per approved section 1
- Implementation must not reintroduce `enableMinimalisticUI` toggle
