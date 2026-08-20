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
import Foundation

enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    
    var id: String { self.rawValue }
    
    var localizedName: String {
        switch self {
        case .nowPlaying: return String(localized: "Now Playing")
        case .appleMusic: return String(localized: "Apple Music")
        }
    }
}

/// Tint applied to the notch player's colored elements: progress bar, time labels,
/// artist name, and the waveform.
enum PlayerTint: String, CaseIterable, Identifiable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .white: return String(localized: "White")
        case .albumArt: return String(localized: "Match album art")
        case .accent: return String(localized: "Follow system")
        }
    }

    /// Album art colors get a brightness floor so dark artwork stays visible on the black notch.
    func resolvedColor(albumArt: NSColor) -> Color {
        switch self {
        case .white: return .white
        case .albumArt: return Color(nsColor: albumArt).ensureMinimumBrightness(factor: 0.6)
        case .accent: return .accentColor
        }
    }
}

extension Defaults.Keys {
    // MARK: General (menu bar)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let showAlbumArtBackgroundEffects = Key<Bool>("showAlbumArtBackgroundEffects", default: true)
    static let showWindowShadow = Key<Bool>("showWindowShadow", default: true)

    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: .nowPlaying)

    // MARK: Appearance
    /// Keeps the legacy storage key so an existing progress-bar choice carries over.
    static let playerTint = Key<PlayerTint>(
        "sliderUseAlbumArtColor",
        default: .albumArt
    )

    // MARK: Waveform
    static let enableRealTimeWaveform = Key<Bool>("enableRealTimeWaveform", default: false)
    static let visualizerBarCount = Key<Int>("visualizerBarCount", default: 4)
}
