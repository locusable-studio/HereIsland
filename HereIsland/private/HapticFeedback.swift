/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Darwin
import IOKit

/// Trackpad haptic for non-activating notch panels.
///
/// `NSHapticFeedbackManager` is a no-op while the app is inactive (our island
/// uses `.nonactivatingPanel`), so we drive MultitouchSupport's private
/// `MTActuator` APIs via dlopen — same approach as other notch utilities.
enum HapticFeedback {
    /// Strong click-like pattern (MultitouchSupport actuation ID 6).
    private static let defaultActuationID: Int32 = 6

    static func perform() {
        if actuateViaMultitouchSupport(actuationID: defaultActuationID) {
            return
        }
        // Fallback when private API is unavailable (no Force Touch device, etc.)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    @discardableResult
    private static func actuateViaMultitouchSupport(actuationID: Int32) -> Bool {
        guard let symbols = MultitouchActuatorSymbols.shared else { return false }

        for deviceID in multitouchDeviceIDs() {
            // Create returns +1; takeRetainedValue transfers ownership to ARC.
            guard let unmanaged = symbols.create(deviceID) else { continue }
            let actuator = unmanaged.takeRetainedValue()

            guard symbols.open(actuator) == kIOReturnSuccess else { continue }
            defer { _ = symbols.close(actuator) }

            // Actuator handle is single-shot; recreate per call (done above).
            if symbols.actuate(actuator, actuationID, 0, 0, 0) == kIOReturnSuccess {
                return true
            }
        }
        return false
    }

    private static func multitouchDeviceIDs() -> [UInt64] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleMultitouchDevice")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var ids: [UInt64] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any]
            else {
                continue
            }

            if let number = dict["Multitouch ID"] as? NSNumber {
                ids.append(number.uint64Value)
            }
        }
        return ids
    }
}

private final class MultitouchActuatorSymbols {
    typealias CreateFn = @convention(c) (UInt64) -> Unmanaged<AnyObject>?
    typealias OpenFn = @convention(c) (AnyObject) -> IOReturn
    typealias CloseFn = @convention(c) (AnyObject) -> IOReturn
    typealias ActuateFn = @convention(c) (AnyObject, Int32, UInt32, Float, Float) -> IOReturn

    let create: CreateFn
    let open: OpenFn
    let close: CloseFn
    let actuate: ActuateFn

    static let shared: MultitouchActuatorSymbols? = MultitouchActuatorSymbols()

    private init?() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        guard
            let createSym = dlsym(handle, "MTActuatorCreateFromDeviceID"),
            let openSym = dlsym(handle, "MTActuatorOpen"),
            let closeSym = dlsym(handle, "MTActuatorClose"),
            let actuateSym = dlsym(handle, "MTActuatorActuate")
        else {
            return nil
        }
        create = unsafeBitCast(createSym, to: CreateFn.self)
        open = unsafeBitCast(openSym, to: OpenFn.self)
        close = unsafeBitCast(closeSym, to: CloseFn.self)
        actuate = unsafeBitCast(actuateSym, to: ActuateFn.self)
    }
}
