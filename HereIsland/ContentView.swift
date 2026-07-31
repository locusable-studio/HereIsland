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

    @Namespace private var albumArtNamespace
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?

    private var isIslandMode: Bool {
        shouldUseDynamicIslandMode(for: vm.screen)
    }

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

    private var pillTopOffset: CGFloat {
        isIslandMode ? dynamicIslandTopOffset : 0
    }

    /// Always the open notch size — matches original ContentView.dynamicNotchSize.
    /// Closed content is clipped inside this frame; window size stays the same.
    private var dynamicNotchSize: CGSize {
        minimalisticOpenNotchSize(isDynamicIslandMode: isIslandMode)
    }

    private var showsClosedMusicActivity: Bool {
        vm.notchState == .closed
            && !vm.hideOnClosed
            && coordinator.musicLiveActivityEnabled
            && (musicManager.isPlaying || (!musicManager.isPlayerIdle && musicManager.bundleIdentifier != nil))
    }

    private var pillCornerRadius: CGFloat {
        if vm.notchState == .open {
            return cornerInsets.opened.top
        }
        return max(vm.closedNotchSize.height / 2, dynamicIslandPillCornerRadiusInsets.closed.minimalistic)
    }

    private var notchTopRadius: CGFloat {
        vm.notchState == .open ? cornerInsets.opened.top : cornerInsets.closed.top
    }

    private var notchBottomRadius: CGFloat {
        vm.notchState == .open ? cornerInsets.opened.bottom : cornerInsets.closed.bottom
    }

    var body: some View {
        ZStack(alignment: .top) {
            notchChrome
        }
        .frame(
            maxWidth: (dynamicNotchSize.width
                + (vm.notchState == .open ? 24 : 0)).rounded(),
            maxHeight: (dynamicNotchSize.height
                + (vm.notchState == .open ? 12 : 0)
                + (isIslandMode ? dynamicIslandTopOffset : 0)).rounded(),
            alignment: .top
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("HereIslandNotch")
        .onAppear {
            coordinator.currentView = .home
            if vm.screen == nil {
                vm.screen = NSScreen.main?.localizedName
            }
            // Ensure window stays at open size even when starting closed.
            AppDelegate.shared?.ensureWindowSize(
                dynamicNotchSize,
                animated: false,
                force: true
            )
        }
        .onDisappear {
            hoverTask?.cancel()
        }
    }

    private var notchChrome: some View {
        Group {
            if isIslandMode {
                chromeBase
                    .clipShape(DynamicIslandPillShape(cornerRadius: pillCornerRadius))
                    .compositingGroup()
                    .padding(.top, pillTopOffset)
                    .contentShape(DynamicIslandPillShape(cornerRadius: pillCornerRadius))
            } else {
                chromeBase
                    .clipShape(NotchShape(topCornerRadius: notchTopRadius, bottomCornerRadius: notchBottomRadius))
                    .compositingGroup()
                    .contentShape(NotchShape(topCornerRadius: notchTopRadius, bottomCornerRadius: notchBottomRadius))
            }
        }
        .onHover(perform: handleHover)
        // Match original: animation driven by state value, not withAnimation(wrong spring).
        .animation(.bouncy.speed(1.2), value: isHovering)
        .animation(vm.notchState == .open ? openSpring : closeSpring, value: vm.notchState)
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
                .frame(height: (isIslandMode ? nil : max(24, vm.effectiveClosedNotchHeight)))
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
        let center = max(vm.closedNotchSize.width + (isHovering ? 8 : 0), 96)
        return HStack(spacing: 0) {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(width: wing, height: height)
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)

            Rectangle()
                .fill(.black)
                .frame(width: center, height: height)

            Rectangle()
                .fill(Color(nsColor: musicManager.avgColor).spectrogramGradient())
                .mask {
                    AudioVisualizerView(isPlaying: .constant(musicManager.isPlaying))
                        .frame(width: max(wing - 4, 12), height: max(height - 4, 10))
                }
                .frame(width: wing, height: height)
                .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
        }
        .frame(width: wing + center + wing, height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
    }

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        if hovering {
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
        if enableHaptics {
            // NSHapticFeedbackManager is ignored for .nonactivatingPanel; use MTActuator.
            HapticFeedback.perform()
        }
        // Implicit animation via .animation(_:value: vm.notchState)
        vm.open()
    }

    private func closeNotch() {
        vm.close()
    }
}
