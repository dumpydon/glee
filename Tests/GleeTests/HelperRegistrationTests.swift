// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ServiceManagement
import Testing
@testable import Glee

@MainActor private final class RegistrationStub: HelperRegistering {
    var status: SMAppService.Status = .enabled
    var events: [String] = []
    var failUnregister = false
    var failRegister = false
    var registrationError: NSError?
    var transientFailures = 0
    var requiresApproval = false
    var holdUnregister = false
    var unregisterContinuation: CheckedContinuation<Void, Never>?
    var unregisterStarted: CheckedContinuation<Void, Never>?
    func waitUntilUnregisterStarts() async {
        if unregisterContinuation != nil { return }
        await withCheckedContinuation { unregisterStarted = $0 }
    }
    func unregister() async throws {
        events.append("unregister")
        if failUnregister { throw Failure.denied }
        if holdUnregister {
            await withCheckedContinuation { continuation in
                unregisterContinuation = continuation
                unregisterStarted?.resume(); unregisterStarted = nil
            }
        } else { await Task.yield() }
        events.append("unregistered")
        status = .notRegistered
    }
    func register() async throws {
        events.append("register")
        if let registrationError { throw registrationError }
        if requiresApproval {
            status = .requiresApproval
            throw NSError(domain: "SMAppServiceErrorDomain", code: 1)
        }
        if transientFailures > 0 {
            transientFailures -= 1
            throw NSError(domain: "SMAppServiceErrorDomain", code: 1)
        }
        if failRegister { throw Failure.denied }
        status = .enabled
    }
    enum Failure: Error { case denied }
}

@MainActor @Suite struct HelperRegistrationTests {
    private func withDefaults(_ body: @MainActor (UserDefaults) async throws -> Void) async throws {
        let suite = "GleeHelperTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    @Test func oneSetupActionEnablesAfterApprovalWithoutAnotherToggle() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub(); system.status = .notRegistered
            system.requiresApproval = true
            let registration = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { false })
            let service = ClosedLidService(registration: registration, signedBuild: true,
                                           healthCheck: { (true, "Ready", false) })
            service.enableAfterSetup()
            for _ in 0..<100 where service.isBusy { await Task.yield() }
            #expect(service.needsApproval)
            #expect(!service.isEnabled)
            system.requiresApproval = false; system.status = .enabled
            service.refresh()
            for _ in 0..<100 where service.isBusy { await Task.yield() }
            #expect(service.isEnabled)
            #expect(!service.isBusy)
            #expect(!service.needsApproval)
        }
    }

    @Test func upgradeAwaitsUnregisterAndPersistsOnlyAfterHealthConfirmation() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub()
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { false })
            try await updater.prepare()
            #expect(system.events == ["unregister", "unregistered", "register"])
            #expect(HelperRegistration(system: system, defaults: defaults, fingerprint: "new").needsUpdate)
            updater.confirmedResponsive()
            let relaunched = HelperRegistration(system: system, defaults: defaults, fingerprint: "new")
            try await relaunched.prepare()
            #expect(system.events.count == 3)
            #expect(HelperRegistration(system: system, defaults: defaults, fingerprint: "next").needsUpdate)
        }
    }

    @Test func cancellingDuringUnregisterKeepsLifecycleBusyUntilItSettles() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub(); system.holdUnregister = true
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { false })
            let service = ClosedLidService(registration: updater, signedBuild: true)
            await system.waitUntilUnregisterStarts()
            service.setEnabled(false)
            #expect(service.isBusy)
            service.install(); service.repair(); service.setEnabled(true)
            #expect(!service.isEnabled)
            #expect(system.events == ["unregister"])
            system.unregisterContinuation?.resume(); system.unregisterContinuation = nil
            for _ in 0..<100 where service.isBusy { await Task.yield() }
            #expect(!service.isBusy)
            #expect(!service.isRegistered)
            #expect(service.canRepair)
            #expect(service.setupAction == .setUp)
            #expect(updater.hasPendingUpdate)
            #expect(system.events == ["unregister", "unregistered"])
        }
    }

    @Test func activeProtectionKeepsRecoveryHelperInstalled() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub()
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { true }, restorationChecks: 0)
            await #expect(throws: HelperRegistration.Failure.self) { try await updater.prepare() }
            #expect(system.events.isEmpty)
        }
    }

    @Test func unreadableSleepStateNeverAuthorizesReplacement() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub()
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { throw RegistrationStub.Failure.denied })
            await #expect(throws: RegistrationStub.Failure.self) { try await updater.prepare() }
            #expect(system.events.isEmpty)
        }
    }

    @Test func waitsForRestorationBeforeReplacingHelper() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub()
            var disabled = true
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { disabled }, restorationChecks: 1, pause: {
                #expect(system.events.isEmpty)
                disabled = false
            })
            try await updater.prepare()
            #expect(system.events == ["unregister", "unregistered", "register"])
        }
    }

    @Test func failedUnregisterNeverAttemptsRegister() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub(); system.failUnregister = true
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { false })
            await #expect(throws: RegistrationStub.Failure.self) { try await updater.prepare() }
            #expect(system.events == ["unregister"])
        }
    }

    @Test func failedRegisterIsNotRememberedAsHealthy() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub(); system.failRegister = true
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { false })
            await #expect(throws: RegistrationStub.Failure.self) { try await updater.prepare() }
            #expect(updater.needsUpdate)
            #expect(HelperRegistration(system: system, defaults: defaults, fingerprint: "new").needsUpdate)
        }
    }

    @Test func approvalAndFirstInstallAreNeverBypassed() async throws {
        try await withDefaults { defaults in
            for status: SMAppService.Status in [.notRegistered, .requiresApproval] {
                let system = RegistrationStub(); system.status = status
                let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { false })
                try await updater.prepare(force: true)
                #expect(system.events.isEmpty)
            }
        }
    }

    @Test func missingServiceRegistersWithoutTryingToUnregisterIt() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub(); system.status = .notFound
            system.failUnregister = true
            let updater = HelperRegistration(system: system, defaults: defaults,
                                             fingerprint: "new", readSleepDisabled: { false })
            try await updater.prepare()
            #expect(system.events == ["register"])
            #expect(system.status == .enabled)
            #expect(updater.hasPendingUpdate)
            updater.confirmedResponsive()
            #expect(!updater.hasPendingUpdate)
        }
    }

    @Test func freshInstallDoesNotImmediatelyRegisterTwice() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub(); system.status = .notRegistered
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { false })
            try await updater.install()
            try await updater.prepare()
            #expect(system.events == ["register"])
        }
    }

    @Test func repairCanRefreshAnUnresponsiveCurrentBuild() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub()
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "same", readSleepDisabled: { false })
            updater.confirmedResponsive()
            try await updater.prepare(force: true)
            #expect(system.events == ["unregister", "unregistered", "register"])
        }
    }

    @Test func registrationRaceGetsABoundedRetry() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub(); system.transientFailures = 1
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { false }, pause: {})
            try await updater.prepare()
            #expect(system.events == ["unregister", "unregistered", "register", "register"])
            #expect(system.status == .enabled)
        }
    }

    @Test func interruptedUpdateResumesAfterRelaunchWithoutUnregisteringTwice() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub(); system.failRegister = true
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { false })
            await #expect(throws: RegistrationStub.Failure.self) { try await updater.prepare() }
            #expect(updater.hasPendingUpdate)
            system.failRegister = false
            let relaunched = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { false })
            try await relaunched.prepare()
            #expect(system.events == ["unregister", "unregistered", "register", "register"])
            relaunched.confirmedResponsive()
            #expect(!relaunched.hasPendingUpdate)
        }
    }

    @Test func persistentRegistrationDenialStopsAfterThreeAttempts() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub(); system.transientFailures = 10
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { false }, pause: {})
            await #expect(throws: NSError.self) { try await updater.prepare() }
            #expect(system.events.filter { $0 == "register" }.count == 3)
            #expect(updater.needsUpdate)
        }
    }

    @Test func approvalRequestIsNotRetriedOrRememberedAsHealthy() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub(); system.requiresApproval = true
            let updater = HelperRegistration(system: system, defaults: defaults, fingerprint: "new", readSleepDisabled: { false }, pause: {})
            try await updater.prepare()
            #expect(system.events.filter { $0 == "register" }.count == 1)
            #expect(system.status == .requiresApproval)
            #expect(updater.needsUpdate)
        }
    }

    @Test func failedFirstSetupPreservesTheSystemErrorForSupport() async throws {
        try await withDefaults { defaults in
            let system = RegistrationStub(); system.status = .notRegistered
            system.registrationError = NSError(domain: "SMAppServiceErrorDomain", code: 5,
                                               userInfo: [NSLocalizedDescriptionKey: "The service could not be loaded."])
            let registration = HelperRegistration(system: system, defaults: defaults, fingerprint: "new")
            let service = ClosedLidService(registration: registration, signedBuild: true)
            service.install()
            for _ in 0..<100 where service.isBusy { await Task.yield() }
            #expect(service.issueMessage?.contains("The service could not be loaded.") == true)
            #expect(service.setupDiagnostics.contains("SMAppServiceErrorDomain (code 5)"))
            #expect(service.setupDiagnostics.contains("Background service: Not registered"))
            #expect(service.setupAction == .setUp)
            #expect(!service.isEnabled)

            system.registrationError = nil; system.requiresApproval = true
            service.install()
            for _ in 0..<100 where service.isBusy { await Task.yield() }
            #expect(service.needsApproval)
            #expect(service.issueMessage == nil)
            #expect(service.setupAction == .approve)
            #expect(!service.setupDiagnostics.contains("code 5"))
        }
    }
}
