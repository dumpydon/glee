// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Testing
@testable import GleeCore

@Suite struct SessionEndTimeTests {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int, second: Int = 0,
                      month: Int = 10, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day,
                                          hour: hour, minute: minute, second: second))!
    }

    @Test func laterClockTimeStaysTodayAndDropsSeconds() throws {
        let c = calendar(), now = date(10, 21, 45, second: 20, calendar: calendar())
        let chosen = date(1, 22, 15, second: 52, calendar: c)
        let end = try #require(SessionEndTime.nextOccurrence(of: chosen, after: now, calendar: c))
        #expect(end == date(10, 22, 15, calendar: c))
        #expect(SessionDuration.until(end).isValid(at: now))
    }

    @Test func elapsedClockTimeMeansTomorrow() throws {
        let c = calendar(), now = date(10, 21, 45, calendar: calendar())
        let end = try #require(SessionEndTime.nextOccurrence(of: date(10, 8, 0, calendar: c), after: now, calendar: c))
        #expect(end == date(11, 8, 0, calendar: c))
    }

    @Test func currentMinuteNeverProducesAnExpiredDeadline() throws {
        let c = calendar(), now = date(10, 21, 45, second: 20, calendar: calendar())
        let end = try #require(SessionEndTime.nextOccurrence(of: now, after: now, calendar: c))
        #expect(end == date(11, 21, 45, calendar: c))
        #expect(SessionDuration.until(end).isValid(at: now))
    }

    @Test func shortcutCrossesMidnightAtMinutePrecision() {
        let c = calendar(), now = date(10, 23, 50, second: 30, calendar: calendar())
        let end = SessionEndTime.preset(minutes: 30, after: now, calendar: c)
        #expect(end == date(11, 0, 20, calendar: c))
        #expect(SessionDuration.until(end).isValid(at: now))
    }

    @Test func missingSpringClockTimeUsesTheNextValidTime() throws {
        let c = calendar("America/New_York")
        let now = date(8, 1, 50, month: 3, calendar: c)
        let chosen = date(7, 2, 30, month: 3, calendar: c)
        let end = try #require(SessionEndTime.nextOccurrence(of: chosen, after: now, calendar: c))
        #expect(end == date(8, 3, 0, month: 3, calendar: c))
        #expect(SessionDuration.until(end).isValid(at: now))
    }

    @Test func longFallDayDoesNotBypassThe24HourLimit() throws {
        let c = calendar("America/New_York")
        let now = date(1, 0, 30, month: 11, calendar: c)
        let chosen = date(1, 0, 0, month: 11, calendar: c)
        let end = try #require(SessionEndTime.nextOccurrence(of: chosen, after: now, calendar: c))
        #expect(end == date(2, 0, 0, month: 11, calendar: c))
        #expect(!SessionDuration.until(end).isValid(at: now))
    }
}
