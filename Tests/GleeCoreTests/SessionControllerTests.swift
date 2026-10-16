// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Testing
@testable import GleeCore

@MainActor
private final class FakePower: PowerManaging {
    var active = false
    var display = false
    var shouldFail = false
    var releases = 0

    func activate(keepDisplayAwake: Bool) throws {
        if shouldFail { throw Failure.denied }
        active = true
        display = keepDisplayAwake
    }

    func deactivate() { active = false; display = false; releases += 1 }
    enum Failure: Error { case denied }
}

@Suite @MainActor
struct SessionControllerTests {
    private let origin = Date(timeIntervalSince1970: 1_000_000)

    @Test func currentErrorReplacesThePreviousSessionNotice() {
        let controller = SessionController(power: FakePower(), schedulesTimers: false)
        controller.start(.minutes(30), at: origin)
        controller.end(reason: .powerRequired)
        #expect(controller.statusMessage == SessionEndReason.powerRequired.description)
        controller.errorMessage = "A newer start error"
        #expect(controller.statusMessage == "A newer start error")
        controller.errorMessage = nil
        #expect(controller.statusMessage == SessionEndReason.powerRequired.description)
    }

    @Test func normalSessionStatesDoNotLeaveANotice() {
        let controller = SessionController(power: FakePower(), schedulesTimers: false)
        #expect(controller.statusMessage == nil)
        controller.start(.minutes(30), at: origin)
        controller.end()
        #expect(controller.statusMessage == nil)
        controller.start(.minutes(1), at: origin)
        controller.refresh(at: origin.addingTimeInterval(60))
        #expect(controller.statusMessage == nil)
    }

    @Test func timedSessionExpiresAtDeadlineAndReleasesPower() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        #expect(controller.start(.minutes(30), at: origin))
        #expect(power.active)
        controller.refresh(at: origin.addingTimeInterval(1799))
        #expect(controller.isActive)
        controller.refresh(at: origin.addingTimeInterval(1800))
        #expect(!controller.isActive)
        #expect(!power.active)
        #expect(controller.lastEndReason == .completed)
    }

    @Test func endingEarlyReleasesPower() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        controller.start(.minutes(30), at: origin)
        controller.end()
        #expect(!power.active && !controller.isActive)
        #expect(controller.lastEndReason == .stopped)
    }

    @Test func freeSessionsCanExtendAndStartAgainWithoutActivation() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        #expect(controller.start(.minutes(1), at: origin))
        controller.extend(at: origin)
        #expect(controller.session?.endsAt == origin.addingTimeInterval(16 * 60))
        controller.end()
        #expect(controller.start(.indefinitely, at: origin))
        controller.refresh(at: origin.addingTimeInterval(30 * 86400))
        #expect(controller.isActive && power.active)
        controller.end()
    }

    @Test func displayToggleUpdatesAssertionsWithoutRestartingTimer() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        controller.start(.minutes(15), at: origin)
        let deadline = controller.session?.endsAt
        #expect(controller.setKeepDisplayAwake(true))
        #expect(power.display)
        #expect(controller.session?.endsAt == deadline)
        #expect(controller.setKeepDisplayAwake(false))
        #expect(!power.display)
        #expect(power.active)
    }

    @Test func failedDisplayChangePreservesWorkingSession() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        controller.start(.minutes(15), at: origin)
        power.shouldFail = true
        #expect(!controller.setKeepDisplayAwake(true))
        #expect(!controller.keepDisplayAwake)
        #expect(controller.isActive)
        #expect(power.active)
        #expect(controller.errorMessage != nil)
    }

    @Test func failedStartNeverClaimsTheMacIsAwake() {
        let power = FakePower()
        power.shouldFail = true
        let controller = SessionController(power: power, schedulesTimers: false)
        #expect(!controller.start(.minutes(30), at: origin))
        #expect(!controller.isActive)
        #expect(!power.active)
        #expect(controller.errorMessage != nil)
    }

    @Test func invalidDurationsDoNotAcquirePower() {
        for minutes in [0, -1, 1441, Int.max] {
            let power = FakePower()
            let controller = SessionController(power: power, schedulesTimers: false)
            #expect(!controller.start(.minutes(minutes), at: origin))
            #expect(!power.active)
        }
    }

    @Test func extensionMovesDeadlineAndDoesNotResurrectExpiredSession() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        controller.start(.minutes(15), at: origin)
        controller.extend(at: origin.addingTimeInterval(60))
        #expect(controller.session?.endsAt == origin.addingTimeInterval(1800))
        controller.extend(at: origin.addingTimeInterval(1800))
        #expect(!controller.isActive)
        #expect(!power.active)
    }

    @Test func extensionIsBoundedTo24Hours() {
        let controller = SessionController(power: FakePower(), schedulesTimers: false)
        controller.start(.minutes(1439), at: origin)
        controller.extend(at: origin)
        #expect(controller.session?.endsAt == origin.addingTimeInterval(86400))
    }

    @Test func sleepEndsSessionWithoutAutomaticRestart() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        controller.start(.minutes(30), at: origin)
        controller.end(reason: .systemSleep)
        controller.refresh(at: origin.addingTimeInterval(60))
        #expect(!power.active)
        #expect(!controller.isActive)
        #expect(controller.lastEndReason == .systemSleep)
    }

    @Test func countdownHandlesBoundaries() {
        #expect(Countdown.string(seconds: 3601) == "1:00:01")
        #expect(Countdown.string(seconds: 59) == "00:59")
        #expect(Countdown.string(seconds: -10) == "00:00")
        let session = AwakeSession(startedAt: origin, endsAt: origin.addingTimeInterval(60))
        #expect(session.remainingSeconds(at: origin.addingTimeInterval(0.1)) == 60)
        #expect(session.remainingSeconds(at: origin.addingTimeInterval(100)) == 0)
    }

    @Test func untilTimeUsesExactChosenDeadline() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        let deadline = origin.addingTimeInterval(95)
        #expect(controller.start(.until(deadline), at: origin))
        #expect(controller.session?.endsAt == deadline)
        controller.refresh(at: deadline.addingTimeInterval(-0.1))
        #expect(power.active)
        controller.refresh(at: deadline)
        #expect(!power.active && controller.lastEndReason == .completed)
    }

    @Test func pastOrOutOfRangeEndTimesCannotStart() {
        for interval in [-60.0, 0, 86401, .infinity, .nan] {
            let power = FakePower()
            let controller = SessionController(power: power, schedulesTimers: false)
            #expect(!controller.start(.until(origin.addingTimeInterval(interval)), at: origin))
            #expect(!power.active)
        }
    }

    @Test func untilStoppedHasNoHiddenDeadlineAndCanEndNormally() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        #expect(controller.start(.indefinitely, at: origin))
        controller.refresh(at: origin.addingTimeInterval(7 * 86400))
        controller.extend(at: origin.addingTimeInterval(7 * 86400))
        #expect(power.active && controller.isActive)
        #expect(controller.session?.endsAt == nil)
        #expect(controller.session?.remainingSeconds(at: origin) == nil)
        controller.end()
        #expect(!power.active && controller.lastEndReason == .stopped)
    }

    @Test func untilStoppedRespectsExplicitSleep() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        controller.start(.indefinitely, at: origin)
        controller.end(reason: .systemSleep)
        #expect(!power.active && controller.lastEndReason == .systemSleep)
    }

    @Test func batteryCutoffEndsTheEntireSessionAndDoesNotResume() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        let policy = SessionPowerPolicy(batteryCutoff: 45, requiresAdapter: false)
        controller.updatePowerSafety(policy: policy, state: .init(source: .battery, batteryPercent: 80))
        controller.start(.indefinitely, at: origin)
        #expect(power.active)
        controller.updatePowerSafety(policy: policy, state: .init(source: .battery, batteryPercent: 45))
        #expect(!power.active && controller.lastEndReason == .lowBattery(45))
        #expect(!controller.start(.minutes(30), at: origin))
        controller.updatePowerSafety(policy: policy, state: .init(source: .adapter, batteryPercent: 45))
        controller.refresh(at: origin.addingTimeInterval(60))
        #expect(!power.active)
        #expect(controller.start(.minutes(30), at: origin))
    }

    @Test func requireAdapterStopsOnUnplugEvenAboveBatteryCutoff() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        let policy = SessionPowerPolicy(batteryCutoff: 30, requiresAdapter: true)
        controller.updatePowerSafety(policy: policy, state: .init(source: .adapter, batteryPercent: 100))
        controller.start(.minutes(120), at: origin)
        controller.updatePowerSafety(policy: policy, state: .init(source: .battery, batteryPercent: 100))
        #expect(!power.active && controller.lastEndReason == .powerRequired)
        #expect(!controller.start(.indefinitely, at: origin))
    }

    @Test func unreadablePowerCannotBypassAnEnabledBatteryGuard() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        let policy = SessionPowerPolicy(batteryCutoff: 30, requiresAdapter: false)
        controller.updatePowerSafety(policy: policy, state: .init(source: .adapter, batteryPercent: 80))
        controller.start(.minutes(30), at: origin)
        controller.updatePowerSafety(policy: policy, state: .init(source: .unknown, batteryPercent: nil))
        #expect(!power.active && controller.lastEndReason == .powerUnknown)
        #expect(!controller.start(.minutes(30), at: origin))
    }

    @Test func startingAgainCannotReplaceAnActiveSession() {
        let power = FakePower()
        let controller = SessionController(power: power, schedulesTimers: false)
        controller.start(.minutes(30), at: origin)
        #expect(!controller.start(.indefinitely, at: origin.addingTimeInterval(10)))
        #expect(controller.session?.endsAt == origin.addingTimeInterval(1800))
    }
}
