// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// A clock-only choice means its next occurrence, never a silently expired date.
public enum SessionEndTime {
    public static func nextOccurrence(of time: Date, after now: Date = .now,
                                      calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.hour, .minute], from: time)
        components.second = 0
        return calendar.nextDate(after: now, matching: components,
                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }

    public static func preset(minutes: Int, after now: Date = .now,
                              calendar: Calendar = .current) -> Date {
        let end = now.addingTimeInterval(Double(minutes * 60))
        return calendar.dateInterval(of: .minute, for: end)?.start ?? end
    }
}
