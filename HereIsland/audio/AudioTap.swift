/*
 * Atoll (DynamicIsland)
 * Original work Copyright (C) 2026 ZephyrCodesStuff (https://github.com/ZephyrCodesStuff/rtaudio)
 * Modified work Copyright (C) 2026 Atoll Contributors
 *
 * CoreAudio tap for capturing real-time audio from music applications.
 * Uses macOS 14.2+ Process Tap API for efficient audio capture.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This file is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import AudioToolbox
import CoreAudio
import Defaults
import os.log

private let audioTapLog = OSLog(subsystem: "com.locusable.hereisland", category: "AudioTap")

// CoreAudio fires this on a high-priority background real-time thread.
let audioIOProc: AudioDeviceIOProc = {
    inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, clientData in

    guard let clientData else { return noErr }
    let tap = Unmanaged<AudioTap>.fromOpaque(clientData).takeUnretainedValue()

    let mutableInputData = UnsafeMutablePointer(mutating: inInputData)
    let bufferList = UnsafeMutableAudioBufferListPointer(mutableInputData)

    if let firstBuffer = bufferList.first, let data = firstBuffer.mData {
        let floatCount = Int32(firstBuffer.mDataByteSize) / Int32(MemoryLayout<Float>.size)
        tap.bridge.processBuffer(data.assumingMemoryBound(to: Float.self), count: floatCount)
    }

    return noErr
}

/// Captures a mono mixdown of all system audio and exposes smoothed spectrum magnitudes.
class AudioTap: NSObject, @unchecked Sendable {
    static let shared = AudioTap()

    let bridge = AudioBridge()
    private var displayMagnitudes: [Float] = Array(repeating: 0, count: 6)

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var captureIsRunning = false
    private var wantsCapture = false
    private var updateTimer: Timer?

    private let audioQueue = DispatchQueue(label: "com.locusable.hereisland.audiotap", qos: .userInitiated)

    private override init() {
        super.init()
    }

    var isCapturing: Bool { captureIsRunning }

    func getSmoothedMagnitudes() -> [Float] {
        displayMagnitudes
    }

    @objc private func updateSmoothedMagnitudes() {
        let targetLevels = bridge.getSmoothedMagnitudes().map(\.floatValue)
        let smoothingFactor: Float = 0.4

        for i in 0..<min(targetLevels.count, displayMagnitudes.count) {
            displayMagnitudes[i] += (targetLevels[i] - displayMagnitudes[i]) * smoothingFactor
        }
    }

    func setWantsCapture(_ wants: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            wantsCapture = wants
            if wants {
                startCaptureSync()
            } else {
                stopCaptureSync()
            }
        }
    }

    func stopCapture() {
        audioQueue.sync { [weak self] in
            self?.wantsCapture = false
            self?.stopCaptureSync()
        }
    }

    /// A global tap covers every app that outputs audio, so it never needs to be
    /// rebuilt when the user switches players.
    private func startCaptureSync() {
        guard wantsCapture, Defaults[.enableRealTimeWaveform], !captureIsRunning else { return }

        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "HereIsland_Tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        tapID = kAudioObjectUnknown
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            os_log(.error, log: audioTapLog, "Tap creation failed: %d", status)
            reportCaptureFailure()
            return
        }

        var tapUID: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.stride)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        status = withUnsafeMutablePointer(to: &tapUID) { uidPtr in
            AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &propertySize, uidPtr)
        }
        guard status == noErr else {
            os_log(.error, log: audioTapLog, "Tap UID lookup failed: %d", status)
            teardownCoreAudioObjects()
            reportCaptureFailure()
            return
        }

        bridge.configure(withSampleRate: tapSampleRate())

        // Route the tap into a private aggregate device so we can attach an IOProc.
        // Drift compensation keeps the tap clock aligned with the aggregate device.
        let aggregateDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "HereIsland_Virtual_Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]

        aggregateDeviceID = kAudioObjectUnknown
        status = AudioHardwareCreateAggregateDevice(aggregateDict as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            os_log(.error, log: audioTapLog, "Aggregate device creation failed: %d", status)
            teardownCoreAudioObjects()
            reportCaptureFailure()
            return
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        status = AudioDeviceCreateIOProcID(aggregateDeviceID, audioIOProc, selfPointer, &ioProcID)
        guard status == noErr, let ioProcID else {
            os_log(.error, log: audioTapLog, "IOProc creation failed: %d", status)
            teardownCoreAudioObjects()
            reportCaptureFailure()
            return
        }

        status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else {
            os_log(.error, log: audioTapLog, "Device start failed: %d", status)
            teardownCoreAudioObjects()
            reportCaptureFailure()
            return
        }

        // Play state or the preference may have changed while CoreAudio setup ran.
        guard wantsCapture, Defaults[.enableRealTimeWaveform] else {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            teardownCoreAudioObjects()
            return
        }

        captureIsRunning = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            updateTimer?.invalidate()
            let timer = Timer(
                timeInterval: 1.0 / 30.0,
                target: self,
                selector: #selector(updateSmoothedMagnitudes),
                userInfo: nil,
                repeats: true
            )
            RunLoop.main.add(timer, forMode: .common)
            updateTimer = timer
        }
    }

    private func stopCaptureSync() {
        guard captureIsRunning else { return }

        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
        }
        teardownCoreAudioObjects()
        captureIsRunning = false

        DispatchQueue.main.async { [weak self] in
            self?.updateTimer?.invalidate()
            self?.updateTimer = nil
            self?.displayMagnitudes = Array(repeating: 0, count: 6)
        }
    }

    /// Falls back to 48 kHz when the tap does not report a usable format.
    private func tapSampleRate() -> Double {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard status == noErr, format.mSampleRate > 0 else { return 48000 }
        return format.mSampleRate
    }

    private func teardownCoreAudioObjects() {
        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateDeviceID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown
    }

    /// Setup only fails for permission or hardware reasons, so fall back to the
    /// animated waveform instead of leaving the user with flat bars.
    private func reportCaptureFailure() {
        DispatchQueue.main.async {
            guard Defaults[.enableRealTimeWaveform] else { return }
            Defaults[.enableRealTimeWaveform] = false

            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't start real-time waveform")
            alert.informativeText = String(localized: "Here Island needs audio capture permission. Grant access in System Settings → Privacy & Security, then turn Real-time waveform on again.")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Open System Settings"))
            alert.addButton(withTitle: String(localized: "OK"))

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    deinit {
        stopCaptureSync()
    }
}
