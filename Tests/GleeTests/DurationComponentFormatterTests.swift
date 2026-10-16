// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Testing
@testable import Glee

struct DurationComponentFormatterTests {
    @Test(arguments: ["2ddD", "2 hours", "1.5", "-1", "+1", "60", "100", "12\n34", ""])
    func typingAndCommitUseTheSameConstraints(_ text: String) {
        let formatter = DurationComponentFormatter()
        let accepted = text.isEmpty
        #expect(formatter.isPartialStringValid(text, newEditingString: nil, errorDescription: nil) == accepted)
        #expect(formatter.getObjectValue(nil, for: text, errorDescription: nil) == accepted)
    }

    @Test func rangeChangesAreAppliedWithoutRecreatingTheField() {
        let formatter = DurationComponentFormatter()
        #expect(formatter.isPartialStringValid("59", newEditingString: nil, errorDescription: nil))
        formatter.maximum = 24
        #expect(!formatter.isPartialStringValid("59", newEditingString: nil, errorDescription: nil))
        #expect(formatter.isPartialStringValid("24", newEditingString: nil, errorDescription: nil))
        formatter.maximum = 0
        #expect(!formatter.isPartialStringValid("1", newEditingString: nil, errorDescription: nil))
        #expect(formatter.isPartialStringValid("0", newEditingString: nil, errorDescription: nil))
    }

    @Test func acceptedDigitsRoundTripWithoutLosingAnEmptyDraftOrLeadingZero() {
        let formatter = DurationComponentFormatter()
        for text in ["", "0", "05", "59"] {
            var object: AnyObject?
            #expect(formatter.getObjectValue(&object, for: text, errorDescription: nil))
            #expect(formatter.string(for: object) == text)
        }
    }
}
