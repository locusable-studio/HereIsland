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

import SwiftUI
import Defaults

#if canImport(AppKit)
import AppKit
#endif

struct MinimalisticMusicPlayerView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID
    private let skipMagnitude: CGFloat = 8

    var body: some View {
        if !musicManager.hasActiveSession {
            // Nothing playing state
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    Image(systemName: "music.note.slash")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(.gray)
                    Text(String(localized: "Nothing Playing"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }

                Spacer(minLength: 0)

            }
            .padding(.horizontal, shouldUseDynamicIslandMode(for: vm.screen) ? -4 : 12)
            .padding(.vertical, shouldUseDynamicIslandMode(for: vm.screen) ? 14 : 0)
            .frame(maxWidth: .infinity)
            .frame(height: calculateDynamicHeight())
            .animation(.smooth(duration: 0.3), value: dynamicHeightSignature)
        } else {
            VStack(spacing: 0) {
                if shouldUseDynamicIslandMode(for: vm.screen) {
                    GeometryReader { headerGeo in
                        let albumArtWidth: CGFloat = 50
                        let spacing: CGFloat = 10
                        let textWidth = max(0, headerGeo.size.width - albumArtWidth - spacing)
                        HStack(alignment: .center, spacing: spacing) {
                            MinimalisticAlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                                .frame(width: albumArtWidth, height: albumArtWidth)

                            VStack(alignment: .leading, spacing: 1) {
                                if !musicManager.songTitle.isEmpty {
                                    MusicTitleMarqueeView(
                                        text: musicManager.songTitle,
                                        isExplicit: musicManager.isCurrentTrackExplicit,
                                        font: .system(size: 12, weight: .semibold),
                                        nsFont: .subheadline,
                                        textColor: .white,
                                        frameWidth: textWidth,
                                        badgeHeight: 13
                                    )
                                }

                                Text(musicManager.artistName)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                                    .lineLimit(1)

                            }
                            .frame(width: textWidth, alignment: .leading)
                        }
                    }
                    .frame(height: 50)
                } else {
                    notchHuggingHeader
                }

                // Compact progress bar
                progressBar
                    .padding(.top, shouldUseDynamicIslandMode(for: vm.screen) ? 6 : 4)
                
                // Compact playback controls
                playbackControls
                    .padding(.top, 4)

            }
            .padding(.horizontal, shouldUseDynamicIslandMode(for: vm.screen) ? -4 : 12)
            .padding(.top, shouldUseDynamicIslandMode(for: vm.screen) ? 14 : 10)
            .padding(.bottom, shouldUseDynamicIslandMode(for: vm.screen) ? 14 : 10)
            .frame(maxWidth: .infinity)
            .frame(height: calculateDynamicHeight(), alignment: .top)
            .animation(.smooth(duration: 0.3), value: dynamicHeightSignature)
        }
    }

    private var brandAccentColor: Color {
        musicManager.brandAccentColor
    }

    private var dynamicHeightSignature: Int {
        shouldUseDynamicIslandMode(for: vm.screen) ? 1000 : 0
    }

    private func calculateDynamicHeight() -> CGFloat {
        let isDynamicIsland = shouldUseDynamicIslandMode(for: vm.screen)

        if isDynamicIsland {
            var height: CGFloat = 50 // header
            height += 6 + 4          // progress bar top padding + bar
            height += 54 + 2         // controls + top padding
            height += 14 // top padding
            height += 14 // bottom padding
            return height
        }

        // Notch mode: tighter height for U-shaped layout.
        // The album art is pulled UP into the notch header area, so the
        // visible header in-flow is only the title + artist text (~26pt).
        var height: CGFloat = 26 // reduced header (text only; art overlaps upward)
        height += 4 + 4          // progress bar top padding + bar
        height += 54 + 2         // controls + top padding
        height += 10 // top padding
        height += 10 // bottom padding
        return height
    }

    // MARK: - U-Shaped Notch-Hugging Header

    /// Layout that wraps content around the physical notch cutout.
    private var notchHuggingHeader: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let albumArtSize: CGFloat = 50
            let notchHeight = vm.effectiveClosedNotchHeight
            let pullUp = max(notchHeight - 4, 20)
            
            ZStack(alignment: .top) {
                // ── Left: Album art ──
                HStack {
                    MinimalisticAlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                        .frame(width: albumArtSize, height: albumArtSize)
                    Spacer()
                }
                .offset(y: -pullUp)
                .frame(width: totalWidth)

                // ── Center: Title + Artist (below the notch) ──
                VStack(alignment: .leading, spacing: 1) {
                    if !musicManager.songTitle.isEmpty {
                        let textAreaWidth = max(0, totalWidth - albumArtSize - 10)
                        MusicTitleMarqueeView(
                            text: musicManager.songTitle,
                            isExplicit: musicManager.isCurrentTrackExplicit,
                            font: .system(size: 12, weight: .semibold),
                            nsFont: .subheadline,
                            textColor: .white,
                            frameWidth: textAreaWidth,
                            badgeHeight: 13
                        )
                    }

                    Text(musicManager.artistName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, albumArtSize + 10)
                // Position so the bottom of the artist text aligns with the
                // bottom of the album art (which was pulled up by pullUp).
                .offset(y: albumArtSize - pullUp - 28)
            }
        }
        .frame(height: 26) // Only the text portion is in-flow; album art overlaps upward
    }
    
    // MARK: - Progress Bar (Full Width)
    
    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double = MusicManager.shared.estimatedPlaybackPosition()
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    
    /// Whether the progress timeline should be paused (no ticks).
    private var isProgressTimelinePaused: Bool {
        !musicManager.isPlaying || musicManager.isLiveStream || musicManager.playbackRate <= 0
    }

    private var progressBar: some View {
        TimelineView(
            .animation(
                paused: isProgressTimelinePaused
            )
        ) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: Binding(
                    get: { musicManager.songDuration },
                    set: { musicManager.songDuration = $0 }
                ),
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                isLiveStream: musicManager.isLiveStream,
                onValueChange: { newValue in
                    musicManager.seek(to: newValue)
                },
                labelLayout: .inline,
                trailingLabel: .remaining,
                restingTrackHeight: 7,
                draggingTrackHeight: 11
            )
        }
        .onAppear {
            sliderValue = musicManager.estimatedPlaybackPosition()
        }
        .onChange(of: musicManager.isLiveStream) { _, isLive in
            if isLive {
                dragging = false
                sliderValue = 0
            }
        }
    }

    // MARK: - Playback Controls (Larger)
    
    private var playbackControls: some View {
        HStack(spacing: 10) {
            ForEach(Array(MusicControlButton.fixedLayout.enumerated()), id: \.offset) { _, control in
                slotView(for: control)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    private var playPauseButton: some View {
        MinimalisticSquircircleButton(
            icon: musicManager.isPlaying ? (musicManager.isLiveStream ? "stop.fill" : "pause.fill") : "play.fill",
            fontSize: 26,
            fontWeight: .semibold,
            frameSize: CGSize(width: 54, height: 54),
            cornerRadius: 22,
            foregroundColor: .white,
            pressEffect: .none,
            symbolEffectStyle: .replace,
            action: {
                musicManager.togglePlay()
            }
        )
    }
    
    private struct SkipTrigger {
        let token: Int
        let pressEffect: MinimalisticSquircircleButton.PressEffect
    }

    private func controlButton(
        icon: String,
        size: CGFloat = 18,
        isActive: Bool = false,
        activeColor: Color? = nil,
        pressEffect: MinimalisticSquircircleButton.PressEffect = .none,
        symbolEffect: MinimalisticSquircircleButton.SymbolEffectStyle = .none,
        trigger: SkipTrigger? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let resolvedActiveColor = activeColor ?? brandAccentColor
        return MinimalisticSquircircleButton(
            icon: icon,
            fontSize: size,
            fontWeight: .medium,
            frameSize: CGSize(width: 36, height: 36),
            cornerRadius: 14,
            foregroundColor: isActive ? resolvedActiveColor : .white.opacity(0.85),
            pressEffect: pressEffect,
            symbolEffectStyle: symbolEffect,
            externalTriggerToken: trigger?.token,
            externalTriggerEffect: trigger?.pressEffect,
            action: action
        )
    }

    @ViewBuilder
    private func slotView(for control: MusicControlButton) -> some View {
        switch control {
        case .playPause:
            playPauseButton
        case .trackBackward:
            controlButton(
                icon: "backward.fill",
                size: 18,
                pressEffect: .nudge(-skipMagnitude),
                symbolEffect: .replace,
                trigger: skipGestureTrigger(for: .trackBackward),
                action: { musicManager.previousTrack() }
            )
        case .trackForward:
            controlButton(
                icon: "forward.fill",
                size: 18,
                pressEffect: .nudge(skipMagnitude),
                symbolEffect: .replace,
                trigger: skipGestureTrigger(for: .trackForward),
                action: { musicManager.nextTrack() }
            )
        case .shuffle:
            controlButton(icon: "shuffle", isActive: musicManager.isShuffled) {
                musicManager.toggleShuffle()
            }
        case .repeatMode:
            controlButton(icon: repeatIcon, isActive: musicManager.repeatMode != .off, symbolEffect: .replace) {
                musicManager.toggleRepeat()
            }
        }
    }

    private func skipGestureTrigger(for control: MusicControlButton) -> SkipTrigger? {
        guard let pulse = musicManager.skipGesturePulse else { return nil }

        switch control {
        case .trackBackward where pulse.behavior == .track && pulse.direction == .backward:
            return SkipTrigger(token: pulse.token, pressEffect: .nudge(-skipMagnitude))
        case .trackForward where pulse.behavior == .track && pulse.direction == .forward:
            return SkipTrigger(token: pulse.token, pressEffect: .nudge(skipMagnitude))
        default:
            return nil
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

// MARK: - Minimalistic Album Art

struct MinimalisticAlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID

    private var usesLiveCanvasArtwork: Bool {
        musicManager.videoArtworkURL != nil
    }

    private var albumArtCornerRadius: CGFloat {
        musicManager.albumArt.size.width / musicManager.albumArt.size.height > 1.0 ? 4 : 12
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }
    
    private var albumArtBackground: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(
                DynamicIslandArtworkSourceView(
                    cornerRadius: albumArtCornerRadius,
                    contentMode: .fill
                )
            )
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: albumArtCornerRadius))
            .scaleEffect(x: 1.04, y: 1.05)
            .rotationEffect(.degrees(92))
            .blur(radius: 14)
            .opacity(
                usesLiveCanvasArtwork
                    ? (musicManager.isPlaying ? 0.35 : 0.12)
                    : min(0.28, 1 - max(musicManager.albumArt.getBrightness(), 0.3))
            )
            .shadow(
                color: Color(nsColor: musicManager.avgColor).opacity(usesLiveCanvasArtwork ? 0.14 : 0.08),
                radius: usesLiveCanvasArtwork ? 6 : 4,
                x: 0,
                y: 0
            )
    }
    
    private var albumArtButton: some View {
        Button {
            musicManager.openMusicApp()
        } label: {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .background(
                        DynamicIslandArtworkSourceView(
                            cornerRadius: albumArtCornerRadius,
                            contentMode: .fit
                        )
                    )
                    .clipped()
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .albumArtFlip(angle: musicManager.flipAngle)
                    .parallax3D()
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(musicManager.isPlaying ? 1 : 0.4)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
    }
}

// MARK: - Hover-highlighted control button

private struct MinimalisticSquircircleButton: View {
    let icon: String
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let frameSize: CGSize
    let cornerRadius: CGFloat
    let foregroundColor: Color
    let pressEffect: PressEffect
    let symbolEffectStyle: SymbolEffectStyle
    let externalTriggerToken: Int?
    let externalTriggerEffect: PressEffect?
    let action: () -> Void

    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @State private var wiggleToken: Int = 0
    @State private var lastExternalTriggerToken: Int?

    init(
        icon: String,
        fontSize: CGFloat,
        fontWeight: Font.Weight,
        frameSize: CGSize,
        cornerRadius: CGFloat,
        foregroundColor: Color,
        pressEffect: PressEffect = .none,
        symbolEffectStyle: SymbolEffectStyle = .none,
        externalTriggerToken: Int? = nil,
        externalTriggerEffect: PressEffect? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.frameSize = frameSize
        self.cornerRadius = cornerRadius
        self.foregroundColor = foregroundColor
        self.pressEffect = pressEffect
        self.symbolEffectStyle = symbolEffectStyle
        self.externalTriggerToken = externalTriggerToken
        self.externalTriggerEffect = externalTriggerEffect
        self.action = action
    }

    var body: some View {
        Button {
            triggerPressEffect()
            action()
        } label: {
            iconView()
                .frame(width: frameSize.width, height: frameSize.height)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovering ? Color.white.opacity(0.18) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: pressOffset)
        .rotationEffect(.degrees(rotationAngle))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
        .onChange(of: externalTriggerToken) { _, newToken in
            guard let newToken, newToken != lastExternalTriggerToken else { return }
            lastExternalTriggerToken = newToken
            triggerPressEffect(override: externalTriggerEffect)
        }
    }

    private func triggerPressEffect(override: PressEffect? = nil) {
        let effect = override ?? pressEffect

        switch effect {
        case .none:
            return
        case .nudge(let amount):
            withAnimation(.spring(response: 0.16, dampingFraction: 0.72)) {
                pressOffset = amount
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                    pressOffset = 0
                }
            }
        case .wiggle(let direction):
            wiggleToken += 1
            let angle: Double = direction == .clockwise ? 11 : -11

            withAnimation(.spring(response: 0.18, dampingFraction: 0.52)) {
                rotationAngle = angle
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                    rotationAngle = 0
                }
            }
        }
    }

    @ViewBuilder
    private func iconView() -> some View {
        let image = Image(systemName: icon)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundColor(foregroundColor)

        switch symbolEffectStyle {
        case .none:
            image
        case .replace:
            image.contentTransition(.symbolEffect(.replace))
        case .bounce:
            image.symbolEffect(.bounce, value: icon)
        case .replaceAndBounce:
            image
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: icon)
        case .wiggle:
            image.symbolEffect(
                .wiggle.byLayer,
                options: .nonRepeating,
                value: wiggleToken
            )
        }
    }

    enum PressEffect {
        case none
        case nudge(CGFloat)
        case wiggle(WiggleDirection)
    }

    enum SymbolEffectStyle {
        case none
        case replace
        case bounce
        case replaceAndBounce
        case wiggle
    }

    enum WiggleDirection {
        case clockwise
        case counterClockwise
    }
}
