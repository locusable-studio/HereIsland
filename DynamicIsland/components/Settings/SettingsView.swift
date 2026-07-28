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
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI

private enum SlimSettingsTab: String, CaseIterable, Identifiable {
    case general
    case media
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .media: return String(localized: "Media")
        case .updates: return String(localized: "Updates")
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SlimSettingsTab = .general
    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(SlimSettingsTab.allCases, selection: $selectedTab) { tab in
                Text(tab.title).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            Form {
                switch selectedTab {
                case .general:
                    SlimGeneralSettings()
                case .media:
                    SlimMediaSettings()
                case .updates:
                    SlimUpdatesSettings(updaterController: updaterController)
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct SlimGeneralSettings: View {
    @Default(.menubarIcon) private var menubarIcon
    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.enableGestures) private var enableGestures
    @Default(.enableHaptics) private var enableHaptics
    @Default(.showOnAllDisplays) private var showOnAllDisplays
    @Default(.enableShortcuts) private var enableShortcuts
    @Default(.showMinimalisticBatteryIndicator) private var showMinimalisticBatteryIndicator
    @Default(.showBatteryPercentInside) private var showBatteryPercentInside
    @Default(.settingsIconInNotch) private var settingsIconInNotch
    @Default(.enableShadow) private var enableShadow
    @Default(.useModernCloseAnimation) private var useModernCloseAnimation
    @Default(.inlineHUD) private var inlineHUD
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.enableRealTimeWaveform) private var enableRealTimeWaveform

    var body: some View {
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
            Toggle(String(localized: "Enable shortcuts"), isOn: $enableShortcuts)
            Toggle(String(localized: "Use simpler close animation"), isOn: $useModernCloseAnimation)
        }

        Section(String(localized: "HUD")) {
            Toggle(String(localized: "Inline HUD"), isOn: $inlineHUD)
            Toggle(String(localized: "Enable sneak peek"), isOn: $enableSneakPeek)
            Toggle(String(localized: "Window shadow"), isOn: $enableShadow)
        }

        Section(String(localized: "Battery")) {
            Toggle(String(localized: "Show battery indicator"), isOn: $showMinimalisticBatteryIndicator)
            Toggle(String(localized: "Show battery percentage inside icon"), isOn: $showBatteryPercentInside)
                .disabled(!showMinimalisticBatteryIndicator)
        }

        Section(String(localized: "Audio")) {
            Toggle(String(localized: "Real-time waveform"), isOn: $enableRealTimeWaveform)
        }
    }
}

private struct SlimMediaSettings: View {
    var body: some View {
        Section(String(localized: "Playback")) {
            SpotifyAuthSettingsSection()
            MusicSlotConfigurationView()
        }
    }
}

private struct SlimUpdatesSettings: View {
    let updaterController: SPUStandardUpdaterController?

    var body: some View {
        Section(String(localized: "Updates")) {
            if let updater = updaterController?.updater {
                CheckForUpdatesView(updater: updater)
                UpdaterSettingsView(updater: updater)
            } else {
                Text(String(localized: "Updater unavailable"))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
