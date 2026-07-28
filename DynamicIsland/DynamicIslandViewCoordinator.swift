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

enum SneakContentType: Equatable {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
    var title: String = ""
    var subtitle: String = ""
    var accentColor: Color?
    var styleOverride: SneakPeekStyle? = nil
    var targetScreenName: String? = nil
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
    var autoHideDuration: TimeInterval? = nil
}

class DynamicIslandViewCoordinator: ObservableObject {
    static let shared = DynamicIslandViewCoordinator()
    private var cancellables = Set<AnyCancellable>()
    private var hoverOpenSuppressedUntil: Date = .distantPast
    private var sneakPeekDuration: TimeInterval = 1.5
    private var sneakPeekTask: Task<Void, Never>?
    private var expandingViewTask: Task<Void, Never>?

    @Published var currentView: NotchViews = .home

    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("hudReplacement") var hudReplacement: Bool = true
    @AppStorage("preferred_screen_name") var preferredScreen = NSScreen.main?.localizedName ?? "Unknown" {
        didSet {
            selectedScreen = preferredScreen
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreen: String = NSScreen.main?.localizedName ?? "Unknown"
    @Published var openLastTabByDefault: Bool = false

    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                scheduleSneakPeekHide(after: sneakPeekDuration)
            } else {
                sneakPeekTask?.cancel()
            }
        }
    }

    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewTask?.cancel()
                let duration = expandingView.autoHideDuration ?? 3
                expandingViewTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(duration))
                    guard let self, !Task.isCancelled else { return }
                    self.toggleExpandingView(status: false, type: .battery)
                }
            } else {
                expandingViewTask?.cancel()
            }
        }
    }

    private init() {
        selectedScreen = preferredScreen
    }

    func toggleSneakPeek(
        status: Bool,
        type: SneakContentType,
        duration: TimeInterval = 1.5,
        value: CGFloat = 0,
        icon: String = "",
        title: String = "",
        subtitle: String = "",
        accentColor: Color? = nil,
        styleOverride: SneakPeekStyle? = nil,
        onScreen targetScreen: NSScreen? = nil
    ) {
        sneakPeekDuration = duration
        if type != .music && !Defaults[.enableSystemHUD] {
            return
        }
        DispatchQueue.main.async {
            var updated = self.sneakPeek
            updated.show = status
            updated.type = type
            updated.value = value
            updated.icon = icon
            updated.title = title
            updated.subtitle = subtitle
            updated.accentColor = accentColor
            updated.styleOverride = styleOverride
            updated.targetScreenName = targetScreen?.localizedName
            withAnimation(.smooth(duration: 0.3)) {
                self.sneakPeek = updated
            }
        }
    }

    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        sneakPeekTask?.cancel()
        guard duration.isFinite else { return }
        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    self.toggleSneakPeek(status: false, type: self.sneakPeek.type)
                    self.sneakPeekDuration = 1.5
                }
            }
        }
    }

    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium,
        autoHideDuration: TimeInterval? = nil
    ) {
        Task { @MainActor in
            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
                self.expandingView.autoHideDuration = autoHideDuration
            }
        }
    }

    func showEmpty() {
        currentView = .home
    }

    func suppressHoverOpen(for duration: TimeInterval = 0.8) {
        hoverOpenSuppressedUntil = Date().addingTimeInterval(duration)
    }

    var isHoverOpenSuppressed: Bool {
        Date() < hoverOpenSuppressedUntil
    }
}
