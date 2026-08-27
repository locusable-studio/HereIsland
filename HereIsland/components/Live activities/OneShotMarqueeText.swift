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

import SwiftUI

/// One-pass closed-island title flash. Hold if the title fits; otherwise marquee once, then finish.
/// Used only by the closed-island track-change peek. Never loops — unlike `MarqueeText`.
///
/// Offset is driven by `TimelineView` from elapsed time, not `withAnimation`. Parent
/// island springs and MusicManager updates must not own the glyph position.
struct OneShotMarqueeText: View {
    let text: String
    let font: Font
    let measurementFont: NSFont
    let textColor: Color
    let frameWidth: CGFloat
    var holdDuration: Double = 1.2
    var onFinished: () -> Void

    @State private var scrollStart: Date?
    @State private var runTask: Task<Void, Never>?

    private var textWidth: CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: measurementFont]).width)
    }

    private var isFrameUsable: Bool {
        frameWidth > 8
    }

    private var needsScrolling: Bool {
        isFrameUsable && textWidth > frameWidth
    }

    private var distance: CGFloat {
        max(textWidth - frameWidth, 0)
    }

    private var scrollDuration: Double {
        max(Double(distance) / 36.0, 0.45)
    }

    var body: some View {
        TimelineView(.animation(paused: scrollStart == nil)) { context in
            Text(text)
                .font(font)
                .foregroundColor(textColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: offset(at: context.date))
                .frame(width: frameWidth, alignment: .leading)
                .clipped()
        }
        .transaction { $0.animation = nil }
        .onAppear { begin() }
        .onDisappear {
            runTask?.cancel()
            runTask = nil
            scrollStart = nil
        }
        .onChange(of: text) { _, _ in
            runTask?.cancel()
            scrollStart = nil
            begin()
        }
    }

    private func offset(at date: Date) -> CGFloat {
        guard let start = scrollStart, distance > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(start)
        if elapsed <= 0 { return 0 }
        if elapsed >= scrollDuration { return -distance }
        return -distance * CGFloat(elapsed / scrollDuration)
    }

    private func begin() {
        runTask?.cancel()
        scrollStart = nil
        guard isFrameUsable else {
            runTask = nil
            return
        }
        let scrolling = needsScrolling
        let duration = scrollDuration
        runTask = Task { @MainActor in
            if scrolling {
                // Wait out the island spring (response ~0.36, no overshoot) before moving glyphs.
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled else { return }
                scrollStart = Date()
                try? await Task.sleep(for: .seconds(duration + 0.6))
            } else {
                try? await Task.sleep(for: .seconds(holdDuration))
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}
