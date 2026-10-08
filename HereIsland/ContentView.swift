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
    /// Cover drawn by an Apple Music peek. Never `albumArt` (previous cover or Music icon).
    @State private var peekArtwork: NSImage?
    @State private var peekCoverRequestID: UUID?
    @State private var peekUsesIsolatedCover = false
    @State private var waitingForPeekCover = false

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

    /// Persistent closed music pill follows the live-activity preference.
    /// Quick peek still mounts that same bar while `isFlashing`, then drops it
    /// when the flash ends so a disabled live activity stays off.
    /// Apple Music peeks wait for a decoded cover (or 600ms) before setting `isFlashing`.
    private var showsClosedMusicActivity: Bool {
        vm.notchState == .closed
            && !vm.hideOnClosed
            && (coordinator.musicLiveActivityEnabled || isFlashing)
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
    /// Same budget as Apple Music `artworkTimeoutFromTrackChange`.
    /// Not the 250ms shared-`albumArt` linger.
    private static let peekCoverWait: Duration = .milliseconds(600)
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
        .onChange(of: musicManager.appleMusicPeekRevision) { _, _ in
            applyLateAppleMusicPeekCover()
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
            // Apple Music peeks take their color from the new cover only.
            guard isFlashing, !peekUsesIsolatedCover else { return }
            peekTitleColor = playerTint.resolvedColor(albumArt: newColor)
        }
        .onChange(of: musicManager.appleMusicPeekAccentColor) { _, newColor in
            guard isFlashing, peekUsesIsolatedCover, peekArtwork != nil else { return }
            guard playerTint == .albumArt else { return }
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
            // Apple Music peeks draw only a decoded cover for this request, or
            // nothing. Never albumArt (previous cover or Music icon).
            // The persistent bar uses the shared slot: a real cover, or an empty
            // placeholder while a skip is still resolving. The Music icon is
            // only the confirmed miss.
            if isFlashing && peekUsesIsolatedCover {
                if let peekArtwork {
                    Image(nsImage: peekArtwork)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .frame(width: wing, height: height)
                        .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                } else {
                    Color.clear
                        .frame(width: wing, height: height)
                        .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                }
            } else if musicManager.albumArtSlotIsEmpty {
                Color.clear
                    .frame(width: wing, height: height)
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            } else {
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(width: wing, height: height)
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            }

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
        waitingForPeekCover = false

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
        // A newer skip may already have replaced `songTitle` before this
        // onChange runs. Don't pair that title with the latest cover.
        guard trimmed == normalizedTitle(musicManager.songTitle) else { return }

        // Apple Music: don't mount the peek until the new cover is decoded, or
        // 600ms passes. `musicLiveActivityEnabled` defaults true and has no UI,
        // so the live-activity flag must not choose the shared cover here.
        // Other sources keep the old timing.
        let isolateCover = musicManager.pendingTitleIsAppleMusic
        if isolateCover {
            peekCoverRequestID = musicManager.appleMusicPeekRequestID
            if let image = musicManager.appleMusicPeekImage {
                let requestID = peekCoverRequestID
                debounceTask = Task { @MainActor in
                    guard !Task.isCancelled else { return }
                    guard normalizedTitle(musicManager.songTitle) == trimmed else { return }
                    guard musicManager.appleMusicPeekRequestID == requestID else { return }
                    startFlash(title: trimmed, artwork: image, isolateCover: true)
                }
                return
            }
            if isFlashing {
                retractFlash()
            }
            let requestID = peekCoverRequestID
            waitingForPeekCover = true
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: Self.peekCoverWait)
                guard !Task.isCancelled else { return }
                waitingForPeekCover = false
                guard vm.notchState == .closed, !vm.hideOnClosed else { return }
                guard !isFlashing else { return }
                let settled = normalizedTitle(musicManager.songTitle)
                guard settled == trimmed, isFlashableTitle(settled) else { return }
                let image = musicManager.appleMusicPeekRequestID == requestID
                    ? musicManager.appleMusicPeekImage
                    : nil
                startFlash(title: settled, artwork: image, isolateCover: true)
            }
            return
        }

        debounceTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            guard vm.notchState == .closed, !vm.hideOnClosed else {
                rememberTitle(musicManager.songTitle)
                return
            }
            let settled = normalizedTitle(musicManager.songTitle)
            guard isFlashableTitle(settled), settled != lastFlashedTitle else { return }
            startFlash(title: settled, artwork: nil, isolateCover: false)
        }
    }

    /// Catalog (or delayed script art) finished while this peek is still the current request.
    private func applyLateAppleMusicPeekCover() {
        guard waitingForPeekCover || (isFlashing && peekUsesIsolatedCover) else { return }
        guard musicManager.appleMusicPeekRequestID == peekCoverRequestID else { return }
        guard let image = musicManager.appleMusicPeekImage else { return }
        if isFlashing && peekUsesIsolatedCover {
            peekArtwork = image
            peekTitleColor = isolatedPeekTitleColor(hasCover: true)
            return
        }
        guard waitingForPeekCover else { return }
        let title = normalizedTitle(musicManager.songTitle)
        guard isFlashableTitle(title) else { return }
        waitingForPeekCover = false
        debounceTask?.cancel()
        debounceTask = nil
        startFlash(title: title, artwork: image, isolateCover: true)
    }

    private func peekSlotWidth(for title: String) -> CGFloat {
        let height = max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
        let wing = max(0, height)
        let needed = ceil((title as NSString).size(withAttributes: [.font: flashTitleMeasurementFont]).width)
        let maxSideGrow = Self.flashWidthExtraMax / 2
        return min(max(needed, wing), wing + maxSideGrow)
    }

    /// Apple Music peek title. From the new cover once that sample exists;
    /// otherwise a neutral white (album-art tint) or the non-cover tint.
    /// Never `avgColor`, which may still be the previous cover or an icon sample.
    private func isolatedPeekTitleColor(hasCover: Bool) -> Color {
        if playerTint == .albumArt {
            guard hasCover else { return .white }
            return playerTint.resolvedColor(albumArt: musicManager.appleMusicPeekAccentColor)
        }
        return playerTint.resolvedColor(albumArt: .white)
    }

    private func startFlash(title: String, artwork: NSImage?, isolateCover: Bool) {
        guard showTitleOnTrackChange else {
            lastFlashedTitle = title
            return
        }
        flashTask?.cancel()
        lastFlashedTitle = title
        peekTitle = title
        peekUsesIsolatedCover = isolateCover
        peekArtwork = isolateCover ? artwork : nil
        peekTitleColor = isolateCover
            ? isolatedPeekTitleColor(hasCover: artwork != nil)
            : playerTint.resolvedColor(albumArt: musicManager.avgColor)
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
        peekUsesIsolatedCover = false
        peekArtwork = nil
    }

    private func cancelFlashForOpen() {
        debounceTask?.cancel()
        debounceTask = nil
        waitingForPeekCover = false
        flashTask?.cancel()
        flashTask = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isFlashing = false
            peekTitle = ""
            peekUsesIsolatedCover = false
            peekArtwork = nil
        }
    }

    private func handleFlashFinished() {
        guard isFlashing, vm.notchState == .closed else { return }
        retractFlash()
    }
}
