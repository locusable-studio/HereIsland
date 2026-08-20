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

import Foundation
import Sparkle

/// Tracks an update that Sparkle has already downloaded and is holding until the app quits.
final class UpdateReadyState: ObservableObject {
    @Published fileprivate(set) var isReady = false
}

class HereIslandUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    let readyState = UpdateReadyState()

    private var immediateInstallHandler: (() -> Void)?

    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateChannel.feedURL.absoluteString
    }

    /// With automatic downloads enabled, Sparkle installs silently on termination and shows no UI.
    /// Here Island lives in the menu bar and is rarely quit, so claim the installation and surface
    /// it as a menu action instead of waiting for a quit that may never come.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock installHandler: @escaping () -> Void
    ) -> Bool {
        onMain {
            self.immediateInstallHandler = installHandler
            self.readyState.isReady = true
        }
        return true
    }

    /// Installs the already downloaded update and relaunches the app.
    func installDownloadedUpdate() {
        immediateInstallHandler?()
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        discardDownloadedUpdate()
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        discardDownloadedUpdate()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // A finished check that simply found nothing must not invalidate a pending install.
        guard !Self.isBenign(error) else { return }
        discardDownloadedUpdate()
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Dismissing a downloaded update leaves it installable from the menu.
        if choice == .dismiss, state.stage == .downloaded { return }
        discardDownloadedUpdate()
    }

    private func discardDownloadedUpdate() {
        onMain {
            self.immediateInstallHandler = nil
            self.readyState.isReady = false
        }
    }

    private static func isBenign(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SUSparkleErrorDomain
            && error.code == Int(SUError.noUpdateError.rawValue)
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
