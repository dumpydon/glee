// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Testing
@testable import Glee

struct ClosedLidSetupActionTests {
    @Test func firstInstallHasOneSetupActionEvenAfterARegistrationFailure() {
        for repairFlag in [false, true] {
            #expect(ClosedLidSetupAction(signedBuild: true, isRegistered: false,
                                        needsApproval: false, canRepair: repairFlag) == .setUp)
        }
    }

    @Test func approvalMustBeCompletedBeforeInstallationOrRepair() {
        for registered in [false, true] {
            for repairFlag in [false, true] {
                #expect(ClosedLidSetupAction(signedBuild: true, isRegistered: registered,
                                            needsApproval: true, canRepair: repairFlag) == .approve)
            }
        }
    }

    @Test func onlyAnInstalledHelperOffersRepair() {
        #expect(ClosedLidSetupAction(signedBuild: true, isRegistered: true,
                                    needsApproval: false, canRepair: true) == .repair)
        #expect(ClosedLidSetupAction(signedBuild: true, isRegistered: true,
                                    needsApproval: false, canRepair: false) == nil)
    }

    @Test func unsignedBuildCannotOfferAHelperAction() {
        #expect(ClosedLidSetupAction(signedBuild: false, isRegistered: false,
                                    needsApproval: false, canRepair: true) == nil)
        #expect(ClosedLidSetupAction(signedBuild: false, isRegistered: true,
                                    needsApproval: true, canRepair: true) == nil)
    }
}
