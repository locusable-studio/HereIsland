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

import AppKit
import Sparkle
import SwiftUI

/// Presents settings for an `LSUIElement` menu-bar app.
///
/// Content is a single-page SwiftUI `Form` (`SettingsView`). The window itself
/// is a normal AppKit window because SwiftUI `Settings` / `SettingsLink` is
/// unreliable while `LSUIElement` keeps the app in accessory mode.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var updaterController: SPUStandardUpdaterController?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        super.init(window: window)
        configureWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUpdaterController(_ controller: SPUStandardUpdaterController) {
        updaterController = controller
        installRootView()
    }

    private func configureWindow() {
        guard let window else { return }
        window.title = String(localized: "Here Island Settings")
        window.minSize = NSSize(width: 480, height: 400)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.hidesOnDeactivate = false
        window.identifier = NSUserInterfaceItemIdentifier("HereIslandSettingsWindow")
        window.delegate = self
        installRootView()
        ScreenCaptureVisibilityManager.shared.register(window, scope: .panelsOnly)
    }

    private func installRootView() {
        guard let window else { return }
        window.contentView = NSHostingView(
            rootView: SettingsView(updaterController: updaterController)
        )
    }

    func openSettings() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            self.window = window
            configureWindow()
        } else if window?.contentView == nil {
            installRootView()
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func showWindow() {
        openSettings()
    }

    deinit {
        if let window {
            ScreenCaptureVisibilityManager.shared.unregister(window)
        }
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
