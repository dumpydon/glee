// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Updating replaces the helper's containing bundle. Wait for both the session
/// and any system-wide sleep override to finish before allowing replacement.
public struct UpdateSafetyPolicy {
    public let sessionActive: Bool
    public let helperBusy: Bool
    public let protectionActive: Bool
    public let helperRegistered: Bool
    public let sleepDisabled: Bool?

    public init(sessionActive: Bool, helperBusy: Bool, protectionActive: Bool,
                helperRegistered: Bool, sleepDisabled: Bool?) {
        self.sessionActive = sessionActive
        self.helperBusy = helperBusy
        self.protectionActive = protectionActive
        self.helperRegistered = helperRegistered
        self.sleepDisabled = sleepDisabled
    }

    public var blockingReason: String? {
        if sessionActive { return "End your keep-awake session before updating Glee." }
        if helperBusy || protectionActive { return "Wait for closed-lid protection to finish before updating." }
        if helperRegistered && sleepDisabled != false {
            return "Waiting for macOS sleep settings to be restored. Keep the lid open and try again."
        }
        return nil
    }

    public func validate() throws {
        if let blockingReason {
            throw NSError(domain: "com.dumpydon.glee.updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: blockingReason])
        }
    }
}
