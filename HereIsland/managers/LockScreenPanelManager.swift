/*
 * Here Island
 * Copyright (C) 2024-2026 Here Island Contributors
 *
 * Originally from boring.notch / Atoll
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
 * along with this program. If you did not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import CoreGraphics
import Defaults
import SwiftUI

@MainActor
final class LockScreenPanelManager {
    static let shared = LockScreenPanelManager()

    /// Content hugs 88pt artwork with 16pt equal insets (390 × 120).
    static let panelSize = CGSize(width: 390, height: 120)
    static let contentPadding: CGFloat = 16
    private static let verticalLowering: CGFloat = 68
    private static let cornerRadius: CGFloat = 28

    private var windows: [String: NSWindow] = [:]
    private var delegatedIDs: Set<String> = []
    private var hideTasks: [String: Task<Void, Never>] = [:]
    private var screenChangeObserver: NSObjectProtocol?

    private init() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, LockScreenManager.shared.isLocked else { return }
                self.showPanel()
            }
        }
    }

    /// Menu-bar / clock display (`CGMainDisplayID`), not the notch Display picker
    /// and not `NSScreen.main` (that's the key-window screen).
    func targetScreens() -> [NSScreen] {
        menuBarScreen().map { [$0] } ?? []
    }

    private func menuBarScreen() -> NSScreen? {
        let mainID = CGMainDisplayID()
        if let match = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == mainID
        }) {
            return match
        }
        return NSScreen.screens.first
    }

    func showPanel() {
        guard Defaults[.enableLockScreenMediaPanel] else {
            hidePanel()
            return
        }

        let targets = targetScreens()
        let keep = Set(targets.map(\.stableDisplayID))
        for (id, window) in windows where !keep.contains(id) {
            hideWindow(id, window)
        }
        for screen in targets {
            present(on: screen)
        }
    }

    func hidePanel() {
        for (id, window) in windows {
            hideWindow(id, window)
        }
    }

    func ensurePresentedWhileLocked() {
        guard Defaults[.enableLockScreenMediaPanel] else { return }
        guard LockScreenManager.shared.isLocked else { return }
        let targets = targetScreens()
        let missing = targets.contains { screen in
            let id = screen.stableDisplayID
            let window = windows[id]
            return window == nil || window?.isVisible != true || window?.contentView == nil
        }
        guard missing else { return }
        showPanel()
    }

    private func present(on screen: NSScreen) {
        let id = screen.stableDisplayID
        hideTasks[id]?.cancel()
        hideTasks[id] = nil

        let targetFrame = frame(on: screen)
        let window: NSWindow
        if let existing = windows[id] {
            window = existing
        } else {
            let created = NSWindow(
                contentRect: targetFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isReleasedWhenClosed = false
            created.isOpaque = false
            created.backgroundColor = .clear
            created.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            created.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            created.isMovable = false
            created.hasShadow = false
            ScreenCaptureVisibilityManager.shared.register(created)
            windows[id] = created
            window = created
        }

        window.setFrame(targetFrame, display: true)
        let hosting = FirstMouseHostingView(rootView: LockScreenMusicPanel())
        hosting.frame = NSRect(origin: .zero, size: targetFrame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        if let content = window.contentView {
            content.wantsLayer = true
            content.layer?.masksToBounds = true
            content.layer?.cornerRadius = Self.cornerRadius
            content.layer?.backgroundColor = NSColor.clear.cgColor
        }

        if !delegatedIDs.contains(id) {
            SkyLightOperator.shared.delegateWindow(window)
            delegatedIDs.insert(id)
        }

        window.orderFrontRegardless()
    }

    private func hideWindow(_ id: String, _ window: NSWindow) {
        hideTasks[id]?.cancel()
        window.orderOut(nil)
        hideTasks[id] = Task { [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                window?.contentView = nil
                self?.hideTasks[id] = nil
            }
        }
    }

    private func frame(on screen: NSScreen) -> NSRect {
        let size = Self.panelSize
        let screenFrame = screen.frame
        let originX = screenFrame.midX - (size.width / 2)
        let originY = screenFrame.midY - size.height - Self.verticalLowering
        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }
}
