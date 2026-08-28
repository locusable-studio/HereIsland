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
import Combine
import Defaults

/// Menu toggle “Hide during screenshots and recordings”.
/// Only `NSWindow.sharingType`. Does not order the notch out.
final class ScreenCaptureVisibilityManager {
    static let shared = ScreenCaptureVisibilityManager()

    private let windows = NSHashTable<NSWindow>.weakObjects()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Defaults.publisher(.hideFromScreenCapture)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateAllWindows()
            }
            .store(in: &cancellables)
    }

    func register(_ window: NSWindow) {
        windows.add(window)
        applyVisibility(to: window)
    }

    func unregister(_ window: NSWindow) {
        windows.remove(window)
    }

    private func updateAllWindows() {
        for window in windows.allObjects {
            applyVisibility(to: window)
        }
    }

    private func applyVisibility(to window: NSWindow) {
        let shouldHide = Defaults[.hideFromScreenCapture]
        window.sharingType = shouldHide ? .none : .readOnly
    }
}
