// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import GleeCore
import GleeHelperProtocol
import Darwin
import Foundation
import OSLog

final class HelperHost: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.dumpydon.glee.helper.leases")
    let leases = ClosedLidLease(setting: SystemSleepSetting())
    let log = Logger(subsystem: HelperIdentity.service, category: "Recovery")
    var watchdog: DispatchSourceTimer?
    var terminationSources: [DispatchSourceSignal] = []
    let clientPolicy: (requirement: String, ownerUID: UInt32?)
    init(clientPolicy: (requirement: String, ownerUID: UInt32?)) {
        self.clientPolicy = clientPolicy
        super.init()
    }
    func start() {
        queue.sync { do { try leases.recover() } catch { log.error("Recovery failed: \(error.localizedDescription)") } }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [self] in
            guard leases.needsMonitoring else { return }
            do { try leases.tick(now: ProcessInfo.processInfo.systemUptime, power: SystemPowerState.snapshot) }
            catch { log.error("Sleep restoration failed; will retry: \(error.localizedDescription)") }
        }
        timer.resume(); watchdog = timer
        for value in [SIGTERM, SIGINT] {
            signal(value, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: value, queue: queue)
            source.setEventHandler { [self] in
                try? leases.recover()
                exit(0)
            }
            source.resume(); terminationSources.append(source)
        }
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else { return false }
        if let ownerUID = clientPolicy.ownerUID,
           connection.effectiveUserIdentifier != ownerUID { return false }
        connection.setCodeSigningRequirement(clientPolicy.requirement)
        let client = UUID()
        connection.exportedInterface = NSXPCInterface(with: GleeHelperProtocol.self)
        connection.exportedObject = HelperEndpoint(host: self, client: client)
        connection.invalidationHandler = { [self] in
            queue.async {
                do { try self.leases.release(client: client) }
                catch { self.log.error("Disconnected client recovery failed; will retry.") }
            }
        }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume()
        return true
    }
}
final class HelperEndpoint: NSObject, GleeHelperProtocol, @unchecked Sendable {
    let host: HelperHost
    let client: UUID
    init(host: HelperHost, client: UUID) { self.host = host; self.client = client }
    func checkHealth(reply: @escaping @Sendable (Bool, String) -> Void) {
        host.queue.async {
            do {
                try LegacyHelperGuard.ensureReady()
                _ = try SystemSleepState.readDisabled()
                reply(true, "Helper connected. Ready for closed-lid sessions.")
            } catch { reply(false, error.localizedDescription) }
        }
    }
    func renew(reply: @escaping @Sendable (Bool, String) -> Void) {
        renewWithPolicy(allowsBattery: false, minimumBatteryPercent: 30, maximumBatteryMinutes: 30, reply: reply)
    }
    func renewWithPolicy(allowsBattery: Bool, minimumBatteryPercent: Int, maximumBatteryMinutes: Int,
                         reply: @escaping @Sendable (Bool, String) -> Void) {
        host.queue.async { [self] in
            do {
                try LegacyHelperGuard.ensureReady()
                let policy = try ClosedLidPolicy(allowsBattery: allowsBattery,
                                                minimumBatteryPercent: minimumBatteryPercent,
                                                maximumBatteryMinutes: maximumBatteryMinutes)
                let power = SystemPowerState.snapshot
                try host.leases.renew(client: client, now: ProcessInfo.processInfo.systemUptime, policy: policy, power: power)
                reply(true, power.source == .battery ? "Closed-lid protection is active on battery." : "Closed-lid protection is active on power adapter.")
            } catch {
                if error is LegacyHelperGuard.Failure {
                    do { try host.leases.recover() }
                    catch { reply(false, error.localizedDescription); return }
                }
                // An invalid request must revoke an existing lease as well.
                if error as? ClosedLidStopReason == .invalidPolicy {
                    do { try host.leases.release(client: client) }
                    catch { reply(false, error.localizedDescription); return }
                }
                reply(false, error.localizedDescription)
            }
        }
    }
    func releaseLease(reply: @escaping @Sendable (Bool, String) -> Void) {
        host.queue.async { [self] in
            do {
                try host.leases.release(client: client)
                reply(!host.leases.isApplied, host.leases.isApplied ? "Another Glee session is using the helper." : "Normal sleep settings restored")
            }
            catch { reply(false, error.localizedDescription) }
        }
    }
}

// Apple team anchoring or an admin-installed, root-owned per-build pin is mandatory.
guard geteuid() == 0, let clientPolicy = HelperIdentity.currentHelperClientPolicy else {
    fputs("Glee helper requires root and an authenticated Apple or local installation.\n", stderr)
    exit(77)
}
umask(0o077)
let host = HelperHost(clientPolicy: clientPolicy)
host.start()
let listener = NSXPCListener(machServiceName: HelperIdentity.service)
listener.delegate = host
listener.resume()
RunLoop.current.run()
