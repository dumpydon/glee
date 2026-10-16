// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

public struct AwakeSession: Equatable, Sendable {
    public let startedAt: Date
    public var endsAt: Date?

    public init(startedAt: Date, endsAt: Date?) {
        self.startedAt = startedAt
        self.endsAt = endsAt
    }

    public func remainingSeconds(at date: Date) -> Int? {
        guard let endsAt else { return nil }
        return max(0, Int(ceil(endsAt.timeIntervalSince(date))))
    }
}

public enum SessionEndReason: Equatable, Sendable {
    case stopped, completed, systemSleep
    case lowBattery(Int), powerRequired, powerUnknown

    public var description: String {
        switch self {
        case .stopped: "Session ended."
        case .completed: "Session complete."
        case .systemSleep: "Session ended when your Mac went to sleep."
        case .lowBattery(let cutoff): "Session ended at the \(cutoff)% battery cutoff."
        case .powerRequired: "Plug in your charger to continue, or allow battery use in Settings."
        case .powerUnknown: "Could not verify battery or power status. Session protection is off."
        }
    }
}

public enum Countdown {
    public static func string(seconds: Int) -> String {
        let seconds = max(0, seconds)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }
}
