/*
 * Here Island
 * Copyright (C) 2024-2026 Atoll Contributors / Here Island
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

enum ScreenCaptureScope: Int {
    /// Settings / about panels: apply sharingType only, stay on screen.
    case panelsOnly
    /// Notch windows: apply sharingType, and hide locally while capture is active.
    case entireInterface
}

/// Applies the two menu-bar hide toggles to registered windows.
///
/// macOS exposes one window-level exclusion knob (`NSWindow.sharingType`).
/// Either toggle sets `.none` so the window is left out of screenshots and
/// most share/record pipelines. The share/record toggle additionally hides
/// the notch on the local display while a capture UI is running.
final class ScreenCaptureVisibilityManager {
    static let shared = ScreenCaptureVisibilityManager()

    private let scopedWindows = NSMapTable<NSWindow, NSNumber>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private var cancellables = Set<AnyCancellable>()
    private var capturePoll: Timer?
    private var lastCaptureActive = false
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        Defaults.publisher(.hideFromScreenshots, options: [.initial])
            .combineLatest(Defaults.publisher(.hideFromScreenShare, options: [.initial]))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.apply()
            }
            .store(in: &cancellables)
    }

    func stop() {
        capturePoll?.invalidate()
        capturePoll = nil
        lastCaptureActive = false
        AppDelegate.shared?.setHiddenForCapture(false)
    }

    func register(_ window: NSWindow, scope: ScreenCaptureScope) {
        scopedWindows.setObject(NSNumber(value: scope.rawValue), forKey: window)
        apply(to: window)
    }

    func unregister(_ window: NSWindow) {
        scopedWindows.removeObject(forKey: window)
    }

    private func apply() {
        for window in registeredWindows() {
            apply(to: window)
        }
        syncCapturePolling()
    }

    private func apply(to window: NSWindow) {
        let exclude = Defaults[.hideFromScreenshots] || Defaults[.hideFromScreenShare]
        window.sharingType = exclude ? .none : .readOnly
    }

    private func syncCapturePolling() {
        if Defaults[.hideFromScreenShare] {
            if capturePoll == nil {
                let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
                    self?.evaluateCaptureState()
                }
                RunLoop.main.add(timer, forMode: .common)
                capturePoll = timer
                evaluateCaptureState()
            }
        } else {
            capturePoll?.invalidate()
            capturePoll = nil
            if lastCaptureActive {
                lastCaptureActive = false
                AppDelegate.shared?.setHiddenForCapture(false)
            }
        }
    }

    private func evaluateCaptureState() {
        let active = isCaptureUIActive()
        guard active != lastCaptureActive else { return }
        lastCaptureActive = active
        AppDelegate.shared?.setHiddenForCapture(active)
    }

    /// Best-effort public signal that a system screenshot/record/share UI is up.
    /// Zoom/Meet-style in-app share is covered by `sharingType = .none` instead.
    private func isCaptureUIActive() -> Bool {
        let captureBundleIDs: Set<String> = [
            "com.apple.screencaptureui",
            "com.apple.ScreenSharing",
            "com.apple.screensharing.agent",
            "com.apple.QuickTimePlayerX",
        ]
        if NSWorkspace.shared.runningApplications.contains(where: {
            captureBundleIDs.contains($0.bundleIdentifier ?? "")
        }) {
            return true
        }

        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let names = [
            "screencaptureui",
            "screen recording",
            "screen sharing",
            "屏幕录制",
            "屏幕共享",
        ]
        return info.contains { window in
            let owner = (window[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            let title = (window[kCGWindowName as String] as? String ?? "").lowercased()
            return names.contains { owner.contains($0) || title.contains($0) }
        }
    }

    private func registeredWindows() -> [NSWindow] {
        (scopedWindows.keyEnumerator().allObjects as? [NSWindow]) ?? []
    }
}
