/*
 * Here Island
 * Copyright (C) 2024-2026 Here Island Contributors
 *
 * Originally from boring.notch / Atoll
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

import Defaults
import SwiftUI

/// Fixed lock-screen media card. Reuses MusicManager + playerTint.
/// Glass card. Title / artist / progress / times follow playerTint (artist 0.85).
/// Play / prev / next stay white. Shuffle / repeat use playerTint when on, white 0.65 when off.
/// Artwork shadow is faint avgColor (0.08), same as the notch. No waveform.
struct LockScreenMusicPanel: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.playerTint) private var playerTint
    @State private var sliderValue: Double = 0
    @State private var dragging = false

    private var tint: Color {
        playerTint.resolvedColor(albumArt: musicManager.avgColor)
    }

    private var isProgressTimelinePaused: Bool {
        !musicManager.isPlaying || musicManager.isLiveStream || musicManager.playbackRate <= 0
    }

    var body: some View {
        HStack(spacing: 16) {
            artwork
            VStack(alignment: .leading, spacing: 6) {
                Text(musicManager.hasActiveSession ? musicManager.songTitle : String(localized: "Not Playing"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Text(musicManager.hasActiveSession ? musicManager.artistName : "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint.opacity(0.85))
                    .lineLimit(1)
                controls
                progress
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(LockScreenPanelManager.contentPadding)
        .frame(
            width: LockScreenPanelManager.panelSize.width,
            height: LockScreenPanelManager.panelSize.height
        )
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private var artwork: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(nsColor: musicManager.avgColor).opacity(0.08), radius: 4, y: 0)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            controlButton(
                systemName: "shuffle",
                pointSize: 13,
                color: musicManager.isShuffled ? tint : .white.opacity(0.65)
            ) {
                musicManager.toggleShuffle()
            }
            controlButton(systemName: "backward.fill") {
                musicManager.previousTrack()
            }
            controlButton(systemName: playIcon, pointSize: 18) {
                musicManager.togglePlay()
            }
            controlButton(systemName: "forward.fill") {
                musicManager.nextTrack()
            }
            controlButton(
                systemName: repeatIcon,
                pointSize: 13,
                color: musicManager.repeatMode != .off ? tint : .white.opacity(0.65)
            ) {
                musicManager.toggleRepeat()
            }
        }
    }

    private var playIcon: String {
        if musicManager.isPlaying {
            return musicManager.isLiveStream ? "stop.fill" : "pause.fill"
        }
        return "play.fill"
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func controlButton(
        systemName: String,
        pointSize: CGFloat = 14,
        color: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: pointSize, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private var progress: some View {
        TimelineView(.animation(paused: isProgressTimelinePaused)) { _ in
            progressBody
        }
        .frame(height: 12)
    }

    @ViewBuilder
    private var progressBody: some View {
        if musicManager.isLiveStream {
            LiveStreamProgressIndicator(tint: tint)
                .frame(height: 10)
        } else {
            let duration = max(musicManager.songDuration, 0.001)
            let position = dragging ? sliderValue : musicManager.estimatedPlaybackPosition()
            HStack(spacing: 6) {
                Text(timeString(from: position))
                    .frame(width: 36, alignment: .leading)
                GeometryReader { geo in
                    let fraction = min(max(position / duration, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule()
                            .fill(tint)
                            .frame(width: geo.size.width * fraction)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragging = true
                                sliderValue = min(max(value.location.x / geo.size.width, 0), 1) * duration
                            }
                            .onEnded { _ in
                                musicManager.seek(to: sliderValue)
                                dragging = false
                            }
                    )
                }
                .frame(height: 4)
                Text("-" + timeString(from: max(duration - position, 0)))
                    .frame(width: 42, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(tint)
        }
    }

    private func timeString(from seconds: Double) -> String {
        let clamped = max(seconds, 0)
        let totalMinutes = Int(clamped) / 60
        let remainingSeconds = Int(clamped) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
