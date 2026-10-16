// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import IOKit

/// Reads the effective kernel setting. `pmset -g` only prints SleepDisabled
/// after an explicit preference exists, so its omission is not a read failure.
public enum SystemSleepState {
    public static func readDisabled() throws -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { throw ReadError.unavailable }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString,
                                                  kCFAllocatorDefault, 0)?.takeRetainedValue()
        return try decode(value)
    }

    static func decode(_ value: CFTypeRef?) throws -> Bool {
        // Never coerce a missing property, string, or number into a safe default.
        guard let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw ReadError.unavailable }
        return CFEqual(value, kCFBooleanTrue)
    }

    public enum ReadError: LocalizedError {
        case unavailable
        public var errorDescription: String? {
            "macOS did not report a verifiable sleep setting. Closed-lid protection is unavailable."
        }
    }
}
