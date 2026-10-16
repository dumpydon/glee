// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Testing
@testable import GleeCore

@Suite struct ClosedLidPolicyTests {
    @Test func batteryUseRequiresExplicitOptIn() throws {
        let battery = ClosedLidPowerState(source: .battery, batteryPercent: 100)
        #expect(ClosedLidPolicy.standard.stopReason(for: battery) == .powerRequired)
        let policy = try ClosedLidPolicy(allowsBattery: true, minimumBatteryPercent: 30, maximumBatteryMinutes: 30)
        #expect(policy.stopReason(for: battery) == nil)
    }

    @Test(arguments: ClosedLidPolicy.batteryCutoffs)
    func cutoffStopsAtExactSelectedPercentage(_ cutoff: Int) throws {
        let policy = try ClosedLidPolicy(allowsBattery: true, minimumBatteryPercent: cutoff, maximumBatteryMinutes: 30)
        #expect(policy.stopReason(for: .init(source: .battery, batteryPercent: cutoff + 1)) == nil)
        #expect(policy.stopReason(for: .init(source: .battery, batteryPercent: cutoff)) == .lowBattery(cutoff))
        #expect(policy.stopReason(for: .init(source: .battery, batteryPercent: cutoff - 1)) == .lowBattery(cutoff))
    }

    @Test(arguments: [Int.min, -1, 0, 19, 21, 81, 100, Int.max])
    func invalidCutoffsAreRejectedByHelperPolicy(_ cutoff: Int) {
        #expect(throws: ClosedLidStopReason.invalidPolicy) {
            try ClosedLidPolicy(allowsBattery: true, minimumBatteryPercent: cutoff, maximumBatteryMinutes: 30)
        }
    }

    @Test(arguments: [Int.min, -1, 14, 31, 121, Int.max])
    func invalidDurationsCannotDisableOrOverflowTimeLimit(_ minutes: Int) {
        #expect(throws: ClosedLidStopReason.invalidPolicy) {
            try ClosedLidPolicy(allowsBattery: true, minimumBatteryPercent: 30, maximumBatteryMinutes: minutes)
        }
    }

    @Test func noBatteryTimeLimitRequiresTheExplicitSentinel() throws {
        let policy = try ClosedLidPolicy(allowsBattery: true, minimumBatteryPercent: 45,
                                        maximumBatteryMinutes: ClosedLidPolicy.noBatteryTimeLimit)
        #expect(!policy.hasBatteryTimeLimit)
        #expect(policy.maximumBatteryMinutes == 0)
        #expect(ClosedLidPolicy.standard.hasBatteryTimeLimit)
        #expect(policy.stopReason(for: .init(source: .battery, batteryPercent: 45)) == .lowBattery(45))
    }

    @Test func unknownBatteryOrThermalPressureNeverActivates() throws {
        let policy = try ClosedLidPolicy(allowsBattery: true, minimumBatteryPercent: 20, maximumBatteryMinutes: 120)
        for percent in [nil, -1, 101] as [Int?] {
            #expect(policy.stopReason(for: .init(source: .battery, batteryPercent: percent)) == .powerUnknown)
        }
        #expect(policy.stopReason(for: .init(source: .unknown, batteryPercent: 80)) == .powerUnknown)
        for source in [ClosedLidPowerState.Source.adapter, .battery] {
            #expect(policy.stopReason(for: .init(source: source, batteryPercent: 100, thermalSafe: false)) == .thermalPressure)
        }
    }

    @Test func adapterPolicyPreservesExistingLowBatteryFloorAndSupportsDesktops() throws {
        let policy = try ClosedLidPolicy(allowsBattery: true, minimumBatteryPercent: 80, maximumBatteryMinutes: 15)
        #expect(policy.stopReason(for: .init(source: .adapter, batteryPercent: 21)) == nil)
        #expect(policy.stopReason(for: .init(source: .adapter, batteryPercent: 20)) == .lowBattery(20))
        #expect(policy.stopReason(for: .init(source: .adapter, batteryPercent: nil)) == nil)
    }
}
