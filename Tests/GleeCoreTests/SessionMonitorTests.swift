// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Testing
@testable import GleeCore

@MainActor private final class MonitorPower: PowerManaging {
    func activate(keepDisplayAwake: Bool) throws {}
    func deactivate() {}
}

@Suite @MainActor struct SessionMonitorTests {
    private let origin = Date(timeIntervalSince1970: 1_000_000)

    @Test func timerDemandStopsAtExpiryWithoutAnyAgentService() {
        let session = SessionController(power: MonitorPower(), schedulesTimers: false)
        var demand: [Bool] = []
        let monitor = SessionMonitor(session: session, schedulesTimer: false) { demand.append($0) }
        session.start(.minutes(1), at: origin)
        monitor.refresh(at: origin)
        monitor.refresh(at: origin.addingTimeInterval(59))
        monitor.refresh(at: origin.addingTimeInterval(60))
        #expect(demand == [true, true, false])
        #expect(session.session == nil)
    }

    @Test func shutdownReleasesDemandAndCannotRenewAgain() {
        let session = SessionController(power: MonitorPower(), schedulesTimers: false)
        var demand: [Bool] = []
        let monitor = SessionMonitor(session: session, schedulesTimer: false) { demand.append($0) }
        session.start(.minutes(30), at: origin)
        monitor.refresh(at: origin)
        monitor.stop()
        monitor.refresh(at: origin.addingTimeInterval(60))
        monitor.stop()
        #expect(demand == [true, false])
    }
}
