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
import Combine
import CoreGraphics
import Defaults
import Foundation

@MainActor
final class LockScreenManager {
    static let shared = LockScreenManager()

    private(set) var isLocked = false
    private var lockStatePollTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenLocked),
            name: .init("com.apple.screenIsLocked"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: .init("com.apple.screenIsUnlocked"),
            object: nil
        )
        // Unlock notifications can arrive late; session-active usually fires first.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        Defaults.publisher(.enableLockScreenMediaPanel)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue, self.isLocked {
                    LockScreenPanelManager.shared.showPanel()
                    self.startLockStatePolling()
                } else if !change.newValue {
                    self.stopLockStatePolling()
                    LockScreenPanelManager.shared.hidePanel()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        lockStatePollTask?.cancel()
    }

    @objc private func screenLocked() {
        guard !isLocked else { return }
        isLocked = true
        if Defaults[.enableLockScreenMediaPanel] {
            LockScreenPanelManager.shared.showPanel()
            startLockStatePolling()
        }
    }

    @objc private func screenUnlocked() {
        guard isLocked else { return }
        isLocked = false
        stopLockStatePolling()
        LockScreenPanelManager.shared.hidePanel()
    }

    /// Poll only after we already believe the Mac is locked.
    /// Catches a missed unlock and re-presents a dropped panel.
    private func startLockStatePolling() {
        lockStatePollTask?.cancel()
        lockStatePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self, self.isLocked else { return }
                    if !Self.isSessionScreenLocked() {
                        self.screenUnlocked()
                        return
                    }
                    LockScreenPanelManager.shared.ensurePresentedWhileLocked()
                }
            }
        }
    }

    private func stopLockStatePolling() {
        lockStatePollTask?.cancel()
        lockStatePollTask = nil
    }

    private static func isSessionScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
