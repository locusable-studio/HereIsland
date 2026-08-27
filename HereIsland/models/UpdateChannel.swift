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

import Defaults
import Foundation

/// Sparkle update feed. Stable never sees beta items; beta also receives graduating stables.
enum UpdateChannel: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case stable
    case beta

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .stable: return String(localized: "Stable")
        case .beta: return String(localized: "Beta")
        }
    }

    var feedURL: URL {
        let base = "https://raw.githubusercontent.com/locusable-studio/HereIsland/main/Updates"
        switch self {
        case .stable: return URL(string: "\(base)/appcast.xml")!
        case .beta: return URL(string: "\(base)/appcast-beta.xml")!
        }
    }
}
