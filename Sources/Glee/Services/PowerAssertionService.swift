// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import GleeCore
import Foundation
import IOKit.pwr_mgt

@MainActor
final class PowerAssertionService: PowerManaging {
    private var assertionIDs: [IOPMAssertionID] = []

    func activate(keepDisplayAwake: Bool) throws {
        var replacements: [IOPMAssertionID] = []
        do {
            replacements.append(try create(type: kIOPMAssertionTypePreventUserIdleSystemSleep,
                                           reason: "Glee keep-awake session"))
            if keepDisplayAwake {
                replacements.append(try create(type: kIOPMAssertionTypePreventUserIdleDisplaySleep,
                                               reason: "Glee display awake"))
            }
        } catch {
            replacements.forEach { IOPMAssertionRelease($0) }
            throw error
        }
        deactivate()
        assertionIDs = replacements
    }

    func deactivate() {
        assertionIDs.forEach { IOPMAssertionRelease($0) }
        assertionIDs.removeAll()
    }

    private func create(type: String, reason: String) throws -> IOPMAssertionID {
        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               reason as CFString, &identifier)
        guard result == kIOReturnSuccess else { throw PowerError(code: result) }
        return identifier
    }
}

private struct PowerError: LocalizedError {
    let code: IOReturn
    var errorDescription: String? {
        "macOS couldn’t start sleep prevention (\(code)). Try starting the session again."
    }
}
