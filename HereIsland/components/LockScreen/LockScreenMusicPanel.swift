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
 * along with this program. If you did not, see <https://www.gnu.org/licenses/>.
 */

import Defaults
import SwiftUI

/// Fixed lock-screen media card. Reuses MusicManager + playerTint.
/// Play / prev / next stay white. Artwork shadow uses raw `avgColor`.
struct LockScreenMusicPanel: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.playerTint) private var playerTint
    @State private var sliderValue: Double = 0
    @State private var dragging = false

    private var tint: Color {
        playerTint.resolvedColor(albumArt: musicManager.avgColor)
    }

    var body: some View {
        HStack(spacing: 16) {
            artwork
            VStack(alignment: .leading, spacing: 8) {
                Text(musicManager.songTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Text(musicManager.artistName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint.opacity(0.72))
                    .lineLimit(1)
                controls
                progress
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(
            width: LockScreenPanelManager.panelSize.width,
            height: LockScreenPanelManager.panelSize.height
        )
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.black.opacity(0.72))
        )
    }

    private var artwork: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(nsColor: musicManager.avgColor).opacity(0.55), radius: 12, y: 4)
    }

    private var controls: some View {
        HStack(spacing: 18) {
            controlButton(systemName: "backward.fill") {
                musicManager.previousTrack()
            }
            controlButton(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill", pointSize: 18) {
                musicManager.togglePlay()
            }
            controlButton(systemName: "forward.fill") {
                musicManager.nextTrack()
            }
        }
    }

    private func controlButton(systemName: String, pointSize: CGFloat = 14, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: pointSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private var progress: some View {
        let duration = max(musicManager.songDuration, 0.001)
        let position = dragging ? sliderValue : musicManager.estimatedPlaybackPosition()
        return GeometryReader { geo in
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
    }
}
