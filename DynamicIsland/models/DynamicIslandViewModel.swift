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
import Defaults
import SwiftUI

@MainActor
class DynamicIslandViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: DynamicIslandAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    @Published var dragDetectorTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []

    var onViewTeardown: (() -> Void)?

    @Published var hideOnClosed: Bool = true
    @Published var isBatteryPopoverActive: Bool = false
    @Published var isMediaOutputPopoverActive: Bool = false
    @Published var shouldRecheckHover: Bool = false
    @Published var isScrollGestureActive: Bool = false
    private var scrollGestureSuppressionTokens: Set<UUID> = []
    @Published private(set) var isAutoCloseSuppressed: Bool = false
    private var autoCloseSuppressionTokens: Set<UUID> = []

    @Published var screen: String?
    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()

    @MainActor
    deinit {
        destroy()
    }

    init(screen: String? = nil) {
        animation = animationLibrary.animation
        self.screen = screen
        super.init()
        notchSize = getClosedNotchSize(screen: screen)
        closedNotchSize = notchSize
        setupDetectorObserver()
        setupSizeObservers()
    }

    func destroy() {
        cancellables.removeAll()
        onViewTeardown?()
        onViewTeardown = nil
    }

    func setScrollGestureSuppression(_ active: Bool, token: UUID) {
        if active {
            if scrollGestureSuppressionTokens.insert(token).inserted {
                isScrollGestureActive = true
            }
        } else if scrollGestureSuppressionTokens.remove(token) != nil {
            isScrollGestureActive = !scrollGestureSuppressionTokens.isEmpty
        }
    }

    private func resetScrollGestureSuppression() {
        scrollGestureSuppressionTokens.removeAll()
        isScrollGestureActive = false
    }

    func setAutoCloseSuppression(_ active: Bool, token: UUID) {
        if active {
            if autoCloseSuppressionTokens.insert(token).inserted {
                isAutoCloseSuppressed = true
            }
        } else if autoCloseSuppressionTokens.remove(token) != nil {
            isAutoCloseSuppressed = !autoCloseSuppressionTokens.isEmpty
        }
    }

    private func resetAutoCloseSuppression() {
        autoCloseSuppressionTokens.removeAll()
        isAutoCloseSuppressed = false
    }

    private func setupSizeObservers() {
        Defaults.publisher(.enableLyrics, options: [])
            .combineLatest(MusicManager.shared.$currentLyrics)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.notchState == .open else { return }
                let updatedTarget = self.calculateDynamicNotchSize()
                guard self.notchSize != updatedTarget else { return }
                withAnimation(.smooth) {
                    self.notchSize = updatedTarget
                }
                AppDelegate.shared?.ensureWindowSize(
                    addShadowPadding(to: updatedTarget, isMinimalistic: true),
                    animated: true,
                    force: true
                )
            }
            .store(in: &cancellables)
    }

    private func setupDetectorObserver() {
        let enabledPublisher = Defaults
            .publisher(.enableFullscreenMediaDetection)
            .map(\.newValue)

        let statusPublisher = $screen
            .compactMap { $0 }
            .removeDuplicates()
            .map { screenName in
                self.detector.$fullscreenStatus
                    .map { $0[screenName] ?? false }
                    .removeDuplicates()
            }
            .switchToLatest()

        Publishers.CombineLatest(statusPublisher, enabledPublisher)
            .map { status, enabled in enabled && status }
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
            addShadowPadding(to: targetSize, isMinimalistic: true),
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
        resetScrollGestureSuppression()
        resetAutoCloseSuppression()
        coordinator.currentView = .home
    }

    func toggleCameraPreview() {}
}
