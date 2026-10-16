// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

public protocol SleepSettingManaging: AnyObject {
    func readDisabled() throws -> Bool
    func writeDisabled(_ value: Bool) throws
    func saveRecovery(_ previousValue: Bool) throws
    func loadRecovery() throws -> Bool?
    func clearRecovery() throws
}

/// Used only on the helper's serial queue. The recovery journal is durable before
/// a system setting changes. A failed restore is retried, never forgotten.
public final class ClosedLidLease {
    private let setting: SleepSettingManaging
    private struct Lease {
        var policy: ClosedLidPolicy
        let started: TimeInterval
        var expires: TimeInterval
        var sampledAt: TimeInterval
        var wasOnBattery: Bool
        var batterySeconds: TimeInterval = 0
        var stopped: ClosedLidStopReason?

        mutating func check(now: TimeInterval, power: ClosedLidPowerState) {
            guard stopped == nil else { return }
            // Count transitions conservatively. Reconnecting the charger pauses
            // this budget; it never resets the battery time already used.
            if wasOnBattery || power.source == .battery { batterySeconds += max(0, now - sampledAt) }
            sampledAt = now
            wasOnBattery = power.source == .battery
            if now >= expires { stopped = .contactLost }
            else if now - started >= 4 * 3600 { stopped = .timeLimit }
            else if let reason = policy.stopReason(for: power) { stopped = reason }
            else if power.source == .battery, policy.hasBatteryTimeLimit,
                    batterySeconds >= Double(policy.maximumBatteryMinutes * 60) {
                stopped = .batteryTimeLimit(policy.maximumBatteryMinutes)
            }
        }
    }
    // Retain stopped records until explicit release/disconnect: a later renewal
    // or a returning charger must never silently undo a safety stop.
    private var leases: [UUID: Lease] = [:]
    public private(set) var isApplied = false
    private var restorationPending = true
    public var needsMonitoring: Bool { !leases.isEmpty || restorationPending || isApplied }

    public init(setting: SleepSettingManaging) { self.setting = setting }
    public func recover() throws {
        leases.removeAll()
        try restore()
    }
    public func renew(client: UUID, now: TimeInterval, policy: ClosedLidPolicy = .standard,
                      power: ClosedLidPowerState) throws {
        try tick(now: now, power: power)
        var lease = leases[client] ?? Lease(policy: policy, started: now, expires: now + 30,
                                           sampledAt: now, wasOnBattery: power.source == .battery)
        lease.policy = policy
        lease.check(now: now, power: power)
        if let reason = lease.stopped {
            leases[client] = lease
            if !hasLiveLease { try restore() }
            throw reason
        }
        if !isApplied {
            // Recover any prior failed operation before creating a fresh lease.
            try restore()
            let previous = try setting.readDisabled()
            restorationPending = true
            try setting.saveRecovery(previous)
            do { try setting.writeDisabled(true); isApplied = true }
            catch { try? restore(); throw error }
        }
        lease.expires = now + 30
        leases[client] = lease
    }
    public func release(client: UUID) throws {
        leases.removeValue(forKey: client)
        if !hasLiveLease { try restore() }
    }
    public func tick(now: TimeInterval, power: ClosedLidPowerState) throws {
        for client in Array(leases.keys) { leases[client]?.check(now: now, power: power) }
        if !hasLiveLease { try restore() }
    }
    private var hasLiveLease: Bool { leases.values.contains { $0.stopped == nil } }
    private func restore() throws {
        if let previous = try setting.loadRecovery() {
            try setting.writeDisabled(previous)
            try setting.clearRecovery()
        }
        isApplied = false
        restorationPending = false
    }
}
