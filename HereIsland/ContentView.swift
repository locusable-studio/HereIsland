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

import Combine
import Defaults
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared

    @Default(.enableHaptics) private var enableHaptics
    @Default(.playerTint) private var playerTint
    @Default(.showTitleOnTrackChange) private var showTitleOnTrackChange

    @Namespace private var albumArtNamespace
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var isFlashing = false
    @State private var peekTitle = ""
    @State private var peekTitleColor: Color = .white
    @State private var peekSlotWidth: CGFloat = 0
    @State private var lastFlashedTitle = ""
    @State private var flashTask: Task<Void, Never>?
    @State private var debounceTask: Task<Void, Never>?

    private var cornerInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) {
        (opened: minimalisticCornerRadiusInsets.opened, closed: cornerRadiusInsets.closed)
    }

    /// Horizontal inset that keeps the clipped notch shape aligned with the physical cutout.
    private var notchHorizontalPadding: CGFloat {
        if vm.notchState == .open {
            return cornerInsets.opened.top - 5
        }
        return cornerInsets.closed.bottom
    }

    /// Always the open notch size — matches original ContentView.dynamicNotchSize.
    /// Closed content is clipped inside this frame; window size stays the same.
    private var dynamicNotchSize: CGSize {
        minimalisticOpenNotchSize()
    }

    private var showsClosedMusicActivity: Bool {
        vm.notchState == .closed
            && !vm.hideOnClosed
            && coordinator.musicLiveActivityEnabled
            && (musicManager.isPlaying || (!musicManager.isPlayerIdle && musicManager.bundleIdentifier != nil))
    }

    private var notchTopRadius: CGFloat {
        vm.notchState == .open ? cornerInsets.opened.top : cornerInsets.closed.top
    }

    private var notchBottomRadius: CGFloat {
        vm.notchState == .open ? cornerInsets.opened.bottom : cornerInsets.closed.bottom
    }

    private static let placeholderTitles: Set<String> = [
        "i'm handsome", "unknown", "not playing"
    ]
    private static let flashTitleFontSize: CGFloat = 12
    private static let flashWidthExtraMax: CGFloat = 80
    private var flashTitleFont: Font {
        .system(size: Self.flashTitleFontSize, weight: .medium, design: .rounded)
    }

    private var flashTitleMeasurementFont: NSFont {
        let base = NSFont.systemFont(ofSize: Self.flashTitleFontSize, weight: .medium)
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: rounded, size: Self.flashTitleFontSize) ?? base
        }
        return base
    }

    private func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isFlashableTitle(_ title: String) -> Bool {
        let trimmed = normalizedTitle(title)
        guard !trimmed.isEmpty else { return false }
        return !Self.placeholderTitles.contains(trimmed.lowercased())
    }

    private func rememberTitle(_ title: String) {
        let trimmed = normalizedTitle(title)
        if isFlashableTitle(trimmed) {
            lastFlashedTitle = trimmed
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            notchChrome
        }
        .frame(
            maxWidth: (dynamicNotchSize.width
                + (vm.notchState == .open ? 24 : 0)).rounded(),
            maxHeight: (dynamicNotchSize.height
                + (vm.notchState == .open ? 12 : 0)).rounded(),
            alignment: .top
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("HereIslandNotch")
        .onAppear {
            coordinator.currentView = .home
            if vm.screen == nil {
                vm.setScreen(resolveNotchHostScreen()?.localizedName)
            } else {
                vm.refreshClosedNotchSize()
            }
            // Ensure window stays at open size even when starting closed.
            AppDelegate.shared?.ensureWindowSize(
                dynamicNotchSize,
                animated: false,
                force: true
            )
            rememberTitle(musicManager.songTitle)
        }
        .onDisappear {
            hoverTask?.cancel()
            flashTask?.cancel()
            debounceTask?.cancel()
        }
        .onChange(of: musicManager.songTitle) { _, newTitle in
            handleSongTitleChange(newTitle)
        }
        .onChange(of: vm.notchState) { _, newState in
            if newState == .open {
                cancelFlashForOpen()
                rememberTitle(musicManager.songTitle)
            }
        }
        .onChange(of: showTitleOnTrackChange) { _, enabled in
            if !enabled {
                cancelFlashForOpen()
                rememberTitle(musicManager.songTitle)
            }
        }
        .onChange(of: musicManager.avgColor) { _, newColor in
            guard isFlashing else { return }
            peekTitleColor = playerTint.resolvedColor(albumArt: newColor)
        }
    }

    private var notchChrome: some View {
        chromeBase
            .clipShape(NotchShape(topCornerRadius: notchTopRadius, bottomCornerRadius: notchBottomRadius))
            .compositingGroup()
            .contentShape(NotchShape(topCornerRadius: notchTopRadius, bottomCornerRadius: notchBottomRadius))
            .onHover(perform: handleHover)
            // Match original: animation driven by state value, not withAnimation(wrong spring).
            .animation(.bouncy.speed(1.2), value: isHovering)
            .animation(vm.notchState == .open ? openSpring : closeSpring, value: vm.notchState)
            .animation(isFlashing ? flashSpring : closeSpring, value: isFlashing)
            // Retarget while peek is open only changes width — keep the same spring.
            .animation(flashSpring, value: peekSlotWidth)
    }

    private var chromeBase: some View {
        notchBody
            .frame(alignment: .top)
            .padding(.horizontal, notchHorizontalPadding)
            .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
            .background(.black)
    }

    private var openSpring: Animation {
        .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    }

    /// Peek grow/retract: no bounce. Overshoot was sliding the title clip under the glyphs.
    private var flashSpring: Animation {
        .spring(response: 0.36, dampingFraction: 1.0, blendDuration: 0)
    }

    private var closeSpring: Animation {
        .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    }

    @ViewBuilder
    private var notchBody: some View {
        VStack(spacing: 0) {
            closedOrHeaderRow
            ZStack {
                if vm.notchState == .open {
                    NotchHomeView(albumArtNamespace: albumArtNamespace)
                        .environmentObject(vm)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(vm.notchState == .open)
        }
    }

    @ViewBuilder
    private var closedOrHeaderRow: some View {
        if vm.notchState == .closed {
            closedContent
                .frame(height: max(vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), 0))
        } else {
            DynamicIslandHeader()
                .frame(height: max(24, vm.effectiveClosedNotchHeight))
        }
    }

    @ViewBuilder
    private var closedContent: some View {
        if showsClosedMusicActivity {
            closedMusicActivity
        } else {
            Color.clear
                .frame(width: max(vm.closedNotchSize.width - 20, 0))
        }
    }

    private var closedMusicActivity: some View {
        let height = max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
        let wing = max(0, height)
        let baseCenter = max(vm.closedNotchSize.width + (isHovering ? 8 : 0), 96)
        let closedWidth = wing + baseCenter + wing
        let titleWidth = isFlashing ? peekSlotWidth : 0
        let sideGrow = isFlashing ? max(titleWidth - wing, 0) : 0
        let titleInner = max(titleWidth, 8)
        return HStack(spacing: 0) {
            // Always bind live art — a flash snapshot goes stale when the
            // track changes again before peek retracts.
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(width: wing, height: height)
                .id(musicManager.artworkGeneration)
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)

            if isFlashing {
                Rectangle()
                    .fill(.clear)
                    .frame(width: sideGrow, height: height)
            }

            Rectangle()
                .fill(.black)
                .frame(width: baseCenter, height: height)

            if isFlashing {
                OneShotMarqueeText(
                    text: peekTitle,
                    font: flashTitleFont,
                    measurementFont: flashTitleMeasurementFont,
                    textColor: peekTitleColor,
                    frameWidth: titleInner,
                    holdDuration: 1.2,
                    onFinished: handleFlashFinished
                )
                .frame(width: titleWidth, height: height, alignment: .leading)
            } else {
                Rectangle()
                    .fill(playerTint.resolvedColor(albumArt: musicManager.avgColor))
                    .mask {
                        AudioVisualizerView(isPlaying: .constant(musicManager.isPlaying))
                            .frame(width: max(wing - 4, 12), height: max(height - 4, 10))
                    }
                    .frame(width: wing, height: height)
                    .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
            }
        }
        .frame(width: closedWidth + (sideGrow * 2), height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
    }

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        if hovering {
            // Open wins: cancel flash immediately, then take the existing hover-open path.
            cancelFlashForOpen()
            rememberTitle(musicManager.songTitle)
            withAnimation(.bouncy.speed(1.2)) { isHovering = true }
            guard vm.notchState == .closed else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                openNotch()
            }
        } else {
            withAnimation(.bouncy.speed(1.2)) { isHovering = false }
            guard vm.notchState == .open else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                closeNotch()
            }
        }
    }

    private func openNotch() {
        guard vm.notchState == .closed else { return }
        cancelFlashForOpen()
        if enableHaptics {
            // NSHapticFeedbackManager is ignored for .nonactivatingPanel; use MTActuator.
            HapticFeedback.perform()
        }
        // Implicit animation via .animation(_:value: vm.notchState)
        vm.open()
    }

    private func closeNotch() {
        rememberTitle(musicManager.songTitle)
        vm.close()
    }

    private func handleSongTitleChange(_ newTitle: String) {
        // No queue: latest title wins. If a peek is already open, retarget it
        // in place — tearing down and restarting leaves title/cover out of sync.
        debounceTask?.cancel()
        debounceTask = nil

        let trimmed = normalizedTitle(newTitle)
        guard vm.notchState == .closed, !vm.hideOnClosed else {
            rememberTitle(trimmed)
            return
        }
        guard showTitleOnTrackChange else {
            rememberTitle(trimmed)
            return
        }
        guard isFlashableTitle(trimmed) else { return }
        guard trimmed != lastFlashedTitle else { return }
        debounceTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            guard vm.notchState == .closed, !vm.hideOnClosed else {
                rememberTitle(musicManager.songTitle)
                return
            }
            let settled = normalizedTitle(musicManager.songTitle)
            guard isFlashableTitle(settled), settled != lastFlashedTitle else { return }
            startFlash(title: settled)
        }
    }

    private func peekSlotWidth(for title: String) -> CGFloat {
        let height = max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
        let wing = max(0, height)
        let needed = ceil((title as NSString).size(withAttributes: [.font: flashTitleMeasurementFont]).width)
        let maxSideGrow = Self.flashWidthExtraMax / 2
        return min(max(needed, wing), wing + maxSideGrow)
    }

    private func startFlash(title: String) {
        guard showTitleOnTrackChange else {
            lastFlashedTitle = title
            return
        }
        flashTask?.cancel()
        lastFlashedTitle = title
        peekTitle = title
        peekTitleColor = playerTint.resolvedColor(albumArt: musicManager.avgColor)
        peekSlotWidth = peekSlotWidth(for: title)
        isFlashing = true
        // Safety retract if the one-shot view never reports finished.
        flashTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            retractFlash()
        }
    }

    private func retractFlash() {
        flashTask?.cancel()
        flashTask = nil
        isFlashing = false
        peekTitle = ""
    }

    private func cancelFlashForOpen() {
        debounceTask?.cancel()
        debounceTask = nil
        flashTask?.cancel()
        flashTask = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isFlashing = false
            peekTitle = ""
        }
    }

    private func handleFlashFinished() {
        guard isFlashing, vm.notchState == .closed else { return }
        retractFlash()
    }
}
