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

import AppKit
import CoreGraphics
import Defaults
import Foundation
import SwiftUI

private let minimalisticBaseOpenNotchSize: CGSize = .init(width: 420, height: 180)

@MainActor
func minimalisticOpenNotchSize(isDynamicIslandMode: Bool = false) -> CGSize {
    // Island mode stays off; keep the notch open size only.
    _ = isDynamicIslandMode
    return minimalisticBaseOpenNotchSize
}

let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))
let minimalisticCornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 35, bottom: 35), closed: cornerRadiusInsets.closed)

/// External / non-notched Dynamic Island pill mode is not exposed in settings;
/// always use the standard notch shape.
func shouldUseDynamicIslandMode(for screenName: String?) -> Bool {
    false
}

/// Corner radius insets for the Dynamic Island pill shape.
/// - closed: half the closed notch height for a true capsule look
/// - opened: generous radius for smooth expanded pill
let dynamicIslandPillCornerRadiusInsets: (opened: CGFloat, closed: (standard: CGFloat, minimalistic: CGFloat)) = (
    opened: 24,
    closed: (standard: 16, minimalistic: 16)
)

/// Vertical offset from the top screen edge for the Dynamic Island pill.
let dynamicIslandTopOffset: CGFloat = 6

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

extension NSScreen {
    var displayIdentifier: String? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }

    var displayUUIDString: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Session list identity (`ForEach` id): `CGDirectDisplayID` string.
    var stableDisplayID: String {
        displayIdentifier ?? localizedName
    }

    /// Persisted `displayDestination` token: display UUID when CoreGraphics
    /// provides one (survives unplug/replug). Falls back to CGDirectDisplayID,
    /// then localized name.
    var preferenceDisplayToken: String {
        displayUUIDString ?? displayIdentifier ?? localizedName
    }

    func matchesDisplayToken(_ token: String) -> Bool {
        let needle = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        if let displayUUIDString, displayUUIDString.caseInsensitiveCompare(needle) == .orderedSame {
            return true
        }
        if let displayIdentifier, displayIdentifier.caseInsensitiveCompare(needle) == .orderedSame {
            return true
        }
        return localizedName.caseInsensitiveCompare(needle) == .orderedSame
    }

    /// True when AppKit exposes notch/cutout geometry for this screen.
    var hasNotchGeometry: Bool {
        if safeAreaInsets.top > 0 { return true }
        return auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil
    }
}

func screenMatchingDisplayDestination(
    _ destination: String,
    screens: [NSScreen] = NSScreen.screens
) -> NSScreen? {
    guard destination != DisplayDestination.allDisplays, !destination.isEmpty else { return nil }
    return screens.first { $0.matchesDisplayToken(destination) }
}

/// Preferred screen if connected; otherwise the current window's screen, then `NSScreen.main`.
func resolveNotchHostScreen(windowFallback: NSScreen? = nil) -> NSScreen? {
    if let match = screenMatchingDisplayDestination(Defaults[.displayDestination]) {
        return match
    }
    return windowFallback ?? NSScreen.main ?? NSScreen.screens.first
}

/// Migrates legacy keys. Does not rewrite the remembered destination when that screen is unplugged.
@discardableResult
func reconcileDisplayDestination() -> NSScreen? {
    migrateLegacyDisplayDefaultsIfNeeded()
    return resolveNotchHostScreen()
}

/// One-shot migration from the previous boolean + optional screen-id pair.
private func migrateLegacyDisplayDefaultsIfNeeded() {
    let defaults = UserDefaults.standard
    let current = defaults.string(forKey: "displayDestination") ?? ""
    guard current.isEmpty else { return }

    if defaults.bool(forKey: "showOnAllDisplays") {
        Defaults[.displayDestination] = DisplayDestination.allDisplays
    } else if let preferred = defaults.string(forKey: "preferredScreenIdentifier"), !preferred.isEmpty {
        Defaults[.displayDestination] = preferred
    }
}

func getScreenFrame(_ screen: String? = nil) -> CGRect? {
    if let screen,
       let match = NSScreen.screens.first(where: { $0.localizedName == screen }) {
        return match.frame
    }
    return resolveNotchHostScreen()?.frame
}

func getClosedNotchSize(screen: String? = nil) -> CGSize {
    var notchHeight: CGFloat = 32
    var notchWidth: CGFloat = 150

    let selectedScreen: NSScreen?
    if let screen {
        selectedScreen = NSScreen.screens.first(where: { $0.localizedName == screen })
            ?? resolveNotchHostScreen()
    } else {
        selectedScreen = resolveNotchHostScreen()
    }

    if let screen = selectedScreen {
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        if screen.safeAreaInsets.top > 0 {
            notchHeight = screen.safeAreaInsets.top
        } else {
            notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
