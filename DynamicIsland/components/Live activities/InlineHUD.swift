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
import Defaults

struct InlineHUD: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat

    @Default(.showProgressPercentages) private var showProgressPercentages

    var body: some View {
        HStack(spacing: 8) {
            leadingIcon
                .foregroundStyle(.white)
                .frame(width: 20, height: 15)

            Text(typeName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            if type == .mic {
                Text(value > 0 ? "Unmuted" : "Muted")
                    .font(.caption)
                    .foregroundStyle(.gray)
            } else if type != .music {
                ProgressView(value: min(max(Double(value), 0), 1))
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 72)
                if showProgressPercentages {
                    Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.gray)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: max(vm.effectiveClosedNotchHeight + (hoverAnimation ? 8 : 0), 28))
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch type {
        case .volume:
            Image(systemName: icon.isEmpty ? (value.isZero ? "speaker.slash.fill" : "speaker.wave.2.fill") : icon)
        case .brightness:
            Image(systemName: icon.isEmpty ? "sun.max.fill" : icon)
        case .backlight:
            Image(systemName: icon.isEmpty ? "keyboard" : icon)
        case .mic:
            Image(systemName: "mic")
                .symbolVariant(value > 0 ? .none : .slash)
        case .battery:
            Image(systemName: "battery.100")
        case .music:
            Image(systemName: "music.note")
        }
    }

    private var typeName: String {
        switch type {
        case .volume: return String(localized: "Volume")
        case .brightness: return String(localized: "Brightness")
        case .backlight: return String(localized: "Backlight")
        case .mic: return String(localized: "Microphone")
        case .battery: return String(localized: "Battery")
        case .music: return String(localized: "Music")
        }
    }
}
