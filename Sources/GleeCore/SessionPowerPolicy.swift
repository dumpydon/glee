// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// These rules apply to all manual sessions, including those with the lid open.
/// Closed-lid safety is enforced independently by the privileged helper.
public struct SessionPowerPolicy: Equatable, Sendable {
    public let batteryCutoff: Int?
    public let requiresAdapter: Bool
    public static let unrestricted = SessionPowerPolicy(batteryCutoff: nil, requiresAdapter: false)

    public init(batteryCutoff: Int?, requiresAdapter: Bool) {
        // Corrupted preferences must not silently disable the battery guard.
        self.batteryCutoff = batteryCutoff.map { ClosedLidPolicy.batteryCutoffs.contains($0) ? $0 : 30 }
        self.requiresAdapter = requiresAdapter
    }

    public func stopReason(for power: ClosedLidPowerState) -> SessionEndReason? {
        guard batteryCutoff != nil || requiresAdapter else { return nil }
        guard power.source != .unknown else { return .powerUnknown }
        if requiresAdapter && power.source != .adapter { return .powerRequired }
        // While connected to a power adapter, a Mac needn't end a
        // normal session at the battery floor. Closed-lid rules remain stricter.
        guard power.source == .battery, let cutoff = batteryCutoff else { return nil }
        guard let percent = power.batteryPercent, (0...100).contains(percent) else { return .powerUnknown }
        return percent <= cutoff ? .lowBattery(cutoff) : nil
    }
}
