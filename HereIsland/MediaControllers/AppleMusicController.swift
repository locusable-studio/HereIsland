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
import Combine
import Foundation

private struct ITunesSearchResponse: Decodable {
    let results: [ITunesTrack]
}

private struct ITunesTrack: Decodable {
    let trackName: String?
    let collectionName: String?
    let artworkUrl100: String?
}

private enum CatalogArtworkResult {
    case available(Data)
    case unavailable
    case transientFailure
}

private struct AppleMusicPlaybackSnapshot: Sendable {
    let isPlaying: Bool
    let title: String
    let artist: String
    let album: String
    let currentTime: Double
    let duration: Double
    let isShuffled: Bool
    let repeatModeValue: Int
    let artwork: Data?
    let contentIdentifier: String?

    init?(_ descriptor: NSAppleEventDescriptor) {
        guard descriptor.numberOfItems >= 10 else { return nil }
        isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        title = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        artist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        album = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        duration = descriptor.atIndex(6)?.doubleValue ?? 0
        isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        repeatModeValue = Int(descriptor.atIndex(8)?.int32Value ?? 0)
        artwork = descriptor.atIndex(9)?.data as Data?
        let persistentID = descriptor.atIndex(10)?.stringValue
        contentIdentifier = persistentID?.isEmpty == false
            ? persistentID
            : "\(title)|\(artist)|\(album)|\(duration)"
    }
}

class AppleMusicController: MediaControllerProtocol {
    // MARK: - Properties
    private static let bundleIdentifier = "com.apple.Music"

    /// Max time the previous track's cover may remain on screen after a skip
    /// with no replacement art yet. After this, clear via `.unavailable`.
    private static let previousCoverLinger: Duration = .milliseconds(100)

    /// Catalog + script give-up deadline, counted from track change (not
    /// linger + timeout). If still no art, Music logo sticks as fallback.
    private static let artworkTimeoutFromTrackChange: Duration = .milliseconds(600)

    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: AppleMusicController.bundleIdentifier,
        playbackRate: 1
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var isWorking: Bool {
        return true  // AppleMusic controller always works
    }

    var supportsQueueModeControls: Bool { true }

    /// Minimum byte count for artwork data to be considered valid. Anything
    /// smaller is likely an empty descriptor or error string, not image data.
    private static let minimumArtworkSize = 16

    private var notificationTask: Task<Void, Never>?
    private var playbackInfoRequestGeneration: UInt = 0
    private var artworkFetchTask: Task<Void, Never>?
    private var artworkRequestID: UUID?
    private var artworkRequestContentIdentifier: String?
    /// Coalesce dense `playerInfo` notifications so we do not storm Music with
    /// full AppleScript snapshots (especially artwork raw data).
    private var playbackInfoCoalesceTask: Task<Void, Never>?
    private var artworkFollowUpTask: Task<Void, Never>?
    private static let playerInfoCoalesce: Duration = .milliseconds(200)

    // MARK: - Initialization
    init() {
        setupPlaybackStateChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }
    
    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.apple.Music.playerInfo")
            )

            for await _ in notifications {
                // Peak notifications: coalesce and skip artwork raw data by default.
                await MainActor.run {
                    self?.scheduleCoalescedPlaybackInfoRefresh(includeArtwork: false)
                }
            }
        }
    }

    /// Trailing-edge coalesce for `playerInfo` floods after skips.
    @MainActor
    private func scheduleCoalescedPlaybackInfoRefresh(includeArtwork: Bool) {
        playbackInfoCoalesceTask?.cancel()
        playbackInfoCoalesceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.playerInfoCoalesce)
            guard !Task.isCancelled else { return }
            await self?.updatePlaybackInfo(includeArtwork: includeArtwork)
        }
    }

    deinit {
        notificationTask?.cancel()
        playbackInfoCoalesceTask?.cancel()
        artworkFollowUpTask?.cancel()
        artworkFetchTask?.cancel()
    }
    
    // MARK: - Protocol Implementation
    func play() async {
        await executeCommand("play")
    }
    
    func pause() async {
        await executeCommand("pause")
    }
    
    func togglePlay() async {
        await executeCommand("playpause")
    }
    
    func nextTrack() async {
        await executeAndRefresh("next track")
    }
    
    func previousTrack() async {
        await executeAndRefresh("previous track")
    }
    
    func seek(to time: Double) async {
        await executeCommand("set player position to \(time)")
        await updatePlaybackInfo()
    }
    
    func toggleShuffle() async {
        await executeCommand("set shuffle enabled to not shuffle enabled")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func toggleRepeat() async {
        await executeCommand("""
            if song repeat is off then
                set song repeat to all
            else if song repeat is all then
                set song repeat to one
            else
                set song repeat to off
            end if
            """)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == Self.bundleIdentifier }
    }
    
    func updatePlaybackInfo(includeArtwork: Bool = true) async {
        let generation = await MainActor.run { beginPlaybackInfoRequest() }
        guard let snapshot = try? await fetchPlaybackSnapshotAsync(includeArtwork: includeArtwork)
        else { return }
        await MainActor.run {
            let contentChanged = applyPlaybackInfo(
                snapshot,
                generation: generation,
                fetchedArtwork: includeArtwork
            )
            // Metadata-only peak refresh still needs one artwork pass when the
            // track identity changed, without re-entering the notification flood.
            if contentChanged && !includeArtwork {
                artworkFollowUpTask?.cancel()
                artworkFollowUpTask = Task { [weak self] in
                    await self?.updatePlaybackInfo(includeArtwork: true)
                }
            }
        }
    }

    @MainActor
    private func beginPlaybackInfoRequest() -> UInt {
        playbackInfoRequestGeneration &+= 1
        return playbackInfoRequestGeneration
    }

    private func executeAndRefresh(_ command: String) async {
        await executeCommand(command)
        try? await Task.sleep(for: .milliseconds(25))
        await updatePlaybackInfo()
    }

    @MainActor
    @discardableResult
    private func applyPlaybackInfo(
        _ snapshot: AppleMusicPlaybackSnapshot,
        generation: UInt,
        fetchedArtwork: Bool
    ) -> Bool {
        guard generation == playbackInfoRequestGeneration else { return false }
        var updatedState = self.playbackState
        let contentChanged =
            snapshot.contentIdentifier != playbackState.contentIdentifier
            || snapshot.title != playbackState.title
            || snapshot.artist != playbackState.artist
            || snapshot.album != playbackState.album
            || abs(snapshot.duration - playbackState.duration) >= 0.5

        updatedState.isPlaying = snapshot.isPlaying
        updatedState.title = snapshot.title
        updatedState.artist = snapshot.artist
        updatedState.album = snapshot.album
        updatedState.currentTime = snapshot.currentTime
        updatedState.duration = snapshot.duration
        updatedState.isShuffled = snapshot.isShuffled
        updatedState.repeatMode = RepeatMode(rawValue: snapshot.repeatModeValue) ?? .off
        updatedState.contentIdentifier = snapshot.contentIdentifier

        // Script art on a brand-new track can still be the *previous* track's
        // bytes (Apple Music often lags). Identical bytes after contentChanged
        // are treated as missing so the 100ms clear + 600ms logo path can run.
        // Metadata-only refreshes omit artwork entirely — do not treat that as
        // "missing art" / clear the cover until an artwork-inclusive fetch runs.
        let scriptArt: Data? = {
            guard fetchedArtwork else { return nil }
            guard let artworkData = snapshot.artwork,
                  artworkData.count > Self.minimumArtworkSize
            else { return nil }
            if contentChanged,
               let previous = playbackState.artwork,
               previous == artworkData {
                return nil
            }
            return artworkData
        }()

        if let artworkData = scriptArt {
            // While a cover request is in flight for this track, ignore
            // progress-only script refreshes. Apple Music often re-sends the
            // previous cover bytes after contentChanged cleared them; treating
            // those as .available cancelled the 100ms/600ms path and left the
            // notch stuck on the old cover (rapid skips).
            if artworkRequestID != nil && !contentChanged {
                // Keep waiting for clear / catalog / deadline.
            } else {
                // Trusted embedded script art (new bytes on track change, or
                // same-track refresh with no in-flight request).
                artworkFetchTask?.cancel()
                artworkFetchTask = nil
                artworkRequestID = nil
                artworkRequestContentIdentifier = nil
                updatedState.artwork = artworkData
                updatedState.artworkAvailability = .available
            }
        } else if contentChanged && fetchedArtwork {
            // New track, no trustworthy art yet: cancel prior generation (incl.
            // in-flight catalog). Publish .unknown so MusicManager may briefly
            // keep the previous cover — never republish stale bytes, never
            // immediate logo.
            artworkFetchTask?.cancel()
            artworkFetchTask = nil
            artworkRequestID = nil
            artworkRequestContentIdentifier = nil
            updatedState.artwork = nil
            updatedState.artworkAvailability = .unknown
        }

        updatedState.lastUpdated = Date()
        self.playbackState = updatedState

        guard fetchedArtwork,
              updatedState.artwork == nil,
              artworkRequestContentIdentifier != snapshot.contentIdentifier
        else { return contentChanged }

        let requestID = UUID()
        let title = updatedState.title
        let artist = updatedState.artist
        let album = updatedState.album
        artworkRequestID = requestID
        artworkRequestContentIdentifier = snapshot.contentIdentifier
        // Cover timing (Apple Music only):
        // 1) Start catalog immediately with this generation.
        // 2) At 100ms from skip: clear previous cover (.unavailable → logo).
        // 3) At 600ms from skip: if still no art, logo sticks (not 100+600).
        // Late catalog bytes for a cancelled requestID are dropped.
        artworkFetchTask = Task { [weak self] in
            let catalogTask = Task {
                await self?.fetchArtworkFromCatalog(
                    title: title,
                    artist: artist,
                    album: album
                ) ?? .transientFailure
            }

            enum TimingEvent {
                case clearOldCover
                case artworkDeadline
                case catalog(CatalogArtworkResult)
            }

            await withTaskGroup(of: TimingEvent.self) { group in
                group.addTask {
                    try? await Task.sleep(for: Self.previousCoverLinger)
                    return .clearOldCover
                }
                group.addTask {
                    try? await Task.sleep(for: Self.artworkTimeoutFromTrackChange)
                    return .artworkDeadline
                }
                group.addTask {
                    let result = await catalogTask.value
                    return .catalog(result)
                }

                var appliedArt = false
                for await event in group {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        catalogTask.cancel()
                        break
                    }
                    switch event {
                    case .catalog(let result):
                        if case .available = result {
                            appliedArt = true
                            await MainActor.run {
                                self?.completeArtworkRequest(result, requestID: requestID)
                            }
                            group.cancelAll()
                            catalogTask.cancel()
                            break
                        }
                        // unavailable / transientFailure: keep waiting for
                        // clear + deadline so we do not flash logo before 100ms.
                    case .clearOldCover:
                        guard !appliedArt else { continue }
                        await MainActor.run {
                            self?.clearPreviousCoverIfNeeded(requestID: requestID)
                        }
                    case .artworkDeadline:
                        if !appliedArt {
                            // Still no art after 600ms from track change → logo.
                            await MainActor.run {
                                self?.completeArtworkRequest(.unavailable, requestID: requestID)
                            }
                        }
                        group.cancelAll()
                        catalogTask.cancel()
                        break
                    }
                }
            }
        }
        return contentChanged
    }

    // MARK: - Private Methods

    /// Drop wrong-track art after the linger window. MusicManager only replaces
    /// the on-screen cover when availability becomes `.unavailable` (Music logo)
    /// until catalog/script upgrades to real art.
    @MainActor
    private func clearPreviousCoverIfNeeded(requestID: UUID) {
        guard artworkRequestID == requestID else { return }
        guard playbackState.artworkAvailability != .available else { return }
        var artworkState = playbackState
        artworkState.artwork = nil
        artworkState.artworkAvailability = .unavailable
        playbackState = artworkState
    }

    @MainActor
    private func completeArtworkRequest(_ result: CatalogArtworkResult, requestID: UUID) {
        guard artworkRequestID == requestID else { return }
        artworkRequestID = nil
        artworkFetchTask = nil
        artworkRequestContentIdentifier = nil

        var artworkState = playbackState
        switch result {
        case .available(let artwork):
            artworkState.artwork = artwork
            artworkState.artworkAvailability = .available
            playbackState = artworkState
        case .unavailable:
            artworkState.artwork = nil
            artworkState.artworkAvailability = .unavailable
            playbackState = artworkState
        case .transientFailure:
            // Network blip: if we already cleared to logo, keep it; otherwise
            // mark unavailable so we do not hang on .unknown forever.
            if artworkState.artworkAvailability != .available {
                artworkState.artwork = nil
                artworkState.artworkAvailability = .unavailable
                playbackState = artworkState
            }
        }
    }

    private func canonicalMetadata(_ value: String?) -> String {
        let simplified = value?
            .applyingTransform(StringTransform("Traditional-Simplified"), reverse: false)
            ?? value
            ?? ""
        let folded = simplified.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        return String(
            folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        )
    }

    private func fetchArtworkFromCatalog(
        title: String,
        artist: String,
        album: String
    ) async -> CatalogArtworkResult {
        let query = "\(title) \(artist)"
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=10")
        else { return .unavailable }

        do {
            let (data, urlResponse) = try await URLSession.shared.data(from: url)
            guard let httpResponse = urlResponse as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                return .transientFailure
            }

            let searchResponse = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard !searchResponse.results.isEmpty else {
                return .unavailable
            }

            let normalizedAlbum = canonicalMetadata(album)
            let normalizedTitle = canonicalMetadata(title)
            let match = searchResponse.results.first(where: {
                !normalizedTitle.isEmpty
                    && !normalizedAlbum.isEmpty
                    && canonicalMetadata($0.trackName) == normalizedTitle
                    && canonicalMetadata($0.collectionName) == normalizedAlbum
            }) ?? searchResponse.results.first(where: {
                !normalizedAlbum.isEmpty
                    && canonicalMetadata($0.collectionName) == normalizedAlbum
            }) ?? searchResponse.results.first(where: {
                !normalizedTitle.isEmpty
                    && canonicalMetadata($0.trackName) == normalizedTitle
            })

            guard let artworkURLString = match?.artworkUrl100 else {
                return .unavailable
            }

            let highResURL = artworkURLString.replacingOccurrences(of: "100x100", with: "600x600")
            guard let imageURL = URL(string: highResURL) else {
                return .transientFailure
            }

            let (imageData, imageResponse) = try await URLSession.shared.data(from: imageURL)
            guard let httpResponse = imageResponse as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  imageData.count > Self.minimumArtworkSize,
                  NSImage(data: imageData) != nil
            else {
                return .transientFailure
            }

            return .available(imageData)
        } catch {
            return .transientFailure
        }
    }

    private func executeCommand(_ command: String) async {
        let script = "tell application \"Music\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }
    
    private func fetchPlaybackSnapshotAsync(includeArtwork: Bool) async throws -> AppleMusicPlaybackSnapshot? {
        // Build with concatenation so artwork lines are not interpolated inside a
        // multi-line string literal (Archive failed on under-indented \(artworkClause)).
        let artworkLines: String
        if includeArtwork {
            artworkLines = """
                            set artData to ""
                            try
                                set artData to raw data of artwork 1 of current track
                            end try

                """
        } else {
            artworkLines = """
                            set artData to ""

                """
        }
        let scriptPrefix = """
                tell application "Music"
                    try
                        set playerState to player state is playing
                        set currentTrackName to name of current track
                        set currentTrackArtist to artist of current track
                        set currentTrackAlbum to album of current track
                        set trackPosition to player position
                        set trackDuration to duration of current track
                        set shuffleState to shuffle enabled
                        set repeatState to song repeat
                        if repeatState is off then
                            set repeatValue to 1
                        else if repeatState is one then
                            set repeatValue to 2
                        else if repeatState is all then
                            set repeatValue to 3
                        end if

                """
        let scriptSuffix = """
                        set trackPersistentID to ""
                        try
                            set trackPersistentID to persistent ID of current track
                        end try

                        return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatValue, artData, trackPersistentID}
                    on error
                        return {false, "Not Playing", "Unknown", "Unknown", 0, 0, false, 0, "", ""}
                    end try
                end tell
                """
        let script = scriptPrefix + artworkLines + scriptSuffix
        guard let descriptor = try await AppleScriptHelper.execute(script) else { return nil }
        return AppleMusicPlaybackSnapshot(descriptor)
    }
}
