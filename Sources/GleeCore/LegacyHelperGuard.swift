// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Darwin

/// Other apps own separate recovery journals, but all helpers change the same
/// system sleep setting. Only inspect their state; never take over their leases.
public enum LegacyHelperGuard {
    // Compatibility identity used by existing callers.
    public static let service = "com.awakemac.helper"
    public static let recoveryPath = "/private/var/db/com.awakemac.helper/recovery.json"

    public struct ProtectedHelper: Sendable {
        public let service: String
        public let recoveryPath: String
    }

    public static let protectedHelpers = [
        ProtectedHelper(service: "app.wakebee.helper",
                        recoveryPath: "/private/var/db/app.wakebee.helper/recovery.json"),
        ProtectedHelper(service: service, recoveryPath: recoveryPath)
    ]

    public static func checkResult(exitStatus: Int32, hasRecovery: Bool) throws {
        guard !hasRecovery, exitStatus == 113 else {
            throw exitStatus == 0 || hasRecovery ? Failure.cleanupRequired : Failure.cannotCheck
        }
    }

    public static func ensureReady(checkRecovery: Bool = true) throws {
        try ensureReady(checkRecovery: checkRecovery, serviceStatus: readServiceStatus,
                        recoveryExists: { FileManager.default.fileExists(atPath: $0) })
    }

    // Inject read-only observations so tests cannot launch, unregister, or change
    // either app's helper and can check each independent conflict.
    static func ensureReady(checkRecovery: Bool = true,
                            serviceStatus: (String) throws -> Int32,
                            recoveryExists: (String) -> Bool) throws {
        for helper in protectedHelpers {
            let status = try serviceStatus(helper.service)
            try checkResult(exitStatus: status,
                            hasRecovery: checkRecovery && recoveryExists(helper.recoveryPath))
        }
    }

    private static func readServiceStatus(_ service: String) throws -> Int32 {
        let process = Process(), finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/\(service)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + 3) == .success else {
            process.terminate()
            if finished.wait(timeout: .now() + 1) != .success { kill(process.processIdentifier, SIGKILL) }
            throw Failure.cannotCheck
        }
        return process.terminationStatus
    }

    public enum Failure: LocalizedError, Equatable {
        case cleanupRequired, cannotCheck
        public var errorDescription: String? {
            switch self {
            case .cleanupRequired:
                "Another sleep app still has a closed-lid helper or sleep recovery pending. End its session, restore normal sleep, and remove its closed-lid setup from that app’s settings before setting up Glee. Keep the lid open. Glee does not change the other app’s setup."
            case .cannotCheck:
                "Glee couldn’t check the other apps’ closed-lid setup. Keep the lid open and try again."
            }
        }
    }
}
