# Minimalistic-Only Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Physically strip Atoll to always-on Minimalistic notch media + core system HUDs; remove all other feature domains and the Minimalistic toggle.

**Architecture:** Delete unused component/manager/service trees; hardcode minimalistic notch path; slim AppDelegate bootstrap and Settings; drop unused SPM deps; fix `project.pbxproj` so the app target builds.

**Tech Stack:** SwiftUI/AppKit macOS app, Xcode project, Defaults, Sparkle, existing MediaControllers.

**Spec:** `docs/superpowers/specs/2026-07-28-minimalistic-only-design.md`

## Global Constraints

- Always minimalistic — no `enableMinimalisticUI` toggle
- Keep all media controllers
- HUD keep set: volume, brightness, keyboard backlight, battery only
- Do not rename Bundle ID / product name in this plan
- User asked not to re-confirm; implement without further questions
- Do not commit unless user later asks

---

### Task 1: Inventory keep-set and wire map

**Files:**
- Read: `DynamicIsland/DynamicIslandApp.swift` (AppDelegate)
- Read: `DynamicIsland/components/Notch/NotchHomeView.swift`, `MinimalisticMusicPlayerView.swift`
- Read: `DynamicIsland/models/DynamicIslandViewModel.swift`, `DynamicIslandViewCoordinator.swift`

- [ ] **Step 1:** List every manager/view initialized from AppDelegate and tag KEEP vs DELETE per spec
- [ ] **Step 2:** Note shared helpers (sizing, Defaults keys, OSD) that KEEP code still imports

**Done when:** Written keep/delete checklist exists in the working notes / agent memory for subsequent tasks.

---

### Task 2: Force always-minimalistic notch path

**Files:**
- Modify: `DynamicIsland/components/Notch/NotchHomeView.swift`
- Modify: `DynamicIsland/models/DynamicIslandViewModel.swift`
- Modify: `DynamicIsland/sizing/matters.swift`
- Modify: any remaining `Defaults[.enableMinimalisticUI]` call sites that stay

- [ ] **Step 1:** Make home content always `MinimalisticMusicPlayerView` (remove standard branch / extension override)
- [ ] **Step 2:** Replace size/corner logic with minimalistic-only helpers; delete standard open size paths if unused
- [ ] **Step 3:** Remove or constant-fold `enableMinimalisticUI` key (always true behavior; prefer delete key + dead branches)

**Done when:** Grep for `enableMinimalisticUI` returns no functional branches (key may be gone).

---

### Task 3: Delete feature directories (disk)

**Files:**
- Delete directories under `DynamicIsland/components/`: Stats, Shelf, Clipboard, ColorPicker, ScreenAssistant, Timer, LockScreen, Extensions, Downloads, Focus, Privacy, Recording, Webcam, Calendar, Tabs (if unused), Live activities extras not needed
- Delete managers listed DELETE in Task 1 (LockScreen*, Extension*, Clipboard*, ColorPicker*, Stats*, Terminal*, Timer*, ScreenAssistant*, Download*, Privacy*, BluetoothAudio*, Webcam*, CapsLock*, DoNotDisturb*, Reminder*, Calendar*, LLMUsage*, LocalSend*, AppleNotes*, MemoryUsage*, Camera*, Microphone* if only for privacy, etc.)
- Delete `DynamicIsland/services/Extensions/`

- [ ] **Step 1:** Delete DELETE-tagged directories/files from disk
- [ ] **Step 2:** Remove Onboarding profile matrix files or gut to slim welcome

**Done when:** Deleted trees no longer exist on disk.

---

### Task 4: Slim AppDelegate / coordinator / Defaults

**Files:**
- Modify: `DynamicIsland/DynamicIslandApp.swift`
- Modify: `DynamicIsland/DynamicIslandViewCoordinator.swift`
- Modify: `DynamicIsland/models/Constants.swift` (Defaults keys)

- [ ] **Step 1:** Remove startup of deleted managers and related observers
- [ ] **Step 2:** Trim `SneakContentType` to music + volume/brightness/backlight/battery
- [ ] **Step 3:** Remove Defaults keys for deleted features when unreferenced

**Done when:** App entry compiles against remaining types only (may still fail until pbxproj cleaned).

---

### Task 5: Slim Settings

**Files:**
- Modify: `DynamicIsland/components/Settings/SettingsView.swift` (and related settings files)
- Delete: `ExtensionsSettings.swift` and other settings-only files for deleted domains

- [ ] **Step 1:** Reduce `SettingsTab` to General / Media / Updates (+ Permissions if separate)
- [ ] **Step 2:** Remove Minimalistic UI section; remove dead settings sections
- [ ] **Step 3:** Keep Spotify/YTM auth sections needed by media backends

**Done when:** Settings UI only exposes kept tabs.

---

### Task 6: Fix project + packages

**Files:**
- Modify: `DynamicIsland.xcodeproj/project.pbxproj`
- Modify: `Package.resolved` / SPM package refs as needed (drop AtollExtensionKit if unused)

- [ ] **Step 1:** Remove pbxproj file references and build-phase entries for deleted files
- [ ] **Step 2:** Remove unused package products from target
- [ ] **Step 3:** `xcodebuild -scheme DynamicIsland -configuration Debug build` (or correct scheme name) until success

**Done when:** Clean build succeeds.

---

### Task 7: Smoke verification

- [ ] **Step 1:** Confirm build success log
- [ ] **Step 2:** Grep for obvious dead imports of deleted modules
- [ ] **Step 3:** Summarize remaining surface for the user

**Done when:** Build green; summary matches spec keep-set.
