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

/// Shared string tags for the system Display picker.
enum DisplayDestination {
    /// Show a notch window on every connected screen.
    static let allDisplays = "__all_displays__"

    static var showsOnAllDisplays: Bool {
        Defaults[.displayDestination] == allDisplays
    }
}

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

/// Tint applied to the notch player's colored elements: song title, artist name,
/// waveform, progress, and the active shuffle/repeat glyphs.
enum PlayerTint: String, CaseIterable, Identifiable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
    case appleMusic = "Apple Music"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .white: return String(localized: "White")
        case .albumArt: return String(localized: "Match album art")
        case .accent: return String(localized: "Follow system")
        case .appleMusic: return String(localized: "Apple Music")
        }
    }

    /// Album art colors get a brightness floor so dark artwork stays visible on the black notch.
    func resolvedColor(albumArt: NSColor) -> Color {
        switch self {
        case .white: return .white
        case .albumArt: return Color(nsColor: albumArt).ensureMinimumBrightness(factor: 0.6)
        case .accent: return .accentColor
        case .appleMusic: return Color(red: 0.999, green: 0.171, blue: 0.331)
        }
    }
}

extension Defaults.Keys {
    // MARK: General (menu bar)
    /// Selected display destination for the notch window.
    /// `"__all_displays__"` shows on every screen; otherwise a `NSScreen.stableDisplayID`.
    static let displayDestination = Key<String>("displayDestination", default: "")
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let showAlbumArtBackgroundEffects = Key<Bool>("showAlbumArtBackgroundEffects", default: true)
    static let showWindowShadow = Key<Bool>("showWindowShadow", default: true)
    /// Menu (General, after Haptics): “Hide during screenshots and recordings”. Default off.
    static let hideFromScreenCapture = Key<Bool>("hideFromScreenCapture", default: false)
    /// Menu (General): hide the notch window on a display that has a native-fullscreen app.
    static let hideWhenFullscreen = Key<Bool>("hideWhenFullscreen", default: true)

    /// Menu (Updates): Channel — Stable (default) or Beta.
    static let updateChannel = Key<UpdateChannel>("updateChannel", default: .stable)

    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: .nowPlaying)
    /// Menu (Appearance, after Quick peek): lock-screen media panel. Default off — SkyLight is private.
    static let enableLockScreenMediaPanel = Key<Bool>("enableLockScreenMediaPanel", default: false)

    // MARK: Appearance
    /// Keeps the legacy storage key so an existing progress-bar choice carries over.
    static let playerTint = Key<PlayerTint>(
        "sliderUseAlbumArtColor",
        default: .albumArt
    )
    static let showTitleOnTrackChange = Key<Bool>("showTitleOnTrackChange", default: true)

    // MARK: Waveform
    static let enableRealTimeWaveform = Key<Bool>("enableRealTimeWaveform", default: false)
    static let visualizerBarCount = Key<Int>("visualizerBarCount", default: 4)
}
