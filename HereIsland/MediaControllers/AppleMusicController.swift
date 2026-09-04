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

private struct MediaRemoteArtworkSnapshot: Decodable {
    let artworkData: String?
    let bundleIdentifier: String?
    let duration: Double?
    let playing: Bool?
}

class AppleMusicController: MediaControllerProtocol {
    // MARK: - Properties
    private static let bundleIdentifier = "com.apple.Music"

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
                await self?.updatePlaybackInfo()
            }
        }
    }
    
    deinit {
        notificationTask?.cancel()
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
    
    func updatePlaybackInfo() async {
        let generation = await MainActor.run { beginPlaybackInfoRequest() }
        guard let snapshot = try? await fetchPlaybackSnapshotAsync() else { return }
        await MainActor.run { applyPlaybackInfo(snapshot, generation: generation) }
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
    private func applyPlaybackInfo(_ snapshot: AppleMusicPlaybackSnapshot, generation: UInt) {
        guard generation == playbackInfoRequestGeneration else { return }
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

        if let artworkData = snapshot.artwork,
           artworkData.count > Self.minimumArtworkSize {
            artworkFetchTask?.cancel()
            artworkFetchTask = nil
            artworkRequestID = nil
            artworkRequestContentIdentifier = nil
            updatedState.artwork = artworkData
            updatedState.artworkAvailability = .available
        } else if contentChanged {
            artworkFetchTask?.cancel()
            artworkFetchTask = nil
            artworkRequestID = nil
            artworkRequestContentIdentifier = nil
            updatedState.artwork = nil
            updatedState.artworkAvailability = .unknown
        }

        updatedState.lastUpdated = Date()
        self.playbackState = updatedState

        guard updatedState.artwork == nil,
              artworkRequestContentIdentifier != snapshot.contentIdentifier
        else { return }

        let requestID = UUID()
        let title = updatedState.title
        let artist = updatedState.artist
        let album = updatedState.album
        let duration = updatedState.duration
        let isPlaying = updatedState.isPlaying
        artworkRequestID = requestID
        artworkRequestContentIdentifier = snapshot.contentIdentifier
        artworkFetchTask = Task { [weak self] in
            let result = await self?.fetchFallbackArtwork(
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                isPlaying: isPlaying
            ) ?? .transientFailure
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.completeArtworkRequest(result, requestID: requestID)
            }
        }
    }

    // MARK: - Private Methods

    private func fetchFallbackArtwork(
        title: String,
        artist: String,
        album: String,
        duration: Double,
        isPlaying: Bool
    ) async -> CatalogArtworkResult {
        if let artwork = await fetchArtworkFromAppleMusicMediaRemote(
            duration: duration,
            isPlaying: isPlaying
        ) {
            return .available(artwork)
        }

        return await fetchArtworkFromCatalog(title: title, artist: artist, album: album)
    }

    private func fetchArtworkFromAppleMusicMediaRemote(
        duration: Double,
        isPlaying: Bool
    ) async -> Data? {
        guard duration > 0 else { return nil }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return nil }

        return readArtworkFromAppleMusicMediaRemote(
            duration: duration,
            isPlaying: isPlaying
        )
    }

    private func readArtworkFromAppleMusicMediaRemote(
        duration: Double,
        isPlaying: Bool
    ) -> Data? {
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworkPath = Bundle.main.resourceURL?
                .appendingPathComponent("MediaRemoteAdapter.framework")
                .path
        else {
            return nil
        }

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "get"]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let timeout = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + 5,
                execute: timeout
            )
            defer { timeout.cancel() }

            let output = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  let snapshot = try? JSONDecoder().decode(MediaRemoteArtworkSnapshot.self, from: output),
                  snapshot.bundleIdentifier == Self.bundleIdentifier,
                  snapshot.playing == isPlaying,
                  let remoteDuration = snapshot.duration,
                  abs(remoteDuration - duration) < 1,
                  let artworkString = snapshot.artworkData,
                  let artwork = Data(
                    base64Encoded: artworkString.trimmingCharacters(in: .whitespacesAndNewlines)
                  ),
                  artwork.count > Self.minimumArtworkSize,
                  NSImage(data: artwork) != nil
            else {
                return nil
            }

            return artwork
        } catch {
            if process.isRunning {
                process.terminate()
            }
            return nil
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
            break
        }
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
    
    private func fetchPlaybackSnapshotAsync() async throws -> AppleMusicPlaybackSnapshot? {
        let script = """
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

                set artData to ""
                try
                    set artData to raw data of artwork 1 of current track
                end try

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
        guard let descriptor = try await AppleScriptHelper.execute(script) else { return nil }
        return AppleMusicPlaybackSnapshot(descriptor)
    }
}
