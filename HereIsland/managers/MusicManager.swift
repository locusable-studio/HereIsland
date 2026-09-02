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
import Defaults
import Foundation
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

private struct ITunesExplicitnessSearchResponse: Decodable {
    let results: [ITunesExplicitnessTrack]
}

private struct ITunesExplicitnessTrack: Decodable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let trackExplicitness: String?
}

private actor MusicExplicitnessResolver {
    struct LookupKey: Hashable, Sendable {
        let title: String
        let artist: String
        let album: String

        init(title: String, artist: String, album: String) {
            self.title = MusicExplicitnessResolver.normalize(title)
            self.artist = MusicExplicitnessResolver.normalize(artist)
            self.album = MusicExplicitnessResolver.normalize(album)
        }

        var canResolve: Bool {
            !title.isEmpty && !artist.isEmpty
        }
    }

    static let shared = MusicExplicitnessResolver()

    private let session = URLSession(configuration: .ephemeral)
    private static let cacheLimit = 300
    private var cache: [LookupKey: Bool] = [:]
    private var cacheOrder: [LookupKey] = []
    private var inFlightTasks: [LookupKey: Task<Bool, Never>] = [:]

    private func store(_ value: Bool, for key: LookupKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            while cacheOrder.count > Self.cacheLimit {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        cache[key] = value
    }

    func resolve(title: String, artist: String, album: String) async -> Bool {
        let key = LookupKey(title: title, artist: artist, album: album)
        guard key.canResolve else { return false }

        if let cached = cache[key] {
            return cached
        }

        if let inFlightTask = inFlightTasks[key] {
            return await inFlightTask.value
        }

        let task = Task<Bool, Never> { [session] in
            await Self.fetchExplicitness(for: key, using: session)
        }

        inFlightTasks[key] = task
        let result = await task.value
        store(result, for: key)
        inFlightTasks[key] = nil
        return result
    }

    private static func fetchExplicitness(for key: LookupKey, using session: URLSession) async -> Bool {
        let query = "\(key.title) \(key.artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(
                string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=15")
        else {
            return false
        }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(ITunesExplicitnessSearchResponse.self, from: data)

            let bestMatch = response.results
                .map { track in (track, matchScore(for: track, key: key)) }
                .max { lhs, rhs in lhs.1 < rhs.1 }

            guard let bestMatch,
                  bestMatch.1 >= 8
            else {
                return false
            }

            return bestMatch.0.trackExplicitness?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == "explicit"
        } catch {
            return false
        }
    }

    private static func matchScore(for track: ITunesExplicitnessTrack, key: LookupKey) -> Int {
        let trackTitle = canonicalTitle(track.trackName ?? "")
        guard !trackTitle.isEmpty else { return Int.min }

        let keyTitle = canonicalTitle(key.title)
        let trackArtist = normalize(track.artistName ?? "")
        let trackAlbum = normalize(track.collectionName ?? "")

        var score = 0

        if trackTitle == keyTitle {
            score += 6
        } else if trackTitle.contains(keyTitle) || keyTitle.contains(trackTitle) {
            score += 4
        } else {
            return Int.min
        }

        if !key.artist.isEmpty {
            if trackArtist == key.artist {
                score += 4
            } else if trackArtist.contains(key.artist) || key.artist.contains(trackArtist) {
                score += 2
            }
        }

        if !key.album.isEmpty {
            if trackAlbum == key.album {
                score += 2
            } else if !trackAlbum.isEmpty && (trackAlbum.contains(key.album) || key.album.contains(trackAlbum)) {
                score += 1
            }
        }

        return score
    }

    private static func canonicalTitle(_ value: String) -> String {
        var title = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        title = title.replacingOccurrences(
            of: #"\([^)]*\)|\[[^\]]*\]"#,
            with: " ",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: #"\s-\s(?:\d{4}\s)?(?:remaster(?:ed)?|live|edit|mix|version|mono|stereo).*$"#,
            with: " ",
            options: .regularExpression
        )
        return normalize(title)
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let stripped = folded.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: " ",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?
    @MainActor private var pendingOptimisticPlayState: Bool?

    // Helper to check if macOS has removed support for NowPlayingController
    @Published public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var isCurrentTrackExplicit: Bool = false

    /// Whether there is an active music session with real metadata.
    /// Returns `false` only when the metadata is still placeholder/fallback defaults
    /// (i.e. nothing has been played since app launch, or the controller returned
    /// unknown/not-playing placeholders). Paused music with real metadata is still
    /// considered an active session.
    private static let placeholderTitles: Set<String> = [
        "i'm handsome", "unknown", "not playing"
    ]
    private static let placeholderArtists: Set<String> = [
        "me", "unknown"
    ]

    var hasActiveSession: Bool {
        if isPlaying { return true }
        let trimmedTitle = songTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasRealTitle = !trimmedTitle.isEmpty && !Self.placeholderTitles.contains(trimmedTitle)
        let hasRealArtist = !trimmedArtist.isEmpty && !Self.placeholderArtists.contains(trimmedArtist)
        return hasRealTitle || hasRealArtist
    }

    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isLiveStream: Bool = false
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false

    private var explicitLookupTask: Task<Void, Never>?
    private var explicitLookupKey: String?

    private(set) var artworkData: Data? = nil

    @Published var videoArtworkURL: URL? = nil

    private var liveStreamUnknownDurationCount: Int = 0
    private var liveStreamEdgeObservationCount: Int = 0
    private var liveStreamCompletionObservationCount: Int = 0
    private var liveStreamCompletionReleaseCount: Int = 0

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil
    private var lastArtworkContentIdentifier: String? = nil
    private var lastArtworkContentURL: String? = nil

    @Published var flipAngle: Double = 0
    private let flipAnimationDuration: TimeInterval = 0.45
    private var flipCooldownActive: Bool = false

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    init() {
        Self.sanitizeMediaControllerPreference()

        Defaults.publisher(.mediaController)
            .sink { [weak self] _ in
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                #if DEBUG
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
                #endif
            } catch {
                #if DEBUG
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                #endif
                self.isNowPlayingDeprecated = false
            }

            if self.isNowPlayingDeprecated, Defaults[.mediaController] == .nowPlaying {
                Defaults[.mediaController] = .appleMusic
            }

            self.setActiveControllerBasedOnPreference()
        }
    }

    /// Drop removed controller preferences (YouTube / Amazon / Cider) left in UserDefaults.
    private static func sanitizeMediaControllerPreference() {
        let raw = UserDefaults.standard.string(forKey: Defaults.Keys.mediaController.name)
        if let raw, MediaControllerType(rawValue: raw) == nil {
            Defaults[.mediaController] = .nowPlaying
        }
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        explicitLookupTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        transitionWorkItem?.cancel()

        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self,
                          self.activeController === controller else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]
        #if DEBUG
        print("Preferred Media Controller: \(preferredType)")
        #endif

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType

        if let controller = createController(for: controllerType) {
            setActiveController(controller)
        } else if controllerType != .appleMusic, let fallbackController = createController(for: .appleMusic) {
            // Fallback to Apple Music if preferred controller couldn't be created
            setActiveController(fallbackController)
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Set new active controller
        activeController = controller

        // Get current state from active controller
        forceUpdate()
    }

    @MainActor
    private func applyPlayState(_ state: Bool, animation: Animation?) {
        // Keep the progress bar continuous across pause/resume:
        // - Pausing: freeze at the currently estimated position (not the stale elapsedTime).
        // - Resuming: re-anchor only when the existing timestamp is stale (optimistic
        //   resume after a pause). Fresh media timestamps are preserved.
        if state != isPlaying {
            if !state {
                let frozen = estimatedPlaybackPosition()
                elapsedTime = frozen
                timestampDate = Date()
            } else if Date().timeIntervalSince(timestampDate) > 0.25 {
                timestampDate = Date()
            }
        }

        if let animation {
            var transaction = Transaction()
            transaction.animation = animation
            withTransaction(transaction) {
                self.isPlaying = state
            }
        } else {
            self.isPlaying = state
        }

        self.updateIdleState(state: state)
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        let eventIsPlaying = state.isPlaying
        let expectedState = pendingOptimisticPlayState
        pendingOptimisticPlayState = nil

        // Detect track/content changes first — timing resets depend on this.
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier
        let contentIdentifierChanged = state.contentIdentifier != self.lastArtworkContentIdentifier
        let contentURLChanged = state.contentURL != self.lastArtworkContentURL
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
        let hasContentChange =
            titleChanged
            || artistChanged
            || albumChanged
            || artworkChanged
            || bundleChanged
            || contentIdentifierChanged
            || contentURLChanged
        // Artwork-only updates must not reset progress; only track identity changes.
        let trackIdentityChanged =
            titleChanged
            || artistChanged
            || albumChanged
            || bundleChanged
            || contentIdentifierChanged
            || contentURLChanged

        // Apply timing fields before play-state transitions so freeze/re-anchor
        // operates on the latest media sample instead of being overwritten after.
        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode

        if trackIdentityChanged {
            // New track: always adopt media time. Diff updates sometimes omit elapsedTime
            // and would otherwise keep the previous track's position while paused.
            self.elapsedTime = timeChanged ? state.currentTime : 0
            self.timestampDate = state.lastUpdated
        } else if timeChanged {
            // Right after an optimistic pause freeze, ignore tiny backward media
            // corrections so the bar doesn't snap left. Once the freeze is stale,
            // trust media again so we don't drift away from the real player.
            let justFroze = Date().timeIntervalSince(timestampDate) < 0.45
            let backwardCorrection =
                !eventIsPlaying
                && justFroze
                && state.currentTime < self.elapsedTime
                && (self.elapsedTime - state.currentTime) <= 1.25
            if !backwardCorrection {
                self.elapsedTime = state.currentTime
            }
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }

        // Keep (elapsedTime, timestampDate) as a consistent estimation anchor.
        // After an optimistic resume we may already hold a fresher local timestamp;
        // don't regress to a stale media timestamp unless the elapsed time also updated.
        if !trackIdentityChanged {
            if timeChanged || state.lastUpdated >= self.timestampDate || !eventIsPlaying {
                self.timestampDate = state.lastUpdated
            }
        }

        if eventIsPlaying != self.isPlaying {
            let animation: Animation? = (expectedState == eventIsPlaying) ? .smooth(duration: 0.18) : .smooth
            applyPlayState(eventIsPlaying, animation: animation)
        } else {
            self.updateIdleState(state: eventIsPlaying)
        }

        let liveArtworkChanged = state.liveArtworkURL != self.videoArtworkURL

        if liveArtworkChanged {
            self.videoArtworkURL = state.liveArtworkURL
        }

        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        // Handle artwork and visual transitions for changed content
        if hasContentChange {
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            }
            if let artwork = state.artwork {
                self.artworkData = artwork
            }

            // Update last artwork change values
            self.lastArtworkTitle = state.title
            self.lastArtworkArtist = state.artist
            self.lastArtworkAlbum = state.album
            self.lastArtworkBundleIdentifier = state.bundleIdentifier
            self.lastArtworkContentIdentifier = state.contentIdentifier
            self.lastArtworkContentURL = state.contentURL

            if let liveArtworkURL = state.liveArtworkURL {
                self.videoArtworkURL = liveArtworkURL
            } else {
                self.fetchVideoArtwork()
            }

            self.refreshExplicitFlag(for: state)
        } else if state.isExplicit != nil {
            self.refreshExplicitFlag(for: state)
        }

        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        
        updateLiveStreamState(with: state)
    }

    @MainActor
    private func refreshExplicitFlag(for state: PlaybackState) {
        if let explicitValue = state.isExplicit {
            explicitLookupTask?.cancel()
            explicitLookupTask = nil
            explicitLookupKey = nil

            if isCurrentTrackExplicit != explicitValue {
                isCurrentTrackExplicit = explicitValue
            }
            return
        }

        refreshGenericExplicitFlag(title: state.title, artist: state.artist, album: state.album)
    }

    @MainActor
    private func refreshGenericExplicitFlag(title: String, artist: String, album: String) {
        let lookupKey = MusicExplicitnessResolver.LookupKey(
            title: title,
            artist: artist,
            album: album
        )
        let lookupIdentifier = "generic|\(lookupKey.title)|\(lookupKey.artist)|\(lookupKey.album)"

        guard lookupKey.canResolve,
              !Self.placeholderTitles.contains(lookupKey.title),
              !Self.placeholderArtists.contains(lookupKey.artist)
        else {
            explicitLookupTask?.cancel()
            explicitLookupTask = nil
            explicitLookupKey = nil
            if isCurrentTrackExplicit {
                isCurrentTrackExplicit = false
            }
            return
        }

        guard explicitLookupKey != lookupIdentifier else { return }

        explicitLookupTask?.cancel()
        explicitLookupKey = lookupIdentifier

        if isCurrentTrackExplicit {
            isCurrentTrackExplicit = false
        }

        explicitLookupTask = Task { [weak self] in
            let isExplicit = await MusicExplicitnessResolver.shared.resolve(
                title: title,
                artist: artist,
                album: album
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      self.explicitLookupKey == lookupIdentifier
                else {
                    return
                }

                self.isCurrentTrackExplicit = isExplicit
                self.explicitLookupTask = nil
            }
        }
    }

    private func triggerFlipAnimation() {
        // Debounce: rapid metadata updates (title, artwork, bundle arriving
        // separately for one track change) should only produce a single flip.
        guard !flipCooldownActive else { return }
        flipCooldownActive = true

        withAnimation(.easeInOut(duration: flipAnimationDuration)) {
            flipAngle += 180
        }

        // Reset cooldown after the animation completes so the next
        // genuine track change can flip again.
        DispatchQueue.main.asyncAfter(deadline: .now() + flipAnimationDuration + 0.15) { [weak self] in
            self?.flipCooldownActive = false
        }
    }

    private func updateLiveStreamState(with state: PlaybackState) {
        let duration = state.duration
        let current = max(state.currentTime, elapsedTime)
        let hasKnownDuration = duration.isFinite && duration > 0
        let isPlaying = state.isPlaying

        if hasKnownDuration {
            liveStreamUnknownDurationCount = 0

            let remaining = duration - current
            let clampedDuration = max(duration, 0)
            let clampedCurrent = clampedDuration > 0
                ? max(0, min(current, clampedDuration))
                : max(0, current)
            let progress = clampedDuration > 0 ? clampedCurrent / clampedDuration : 0
            let sliderAppearsComplete = isPlaying && clampedDuration > 0 && progress >= 0.999
            let nearDurationEdge = isPlaying && remaining.isFinite && remaining <= 1.0 && clampedCurrent >= 10

            if sliderAppearsComplete {
                liveStreamCompletionObservationCount = min(liveStreamCompletionObservationCount + 1, 8)
                liveStreamCompletionReleaseCount = 0
            } else {
                liveStreamCompletionReleaseCount = min(liveStreamCompletionReleaseCount + 1, 8)
                if liveStreamCompletionObservationCount > 0 {
                    liveStreamCompletionObservationCount = max(liveStreamCompletionObservationCount - 1, 0)
                }
            }

            if nearDurationEdge || sliderAppearsComplete {
                liveStreamEdgeObservationCount = min(liveStreamEdgeObservationCount + 1, 12)
            } else if liveStreamEdgeObservationCount > 0 {
                liveStreamEdgeObservationCount = max(liveStreamEdgeObservationCount - 1, 0)
            }

            if !isLiveStream {
                if liveStreamCompletionObservationCount >= 3 || liveStreamEdgeObservationCount >= 5 {
                    isLiveStream = true
                }
            } else {
                let shouldClearForKnownDuration =
                    (duration > 10 && remaining > 5)
                    || (liveStreamCompletionObservationCount == 0
                        && liveStreamEdgeObservationCount == 0
                        && liveStreamCompletionReleaseCount >= 4)

                if shouldClearForKnownDuration {
                    isLiveStream = false
                }
            }
        } else if isPlaying {
            liveStreamEdgeObservationCount = max(liveStreamEdgeObservationCount - 1, 0)
            liveStreamCompletionObservationCount = max(liveStreamCompletionObservationCount - 1, 0)
            liveStreamCompletionReleaseCount = 0

            liveStreamUnknownDurationCount = min(liveStreamUnknownDurationCount + 1, 8)
            if liveStreamUnknownDurationCount >= 3 && !isLiveStream {
                isLiveStream = true
            }
        } else {
            liveStreamUnknownDurationCount = 0
            liveStreamEdgeObservationCount = 0
            liveStreamCompletionObservationCount = 0
            liveStreamCompletionReleaseCount = 0
        }
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(3))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    func updateAlbumArt(newAlbumArt: NSImage) {
        withAnimation(.smooth) {
            albumArt = newAlbumArt
            calculateAverageColor()
        }
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(max(0, elapsedTime), songDuration) }

        let timeDifference = max(0, date.timeIntervalSince(timestampDate))
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.prominentOpposingColors { [weak self] primary, _ in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = primary
                }
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        guard let controller = activeController else { return }
        let targetState = !isPlaying

        Task {
            await MainActor.run {
                pendingOptimisticPlayState = targetState
                applyPlayState(targetState, animation: .smooth(duration: 0.18))
            }

            if targetState {
                await controller.play()
            } else {
                await controller.pause()
            }
        }
    }

    func nextTrack() {
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }

    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            #if DEBUG
            print("Error: appBundleIdentifier is nil")
            #endif
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    #if DEBUG
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                    #endif
                } else {
                    #if DEBUG
                    print("Launched app with bundle ID: \(bundleID)")
                    #endif
                }
            }
        } else {
            #if DEBUG
            print("Failed to find app with bundle ID: \(bundleID)")
            #endif
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                await self?.activeController?.updatePlaybackInfo()
            }
        }
    }

    // MARK: - Video Artwork

    func fetchVideoArtwork() {
        guard bundleIdentifier == "com.apple.Music" else {
            return
        }

        let title = songTitle
        let artist = artistName

        Task {
            let url = await AnimatedArtworkManager.shared.fetchAnimatedArtworkURL(
                title: title, artist: artist
            )
            await MainActor.run {
                self.videoArtworkURL = url
            }
        }
    }
}

// MARK: - Album Art Flip Helper

private struct AlbumArtFlipModifier: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: 0.5
            )
            // Counter-rotate the content so the image never appears mirrored.
            // At odd multiples of 180° the 3D rotation mirrors along X;
            // applying an opposite scaleEffect cancels that out.
            .scaleEffect(x: cosineSign(for: angle), y: 1)
    }

    /// Returns +1 when the front face is showing, −1 when the back face is showing.
    private func cosineSign(for degrees: Double) -> CGFloat {
        let cos = Darwin.cos(degrees * .pi / 180)
        // Use a small tolerance to avoid flickering exactly at 90°/270°.
        if cos > 0.001 { return 1 }
        if cos < -0.001 { return -1 }
        return degrees.truncatingRemainder(dividingBy: 360) >= 0 ? -1 : 1
    }
}

extension View {
    func albumArtFlip(angle: Double) -> some View {
        modifier(AlbumArtFlipModifier(angle: angle))
    }
}
