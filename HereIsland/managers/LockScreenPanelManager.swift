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
import Defaults
import SwiftUI

@MainActor
final class LockScreenPanelManager {
    static let shared = LockScreenPanelManager()

    private var panelWindow: NSWindow?
    private var hasDelegated = false
    private var hideTask: Task<Void, Never>?
    private var screenChangeObserver: NSObjectProtocol?

    /// One fixed style: 390×180, centered on the lock display,
    /// a little below the clock / vertical centre.
    static let panelSize = CGSize(width: 390, height: 180)
    private static let verticalLowering: CGFloat = 68
    private static let cornerRadius: CGFloat = 28

    private init() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.realignIfVisible()
            }
        }
    }

    func showPanel() {
        guard Defaults[.enableLockScreenMediaPanel] else {
            hidePanel()
            return
        }
        guard let screen = LockScreenDisplayContextProvider.shared.currentScreen() else { return }

        hideTask?.cancel()
        hideTask = nil

        let targetFrame = frame(on: screen)
        let window: NSWindow
        if let existing = panelWindow {
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
            panelWindow = created
            window = created
            hasDelegated = false
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

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        // Keep the window alive; closing it after SkyLight attach can crash.
        window.orderFrontRegardless()
    }

    func hidePanel() {
        hideTask?.cancel()
        guard let window = panelWindow else { return }
        window.orderOut(nil)
        hideTask = Task { [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                window?.contentView = nil
                self?.hideTask = nil
            }
        }
    }

    /// `hidePanel` clears `contentView`. If that happens mid-lock, put the panel back.
    func ensurePresentedWhileLocked() {
        guard Defaults[.enableLockScreenMediaPanel] else { return }
        guard LockScreenManager.shared.isLocked else { return }
        let isMissing = panelWindow == nil
            || panelWindow?.isVisible != true
            || panelWindow?.contentView == nil
        guard isMissing else { return }
        showPanel()
    }

    private func realignIfVisible() {
        guard let window = panelWindow, window.isVisible, window.contentView != nil else { return }
        guard let screen = LockScreenDisplayContextProvider.shared.refresh() else { return }
        window.setFrame(frame(on: screen), display: true)
    }

    private func frame(on screen: NSScreen) -> NSRect {
        let size = Self.panelSize
        let screenFrame = screen.frame
        let originX = screenFrame.midX - (size.width / 2)
        let originY = screenFrame.midY - size.height - Self.verticalLowering
        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }
}
