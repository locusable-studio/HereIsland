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

import Combine
import SwiftUI

@MainActor
class DynamicIslandViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    @Published private(set) var notchState: NotchState = .closed
    var cancellables: Set<AnyCancellable> = []

    var onViewTeardown: (() -> Void)?

    @Published var hideOnClosed: Bool = true

    @Published var screen: String?
    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()

    @MainActor
    deinit {
        destroy()
    }

    init(screen: String? = nil) {
        self.screen = screen
        super.init()
        notchSize = getClosedNotchSize(screen: screen)
        closedNotchSize = notchSize
        setupDetectorObserver()
    }

    /// Bind the view model to a display and refresh closed-notch geometry.
    func setScreen(_ name: String?) {
        guard screen != name else {
            refreshClosedNotchSize()
            return
        }
        screen = name
        refreshClosedNotchSize()
    }

    func refreshClosedNotchSize() {
        closedNotchSize = getClosedNotchSize(screen: screen)
    }

    func destroy() {
        cancellables.removeAll()
        onViewTeardown?()
        onViewTeardown = nil
    }

    private func setupDetectorObserver() {
        $screen
            .compactMap { $0 }
            .removeDuplicates()
            .map { screenName in
                self.detector.$fullscreenStatus
                    .map { $0[screenName] ?? false }
                    .removeDuplicates()
            }
            .switchToLatest()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = NSScreen.screens.first { $0.localizedName == screen }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    func open() {
        let targetSize = calculateDynamicNotchSize()
        notchSize = targetSize
        notchState = .open
        // Keep AppKit out of the spring: only sync if size actually differs.
        AppDelegate.shared?.ensureWindowSize(
            targetSize,
            animated: false,
            force: false
        )
        MusicManager.shared.forceUpdate()
    }

    private func calculateDynamicNotchSize() -> CGSize {
        minimalisticOpenNotchSize(isDynamicIslandMode: shouldUseDynamicIslandMode(for: screen))
    }

    func close() {
        closedNotchSize = getClosedNotchSize(screen: screen)
        // Window stays at open size; SwiftUI clips to the closed shape.
        notchSize = calculateDynamicNotchSize()
        notchState = .closed
        coordinator.currentView = .home
    }
}
