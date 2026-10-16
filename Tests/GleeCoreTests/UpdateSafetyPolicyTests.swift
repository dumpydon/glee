// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Testing
@testable import GleeCore

struct UpdateSafetyPolicyTests {
    @Test func ordinaryIdleInstallationDoesNotRequireAHelper() throws {
        try UpdateSafetyPolicy(sessionActive: false, helperBusy: false, protectionActive: false,
                               helperRegistered: false, sleepDisabled: nil).validate()
    }

    @Test func activeSessionAlwaysBlocksReplacement() {
        #expect(throws: NSError.self) {
            try UpdateSafetyPolicy(sessionActive: true, helperBusy: false, protectionActive: false,
                                   helperRegistered: false, sleepDisabled: false).validate()
        }
    }

    @Test func endingSessionStillWaitsForHelperRestoration() throws {
        for state: Bool? in [true, nil] {
            #expect(throws: NSError.self) {
                try UpdateSafetyPolicy(sessionActive: false, helperBusy: false, protectionActive: false,
                                       helperRegistered: true, sleepDisabled: state).validate()
            }
        }
        try UpdateSafetyPolicy(sessionActive: false, helperBusy: false, protectionActive: false,
                               helperRegistered: true, sleepDisabled: false).validate()
    }

    @Test func helperRegistrationAndProtectionCannotRaceAnInstallation() {
        for (busy, active) in [(true, false), (false, true)] {
            #expect(throws: NSError.self) {
                try UpdateSafetyPolicy(sessionActive: false, helperBusy: busy, protectionActive: active,
                                       helperRegistered: true, sleepDisabled: false).validate()
            }
        }
    }
}
