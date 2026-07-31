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

import AppKit
import Defaults

/// Sparkle update feed channel. Here Island only ships a single stable channel.
enum UpdateChannel: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case stable

    var id: String { rawValue }

    var displayName: String {
        String(localized: "Stable")
    }

    var description: String {
        String(localized: "Production releases, thoroughly tested")
    }

    /// Stable Sparkle feed URL — path never changes; `Updates/appcast.xml` on `main` is rewritten each release.
    /// Enclosure URLs inside the feed point at immutable versioned GitHub Release assets.
    var feedURL: URL {
        URL(string: "https://raw.githubusercontent.com/\(Self.feedRepository)/main/Updates/appcast.xml")!
    }

    /// Keep in sync with the GitHub repository that hosts `Updates/appcast.xml`.
    private static let feedRepository = "locusable-studio/HereIsland"

    var badgeColor: NSColor { .systemGreen }

    var badgeIcon: String { "checkmark.seal.fill" }

    static var buildChannel: UpdateChannel { .stable }

    static var availableChannels: [UpdateChannel] { [.stable] }
}
