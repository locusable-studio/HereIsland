/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Animated waveform visualizer.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI

struct AudioVisualizerView: View {
    @Binding var isPlaying: Bool
    
    var body: some View {
        AudioSpectrumView(isPlaying: $isPlaying)
    }
}

#Preview("Animated") {
    AudioVisualizerView(isPlaying: .constant(true))
        .frame(width: 16, height: 20)
        .padding()
}
