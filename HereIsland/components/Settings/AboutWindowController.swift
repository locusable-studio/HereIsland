/*
 * Here Island
 * Copyright (C) 2024-2026 Here Island Contributors
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
import SwiftUI

/// Presents the About window for an `LSUIElement` menu-bar app.
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
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

    private func configureWindow() {
        guard let window else { return }
        window.title = String(localized: "About Here Island")
        window.minSize = NSSize(width: 420, height: 480)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.hidesOnDeactivate = false
        window.identifier = NSUserInterfaceItemIdentifier("HereIslandAboutWindow")
        window.delegate = self
        window.contentView = NSHostingView(rootView: AboutView())
        ScreenCaptureVisibilityManager.shared.register(window, scope: .panelsOnly)
    }

    func openAbout() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            self.window = window
            configureWindow()
        } else if window?.contentView == nil {
            window?.contentView = NSHostingView(rootView: AboutView())
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

    deinit {
        if let window {
            ScreenCaptureVisibilityManager.shared.unregister(window)
        }
    }
}

extension AboutWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
        // Keep regular activation if Settings is still open.
        if SettingsWindowController.shared.window?.isVisible != true {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
