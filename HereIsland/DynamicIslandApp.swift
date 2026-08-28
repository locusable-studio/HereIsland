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
import LaunchAtLogin
import Sparkle
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.enableHaptics) var enableHaptics
    @Default(.displayDestination) var displayDestination
    @Default(.showAlbumArtBackgroundEffects) var showAlbumArtBackgroundEffects
    @Default(.showWindowShadow) var showWindowShadow
    @Default(.hideFromScreenCapture) var hideFromScreenCapture
    @Default(.hideWhenFullscreen) var hideWhenFullscreen
    @Default(.enableRealTimeWaveform) var enableRealTimeWaveform
    @Default(.showTitleOnTrackChange) var showTitleOnTrackChange
    @Default(.mediaController) var mediaController
    @Default(.playerTint) var playerTint
    @Default(.updateChannel) var updateChannel
    @ObservedObject private var musicManager = MusicManager.shared

    let updaterController: SPUStandardUpdaterController
    private let updaterDelegate = HereIslandUpdaterDelegate()

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !AppRuntimeEnvironment.isUITesting,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra("Here Island", systemImage: "inset.filled.capsule") {
            Section(String(localized: "General")) {
                LaunchAtLogin.Toggle {
                    Text(String(localized: "Launch at login"))
                }
                Toggle(String(localized: "Haptics"), isOn: $enableHaptics)
                Toggle(String(localized: "Hide during screenshots and recordings"), isOn: $hideFromScreenCapture)
                Toggle(String(localized: "Hide when fullscreen"), isOn: $hideWhenFullscreen)
                Picker(String(localized: "Display"), selection: $displayDestination) {
                    ForEach(orderedScreens(), id: \.stableDisplayID) { screen in
                        Text(screen.localizedName).tag(screen.stableDisplayID)
                    }
                    Divider()
                    Text(String(localized: "Show on all displays"))
                        .tag(DisplayDestination.allDisplays)
                }
            }

            Section(String(localized: "Appearance")) {
                Toggle(String(localized: "Album art background"), isOn: $showAlbumArtBackgroundEffects)
                Toggle(String(localized: "Window shadow"), isOn: $showWindowShadow)
                Toggle(String(localized: "Real-time waveform"), isOn: $enableRealTimeWaveform)
                Toggle(String(localized: "Quick peek"), isOn: $showTitleOnTrackChange)
                Picker(String(localized: "Accent color"), selection: $playerTint) {
                    ForEach(PlayerTint.allCases) { option in
                        Text(option.localizedName).tag(option)
                    }
                }
            }

            Section(String(localized: "Media")) {
                Picker(String(localized: "Source"), selection: $mediaController) {
                    ForEach(availableMediaControllers) { type in
                        Text(type.localizedName).tag(type)
                    }
                }
            }

            Section(String(localized: "Updates")) {
                CheckForUpdatesView(updater: updaterController.updater, updaterDelegate: updaterDelegate)
                Picker(String(localized: "Channel"), selection: $updateChannel) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.localizedName).tag(channel)
                    }
                }
                .onChange(of: updateChannel) { _, _ in
                    updaterController.updater.resetUpdateCycle()
                }
                Menu(String(localized: "Update Settings")) {
                    UpdaterSettingsView(updater: updaterController.updater)
                }
            }

            Section {
                Button(String(localized: "About Here Island")) {
                    AboutWindowController.shared.openAbout()
                }
                Button(String(localized: "Quit"), role: .destructive) {
                    NSApplication.shared.terminate(self)
                }
                .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
            }
        }
    }

    private var availableMediaControllers: [MediaControllerType] {
        if musicManager.isNowPlayingDeprecated {
            return [.appleMusic]
        }
        return MediaControllerType.allCases
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
    private var screensHiddenForFullscreen: Set<String> = []
    private var windowSizeUpdateWorkItem: DispatchWorkItem?
    private var closeNotchWorkItem: DispatchWorkItem?
    private var audioTapStopWorkItem: DispatchWorkItem?
    private var previousScreens: [NSScreen]?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowSizeUpdateWorkItem?.cancel()
        audioTapStopWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
        AudioTap.shared.stopCapture()
    }

    /// Process Tap must be torn down when idle — soft-pausing still keeps the
    /// system “using microphone / system audio” indicator visible.
    private func syncAudioTapCapture() {
        let enabled = Defaults[.enableRealTimeWaveform]
        let shouldCapture = enabled && MusicManager.shared.isPlaying

        audioTapStopWorkItem?.cancel()
        audioTapStopWorkItem = nil

        if shouldCapture {
            AudioTap.shared.setWantsCapture(true)
        } else if enabled {
            let work = DispatchWorkItem {
                AudioTap.shared.setWantsCapture(false)
            }
            audioTapStopWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        } else {
            AudioTap.shared.setWantsCapture(false)
        }
    }

    @objc func onScreenLocked(_: Notification) {
        hideWindowsForLock()
    }

    @objc func onScreenUnlocked(_: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.restoreWindowsAfterLock()
            self?.adjustWindowPosition(changeAlpha: true)
            self?.applyFullscreenWindowVisibility()
        }
    }

    private func hideWindowsForLock() {
        guard !windowsHiddenForLock else { return }
        windowsHiddenForLock = true
        if DisplayDestination.showsOnAllDisplays {
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
    }

    /// Order the notch window out on each display that has a native-fullscreen app.
    /// Independent of the lock-screen 1s restore. No-op while locked.
    private func applyFullscreenWindowVisibility() {
        guard !windowsHiddenForLock else { return }
        let enabled = Defaults[.hideWhenFullscreen]
        let status = FullscreenMediaDetector.shared.fullscreenStatus

        if DisplayDestination.showsOnAllDisplays {
            for (screen, window) in windows {
                applyFullscreenVisibility(to: window, screenName: screen.localizedName, enabled: enabled, status: status)
            }
        } else if let window {
            let screen = resolvedTargetScreen()
            applyFullscreenVisibility(to: window, screenName: screen.localizedName, enabled: enabled, status: status)
        }
    }

    private func applyFullscreenVisibility(
        to window: NSWindow,
        screenName: String,
        enabled: Bool,
        status: [String: Bool]
    ) {
        let shouldHide = enabled && (status[screenName] ?? false)
        if shouldHide {
            window.alphaValue = 0
            window.orderOut(nil)
            screensHiddenForFullscreen.insert(screenName)
        } else {
            screensHiddenForFullscreen.remove(screenName)
            window.orderFrontRegardless()
            window.alphaValue = 1
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        if shouldInvert ? !DisplayDestination.showsOnAllDisplays : DisplayDestination.showsOnAllDisplays {
            for (screen, window) in windows {
                viewModels[screen]?.onViewTeardown?()
                viewModels[screen]?.onViewTeardown = nil
                window.close()
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window {
            vm.onViewTeardown?()
            vm.onViewTeardown = nil
            window.close()
            self.window = nil
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
        return minimalisticOpenNotchSize()
    }

    private func adjustedSizeForScreen(_ size: CGSize, screen: NSScreen) -> CGSize {
        var adjusted = size
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

        if DisplayDestination.showsOnAllDisplays {
            for (screen, window) in windows {
                apply(window, screen)
            }
        } else if let window {
            apply(window, window.screen ?? resolvedTargetScreen())
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
        Publishers.CombineLatest(
            Defaults.publisher(.enableRealTimeWaveform, options: [.initial]),
            MusicManager.shared.$isPlaying
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            self?.syncAudioTapCapture()
        }
        .store(in: &cancellables)

        coordinator.$currentView
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateWindowSizeIfNeeded() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        Defaults.publisher(.displayDestination, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                reconcileDisplayDestination()
                let wasAll = change.oldValue == DisplayDestination.allDisplays
                let isAll = Defaults[.displayDestination] == DisplayDestination.allDisplays
                if wasAll != isAll {
                    self?.handleShowOnAllDisplaysChanged()
                } else if !isAll {
                    self?.handlePreferredScreenChanged()
                }
            }
            .store(in: &cancellables)
        Defaults.publisher(.showWindowShadow, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.setWindowShadow(change.newValue)
            }
            .store(in: &cancellables)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(onScreenLocked(_:)),
            name: NSNotification.Name(rawValue: "com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(onScreenUnlocked(_:)),
            name: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"), object: nil)

        if !DisplayDestination.showsOnAllDisplays {
            reconcileDisplayDestination()
            let screen = resolvedTargetScreen()
            vm.setScreen(screen.localizedName)
            window = createDynamicIslandWindow(
                for: screen,
                with: vm
            )
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        previousScreens = NSScreen.screens
        debouncedUpdateWindowSize()

        FullscreenMediaDetector.shared.$fullscreenStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyFullscreenWindowVisibility()
            }
            .store(in: &cancellables)
        Defaults.publisher(.hideWhenFullscreen)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyFullscreenWindowVisibility()
            }
            .store(in: &cancellables)
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens
        defer { previousScreens = currentScreens }
        reconcileDisplayDestination()
        cleanupWindows()
        if !DisplayDestination.showsOnAllDisplays {
            let screen = resolvedTargetScreen()
            vm.setScreen(screen.localizedName)
            window = createDynamicIslandWindow(
                for: screen,
                with: vm
            )
        }
        adjustWindowPosition(changeAlpha: true)
    }

    private func handleShowOnAllDisplaysChanged() {
        cleanupWindows(shouldInvert: true)
        if !DisplayDestination.showsOnAllDisplays {
            let screen = resolvedTargetScreen()
            vm.setScreen(screen.localizedName)
            let window = createDynamicIslandWindow(
                for: screen,
                with: vm
            )
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            window = nil
            adjustWindowPosition(changeAlpha: true)
        }
    }

    private func handlePreferredScreenChanged() {
        guard let window else {
            let screen = resolvedTargetScreen()
            vm.setScreen(screen.localizedName)
            self.window = createDynamicIslandWindow(for: screen, with: vm)
            adjustWindowPosition(changeAlpha: true)
            return
        }
        let screen = resolvedTargetScreen()
        vm.setScreen(screen.localizedName)
        positionWindow(window, on: screen, changeAlpha: false)
        updateWindowSizeIfNeeded()
    }

    private func setWindowShadow(_ enabled: Bool) {
        window?.hasShadow = enabled
        for window in windows.values {
            window.hasShadow = enabled
        }
    }

    private func resolvedTargetScreen() -> NSScreen {
        resolveNotchHostScreen() ?? NSScreen.screens.first!
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if DisplayDestination.showsOnAllDisplays {
            let screens = NSScreen.screens
            for screen in screens {
                if windows[screen] == nil {
                    let viewModel = DynamicIslandViewModel(screen: screen.localizedName)
                    let window = createDynamicIslandWindow(for: screen, with: viewModel)
                    windows[screen] = window
                    viewModels[screen] = viewModel
                } else {
                    viewModels[screen]?.setScreen(screen.localizedName)
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
            let screen = resolvedTargetScreen()
            vm.setScreen(screen.localizedName)
            positionWindow(window, on: screen, changeAlpha: changeAlpha)
        }
        updateWindowSizeIfNeeded()
        applyFullscreenWindowVisibility()
    }
}
