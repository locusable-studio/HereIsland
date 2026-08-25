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

enum ScreenCaptureScope: Int {
    case panelsOnly
    case entireInterface
}

/// SkyLight private API used by Atoll's ScreenRecordingManager.
/// Event-driven: 1502 connect / 1503 disconnect. Not a public API.
@_silgen_name("CGSIsScreenWatcherPresent")
func CGSIsScreenWatcherPresent() -> Bool

@_silgen_name("CGSRegisterNotifyProc")
func CGSRegisterNotifyProc(
    _ callback: (@convention(c) (Int32, Int32, Int32, UnsafeMutableRawPointer?) -> Void)?,
    _ event: Int32,
    _ context: UnsafeMutableRawPointer?
) -> Bool

private func screenCaptureEventCallback(
    eventType: Int32,
    _: Int32,
    _: Int32,
    context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let manager = Unmanaged<ScreenCaptureVisibilityManager>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.handleScreenWatcherEvent(eventType)
    }
}

/// Same hide path as Atoll: `NSWindow.sharingType`.
/// Share/record local hide follows Atoll's CGS screen-watcher, not process polling.
final class ScreenCaptureVisibilityManager {
    static let shared = ScreenCaptureVisibilityManager()

    private let scopedWindows = NSMapTable<NSWindow, NSNumber>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private var cancellables = Set<AnyCancellable>()
    private var lastCaptureActive = false
    private var started = false
    private var registeredNotify = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        registerWatcherNotifications()

        Defaults.publisher(.hideFromScreenshots, options: [.initial])
            .combineLatest(Defaults.publisher(.hideFromScreenShare, options: [.initial]))
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.updateAllWindows()
                self?.refreshCaptureVisibility()
            }
            .store(in: &cancellables)
    }

    func stop() {
        lastCaptureActive = false
        AppDelegate.shared?.setHiddenForCapture(false)
    }

    func register(_ window: NSWindow, scope: ScreenCaptureScope) {
        scopedWindows.setObject(NSNumber(value: scope.rawValue), forKey: window)
        applyVisibility(to: window)
    }

    func unregister(_ window: NSWindow) {
        scopedWindows.removeObject(forKey: window)
    }

    func handleScreenWatcherEvent(_ eventType: Int32) {
        refreshCaptureVisibility()
    }

    private func registerWatcherNotifications() {
        guard !registeredNotify else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let connect = CGSRegisterNotifyProc(screenCaptureEventCallback, 1502, context)
        let disconnect = CGSRegisterNotifyProc(screenCaptureEventCallback, 1503, context)
        registeredNotify = connect && disconnect
        refreshCaptureVisibility()
    }

    private func updateAllWindows() {
        guard let windows = scopedWindows.keyEnumerator().allObjects as? [NSWindow] else { return }
        for window in windows {
            applyVisibility(to: window)
        }
    }

    private func applyVisibility(to window: NSWindow) {
        let shouldHide = Defaults[.hideFromScreenshots] || Defaults[.hideFromScreenShare]
        window.sharingType = shouldHide ? .none : .readOnly
    }

    private func refreshCaptureVisibility() {
        let active = Defaults[.hideFromScreenShare] && CGSIsScreenWatcherPresent()
        guard active != lastCaptureActive else { return }
        lastCaptureActive = active
        AppDelegate.shared?.setHiddenForCapture(active)
    }
}
