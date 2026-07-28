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

import Defaults

enum MusicControlButton: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case shuffle
    case trackBackward
    case playPause
    case trackForward
    case repeatMode

    static let fixedLayout: [MusicControlButton] = [
        .shuffle,
        .trackBackward,
        .playPause,
        .trackForward,
        .repeatMode
    ]

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shuffle:
            return String(localized: "Shuffle")
        case .trackBackward:
            return String(localized: "Previous Track")
        case .playPause:
            return String(localized: "Play / Pause")
        case .trackForward:
            return String(localized: "Next Track")
        case .repeatMode:
            return String(localized: "Repeat")
        }
    }

    var iconName: String {
        switch self {
        case .shuffle:
            return "shuffle"
        case .trackBackward:
            return "backward.fill"
        case .playPause:
            return "playpause"
        case .trackForward:
            return "forward.fill"
        case .repeatMode:
            return "repeat"
        }
    }

    var prefersLargeScale: Bool {
        self == .playPause
    }
}
