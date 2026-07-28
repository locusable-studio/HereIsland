/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Defaults
import LaunchAtLogin
import Sparkle
import SwiftUI

/// Single-page native Settings Form (no tabs).
struct SettingsView: View {
    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        Form {
            Section(String(localized: "App")) {
                LaunchAtLogin.Toggle {
                    Text(String(localized: "Launch at login"))
                }
                Toggle(String(localized: "Menubar icon"), isOn: $menubarIcon)
                Toggle(String(localized: "Settings icon in notch"), isOn: $settingsIconInNotch)
                Toggle(String(localized: "Show on all displays"), isOn: $showOnAllDisplays)
            }

            Section(String(localized: "Interaction")) {
                Toggle(String(localized: "Open on hover"), isOn: $openNotchOnHover)
                Toggle(String(localized: "Enable gestures"), isOn: $enableGestures)
                Toggle(String(localized: "Enable haptics"), isOn: $enableHaptics)
                Toggle(String(localized: "Use simpler close animation"), isOn: $useModernCloseAnimation)
            }

            Section(String(localized: "Appearance")) {
                Toggle(String(localized: "Enable sneak peek"), isOn: $enableSneakPeek)
                Toggle(String(localized: "Window shadow"), isOn: $enableShadow)
            }

            Section(String(localized: "Audio")) {
                Toggle(String(localized: "Real-time waveform"), isOn: $enableRealTimeWaveform)
            }

            Section(String(localized: "Software updates")) {
                if let updater = updaterController?.updater {
                    CheckForUpdatesView(updater: updater)
                    UpdaterSettingsView(updater: updater)
                } else {
                    Text(String(localized: "Updater unavailable"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 420)
    }

    @Default(.menubarIcon) private var menubarIcon
    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.enableGestures) private var enableGestures
    @Default(.enableHaptics) private var enableHaptics
    @Default(.showOnAllDisplays) private var showOnAllDisplays
    @Default(.settingsIconInNotch) private var settingsIconInNotch
    @Default(.enableShadow) private var enableShadow
    @Default(.useModernCloseAnimation) private var useModernCloseAnimation
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.enableRealTimeWaveform) private var enableRealTimeWaveform
}
