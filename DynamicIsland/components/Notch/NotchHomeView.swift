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

import Combine
import Defaults
import SwiftUI
import AppKit
import AVFoundation

private final class DynamicIslandArtworkLoopController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?
    private var playbackStateCancellable: AnyCancellable?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)

        if MusicManager.shared.isPlaying {
            player.play()
        }

        playbackStateCancellable = MusicManager.shared.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self else { return }
                if isPlaying {
                    self.player.play()
                } else {
                    self.player.pause()
                }
            }
    }

    deinit {
        player.pause()
        looper = nil
        playbackStateCancellable = nil
    }
}

private final class DynamicIslandArtworkVideoContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

private struct DynamicIslandArtworkVideoView: NSViewRepresentable {
    let url: URL
    let videoGravity: AVLayerVideoGravity

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DynamicIslandArtworkVideoContainerView {
        let view = DynamicIslandArtworkVideoContainerView(frame: .zero)
        context.coordinator.attach(layer: view.playerLayer, url: url, gravity: videoGravity)
        return view
    }

    func updateNSView(_ nsView: DynamicIslandArtworkVideoContainerView, context: Context) {
        context.coordinator.attach(layer: nsView.playerLayer, url: url, gravity: videoGravity)
    }

    final class Coordinator {
        private var controller: DynamicIslandArtworkLoopController?
        private var currentURL: URL?

        func attach(layer: AVPlayerLayer, url: URL, gravity: AVLayerVideoGravity) {
            layer.videoGravity = gravity

            if currentURL != url || controller == nil {
                currentURL = url
                controller = DynamicIslandArtworkLoopController(url: url)
            }

            if layer.player !== controller?.player {
                layer.player = controller?.player
            }
        }
    }
}

struct DynamicIslandArtworkSourceView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.showLiveCanvasInDynamicIsland) private var showLiveCanvasInDynamicIsland

    let cornerRadius: CGFloat
    let contentMode: ContentMode

    private var liveCanvasURL: URL? {
        guard showLiveCanvasInDynamicIsland else { return nil }
        return musicManager.videoArtworkURL
    }

    var body: some View {
        Group {
            if let liveCanvasURL {
                DynamicIslandArtworkVideoView(url: liveCanvasURL, videoGravity: .resizeAspectFill)
            } else {
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        MinimalisticMusicPlayerView(albumArtNamespace: albumArtNamespace)
            .transition(.opacity.combined(with: .blurReplace))
            .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    let isLiveStream: Bool
    var onValueChange: (Double) -> Void
    var labelLayout: TimeLabelLayout = .stacked
    var trailingLabel: TrailingLabel = .duration
    var restingTrackHeight: CGFloat = 8
    var draggingTrackHeight: CGFloat = 14

    enum TimeLabelLayout {
        case stacked
        case inline
    }

    enum TrailingLabel {
        case duration
        case remaining
    }

    var body: some View {
        Group {
            if isLiveStream {
                liveStreamView
            } else {
                switch labelLayout {
                case .stacked:
                    stackedContent
                case .inline:
                    inlineContent
                }
            }
        }
        .onAppear {
            guard !isLiveStream else { return }
            guard !dragging else { return }
            setSliderValueWithoutAnimation(MusicManager.shared.estimatedPlaybackPosition())
        }
        .onChange(of: currentDate) { newDate in
            guard !isLiveStream else { return }
            guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            setSliderValueWithoutAnimation(MusicManager.shared.estimatedPlaybackPosition(at: newDate))
        }
        .onChange(of: isPlaying) { _, playing in
            // Snap slider to the exact position when music pauses so
            // the in-flight animation doesn't coast past the true value.
            if !playing {
                sliderValue = MusicManager.shared.estimatedPlaybackPosition()
            }
        }
        .onChange(of: isLiveStream) { isLive in
            if isLive {
                sliderValue = 0
            }
        }
    }

    private func setSliderValueWithoutAnimation(_ value: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sliderValue = value
        }
    }

    private var stackedContent: some View {
        VStack(spacing: 6) {
            sliderCore
                .frame(height: sliderFrameHeight)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(trailingTimeText)
            }
            .fontWeight(.medium)
            .foregroundColor(timeLabelColor)
            .font(.system(size: 11, weight: .medium, design: .default).monospacedDigit())
        }
    }

    private var inlineContent: some View {
        HStack(spacing: 6) {
            Text(timeString(from: sliderValue))
                .font(inlineLabelFont)
                .foregroundColor(timeLabelColor)
                .frame(width: 36, alignment: .leading)

            sliderCore
                .frame(height: sliderFrameHeight)
                .frame(maxWidth: .infinity)

            Text(trailingTimeText)
                .font(inlineLabelFont)
                .foregroundColor(timeLabelColor)
                .frame(width: 42, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var liveStreamView: some View {
        switch labelLayout {
        case .stacked:
            LiveStreamProgressIndicator(tint: sliderTint)
                .frame(maxWidth: .infinity)
                .frame(height: sliderFrameHeight)
                
        case .inline:
            HStack(spacing: 6) {
                Spacer()
                    .frame(width: 36)
                LiveStreamProgressIndicator(tint: sliderTint)
                    .frame(maxWidth: .infinity)
                    .frame(height: sliderFrameHeight)

                Spacer()
                    .frame(width: 42)
            }
        }
    }

    private var sliderCore: some View {
        CustomSlider(
            value: $sliderValue,
            range: 0 ... duration,
            color: sliderTint,
            dragging: $dragging,
            lastDragged: $lastDragged,
            onValueChange: onValueChange,
            restingTrackHeight: restingTrackHeight,
            draggingTrackHeight: draggingTrackHeight
        )
    }

    private var sliderTint: Color {//
        switch Defaults[.sliderColor] {
        case .albumArt:
            return Color(nsColor: color).ensureMinimumBrightness(factor: 0.6)
        case .accent:
            return .accentColor
        case .white:
            return .white
        }
    }

    private var timeLabelColor: Color {
        Defaults[.playerColorTinting]
            ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6)
            : .gray
    }

    private var trailingTimeText: String {
        switch trailingLabel {
        case .duration:
            return timeString(from: duration)
        case .remaining:
            let remaining = max(duration - sliderValue, 0)
            return "-" + timeString(from: remaining)
        }
    }

    private var inlineLabelFont: Font {
        .system(size: 11, weight: .medium, design: .default).monospacedDigit()
    }

    private var sliderFrameHeight: CGFloat {
        max(restingTrackHeight, draggingTrackHeight)
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }

}


struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var thumbSize: CGFloat = 12
    var restingTrackHeight: CGFloat = 8
    var draggingTrackHeight: CGFloat = 14
    
    @State private var isHovering: Bool = false
    @Default(.enableRealTimeWaveform) var enableRealTimeWaveform
    @Default(.enableWaveformScrubber) var enableWaveformScrubber

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let trackHeight = CGFloat(dragging ? draggingTrackHeight : restingTrackHeight)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width
            
            let showScrubber = false

            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: trackHeight)
                    .cornerRadius(trackHeight / 2)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: trackHeight)
                    .cornerRadius(trackHeight / 2)
            }
            .frame(height: max(restingTrackHeight, draggingTrackHeight), alignment: .bottom)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.bouncy.speed(1.4), value: dragging)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
        }
    }
}

private struct MediaOutputPickerButton: View {
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @StateObject private var volumeModel = MediaOutputVolumeViewModel()
    @State private var isPopoverPresented = false
    @State private var isHoveringPopover = false
    @EnvironmentObject private var vm: DynamicIslandViewModel

    var body: some View {
        HoverButton(icon: buttonIcon, iconColor: .white, scale: .medium) {
            isPopoverPresented.toggle()
            if isPopoverPresented {
                routeManager.refreshDevices()
            }
        }
        .accessibilityLabel(String(localized: "Media output"))
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            MediaOutputSelectorPopover(
                routeManager: routeManager,
                volumeModel: volumeModel,
                onHoverChanged: { hovering in
                    isHoveringPopover = hovering
                    updatePopoverActivity()
                }
            ) {
                isPopoverPresented = false
                isHoveringPopover = false
                updatePopoverActivity()
            }
        }
        .onAppear {
            routeManager.refreshDevices()
        }
        .onChange(of: isPopoverPresented) { _, presented in
            if !presented {
                isHoveringPopover = false
            }
            updatePopoverActivity()
        }
        .onDisappear {
            vm.isMediaOutputPopoverActive = false
        }
    }

    private var buttonIcon: String {
        routeManager.activeDevice?.iconName ?? "speaker.wave.2"
    }

    private func updatePopoverActivity() {
        vm.isMediaOutputPopoverActive = isPopoverPresented && isHoveringPopover
    }
}

private struct AirPlayPickerButton: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var airPlayManager = AppleMusicAirPlayManager.shared
    @State private var isPopoverPresented = false
    @State private var isHoveringPopover = false
    @EnvironmentObject private var vm: DynamicIslandViewModel

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    var body: some View {
        HoverButton(icon: "airplayaudio", iconColor: .white, scale: .medium) {
            isPopoverPresented.toggle()
            if isPopoverPresented {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .accessibilityLabel(String(localized: "AirPlay"))
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            AirPlaySelectorPopover(
                airPlayManager: airPlayManager,
                onHoverChanged: { hovering in
                    isHoveringPopover = hovering
                    updatePopoverActivity()
                }
            ) {
                isPopoverPresented = false
                isHoveringPopover = false
                updatePopoverActivity()
            }
        }
        .onAppear {
            if isAppleMusicActive {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .onChange(of: isPopoverPresented) { _, presented in
            if !presented { isHoveringPopover = false }
            updatePopoverActivity()
        }
        .onChange(of: musicManager.bundleIdentifier) { _, newBundle in
            if newBundle == "com.apple.Music" {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .onDisappear {
            vm.isMediaOutputPopoverActive = false
        }
    }

    private func updatePopoverActivity() {
        vm.isMediaOutputPopoverActive = isPopoverPresented && isHoveringPopover
    }
}

struct MediaOutputSelectorPopover: View {
    @ObservedObject var routeManager: AudioRouteManager
    @ObservedObject var volumeModel: MediaOutputVolumeViewModel
    var onHoverChanged: (Bool) -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            volumeSection
            Divider()
            devicesSection
        }
        .frame(width: 240)
        .padding(16)
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .onDisappear {
            onHoverChanged(false)
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    volumeModel.toggleMute()
                } label: {
                    Image(systemName: volumeIconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.18))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { Double(volumeModel.level) },
                        set: { newValue in
                            volumeModel.setVolume(Float(newValue))
                        }
                    ),
                    in: 0 ... 1
                )
                .tint(.accentColor)
            }

            HStack {
                Text(String(localized: "Output volume"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(volumePercentage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Output devices"))
                .font(.caption)
                .foregroundColor(.secondary)

            if routeManager.devices.isEmpty {
                Text(String(localized: "No audio outputs available"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(routeManager.devices) { device in
                            Button {
                                routeManager.select(device: device)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: device.iconName)
                                        .font(.system(size: 14, weight: .medium))
                                    Text(device.name)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if device.id == routeManager.activeDeviceID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(device.id == routeManager.activeDeviceID ? Color.primary.opacity(0.12) : .clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }
        }
    }

    private var volumeIconName: String {
        if volumeModel.isMuted || volumeModel.level <= 0.001 {
            return "speaker.slash.fill"
        } else if volumeModel.level < 0.33 {
            return "speaker.wave.1.fill"
        } else if volumeModel.level < 0.66 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    private var volumePercentage: String {
        "\(Int(round(volumeModel.level * 100)))%"
    }
}

struct AirPlaySelectorPopover: View {
    @ObservedObject var airPlayManager: AppleMusicAirPlayManager
    var onHoverChanged: (Bool) -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "AirPlay"))
                .font(.caption)
                .foregroundColor(.secondary)

            if airPlayManager.devices.isEmpty {
                Text(String(localized: "No AirPlay devices found"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(airPlayManager.devices) { device in
                            VStack(spacing: 4) {
                                Button {
                                    Task { await airPlayManager.toggleDevice(device) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: device.iconName)
                                            .font(.system(size: 14, weight: .medium))
                                        Text(device.name)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        if device.isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(device.isSelected ? Color.primary.opacity(0.12) : .clear)
                                    )
                                }
                                .buttonStyle(.plain)

                                if device.isSelected {
                                    AirPlayVolumeSlider(
                                        airPlayManager: airPlayManager,
                                        deviceID: device.id
                                    )
                                    .padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 240)
        .padding(16)
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .onDisappear {
            onHoverChanged(false)
        }
    }
}

/// Local @State slider decoupled from the manager's @Published state.
/// This prevents SwiftUI from resetting the slider position when other
/// published properties on the manager change during a drag.
struct AirPlayVolumeSlider: View {
    @ObservedObject var airPlayManager: AppleMusicAirPlayManager
    let deviceID: String

    @State private var sliderValue: Double = 0
    @State private var isSyncing = false

    var body: some View {
        Slider(value: $sliderValue, in: 0...100)
            .tint(.accentColor)
            .onAppear {
                isSyncing = true
                sliderValue = Double(airPlayManager.currentVolume(for: deviceID))
                isSyncing = false
            }
            .onChange(of: sliderValue) { _, newValue in
                guard !isSyncing else { return }
                airPlayManager.setVolume(Int(newValue), for: deviceID)
            }
    }
}

final class MediaOutputVolumeViewModel: ObservableObject {
    @Published var level: Float
    @Published var isMuted: Bool

    private let controller: SystemVolumeController
    private var cancellables: Set<AnyCancellable> = []

    init(controller: SystemVolumeController = .shared) {
        self.controller = controller
        controller.start()
        level = controller.currentVolume
        isMuted = controller.isMuted

        NotificationCenter.default.publisher(for: .systemVolumeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self,
                      let value = notification.userInfo?["value"] as? Float,
                      let muted = notification.userInfo?["muted"] as? Bool else { return }
                self.level = value
                self.isMuted = muted
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .systemAudioRouteDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFromController()
            }
            .store(in: &cancellables)
    }

    func setVolume(_ value: Float) {
        level = value
        if value > 0 {
            isMuted = false
        }
        controller.setVolume(value)
    }

    func toggleMute() {
        isMuted.toggle()
        controller.toggleMute()
    }

    private func syncFromController() {
        level = controller.currentVolume
        isMuted = controller.isMuted
    }
}

#Preview {
    NotchHomeView(
        albumArtNamespace: Namespace().wrappedValue
    )
    .environmentObject(DynamicIslandViewModel())
}
