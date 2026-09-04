/*
 * Here Island
 * Copyright (C) 2024-2026 Here Island Contributors
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
import SwiftUI

struct AboutView: View {
    private static let repositoryURL = URL(string: "https://github.com/locusable-studio/HereIsland")!
    private static let studioURL = URL(string: "https://locusable.com/")!

    private var studioAttribution: AttributedString {
        var text = AttributedString(String(localized: "Locusable Studio makes Here Island."))
        if let range = text.range(of: "Locusable Studio") {
            text[range].link = Self.studioURL
        }
        if let range = text.range(of: "Here Island") {
            text[range].link = Self.repositoryURL
        }
        return text
    }

    private static let lineageCredits: [AboutCredit] = [
        AboutCredit(
            name: "boring.notch",
            detail: String(localized: "Original Bored Team notch experience"),
            url: URL(string: "https://github.com/TheBoredTeam/boring.notch")!
        ),
        AboutCredit(
            name: "Atoll",
            detail: String(localized: "Dynamic Island–style companion this project builds on"),
            url: URL(string: "https://github.com/Ebullioscopic/Atoll")!
        ),
        AboutCredit(
            name: "Alcove",
            detail: String(localized: "Lock screen media panel inspiration"),
            url: URL(string: "https://tryalcove.com")!
        ),
    ]

    private static let dependencyCredits: [AboutCredit] = [
        AboutCredit(
            name: "Sparkle",
            detail: String(localized: "Software update framework"),
            url: URL(string: "https://github.com/sparkle-project/Sparkle")!
        ),
        AboutCredit(
            name: "Defaults",
            detail: String(localized: "User defaults helpers by Sindre Sorhus"),
            url: URL(string: "https://github.com/sindresorhus/Defaults")!
        ),
        AboutCredit(
            name: "LaunchAtLogin-Modern",
            detail: String(localized: "Launch at login helper by Sindre Sorhus"),
            url: URL(string: "https://github.com/sindresorhus/LaunchAtLogin-Modern")!
        ),
        AboutCredit(
            name: "MacroVisionKit",
            detail: String(localized: "Screen-capture visibility utilities"),
            url: URL(string: "https://github.com/TheBoredTeam/MacroVisionKit")!
        ),
        AboutCredit(
            name: "mediaremote-adapter",
            detail: String(localized: "Now Playing access via MediaRemote Adapter"),
            url: URL(string: "https://github.com/ungive/mediaremote-adapter")!
        ),
        AboutCredit(
            name: "rtaudio",
            detail: String(localized: "Real-time audio capture foundation"),
            url: URL(string: "https://github.com/ZephyrCodesStuff/rtaudio")!
        ),
    ]

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Version")) {
                    Text(versionLabel)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                LabeledContent(String(localized: "Channel")) {
                    Text(Defaults[.updateChannel].localizedName)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(Self.lineageCredits) { credit in
                    AboutCreditRow(credit: credit)
                }
            } header: {
                Text(String(localized: "Acknowledgements"))
            } footer: {
                Text(String(localized: "Here Island is derived from earlier open-source notch projects."))
            }

            Section {
                ForEach(Self.dependencyCredits) { credit in
                    AboutCreditRow(credit: credit)
                }
            } header: {
                Text(String(localized: "Third-party dependencies"))
            } footer: {
                Text(String(localized: "Thanks to these open-source dependencies."))
            }

            Section {
                Text(studioAttribution)
            } header: {
                Text(String(localized: "Team"))
            } footer: {
                Text(String(localized: "© 2026 Locusable Studio. All rights reserved."))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 560)
    }

    private var versionLabel: String {
        let version = Bundle.main.releaseVersionNumber ?? "—"
        let build = Bundle.main.buildVersionNumber ?? "—"
        return "\(version) (\(build))"
    }
}

private struct AboutCredit: Identifiable {
    let name: String
    let detail: String
    let url: URL

    var id: String { name }
}

private struct AboutCreditRow: View {
    let credit: AboutCredit

    var body: some View {
        Button {
            NSWorkspace.shared.open(credit.url)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(credit.name)
                        .foregroundStyle(.primary)
                    Text(credit.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
