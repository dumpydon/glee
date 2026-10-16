// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Keeps session safeguards and closed-lid leases current, including
/// while every window is closed or a menu/sheet is tracking events.
@MainActor
public final class SessionMonitor {
    private let session: SessionController
    private let update: (Bool) -> Void
    private let beforeRefresh: () -> Void
    private var timer: Timer?
    private var stopped = false

    public init(session: SessionController, schedulesTimer: Bool = true,
                beforeRefresh: @escaping () -> Void = {}, update: @escaping (Bool) -> Void) {
        self.session = session
        self.beforeRefresh = beforeRefresh
        self.update = update
        guard schedulesTimer else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.3
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func refresh(at date: Date = .now) {
        guard !stopped else { return }
        beforeRefresh()
        session.refresh(at: date)
        update(session.isActive)
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        timer?.invalidate()
        timer = nil
        update(false)
    }
}
