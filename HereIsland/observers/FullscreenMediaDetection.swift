/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import ApplicationServices
import MacroVisionKit
import SwiftUI

@MainActor
class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    private let detector: MacroVisionKit
    @Published private(set) var fullscreenStatus: [String: Bool] = [:]
    private var notificationTask: Task<Void, Never>?

    private init() {
        self.detector = MacroVisionKit.shared
        detector.configuration.includeSystemApps = true
        setupNotificationObservers()
        updateFullScreenStatus()
    }

    private func setupNotificationObservers() {
        notificationTask = Task { @Sendable [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let activeSpaceNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.activeSpaceDidChangeNotification
                    )
                    for await _ in activeSpaceNotifications {
                        await self?.handleChange()
                    }
                }
                group.addTask {
                    let screenParameterNotifications = NotificationCenter.default.notifications(
                        named: NSApplication.didChangeScreenParametersNotification
                    )
                    for await _ in screenParameterNotifications {
                        await self?.handleChange()
                    }
                }
            }
        }
        // Screen / space only. Any-app native fullscreen does not depend on Now Playing.
    }

    private func handleChange() async {
        try? await Task.sleep(for: .milliseconds(500))
        updateFullScreenStatus()
    }

    private func updateFullScreenStatus() {
        let apps = detector.detectFullscreenApps(debug: false)
        let names = NSScreen.screens.map { $0.localizedName }

        var newStatus: [String: Bool] = [:]
        for name in names {
            newStatus[name] = apps.contains { app in
                guard app.screen.localizedName == name,
                      app.bundleIdentifier != "com.apple.finder" else { return false }

                // Any app in genuine native fullscreen. Finder is excluded (same as Atoll).
                return isInNativeFullscreen(app)
            }
        }

        if newStatus != fullscreenStatus {
            fullscreenStatus = newStatus
            NSLog("✅ Fullscreen status: \(newStatus)")
        }
    }

    /// Confirms an app the detector flagged as screen-filling is in *genuine* native
    /// fullscreen, not merely maximized/zoomed. On a notched Mac a maximized window and a
    /// fullscreen window report nearly identical frames, so frame size alone can't tell them
    /// apart — the Accessibility `AXFullScreen` attribute can. Without Accessibility
    /// trust, frame-fill is treated as *not* native (maximized windows would otherwise hide).
    private func isInNativeFullscreen(_ app: MacroVisionKit.FullscreenWindowInfo) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let appElement = AXUIElementCreateApplication(app.processId)

        // Prefer the focused window, then fall back to scanning all windows.
        if let focused: AXUIElement = copyAttribute(kAXFocusedWindowAttribute as CFString, from: appElement),
           isWindowFullscreen(focused) {
            return true
        }

        if let windows: [AXUIElement] = copyAttribute(kAXWindowsAttribute as CFString, from: appElement) {
            return windows.contains { isWindowFullscreen($0) }
        }

        return false
    }

    private func isWindowFullscreen(_ window: AXUIElement) -> Bool {
        // "AXFullScreen" is the (undocumented but stable) attribute set true only in native
        // fullscreen; maximized/zoomed windows report false or omit it.
        let value: Bool? = copyAttribute("AXFullScreen" as CFString, from: window)
        return value ?? false
    }

    private func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let typed = value as? T else { return nil }
        return typed
    }

    deinit {
        notificationTask?.cancel()
    }
}
