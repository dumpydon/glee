// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Editable duration components, with validation kept at the session boundary too.
public struct DurationDraft: Equatable {
    public var hours: String
    public var minutes: String

    public init(totalMinutes: Int = 30) {
        let value = (1...SessionDuration.maximumMinutes).contains(totalMinutes) ? totalMinutes : 30
        hours = String(value / 60)
        minutes = String(value % 60)
    }

    public var maximumMinuteComponent: Int { Int(hours) == 24 ? 0 : 59 }

    /// Reject the entire edit rather than turning pasted punctuation into a different duration.
    public static func acceptsComponent(_ text: String, maximum: Int) -> Bool {
        if text.isEmpty { return true }
        guard text.utf8.count <= 2, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int(text) else { return false }
        return value <= maximum
    }

    @discardableResult public mutating func editHours(_ text: String) -> Bool {
        guard Self.acceptsComponent(text, maximum: 24) else { return false }
        hours = text
        if Int(hours) == 24 { minutes = "0" }
        return true
    }

    @discardableResult public mutating func editMinutes(_ text: String) -> Bool {
        guard Self.acceptsComponent(text, maximum: maximumMinuteComponent) else { return false }
        minutes = text
        return true
    }

    public var duration: SessionDuration? {
        func number(_ text: String, maximum: Int) -> Int? {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return 0 }
            guard text.utf8.count <= 2, text.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  let value = Int(text), value <= maximum else { return nil }
            return value
        }
        guard let hours = number(hours, maximum: 24), let minutes = number(minutes, maximum: 59) else { return nil }
        let total = hours * 60 + minutes
        return (1...SessionDuration.maximumMinutes).contains(total) ? .minutes(total) : nil
    }
}
