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
struct OneShotMarqueeText: View {
    let text: String
    let font: Font
    let measurementFont: NSFont
    let textColor: Color
    let frameWidth: CGFloat
    var holdDuration: Double = 1.2
    var onFinished: () -> Void

    @State private var offset: CGFloat = 0
    @State private var runTask: Task<Void, Never>?
    @State private var settleTask: Task<Void, Never>?
    @State private var startedAtWidth: CGFloat = 0
    @State private var motionLocked: Bool = false

    private var textWidth: CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: measurementFont]).width)
    }

    private var isFrameUsable: Bool {
        frameWidth > 8
    }

    private func needsScrolling(in width: CGFloat) -> Bool {
        width > 8 && textWidth > width
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(textColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: offset)
            .frame(width: frameWidth, alignment: .leading)
            .clipped()
            .onAppear { scheduleStart() }
            .onDisappear {
                settleTask?.cancel()
                settleTask = nil
                runTask?.cancel()
                runTask = nil
                motionLocked = false
            }
            .onChange(of: text) { _, _ in
                runTask?.cancel()
                settleTask?.cancel()
                motionLocked = false
                snapOffset(to: 0)
                startedAtWidth = 0
                scheduleStart()
            }
            .onChange(of: frameWidth) { _, newWidth in
                // Peek spring interpolates the slot. Hold still until it settles.
                // After motion starts, ignore jitter from album-art / tint updates.
                guard newWidth > 8, !motionLocked else { return }
                if runTask != nil, abs(newWidth - startedAtWidth) <= 1 {
                    return
                }
                runTask?.cancel()
                snapOffset(to: 0)
                scheduleStart()
            }
    }

    private func snapOffset(to value: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offset = value
        }
    }

    private func scheduleStart() {
        settleTask?.cancel()
        guard isFrameUsable else {
            runTask = nil
            return
        }
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            start()
        }
    }

    private func start() {
        runTask?.cancel()
        snapOffset(to: 0)
        guard isFrameUsable else {
            runTask = nil
            return
        }
        let width = frameWidth
        startedAtWidth = width
        motionLocked = true
        let scrolling = needsScrolling(in: width)
        runTask = Task { @MainActor in
            if scrolling {
                // Brief beat so the leading words are readable, then one linear pass.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let distance = max(textWidth - width, 0)
                let duration = max(Double(distance) / 36.0, 0.45)
                var transaction = Transaction(animation: .linear(duration: duration))
                withTransaction(transaction) {
                    offset = -distance
                }
                try? await Task.sleep(for: .seconds(duration + 0.2))
            } else {
                try? await Task.sleep(for: .seconds(holdDuration))
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}
