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
import SwiftUI

struct AboutView: View {
    private static let repositoryURL = URL(string: "https://github.com/locusable-studio/HereIsland")!

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
    ]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Here Island")
                            .font(.title2.weight(.semibold))
                        Text(String(localized: "macOS notch media companion"))
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            Section(String(localized: "Version info")) {
                LabeledContent(String(localized: "Version")) {
                    Text(versionLabel)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                LabeledContent(String(localized: "Channel")) {
                    Text(UpdateChannel.buildChannel.displayName)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "Links")) {
                Button(String(localized: "GitHub Repository")) {
                    NSWorkspace.shared.open(Self.repositoryURL)
                }
            }

            Section {
                Text(String(localized: "Here Island is derived from earlier open-source notch projects."))
                    .foregroundStyle(.secondary)
                    .font(.callout)

                ForEach(Self.lineageCredits) { credit in
                    AboutCreditRow(credit: credit)
                }
            } header: {
                Text(String(localized: "Acknowledgements"))
            }

            Section {
                Text(String(localized: "Thanks to these open-source dependencies."))
                    .foregroundStyle(.secondary)
                    .font(.callout)

                ForEach(Self.dependencyCredits) { credit in
                    AboutCreditRow(credit: credit)
                }
            } header: {
                Text(String(localized: "Third-party dependencies"))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 520)
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
