// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Testing
@testable import GleeCore

@Suite struct SessionPowerPolicyTests {
    @Test(arguments: ClosedLidPolicy.batteryCutoffs)
    func allConfiguredCutoffsApplyOnlyOnBattery(_ cutoff: Int) {
        let policy = SessionPowerPolicy(batteryCutoff: cutoff, requiresAdapter: false)
        #expect(policy.stopReason(for: .init(source: .battery, batteryPercent: cutoff + 1)) == nil)
        #expect(policy.stopReason(for: .init(source: .battery, batteryPercent: cutoff)) == .lowBattery(cutoff))
        #expect(policy.stopReason(for: .init(source: .adapter, batteryPercent: cutoff)) == nil)
    }

    @Test func adapterRequirementDoesNotDependOnBatteryGuard() {
        let policy = SessionPowerPolicy(batteryCutoff: nil, requiresAdapter: true)
        #expect(policy.stopReason(for: .init(source: .battery, batteryPercent: 100)) == .powerRequired)
        #expect(policy.stopReason(for: .init(source: .adapter, batteryPercent: nil)) == nil)
        #expect(policy.stopReason(for: .init(source: .unknown, batteryPercent: nil)) == .powerUnknown)
    }

    @Test func invalidBatteryReadingsFailClosed() {
        let policy = SessionPowerPolicy(batteryCutoff: 30, requiresAdapter: false)
        for percent in [nil, -1, 101] as [Int?] {
            #expect(policy.stopReason(for: .init(source: .battery, batteryPercent: percent)) == .powerUnknown)
        }
    }

    @Test func disabledRulesDoNotInventABatteryRestriction() {
        #expect(SessionPowerPolicy.unrestricted.stopReason(for: .init(source: .battery, batteryPercent: 5)) == nil)
        #expect(SessionPowerPolicy.unrestricted.stopReason(for: .init(source: .unknown, batteryPercent: nil)) == nil)
    }

    @Test func invalidSavedCutoffUsesConservativeDefault() {
        for value in [0, -1, 19, 81, Int.max] {
            let policy = SessionPowerPolicy(batteryCutoff: value, requiresAdapter: false)
            #expect(policy.batteryCutoff == 30)
        }
    }
}
