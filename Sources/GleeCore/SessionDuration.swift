// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

public enum SessionDuration: Equatable, Sendable {
    case minutes(Int)
    case until(Date)
    case indefinitely

    public static let maximumMinutes = 24 * 60

    public func isValid(at date: Date = .now) -> Bool {
        switch self {
        case .minutes(let minutes): (1...Self.maximumMinutes).contains(minutes)
        case .until(let end): end.timeIntervalSince(date) > 0 && end.timeIntervalSince(date) <= Double(Self.maximumMinutes * 60)
        case .indefinitely: true
        }
    }

    public var label: String {
        switch self {
        case .until: return "Until a specific time"
        case .indefinitely: return "Until stopped"
        case .minutes(let minutes):
            let hours = minutes / 60
            let remainder = minutes % 60
            if hours == 0 { return "\(minutes) min" }
            if remainder == 0 { return "\(hours) \(hours == 1 ? "hour" : "hours")" }
            return "\(hours) hr \(remainder) min"
        }
    }
}
