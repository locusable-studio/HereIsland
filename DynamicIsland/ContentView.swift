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

    @Default(.enableShadow) private var enableShadow
    @Default(.cornerRadiusScaling) private var cornerRadiusScaling
    @Default(.useModernCloseAnimation) private var useModernCloseAnimation
    @Default(.enableGestures) private var enableGestures
    @Default(.closeGestureEnabled) private var closeGestureEnabled
    @Default(.reverseScrollGestures) private var reverseScrollGestures
    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.enableHaptics) private var enableHaptics
    @Default(.inlineHUD) private var inlineHUD
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.coloredSpectrogram) private var coloredSpectrogram

    @Namespace private var albumArtNamespace
    @State private var isHovering = false
    @State private var gestureProgress: CGFloat = 0
    @State private var hoverTask: Task<Void, Never>?

    private var isIslandMode: Bool {
        shouldUseDynamicIslandMode(for: vm.screen)
    }

    private var currentShadowPadding: CGFloat {
        notchShadowPaddingValue(isMinimalistic: true)
    }

    private var cornerInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) {
        (opened: minimalisticCornerRadiusInsets.opened, closed: cornerRadiusInsets.closed)
    }

    /// Horizontal inset that keeps the clipped notch shape aligned with the physical cutout.
    private var notchHorizontalPadding: CGFloat {
        if vm.notchState == .open {
            if cornerRadiusScaling {
                return cornerInsets.opened.top - 5
            }
            return cornerInsets.opened.bottom - 5
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
        (vm.notchState == .open && cornerRadiusScaling) ? cornerInsets.opened.top : cornerInsets.closed.top
    }

    private var notchBottomRadius: CGFloat {
        (vm.notchState == .open && cornerRadiusScaling) ? cornerInsets.opened.bottom : cornerInsets.closed.bottom
    }

    var body: some View {
        ZStack(alignment: .top) {
            notchChrome
        }
        .frame(
            maxWidth: (dynamicNotchSize.width
                + (vm.notchState == .open ? 24 : 0)
                + (isIslandMode ? dynamicIslandShadowInset * 2 : 0)).rounded(),
            maxHeight: (dynamicNotchSize.height
                + (vm.notchState == .open ? 12 : 0)
                + (isIslandMode
                    ? dynamicIslandTopOffset + dynamicIslandShadowInset * 2
                    : currentShadowPadding)).rounded(),
            alignment: .top
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            coordinator.currentView = .home
            if vm.screen == nil {
                vm.screen = NSScreen.main?.localizedName
            }
            // Ensure window stays at open size even when starting closed.
            AppDelegate.shared?.ensureWindowSize(
                addShadowPadding(to: dynamicNotchSize, isMinimalistic: true),
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
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && enableShadow) ? .black.opacity(0.6) : .clear,
                        radius: cornerRadiusScaling ? 10 : 5
                    )
                    .padding(.horizontal, dynamicIslandShadowInset)
                    .padding(.bottom, dynamicIslandShadowInset)
                    .padding(.top, pillTopOffset)
                    .padding(.bottom, currentShadowPadding)
                    .contentShape(DynamicIslandPillShape(cornerRadius: pillCornerRadius))
            } else {
                chromeBase
                    .clipShape(NotchShape(topCornerRadius: notchTopRadius, bottomCornerRadius: notchBottomRadius))
                    .compositingGroup()
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && enableShadow) ? .black.opacity(0.6) : .clear,
                        radius: cornerRadiusScaling ? 10 : 5
                    )
                    .padding(.top, pillTopOffset)
                    .padding(.bottom, currentShadowPadding)
                    .contentShape(NotchShape(topCornerRadius: notchTopRadius, bottomCornerRadius: notchBottomRadius))
            }
        }
        .onHover(perform: handleHover)
        .onTapGesture {
            guard vm.notchState == .closed else { return }
            if enableHaptics {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
            openNotch()
        }
        .gesture(openCloseDragGesture)
        // Match original: animation driven by state value, not withAnimation(wrong spring).
        .animation(.bouncy.speed(1.2), value: isHovering)
        .animation(vm.notchState == .open ? openSpring : closeSpring, value: vm.notchState)
        .animation(.smooth, value: gestureProgress)
    }

    private var chromeBase: some View {
        notchBody
            .frame(alignment: .top)
            .padding(.horizontal, notchHorizontalPadding)
            .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
            .background(.black)
    }

    private var openSpring: Animation {
        useModernCloseAnimation
            ? .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
            : .spring.speed(1.2)
    }

    private var closeSpring: Animation {
        useModernCloseAnimation
            ? .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
            : .spring.speed(1.2)
    }

    private var openCloseDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard enableGestures else { return }
                gestureProgress = value.translation.height
            }
            .onEnded { value in
                guard enableGestures else { return }
                defer { gestureProgress = 0 }
                if value.translation.height > 40, vm.notchState == .closed {
                    openNotch()
                } else if (closeGestureEnabled || reverseScrollGestures),
                          value.translation.height < -40,
                          vm.notchState == .open {
                    closeNotch()
                }
            }
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
            .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
            .opacity(abs(gestureProgress) > 0.3 ? min(abs(gestureProgress * 2), 0.8) : 1)
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
        let sneak = coordinator.sneakPeek
        if sneak.show && enableSneakPeek && isCoreHUD(sneak.type) {
            if inlineHUD {
                InlineHUD(
                    type: $coordinator.sneakPeek.type,
                    value: $coordinator.sneakPeek.value,
                    icon: $coordinator.sneakPeek.icon,
                    hoverAnimation: $isHovering,
                    gestureProgress: $gestureProgress
                )
            } else {
                SystemEventIndicatorModifier(
                    eventType: $coordinator.sneakPeek.type,
                    value: $coordinator.sneakPeek.value,
                    icon: $coordinator.sneakPeek.icon,
                    sendEventBack: { _ in }
                )
            }
        } else if showsClosedMusicActivity {
            closedMusicActivity
        } else {
            Color.clear
                .frame(width: max(vm.closedNotchSize.width - 20, 0))
        }
    }

    private func isCoreHUD(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .battery, .mic:
            return true
        default:
            return false
        }
    }

    private var closedMusicActivity: some View {
        let height = max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
        let wing = max(0, height + gestureProgress / 2)
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
                .overlay {
                    if coordinator.expandingView.show && coordinator.expandingView.type == .music {
                        HStack {
                            Text(musicManager.songTitle)
                                .lineLimit(1)
                                .foregroundStyle(coloredSpectrogram ? Color(nsColor: musicManager.avgColor) : .gray)
                                .padding(.leading, 8)
                            Spacer(minLength: vm.closedNotchSize.width)
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .foregroundStyle(coloredSpectrogram ? Color(nsColor: musicManager.avgColor) : .gray)
                                .padding(.trailing, 8)
                        }
                    }
                }

            Rectangle()
                .fill((coloredSpectrogram ? Color(nsColor: musicManager.avgColor) : Color.gray).spectrogramGradient())
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
            guard openNotchOnHover, vm.notchState == .closed else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(Defaults[.minimumHoverDuration] * 1000)))
                guard !Task.isCancelled else { return }
                openNotch()
            }
        } else {
            withAnimation(.bouncy.speed(1.2)) { isHovering = false }
            guard openNotchOnHover, vm.notchState == .open, !vm.isMediaOutputPopoverActive else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                closeNotch()
            }
        }
    }

    private func openNotch() {
        // Implicit animation via .animation(_:value: vm.notchState)
        vm.open()
    }

    private func closeNotch() {
        vm.close()
    }
}

