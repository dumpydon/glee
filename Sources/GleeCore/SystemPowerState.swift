// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import IOKit.ps

public enum SystemPowerState {
    public static var snapshot: ClosedLidPowerState {
        let thermal = ProcessInfo.processInfo.thermalState
        let thermalSafe = thermal == .nominal || thermal == .fair
        let unavailable = ClosedLidPowerState(source: .unknown, batteryPercent: nil, thermalSafe: thermalSafe)
        guard let unmanaged = IOPSCopyPowerSourcesInfo() else { return unavailable }
        let info = unmanaged.takeRetainedValue()
        guard let providingSource = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return unavailable }
        let powerSource: ClosedLidPowerState.Source
        switch providingSource {
        case kIOPSACPowerValue: powerSource = .adapter
        case kIOPSBatteryPowerValue: powerSource = .battery
        default: return unavailable
        }
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        var batteryPercent: Int?
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { return unavailable }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            guard let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0,
                  current >= 0, current <= maximum else { return unavailable }
            let percent = Int((Double(current) / Double(maximum) * 100).rounded(.down))
            batteryPercent = min(batteryPercent ?? 100, percent)
        }
        if powerSource == .battery && batteryPercent == nil { return unavailable }
        return ClosedLidPowerState(source: powerSource, batteryPercent: batteryPercent, thermalSafe: thermalSafe)
    }
}
