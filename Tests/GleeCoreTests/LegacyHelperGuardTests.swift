// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Testing
@testable import GleeCore

@Suite struct LegacyHelperGuardTests {
    @Test func absentOldServiceAndJournalPermitSetup() throws {
        try LegacyHelperGuard.checkResult(exitStatus: 113, hasRecovery: false)
    }

    @Test(arguments: [(Int32(0), false), (Int32(113), true), (Int32(1), false), (Int32(9), false)])
    func activeOrUncertainLegacyStateNeverPermitsTakeover(_ state: (Int32, Bool)) {
        #expect(throws: LegacyHelperGuard.Failure.self) {
            try LegacyHelperGuard.checkResult(exitStatus: state.0, hasRecovery: state.1)
        }
    }

    @Test func bothAppIdentitiesAndRecoveryJournalsAreChecked() throws {
        var services: [String] = []
        var journals: [String] = []
        try LegacyHelperGuard.ensureReady(serviceStatus: { service in
            services.append(service)
            return 113
        }, recoveryExists: { path in
            journals.append(path)
            return false
        })
        #expect(services == ["app.wakebee.helper", "com.awakemac.helper"])
        #expect(journals == ["/private/var/db/app.wakebee.helper/recovery.json",
                             "/private/var/db/com.awakemac.helper/recovery.json"])
        #expect(!services.contains("com.dumpydon.glee.helper"))
        #expect(!journals.contains("/private/var/db/com.dumpydon.glee.helper/recovery.json"))
    }

    @Test(arguments: ["app.wakebee.helper", "com.awakemac.helper"])
    func eitherRegisteredHelperPreventsTakeover(_ activeService: String) {
        #expect(throws: LegacyHelperGuard.Failure.cleanupRequired) {
            try LegacyHelperGuard.ensureReady(serviceStatus: { $0 == activeService ? 0 : 113 },
                                             recoveryExists: { _ in false })
        }
    }

    @Test(arguments: ["/private/var/db/app.wakebee.helper/recovery.json",
                       "/private/var/db/com.awakemac.helper/recovery.json"])
    func eitherRecoveryJournalPreventsTakeover(_ journal: String) {
        #expect(throws: LegacyHelperGuard.Failure.cleanupRequired) {
            try LegacyHelperGuard.ensureReady(serviceStatus: { _ in 113 },
                                             recoveryExists: { $0 == journal })
        }
    }

    @Test(arguments: ["app.wakebee.helper", "com.awakemac.helper"])
    func uncertaintyForEitherAppFailsClosed(_ uncertainService: String) {
        #expect(throws: LegacyHelperGuard.Failure.cannotCheck) {
            try LegacyHelperGuard.ensureReady(serviceStatus: { $0 == uncertainService ? 1 : 113 },
                                             recoveryExists: { _ in false })
        }
    }

    @Test func unprivilegedRegistrationSkipsJournalsButStillChecksBothServices() throws {
        var services: [String] = []
        var checkedRecovery = false
        try LegacyHelperGuard.ensureReady(checkRecovery: false, serviceStatus: { service in
            services.append(service)
            return 113
        }, recoveryExists: { _ in
            checkedRecovery = true
            return true
        })
        #expect(services == ["app.wakebee.helper", "com.awakemac.helper"])
        #expect(!checkedRecovery)
    }

    @Test(arguments: ["app.wakebee.helper", "com.awakemac.helper"])
    func unprivilegedRegistrationStillRejectsEitherService(_ activeService: String) {
        #expect(throws: LegacyHelperGuard.Failure.cleanupRequired) {
            try LegacyHelperGuard.ensureReady(checkRecovery: false,
                                             serviceStatus: { $0 == activeService ? 0 : 113 },
                                             recoveryExists: { _ in false })
        }
    }
}
