// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Testing
@testable import GleeCore

@Suite struct DurationDraftTests {
    @Test(arguments: [("0", "1", 1), ("", "30", 30), ("1", "", 60), ("2", "05", 125),
                      ("24", "0", 1440), (" 1 ", " 30 ", 90)])
    func validInputUsesExactlyTheDisplayedDuration(_ input: (String, String, Int)) {
        var draft = DurationDraft()
        draft.hours = input.0; draft.minutes = input.1
        #expect(draft.duration == .minutes(input.2))
    }

    @Test(arguments: [("", ""), ("0", "0"), ("24", "1"), ("25", "0"), ("1", "60"),
                      ("-1", "30"), ("+1", "30"), ("one", "30"), ("1.5", "0"), ("9999999999999999999", "0")])
    func invalidInputCannotStartUsingAnOlderValue(_ input: (String, String)) {
        var draft = DurationDraft(totalMinutes: 30)
        draft.hours = input.0; draft.minutes = input.1
        #expect(draft.duration == nil)
    }

    @Test func oldIndefinitePreferenceBecomesThirtyMinutes() {
        #expect(DurationDraft(totalMinutes: 0).duration == .minutes(30))
        #expect(DurationDraft(totalMinutes: 1441).duration == .minutes(30))
    }

    @Test(arguments: ["2ddD", "abc", "-1", "+1", "1.5", " 2 ", "2\n", "٢", "１２", "9999999999999999999"])
    func rejectedEditsPreserveTheDisplayedValue(_ text: String) {
        var draft = DurationDraft(totalMinutes: 125)
        let original = draft
        let hoursAccepted = draft.editHours(text)
        let minutesAccepted = draft.editMinutes(text)
        #expect(!hoursAccepted)
        #expect(!minutesAccepted)
        #expect(draft == original)
    }

    @Test func componentLimitsApplyDuringEditing() {
        var draft = DurationDraft()
        let oversizedHours = draft.editHours("25")
        let oversizedMinutes = draft.editMinutes("60")
        #expect(!oversizedHours)
        #expect(!oversizedMinutes)
        let hoursAccepted = draft.editHours("23")
        let minutesAccepted = draft.editMinutes("59")
        #expect(hoursAccepted)
        #expect(minutesAccepted)
        #expect(draft.duration == .minutes(1439))
    }

    @Test func twentyFourHoursClearsMinutesAndKeepsTheTotalWithinTheLimit() {
        var draft = DurationDraft(totalMinutes: 90)
        let hoursAccepted = draft.editHours("24")
        #expect(hoursAccepted)
        #expect(draft.minutes == "0")
        #expect(draft.maximumMinuteComponent == 0)
        let extraMinute = draft.editMinutes("1")
        #expect(!extraMinute)
        #expect(draft.duration == .minutes(1440))
        let shorterHours = draft.editHours("2")
        let restoredMinutes = draft.editMinutes("59")
        #expect(shorterHours)
        #expect(restoredMinutes)
        #expect(draft.duration == .minutes(179))
    }

    @Test func clearingAndLeadingZerosRemainEditableWithoutStartingZeroMinutes() {
        var draft = DurationDraft()
        let clearedHours = draft.editHours("")
        let clearedMinutes = draft.editMinutes("")
        #expect(clearedHours)
        #expect(clearedMinutes)
        #expect(draft.duration == nil)
        let hoursAccepted = draft.editHours("00")
        let minutesAccepted = draft.editMinutes("05")
        #expect(hoursAccepted)
        #expect(minutesAccepted)
        #expect(draft.duration == .minutes(5))
    }
}
