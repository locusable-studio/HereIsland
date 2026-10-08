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
    let artistName: String?
    let collectionName: String?
    let artworkUrl100: String?
}

private enum CatalogArtworkResult {
    case available(Data)
    case unavailable
    case transientFailure
}

/// Decoded cover for the track-change Quick Peek. Not the shared `albumArt`.
struct AppleMusicPeekCoverUpdate {
    let requestID: UUID
    let image: NSImage
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

    /// Shared `albumArt` only. Max time the previous cover stays up after a
    /// skip with no replacement art yet. The slot then goes `.pending` (blank),
    /// never the Music icon. The Quick Peek does not use this.
    private static let previousCoverLinger: Duration = .milliseconds(250)

    /// Counted from the track change. Keeps the blank slot and arms the
    /// one-shot script-art fetch. Does not pin the Music icon and does not
    /// drop `artworkRequestID`.
    private static let artworkTimeoutFromTrackChange: Duration = .milliseconds(600)

    /// Cap for one catalog lookup, from when that lookup starts (the track
    /// change). The blank slot ends when a decoded cover is applied, or when
    /// both this lookup and the one-shot script fetch have settled with no
    /// image. The script fetch is armed at 600ms and waits
    /// `delayedScriptArtworkDelay` (300ms) before one artwork-inclusive
    /// snapshot. If that path does not start, it counts as already settled.
    /// Worst case is therefore max(4s catalog cap, 900ms + that script
    /// round-trip): a fast script miss still waits out a slow catalog, and a
    /// script slower than 4s holds the blank until the script returns.
    /// Confirmed stop is outside this bound and shows the icon immediately.
    /// A new skip does not cancel the previous lookup; this cap is what keeps
    /// rapid skips from piling requests up.
    private static let catalogLookupTimeout: Duration = .seconds(4)

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

    /// Validated catalog images that passed the artist match (album too when it
    /// is real; title when it is not). Key is `artist|album`, or `artist|title`
    /// when the album is empty or `Unknown`, so album-less tracks do not share a cover.
    private let catalogArtworkCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 32
        return cache
    }()

    private var notificationTask: Task<Void, Never>?
    private var playbackInfoRequestGeneration: UInt = 0
    private var artworkFetchTask: Task<Void, Never>?
    /// Catalog lookups detached from `artworkFetchTask`. The 600ms deadline and
    /// a newer skip cancel the timers, not these tasks.
    private var catalogTasks: [UUID: Task<Void, Never>] = [:]
    private var artworkRequestID: UUID?
    /// Quick Peek cover for the latest track change. `albumArt` does not read it.
    private var peekTrackKey: String?
    private var peekArtworkRequestID: UUID?
    private var peekCoverImage: NSImage?
    private let peekCoverUpdates = PassthroughSubject<AppleMusicPeekCoverUpdate, Never>()

    var peekCoverUpdatePublisher: AnyPublisher<AppleMusicPeekCoverUpdate, Never> {
        peekCoverUpdates.eraseToAnyPublisher()
    }
    private var artworkRequestContentIdentifier: String?
    /// Coalesce dense `playerInfo` notifications so we do not storm Music with
    /// full AppleScript snapshots (especially artwork raw data).
    private var playbackInfoCoalesceTask: Task<Void, Never>?
    private static let playerInfoCoalesce: Duration = .milliseconds(200)
    /// One-shot script-art fetch after the 600ms deadline.
    /// Not the immediate playerInfo follow-up removed in #71.
    private var delayedScriptArtworkTask: Task<Void, Never>?
    /// `contentIdentifier` captured when that script fetch is armed.
    /// A result may update `albumArt` only when it still equals the current track.
    private var delayedScriptContentIdentifier: String?
    private static let delayedScriptArtworkDelay: Duration = .milliseconds(300)
    /// Catalog + script settlement for the skip in flight. The Music icon waits
    /// until both have settled with no image. Keyed by the request that started
    /// them; write-back itself checks `contentIdentifier`, not `artworkRequestID`.
    private struct InFlightCoverLookup {
        let requestID: UUID
        let contentIdentifier: String?
        var catalogSettled = false
        var scriptSettled = false
    }
    private var coverLookup: InFlightCoverLookup?
    /// Artwork bytes of the track we just left. Used to reject a late script
    /// snapshot that is still serving the previous cover.
    private var skippedTrackArtwork: Data?
    private var rejectArtworkMatchingSkippedTrack = false
    /// Between-tracks AppleScript error (`Not Playing` / empty). Must not
    /// start `previousCoverLinger` or publish `.unavailable`. A real next
    /// track still applies immediately. This wait only accepts a genuine
    /// empty player; it is not the cover linger.
    private var notPlayingSentinelEpoch: UInt = 0
    private var notPlayingSentinelConfirmTask: Task<Void, Never>?
    /// True only while an empty between-tracks snapshot is being ignored.
    /// Not tied to the task object: a finished task must not keep blocking
    /// `.unavailable` or a later skip.
    private var awaitingTrackAfterNotPlayingSentinel = false
    /// In-flight `updatePlaybackInfo` calls. The confirm fetch waits for
    /// these so it does not bump the generation out from under a real track.
    private var playbackInfoFetchesInFlight: Int = 0
    private static let notPlayingSentinelConfirmDelay: Duration = .milliseconds(700)

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
    /// Stays metadata-only: no `includeArtwork: true` follow-up on contentChanged.
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
        delayedScriptArtworkTask?.cancel()
        artworkFetchTask?.cancel()
        catalogTasks.values.forEach { $0.cancel() }
        notPlayingSentinelConfirmTask?.cancel()
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
    
    func updatePlaybackInfo() async {
        await updatePlaybackInfo(includeArtwork: true)
    }

    private func updatePlaybackInfo(
        includeArtwork: Bool,
        notPlayingSentinelEpoch confirmEpoch: UInt? = nil
    ) async {
        let generation = await MainActor.run { () -> UInt? in
            if let confirmEpoch, confirmEpoch != self.notPlayingSentinelEpoch {
                return nil
            }
            self.playbackInfoFetchesInFlight += 1
            return self.beginPlaybackInfoRequest()
        }
        guard let generation else { return }
        let snapshot = try? await fetchPlaybackSnapshotAsync(includeArtwork: includeArtwork)
        await MainActor.run {
            self.playbackInfoFetchesInFlight = max(0, self.playbackInfoFetchesInFlight - 1)
            if let confirmEpoch, confirmEpoch != self.notPlayingSentinelEpoch {
                return
            }
            guard let snapshot else { return }
            self.applyPlaybackInfo(
                snapshot,
                generation: generation,
                fetchedArtwork: includeArtwork,
                acceptNotPlayingSentinel: confirmEpoch != nil
            )
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
    private func applyPlaybackInfo(
        _ snapshot: AppleMusicPlaybackSnapshot,
        generation: UInt,
        fetchedArtwork: Bool,
        acceptNotPlayingSentinel: Bool = false
    ) {
        guard shouldApplyPlaybackSnapshot(
            snapshot,
            generation: generation,
            fetchedArtwork: fetchedArtwork
        ) else { return }
        // ~25ms after skip, and the coalesced playerInfo behind it, AppleScript
        // `on error` often returns Not Playing before the next track exists.
        // Treating that as a content change starts `previousCoverLinger` from
        // the sentinel, so the 250ms logo clock expires before the real title.
        if Self.isNotPlayingSentinel(snapshot),
           hasConfirmedTrackIdentity,
           !acceptNotPlayingSentinel {
            noteSwallowedNotPlayingSentinel()
            return
        }
        // A same-track refresh must not end the wait: Music often still
        // reports the track we are leaving. Only a real next identity, or
        // this wait's own confirming fetch, may anchor the 250ms clock.
        if acceptNotPlayingSentinel || confirmsNextTrackIdentity(snapshot) {
            cancelNotPlayingSentinelConfirm()
        }
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
        // are treated as missing so the 250ms clear + 600ms logo path can run.
        // Metadata-only (playerInfo) refreshes skip this AppleScript raw-data
        // branch; catalog + 250ms/600ms still run on contentChanged below.
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
            // Delayed post-deadline fetch: Music may still return the skipped
            // track's bytes. Keep the slot empty rather than resticking that cover.
            if rejectArtworkMatchingSkippedTrack,
               let skipped = skippedTrackArtwork,
               skipped == artworkData {
                return nil
            }
            // Bytes alone are not a cover. The icon/blank decision needs a real image.
            guard Self.decodePeekImage(artworkData) != nil else { return nil }
            return artworkData
        }()

        if let artworkData = scriptArt {
            // While a cover request is in flight for this track, ignore
            // progress-only script refreshes. Apple Music often re-sends the
            // previous cover bytes after contentChanged cleared them; treating
            // those as .available cancelled the 250ms/600ms path and left the
            // notch stuck on the old cover (rapid skips).
            // The one-shot fetch armed at 600ms is the exception: its result
            // is accepted only when the contentIdentifier captured at arm time
            // is still this track. A newer skip's identifier does not match,
            // so track 1's image cannot land on track 3.
            let acceptsDelayedScript =
                fetchedArtwork
                && Self.contentIdentifiersMatch(
                    snapshot.contentIdentifier,
                    delayedScriptContentIdentifier
                )
                && contentIdentifierMatchesCurrent(delayedScriptContentIdentifier)
            if artworkRequestID != nil && !contentChanged && !acceptsDelayedScript {
                // Keep waiting for clear / catalog / deadline.
            } else {
                // Trusted embedded script art (new bytes on track change, or
                // same-track refresh with no in-flight request).
                artworkFetchTask?.cancel()
                artworkFetchTask = nil
                artworkRequestID = nil
                artworkRequestContentIdentifier = snapshot.contentIdentifier
                rejectArtworkMatchingSkippedTrack = false
                delayedScriptArtworkTask?.cancel()
                delayedScriptArtworkTask = nil
                delayedScriptContentIdentifier = nil
                coverLookup = nil
                updatedState.artwork = artworkData
                updatedState.artworkAvailability = .available
                if contentChanged {
                    armPeekCover(
                        requestID: UUID(),
                        title: snapshot.title,
                        artist: snapshot.artist,
                        contentIdentifier: snapshot.contentIdentifier,
                        image: Self.decodePeekImage(artworkData)
                    )
                } else if peekCoverImage == nil {
                    noteDecodedPeekCover(artworkData, requestID: peekArtworkRequestID)
                }
            }
        } else if contentChanged {
            // New track, no trustworthy script art (or a metadata-only refresh
            // that never asked Music for raw data). Cancel prior generation.
            // Publish .unknown so MusicManager may briefly keep the previous
            // cover — never republish stale bytes, never immediate logo.
            // Keep the last real bytes when this track never received its own.
            // Otherwise a rapid skip (blank slot, nil artwork) forgets the cover
            // the script fetch must still reject.
            skippedTrackArtwork = playbackState.artwork ?? skippedTrackArtwork
            rejectArtworkMatchingSkippedTrack = false
            delayedScriptArtworkTask?.cancel()
            delayedScriptArtworkTask = nil
            delayedScriptContentIdentifier = nil
            coverLookup = nil
            artworkFetchTask?.cancel()
            artworkFetchTask = nil
            artworkRequestID = nil
            artworkRequestContentIdentifier = nil
            updatedState.artwork = nil
            updatedState.artworkAvailability = .unknown
            peekTrackKey = nil
            peekArtworkRequestID = nil
            peekCoverImage = nil
        }

        updatedState.lastUpdated = Date()

        // Arm the Quick Peek cover before publishing so the title sink reads
        // the decoded image (cache or none) for this track, not the previous one.
        let shouldFetchArtwork =
            updatedState.artwork == nil
            && artworkRequestContentIdentifier != snapshot.contentIdentifier
            && (fetchedArtwork || contentChanged)
        if shouldFetchArtwork {
            let requestID = UUID()
            artworkRequestID = requestID
            artworkRequestContentIdentifier = snapshot.contentIdentifier
            let cachedPeekImage: NSImage? = {
                guard let cached = cachedCatalogArtwork(
                    artist: updatedState.artist,
                    album: updatedState.album,
                    title: updatedState.title
                ) else { return nil }
                return Self.decodePeekImage(cached)
            }()
            armPeekCover(
                requestID: requestID,
                title: updatedState.title,
                artist: updatedState.artist,
                contentIdentifier: snapshot.contentIdentifier,
                image: cachedPeekImage
            )
        }

        self.playbackState = updatedState

        // Catalog + 250ms/600ms: artwork-inclusive fetches (skip/seek/play),
        // or metadata-only playerInfo when the track actually changed.
        // Keep artworkRequestContentIdentifier after a miss so a later
        // artwork-inclusive snapshot (delayed script fetch / expand) does
        // not restart this generation.
        guard shouldFetchArtwork, let requestID = artworkRequestID else { return }

        let title = updatedState.title
        let artist = updatedState.artist
        let album = updatedState.album
        let contentIdentifier = snapshot.contentIdentifier
        // Shared albumArt timing:
        // 1) Catalog starts immediately and is not cancelled at 600ms.
        // 2) At 250ms from skip: clear the previous cover to `.pending` (blank).
        // 3) At 600ms from skip: stay blank, arm the one-shot script fetch, and
        //    keep `artworkRequestID`. Do not publish `.unavailable`.
        // A decoded cover is written only when the contentIdentifier captured
        // as that lookup started still equals the current track.
        coverLookup = InFlightCoverLookup(
            requestID: requestID,
            contentIdentifier: contentIdentifier
        )
        beginCatalogLookup(
            requestID: requestID,
            contentIdentifier: contentIdentifier,
            title: title,
            artist: artist,
            album: album
        )
        artworkFetchTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    try? await Task.sleep(for: Self.previousCoverLinger)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self?.clearPreviousCoverIfNeeded(requestID: requestID)
                    }
                }
                group.addTask { [weak self] in
                    try? await Task.sleep(for: Self.artworkTimeoutFromTrackChange)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self?.noteSharedArtworkDeadline(requestID: requestID)
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    @MainActor
    private func shouldApplyPlaybackSnapshot(
        _ snapshot: AppleMusicPlaybackSnapshot,
        generation: UInt,
        fetchedArtwork: Bool
    ) -> Bool {
        if generation == playbackInfoRequestGeneration { return true }
        // A later metadata-only playerInfo can bump generation while a delayed
        // script-art fetch is still in flight. Accept that late artwork when
        // it is still for this track and we have no cover yet.
        return fetchedArtwork
            && snapshot.contentIdentifier == playbackState.contentIdentifier
            && playbackState.artworkAvailability != .available
    }

    /// AppleScript `on error` payload: no track, no art, not playing.
    private static func isNotPlayingSentinel(_ snapshot: AppleMusicPlaybackSnapshot) -> Bool {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = snapshot.album.trimmingCharacters(in: .whitespacesAndNewlines)
        let artworkCount = snapshot.artwork?.count ?? 0
        let titleIsSentinel = title.isEmpty
            || title.compare("Not Playing", options: .caseInsensitive) == .orderedSame
        let artistIsSentinel = artist.isEmpty
            || artist.compare("Unknown", options: .caseInsensitive) == .orderedSame
        let albumIsSentinel = album.isEmpty
            || album.compare("Unknown", options: .caseInsensitive) == .orderedSame
        return !snapshot.isPlaying
            && snapshot.duration == 0
            && artworkCount <= minimumArtworkSize
            && titleIsSentinel
            && artistIsSentinel
            && albumIsSentinel
    }

    /// A track the user is actually on. The default placeholder and an
    /// already-applied empty player are not confirmed, so a first empty
    /// snapshot still publishes immediately.
    private var hasConfirmedTrackIdentity: Bool {
        let title = playbackState.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = playbackState.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleIsPlaceholder = title.isEmpty
            || title.compare("Not Playing", options: .caseInsensitive) == .orderedSame
            || title.compare("I'm Handsome", options: .caseInsensitive) == .orderedSame
            || title.compare("Unknown", options: .caseInsensitive) == .orderedSame
        let artistIsPlaceholder = artist.isEmpty
            || artist.compare("Unknown", options: .caseInsensitive) == .orderedSame
            || artist.compare("Me", options: .caseInsensitive) == .orderedSame
        if playbackState.duration > 0.5 { return true }
        return !titleIsPlaceholder || !artistIsPlaceholder
    }

    /// True when `snapshot` is a different real track than the one on screen.
    /// Same-track progress is not a next-track identity.
    private func confirmsNextTrackIdentity(_ snapshot: AppleMusicPlaybackSnapshot) -> Bool {
        guard awaitingTrackAfterNotPlayingSentinel else { return false }
        guard !Self.isNotPlayingSentinel(snapshot) else { return false }
        return snapshot.contentIdentifier != playbackState.contentIdentifier
            || snapshot.title != playbackState.title
            || snapshot.artist != playbackState.artist
    }

    /// Ignore further empty snapshots until the deadline. A real next track
    /// cancels this; the deadline's own fetch may publish a genuine stop.
    private func noteSwallowedNotPlayingSentinel() {
        guard !awaitingTrackAfterNotPlayingSentinel else { return }
        awaitingTrackAfterNotPlayingSentinel = true
        notPlayingSentinelEpoch &+= 1
        let epoch = notPlayingSentinelEpoch
        notPlayingSentinelConfirmTask?.cancel()
        notPlayingSentinelConfirmTask = Task { [weak self] in
            try? await Task.sleep(for: Self.notPlayingSentinelConfirmDelay)
            guard !Task.isCancelled else { return }
            await self?.confirmSwallowedNotPlayingSentinel(epoch: epoch, attempt: 0)
        }
    }

    private func cancelNotPlayingSentinelConfirm() {
        notPlayingSentinelEpoch &+= 1
        awaitingTrackAfterNotPlayingSentinel = false
        notPlayingSentinelConfirmTask?.cancel()
        notPlayingSentinelConfirmTask = nil
    }

    /// If no real track arrived, publish the empty player. A missed fetch must
    /// not leave the previous cover up; one short retry, then the logo.
    private func confirmSwallowedNotPlayingSentinel(epoch: UInt, attempt: Int) async {
        for _ in 0..<10 {
            let ready = await MainActor.run { () -> Bool? in
                guard self.notPlayingSentinelEpoch == epoch else { return nil }
                return self.playbackInfoFetchesInFlight == 0
            }
            guard let ready else { return }
            if ready { break }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
        }
        let generation = await MainActor.run { () -> UInt? in
            guard self.notPlayingSentinelEpoch == epoch else { return nil }
            self.playbackInfoFetchesInFlight += 1
            return self.beginPlaybackInfoRequest()
        }
        guard let generation else { return }
        let snapshot = try? await fetchPlaybackSnapshotAsync(includeArtwork: false)
        await MainActor.run {
            self.playbackInfoFetchesInFlight = max(0, self.playbackInfoFetchesInFlight - 1)
            guard self.notPlayingSentinelEpoch == epoch else { return }
            if let snapshot, !Self.isNotPlayingSentinel(snapshot) {
                self.applyPlaybackInfo(
                    snapshot,
                    generation: generation,
                    fetchedArtwork: false,
                    acceptNotPlayingSentinel: true
                )
                return
            }
            let anotherFetchInFlight = self.playbackInfoFetchesInFlight > 0
            if attempt == 0, snapshot == nil || anotherFetchInFlight {
                self.notPlayingSentinelConfirmTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    await self?.confirmSwallowedNotPlayingSentinel(epoch: epoch, attempt: 1)
                }
                return
            }
            self.applyConfirmedEmptyPlayer()
        }
    }

    /// Confirmed empty player. Logo now — do not start another linger, and do
    /// not keep the previous cover if this fetch never returned.
    @MainActor
    private func applyConfirmedEmptyPlayer() {
        cancelNotPlayingSentinelConfirm()
        artworkFetchTask?.cancel()
        artworkFetchTask = nil
        artworkRequestID = nil
        delayedScriptArtworkTask?.cancel()
        delayedScriptArtworkTask = nil
        delayedScriptContentIdentifier = nil
        coverLookup = nil
        var empty = playbackState
        empty.isPlaying = false
        empty.title = "Not Playing"
        empty.artist = "Unknown"
        empty.album = "Unknown"
        empty.currentTime = 0
        empty.duration = 0
        empty.artwork = nil
        empty.artworkAvailability = .unavailable
        empty.contentIdentifier = "Not Playing|Unknown|Unknown|0"
        peekTrackKey = nil
        peekArtworkRequestID = nil
        peekCoverImage = nil
        empty.liveArtworkURL = nil
        empty.lastUpdated = Date()
        playbackState = empty
    }

    /// Drop the previous cover after the linger window. Publishes `.pending`
    /// so every surface clears to an empty slot. The Music icon is not a
    /// stand-in for "still looking".
    @MainActor
    private func clearPreviousCoverIfNeeded(requestID: UUID) {
        guard artworkRequestID == requestID else { return }
        guard playbackState.artworkAvailability != .available else { return }
        // Still waiting for a real track after a swallowed between-tracks
        // snapshot. Blanking now would stick an empty slot under the upcoming
        // title. That track starts its own 250ms linger.
        if awaitingTrackAfterNotPlayingSentinel { return }
        var artworkState = playbackState
        artworkState.artwork = nil
        artworkState.artworkAvailability = .pending
        playbackState = artworkState
    }

    /// 600ms from the skip. Split from the old `completeArtworkRequest(.unavailable)`:
    /// arm the one-shot script fetch, but do not publish the Music icon and do
    /// not nil `artworkRequestID`. The slot stays `.pending` while catalog and
    /// script are still out. `rejectArtworkMatchingSkippedTrack` stays on so
    /// the script fetch cannot put the previous track's cover back.
    @MainActor
    private func noteSharedArtworkDeadline(requestID: UUID) {
        guard artworkRequestID == requestID else { return }
        guard playbackState.artworkAvailability != .available else { return }
        if awaitingTrackAfterNotPlayingSentinel { return }
        let armed = scheduleDelayedScriptArtworkFetch()
        if !armed {
            noteScriptLookupSettled(contentIdentifier: playbackState.contentIdentifier)
        }
    }

    /// Write a decoded cover for the track whose identifier was captured when
    /// the lookup started. `artworkRequestID` may already have been cleared on
    /// a finished request; it is not the write-back key. A different current
    /// track (rapid skip) does not receive this image.
    @MainActor
    private func publishAvailableArtwork(_ artwork: Data, contentIdentifier: String?) {
        guard contentIdentifierMatchesCurrent(contentIdentifier) else { return }
        guard Self.decodePeekImage(artwork) != nil else { return }
        guard playbackState.artworkAvailability != .available
            || playbackState.artwork != artwork
        else { return }
        rejectArtworkMatchingSkippedTrack = false
        delayedScriptArtworkTask?.cancel()
        delayedScriptArtworkTask = nil
        delayedScriptContentIdentifier = nil
        artworkFetchTask?.cancel()
        artworkFetchTask = nil
        artworkRequestID = nil
        coverLookup = nil
        var artworkState = playbackState
        artworkState.artwork = artwork
        artworkState.artworkAvailability = .available
        playbackState = artworkState
    }

    @MainActor
    private func noteCatalogSettled(requestID: UUID, contentIdentifier: String?) {
        guard var lookup = coverLookup, lookup.requestID == requestID else { return }
        guard contentIdentifierMatchesCurrent(contentIdentifier) else { return }
        lookup.catalogSettled = true
        coverLookup = lookup
        publishUnavailableIfCoverLookupsSettled()
    }

    @MainActor
    private func noteScriptLookupSettled(contentIdentifier: String?) {
        guard var lookup = coverLookup else { return }
        guard Self.contentIdentifiersMatch(lookup.contentIdentifier, contentIdentifier) else { return }
        guard contentIdentifierMatchesCurrent(contentIdentifier) else { return }
        if playbackState.artworkAvailability == .available {
            coverLookup = nil
            return
        }
        lookup.scriptSettled = true
        coverLookup = lookup
        publishUnavailableIfCoverLookupsSettled()
    }

    /// Music icon only once catalog (no-match / failure / 4s cap) and the
    /// one-shot script fetch have both settled with no image for this track.
    @MainActor
    private func publishUnavailableIfCoverLookupsSettled() {
        guard let lookup = coverLookup else { return }
        guard lookup.catalogSettled, lookup.scriptSettled else { return }
        guard contentIdentifierMatchesCurrent(lookup.contentIdentifier) else { return }
        guard playbackState.artworkAvailability != .available else {
            coverLookup = nil
            return
        }
        if awaitingTrackAfterNotPlayingSentinel { return }
        var artworkState = playbackState
        artworkState.artwork = nil
        artworkState.artworkAvailability = .unavailable
        playbackState = artworkState
        artworkRequestID = nil
        artworkFetchTask = nil
        coverLookup = nil
    }

    /// After the 600ms deadline, try one throttled raw-data fetch.
    /// playerInfo itself stays metadata-only — this is not the #71 follow-up.
    /// Returns false when the fetch does not start; the caller treats that as settled.
    @MainActor
    @discardableResult
    private func scheduleDelayedScriptArtworkFetch() -> Bool {
        guard playbackState.artworkAvailability != .available else { return false }
        let contentID = playbackState.contentIdentifier
        delayedScriptContentIdentifier = contentID
        rejectArtworkMatchingSkippedTrack = true
        delayedScriptArtworkTask?.cancel()
        delayedScriptArtworkTask = Task { [weak self] in
            try? await Task.sleep(for: Self.delayedScriptArtworkDelay)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let shouldFetch = await MainActor.run {
                self.playbackState.contentIdentifier == contentID
                    && self.playbackState.artworkAvailability != .available
            }
            guard shouldFetch else {
                await MainActor.run {
                    self.noteScriptLookupSettled(contentIdentifier: contentID)
                }
                return
            }
            await self.updatePlaybackInfo(includeArtwork: true)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.noteScriptLookupSettled(contentIdentifier: contentID)
            }
        }
        return true
    }

    /// Both sides non-empty and equal. Nil does not match nil: a lookup that
    /// never captured an identifier must not write onto whatever is current.
    private static func contentIdentifiersMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs, !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs == rhs
    }

    @MainActor
    private func contentIdentifierMatchesCurrent(_ contentIdentifier: String?) -> Bool {
        Self.contentIdentifiersMatch(contentIdentifier, playbackState.contentIdentifier)
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

    /// Equal or prefix after `canonicalMetadata` (case, diacritics, and width
    /// already folded; non-alphanumerics stripped). Either side empty is not a
    /// match: a symbol-only name collapses to "" and would otherwise prefix-match
    /// every string. `A feat. B` vs `A` matches; `B & A` vs `A` does not.
    private func catalogMetadataMatches(_ candidate: String?, _ expected: String) -> Bool {
        let left = canonicalMetadata(candidate)
        let right = canonicalMetadata(expected)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right || left.hasPrefix(right) || right.hasPrefix(left)
    }

    /// Shown song art is cached only when the artist matches and, when the album
    /// is real, the collection does too. An empty / `Unknown` album caches on
    /// artist + title. A title-tier hit with the wrong artist stays uncached.
    private func songArtworkIsCacheable(
        _ track: ITunesTrack,
        title: String,
        artist: String,
        album: String
    ) -> Bool {
        guard catalogMetadataMatches(track.artistName, artist) else { return false }
        if Self.isMissingCatalogAlbum(album) {
            return catalogMetadataMatches(track.trackName, title)
        }
        return catalogMetadataMatches(track.collectionName, album)
    }

    /// Empty and `Unknown` (any case, surrounding whitespace ignored) are not a real album.
    private static func isMissingCatalogAlbum(_ album: String) -> Bool {
        let trimmed = album.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || trimmed.compare("Unknown", options: .caseInsensitive) == .orderedSame
    }

    /// `artist|album`. Empty or `Unknown` album uses `artist|title` instead,
    /// never `artist|` or `artist|Unknown`. Nil when that title is empty too.
    private static func catalogArtworkCacheKey(artist: String, album: String, title: String) -> String? {
        let artistKey = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let second: String
        if isMissingCatalogAlbum(album) {
            second = title.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            second = album.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !second.isEmpty else { return nil }
        return "\(artistKey)|\(second)"
    }

    private func cachedCatalogArtwork(artist: String, album: String, title: String) -> Data? {
        guard let key = Self.catalogArtworkCacheKey(artist: artist, album: album, title: title),
              let cached = catalogArtworkCache.object(forKey: key as NSString)
        else { return nil }
        return Data(referencing: cached)
    }

    private func storeCatalogArtwork(_ data: Data, artist: String, album: String, title: String) {
        guard let key = Self.catalogArtworkCacheKey(artist: artist, album: album, title: title) else { return }
        catalogArtworkCache.setObject(NSData(data: data), forKey: key as NSString)
    }

    /// Quick Peek snapshot for this track. Nil when the stored key is a newer skip.
    func peekSnapshot(
        title: String,
        artist: String,
        contentIdentifier: String?
    ) -> (requestID: UUID, image: NSImage?)? {
        guard peekTrackKey == Self.peekTrackKey(
            title: title,
            artist: artist,
            contentIdentifier: contentIdentifier
        ), let requestID = peekArtworkRequestID else { return nil }
        return (requestID, peekCoverImage)
    }

    @MainActor
    private func armPeekCover(
        requestID: UUID,
        title: String,
        artist: String,
        contentIdentifier: String?,
        image: NSImage?
    ) {
        peekTrackKey = Self.peekTrackKey(
            title: title,
            artist: artist,
            contentIdentifier: contentIdentifier
        )
        peekArtworkRequestID = requestID
        peekCoverImage = image
    }

    private static func peekTrackKey(
        title: String,
        artist: String,
        contentIdentifier: String?
    ) -> String {
        "\(contentIdentifier ?? "")\u{1e}\(title)\u{1e}\(artist)"
    }

    /// 16-byte placeholder guard, then a real decode. Bytes alone are not a cover.
    private static func decodePeekImage(_ data: Data) -> NSImage? {
        guard data.count > minimumArtworkSize else { return nil }
        return NSImage(data: data)
    }

    @MainActor
    private func noteDecodedPeekCover(_ data: Data, requestID: UUID?) {
        guard let requestID, peekArtworkRequestID == requestID, peekCoverImage == nil else { return }
        guard let image = Self.decodePeekImage(data) else { return }
        peekCoverImage = image
        peekCoverUpdates.send(AppleMusicPeekCoverUpdate(requestID: requestID, image: image))
    }

    @MainActor
    private func beginCatalogLookup(
        requestID: UUID,
        contentIdentifier: String?,
        title: String,
        artist: String,
        album: String
    ) {
        let task = Task { [weak self] in
            let result = await self?.fetchArtworkFromCatalog(
                title: title,
                artist: artist,
                album: album
            ) ?? .transientFailure
            await MainActor.run {
                self?.catalogTasks[requestID] = nil
                self?.resolveCatalogArtwork(
                    result,
                    requestID: requestID,
                    contentIdentifier: contentIdentifier
                )
            }
        }
        catalogTasks[requestID] = task
    }

    /// Cache is written inside the fetch, including when this request is stale.
    /// Shared `albumArt` updates only when `contentIdentifier` captured as this
    /// lookup started is still the current track. A stale request never touches
    /// the UI. `artworkRequestID` is not the key: the 600ms deadline used to nil
    /// it and drop a late hit.
    @MainActor
    private func resolveCatalogArtwork(
        _ result: CatalogArtworkResult,
        requestID: UUID,
        contentIdentifier: String?
    ) {
        switch result {
        case .available(let data):
            guard contentIdentifierMatchesCurrent(contentIdentifier) else { return }
            guard Self.decodePeekImage(data) != nil else {
                noteCatalogSettled(requestID: requestID, contentIdentifier: contentIdentifier)
                return
            }
            noteDecodedPeekCover(data, requestID: requestID)
            publishAvailableArtwork(data, contentIdentifier: contentIdentifier)
        case .unavailable, .transientFailure:
            guard contentIdentifierMatchesCurrent(contentIdentifier) else { return }
            noteCatalogSettled(requestID: requestID, contentIdentifier: contentIdentifier)
        }
    }

    private func fetchArtworkFromCatalog(
        title: String,
        artist: String,
        album: String
    ) async -> CatalogArtworkResult {
        if let cached = cachedCatalogArtwork(artist: artist, album: album, title: title) {
            return .available(cached)
        }

        return await catalogArtworkWithinTimeout(title: title, artist: artist, album: album)
    }

    private func catalogArtworkWithinTimeout(
        title: String,
        artist: String,
        album: String
    ) async -> CatalogArtworkResult {
        await withTaskGroup(of: CatalogArtworkResult.self) { group in
            group.addTask { [weak self] in
                guard let self else { return .transientFailure }
                return await self.fetchCatalogArtworkUncached(title: title, artist: artist, album: album)
            }
            group.addTask {
                try? await Task.sleep(for: Self.catalogLookupTimeout)
                return .transientFailure
            }
            let outcome = await group.next() ?? .transientFailure
            group.cancelAll()
            return outcome
        }
    }

    /// Song search, optional album search, and image download.
    private func fetchCatalogArtworkUncached(
        title: String,
        artist: String,
        album: String
    ) async -> CatalogArtworkResult {
        let (songResult, cacheSong) = await fetchSongArtworkFromCatalog(
            title: title,
            artist: artist,
            album: album
        )
        switch songResult {
        case .available(let data):
            if cacheSong {
                storeCatalogArtwork(data, artist: artist, album: album, title: title)
            }
            return .available(data)
        case .transientFailure:
            return .transientFailure
        case .unavailable:
            break
        }

        // Song search missed. One album lookup, and only when the name is real.
        guard !Self.isMissingCatalogAlbum(album) else { return .unavailable }

        let albumResult = await fetchAlbumArtworkFromCatalog(artist: artist, album: album)
        if case .available(let data) = albumResult {
            storeCatalogArtwork(data, artist: artist, album: album, title: title)
        }
        return albumResult
    }

    private func fetchSongArtworkFromCatalog(
        title: String,
        artist: String,
        album: String
    ) async -> (CatalogArtworkResult, Bool) {
        let query = "\(title) \(artist)"
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=10")
        else { return (.unavailable, false) }

        do {
            let (data, urlResponse) = try await URLSession.shared.data(from: url)
            guard let httpResponse = urlResponse as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                return (.transientFailure, false)
            }

            let searchResponse = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard !searchResponse.results.isEmpty else {
                return (.unavailable, false)
            }

            // Same tiers as before (title+album, album, title). No first-result fallback.
            // A missing album is not a name: comparing the `Unknown` sentinel as a
            // prefix would accept unrelated collections. Title-only still accepts a
            // different artist so an existing cover keeps showing.
            let comparableAlbum = Self.isMissingCatalogAlbum(album) ? "" : album
            let match = searchResponse.results.first(where: {
                catalogMetadataMatches($0.trackName, title)
                    && catalogMetadataMatches($0.collectionName, comparableAlbum)
            }) ?? searchResponse.results.first(where: {
                catalogMetadataMatches($0.collectionName, comparableAlbum)
            }) ?? searchResponse.results.first(where: {
                catalogMetadataMatches($0.trackName, title)
            })

            guard let match, let artworkURLString = match.artworkUrl100 else {
                return (.unavailable, false)
            }
            let downloaded = await downloadCatalogArtwork(from: artworkURLString)
            guard case .available = downloaded else {
                return (downloaded, false)
            }
            let cacheable = songArtworkIsCacheable(match, title: title, artist: artist, album: album)
            return (downloaded, cacheable)
        } catch {
            return (.transientFailure, false)
        }
    }

    private func fetchAlbumArtworkFromCatalog(artist: String, album: String) async -> CatalogArtworkResult {
        let query = "\(artist) \(album)"
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=album&limit=5")
        else { return .unavailable }

        do {
            let (data, urlResponse) = try await URLSession.shared.data(from: url)
            guard let httpResponse = urlResponse as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                return .transientFailure
            }

            let searchResponse = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            // Artist and collection must both match. A leftover "any album" hit
            // was cached and then stuck on every later track of this album.
            let match = searchResponse.results.first(where: {
                catalogMetadataMatches($0.artistName, artist)
                    && catalogMetadataMatches($0.collectionName, album)
                    && $0.artworkUrl100 != nil
            })

            guard let artworkURLString = match?.artworkUrl100 else {
                return .unavailable
            }
            return await downloadCatalogArtwork(from: artworkURLString)
        } catch {
            return .transientFailure
        }
    }

    private func downloadCatalogArtwork(from artworkURLString: String) async -> CatalogArtworkResult {
        let highResURL = artworkURLString.replacingOccurrences(of: "100x100", with: "600x600")
        guard let imageURL = URL(string: highResURL) else {
            return .transientFailure
        }

        do {
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
