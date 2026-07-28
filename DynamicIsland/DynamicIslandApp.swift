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

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon

    let updaterController: SPUStandardUpdaterController
    private let updaterDelegate = AtollUpdaterDelegate()

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !AppRuntimeEnvironment.isUITesting,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra("dynamic.island", systemImage: "mountain.2.fill", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                SettingsWindowController.shared.showWindow()
            }
            CheckForUpdatesView(updater: updaterController.updater)
            Divider()
            Button("Restart Here Island") {
                guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
                let workspace = NSWorkspace.shared
                if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.createsNewApplicationInstance = true
                    workspace.openApplication(at: appURL, configuration: configuration)
                }
                NSApplication.shared.terminate(self)
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }

    @CommandsBuilder
    var commands: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                SettingsWindowController.shared.showWindow()
            }
        }
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

extension AppDelegate {
    static var shared: AppDelegate? {
        NSApplication.shared.delegate as? AppDelegate
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSScreen: NSWindow] = [:]
    var viewModels: [NSScreen: DynamicIslandViewModel] = [:]
    var window: NSWindow?
    let vm: DynamicIslandViewModel = .init()
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    private var cancellables = Set<AnyCancellable>()
    private var windowsHiddenForLock = false
    private var windowSizeUpdateWorkItem: DispatchWorkItem?
    private var closeNotchWorkItem: DispatchWorkItem?
    private var previousScreens: [NSScreen]?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowSizeUpdateWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
        SystemOSDManager.resumeOSDUIHelperForTermination()
        AudioTap.shared.stopCapture()
        LunarManager.shared.appWillTerminate()
    }

    @objc func onScreenLocked(_: Notification) {
        hideWindowsForLock()
    }

    @objc func onScreenUnlocked(_: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.restoreWindowsAfterLock()
            self?.adjustWindowPosition(changeAlpha: true)
        }
    }

    private func hideWindowsForLock() {
        guard !windowsHiddenForLock else { return }
        windowsHiddenForLock = true
        if Defaults[.showOnAllDisplays] {
            for window in windows.values {
                window.alphaValue = 0
                window.orderOut(nil)
            }
        } else if let window {
            window.alphaValue = 0
            window.orderOut(nil)
        }
    }

    private func restoreWindowsAfterLock() {
        guard windowsHiddenForLock else { return }
        windowsHiddenForLock = false
        if Defaults[.showOnAllDisplays] {
            for window in windows.values {
                window.orderFrontRegardless()
                window.alphaValue = 1
            }
        } else if let window {
            window.orderFrontRegardless()
            window.alphaValue = 1
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        if shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays] {
            for (screen, window) in windows {
                viewModels[screen]?.onViewTeardown?()
                viewModels[screen]?.onViewTeardown = nil
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
                window.close()
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window {
            vm.onViewTeardown?()
            vm.onViewTeardown = nil
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            window.close()
            self.window = nil
        }
    }

    @MainActor
    private func syncNotchSpaceMembership() {
        guard Defaults[.hideNotchOption] == .never else {
            NotchSpaceManager.shared.notchSpace.windows = []
            return
        }
        if Defaults[.showOnAllDisplays] {
            NotchSpaceManager.shared.notchSpace.windows = Set(windows.values)
        } else if let window {
            NotchSpaceManager.shared.notchSpace.windows = [window]
        } else {
            NotchSpaceManager.shared.notchSpace.windows = []
        }
    }

    private func createDynamicIslandWindow(for screen: NSScreen, with viewModel: DynamicIslandViewModel) -> NSWindow {
        let baseSize = calculateRequiredNotchSize()
        let requiredSize = adjustedSizeForScreen(baseSize, screen: screen)
        let window = DynamicIslandWindow(
            contentRect: NSRect(x: 0, y: 0, width: requiredSize.width.rounded(), height: requiredSize.height.rounded()),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.contentView = FirstMouseHostingView(
            rootView: ContentView().environmentObject(viewModel)
        )
        window.orderFrontRegardless()
        if Defaults[.hideNotchOption] == .never {
            NotchSpaceManager.shared.notchSpace.windows.insert(window)
        }
        return window
    }

    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha { window.alphaValue = 0 }
        let screenFrame = screen.frame
        let centerX = screenFrame.origin.x + (screenFrame.width / 2)
        let roundedWidth = window.frame.width.rounded()
        let roundedHeight = window.frame.height.rounded()
        let newX = (centerX - (roundedWidth / 2)).rounded()
        let newY = (screenFrame.origin.y + screenFrame.height - roundedHeight).rounded()
        window.setFrame(NSRect(x: newX, y: newY, width: roundedWidth, height: roundedHeight), display: false)
        if changeAlpha { window.alphaValue = 1 }
    }

    /// Window is always sized for the open notch (original behavior).
    /// Closed live activities sit inside that larger top-aligned window.
    private func calculateRequiredNotchSize() -> CGSize {
        if vm.notchState == .closed,
           coordinator.expandingView.show,
           coordinator.expandingView.type == .music,
           Defaults[.enableSneakPeek],
           Defaults[.sneakPeekStyles] == .inline {
            return addShadowPadding(
                to: CGSize(width: 460, height: vm.effectiveClosedNotchHeight),
                isMinimalistic: true
            )
        }
        let base = minimalisticOpenNotchSize(isDynamicIslandMode: shouldUseDynamicIslandMode(for: vm.screen))
        return addShadowPadding(to: base, isMinimalistic: true)
    }

    private func adjustedSizeForScreen(_ size: CGSize, screen: NSScreen) -> CGSize {
        var adjusted = size
        if shouldUseDynamicIslandMode(for: screen.localizedName) {
            adjusted.width += dynamicIslandShadowInset * 2
            adjusted.height += dynamicIslandTopOffset
        }
        return CGSize(
            width: min(adjusted.width, screen.frame.width),
            height: min(adjusted.height, screen.frame.height)
        )
    }

    private func resizeWindows(to size: CGSize, animated: Bool, force: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        let apply: (NSWindow, NSScreen) -> Void = { window, screen in
            let adjusted = self.adjustedSizeForScreen(size, screen: screen)
            let screenFrame = screen.frame
            let clampedWidth = min(adjusted.width, screenFrame.width).rounded()
            let clampedHeight = min(adjusted.height, screenFrame.height).rounded()
            // Skip no-op resizes so AppKit doesn't interrupt SwiftUI springs.
            if !force,
               abs(window.frame.width - clampedWidth) < 0.5,
               abs(window.frame.height - clampedHeight) < 0.5 {
                return
            }
            let newX = (screenFrame.midX - (clampedWidth / 2)).rounded()
            let newY = (screenFrame.origin.y + screenFrame.height - clampedHeight).rounded()
            let frame = NSRect(x: newX, y: newY, width: clampedWidth, height: clampedHeight)
            // Never animate AppKit frame during open/close — SwiftUI owns the morph.
            window.setFrame(frame, display: true)
        }

        if Defaults[.showOnAllDisplays] {
            for (screen, window) in windows {
                apply(window, screen)
            }
        } else if let window, let screen = window.screen ?? NSScreen.main {
            apply(window, screen)
        }
    }

    func ensureWindowSize(_ size: CGSize, animated: Bool, force: Bool = false) {
        resizeWindows(to: size, animated: animated, force: force)
    }

    private func updateWindowSizeIfNeeded() {
        resizeWindows(to: calculateRequiredNotchSize(), animated: true, force: false)
    }

    private func debouncedUpdateWindowSize() {
        windowSizeUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateWindowSizeIfNeeded()
        }
        windowSizeUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Defaults.Keys.migrateProgressBarStyle()
        Defaults.Keys.migrateMusicAuxControls()
        Defaults.Keys.migrateMusicControlSlots()
        Defaults.Keys.migrateThirdPartyDDCIntegration()

        Defaults.publisher(.enableThirdPartyDDCIntegration, options: [])
            .sink { _ in Defaults.Keys.syncLegacyThirdPartyDDCKeys() }
            .store(in: &cancellables)
        Defaults.publisher(.thirdPartyDDCProvider, options: [])
            .sink { _ in Defaults.Keys.syncLegacyThirdPartyDDCKeys() }
            .store(in: &cancellables)

        SystemHUDManager.shared.setup(coordinator: coordinator)
        BetterDisplayManager.shared.configure(coordinator: coordinator)
        LunarManager.shared.configure(coordinator: coordinator)

        if Defaults[.enableRealTimeWaveform] {
            Task { await AudioTap.shared.startCapture() }
        }
        Defaults.publisher(.enableRealTimeWaveform, options: [])
            .sink { change in
                if change.newValue {
                    Task { await AudioTap.shared.startCapture() }
                } else {
                    AudioTap.shared.stopCapture()
                }
            }
            .store(in: &cancellables)

        coordinator.$currentView
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateWindowSizeIfNeeded() }
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableShortcuts, options: []).sink { change in
            KeyboardShortcuts.isEnabled = change.newValue
        }.store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            self?.adjustWindowPosition(changeAlpha: true)
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            self?.adjustWindowPosition()
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.cleanupWindows(shouldInvert: true)
            if !Defaults[.showOnAllDisplays] {
                let window = self.createDynamicIslandWindow(
                    for: NSScreen.main ?? NSScreen.screens.first!,
                    with: self.vm
                )
                self.window = window
                self.adjustWindowPosition(changeAlpha: true)
            } else {
                self.adjustWindowPosition()
            }
            self.syncNotchSpaceMembership()
        }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(onScreenLocked(_:)),
            name: NSNotification.Name(rawValue: "com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(onScreenUnlocked(_:)),
            name: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"), object: nil)

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self, Defaults[.enableShortcuts] else { return }
            self.coordinator.toggleSneakPeek(
                status: !self.coordinator.sneakPeek.show,
                type: .music,
                duration: 3.0
            )
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            guard let self, Defaults[.enableShortcuts] else { return }
            self.closeNotchWorkItem?.cancel()
            self.closeNotchWorkItem = nil
            switch self.vm.notchState {
            case .closed:
                self.vm.open()
                let workItem = DispatchWorkItem { [weak self] in self?.vm.close() }
                self.closeNotchWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
            case .open:
                self.vm.close()
            }
        }

        KeyboardShortcuts.isEnabled = Defaults[.enableShortcuts]

        if !Defaults[.showOnAllDisplays] {
            window = createDynamicIslandWindow(
                for: NSScreen.main ?? NSScreen.screens.first!,
                with: vm
            )
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        previousScreens = NSScreen.screens
        syncNotchSpaceMembership()
        debouncedUpdateWindowSize()
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens
        defer { previousScreens = currentScreens }
        cleanupWindows()
        if !Defaults[.showOnAllDisplays] {
            window = createDynamicIslandWindow(
                for: NSScreen.main ?? NSScreen.screens.first!,
                with: vm
            )
        }
        adjustWindowPosition(changeAlpha: true)
        syncNotchSpaceMembership()
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let screens = NSScreen.screens
            for screen in screens {
                if windows[screen] == nil {
                    let viewModel = DynamicIslandViewModel(screen: screen.localizedName)
                    let window = createDynamicIslandWindow(for: screen, with: viewModel)
                    windows[screen] = window
                    viewModels[screen] = viewModel
                }
                if let window = windows[screen] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)
                }
            }
            for screen in windows.keys where !screens.contains(screen) {
                windows[screen]?.close()
                windows.removeValue(forKey: screen)
                viewModels.removeValue(forKey: screen)
            }
        } else if let window {
            let screen = NSScreen.screens.first(where: { $0.localizedName == coordinator.selectedScreen })
                ?? NSScreen.main
                ?? NSScreen.screens.first!
            positionWindow(window, on: screen, changeAlpha: changeAlpha)
        }
        syncNotchSpaceMembership()
        updateWindowSizeIfNeeded()
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
}
