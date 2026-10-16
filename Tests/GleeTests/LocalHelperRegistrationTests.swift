// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ServiceManagement
import Testing
@testable import Glee

@MainActor private final class LocalInstallationState {
    var matches = false
    var installed = false
    var presentedRemoval: [Bool] = []
    var presentationFailure: Error?

    func registration() -> SystemHelperRegistration {
        SystemHelperRegistration(usesLocalSetup: { true },
                                 identityMatches: { self.matches },
                                 hasInstallation: { self.installed },
                                 presenter: { removal in
            if let failure = self.presentationFailure { throw failure }
            self.presentedRemoval.append(removal)
        })
    }
}

@MainActor @Suite struct LocalHelperRegistrationTests {
    private func withService(state: LocalInstallationState,
                             health: @escaping () async -> (Bool, String, Bool),
                             _ body: (ClosedLidService, SystemHelperRegistration) async throws -> Void) async throws {
        let suite = "GleeLocalRegistrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let system = state.registration()
        let registration = HelperRegistration(system: system, defaults: defaults, fingerprint: "local-build",
                                              readSleepDisabled: { false })
        let service = ClosedLidService(registration: registration, signedBuild: true, healthCheck: health)
        try await body(service, system)
    }

    private func settle(_ service: ClosedLidService) async throws {
        for _ in 0..<100 {
            if !service.isBusy { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(!service.isBusy)
    }

    @Test func initialLocalSetupWaitsForObservedInstallation() async throws {
        let state = LocalInstallationState()
        let registration = state.registration()
        #expect(registration.usesLocalSetup)
        #expect(registration.status == .notRegistered)
        try await registration.register()
        #expect(state.presentedRemoval == [false])
        #expect(registration.status == .requiresApproval)
        #expect(!registration.localIdentityMatches)
        state.installed = true
        #expect(registration.status == .requiresApproval)
        state.matches = true
        #expect(registration.status == .enabled)
    }

    @Test func explicitCancellationClearsUnfinishedInstallIntent() async throws {
        let state = LocalInstallationState()
        let registration = state.registration()
        try await registration.register()
        #expect(registration.status == .requiresApproval)
        registration.cancelLocalOperation()
        #expect(registration.status == .notRegistered)
        #expect(!state.installed)
        #expect(state.presentedRemoval == [false])
    }

    @Test func completedInstallDoesNotRetainStaleApprovalIntent() async throws {
        let state = LocalInstallationState()
        let registration = state.registration()
        try await registration.register()
        state.installed = true; state.matches = true
        #expect(registration.status == .enabled)
        state.installed = false; state.matches = false
        #expect(registration.status == .notRegistered)
    }

    @Test func removalOfMismatchedBuildStillOffersApprovalAndCancellation() async throws {
        let state = LocalInstallationState(); state.installed = true
        let registration = state.registration()
        #expect(!registration.localIdentityMatches)
        #expect(registration.hasLocalInstallation)
        try await registration.unregister()
        #expect(state.presentedRemoval == [true])
        #expect(registration.status == .requiresApproval)
        registration.cancelLocalOperation()
        #expect(registration.status == .notRegistered)
        #expect(registration.hasLocalInstallation)
    }

    @Test func cancellationOfRemovalRetainsExistingAuthorization() async throws {
        let state = LocalInstallationState(); state.installed = true; state.matches = true
        let registration = state.registration()
        try await registration.unregister()
        #expect(registration.status == .requiresApproval)
        registration.cancelLocalOperation()
        #expect(registration.status == .enabled)
        #expect(state.installed)
    }

    @Test func removalCompletionIsObservedWithoutAnOldAppPin() async throws {
        let state = LocalInstallationState(); state.installed = true
        let registration = state.registration()
        try await registration.unregister()
        #expect(registration.status == .requiresApproval)
        state.installed = false
        #expect(registration.status == .notRegistered)
        #expect(!registration.hasLocalInstallation)
    }

    @Test func failedPackagePresentationDoesNotInventApproval() async throws {
        let state = LocalInstallationState()
        state.presentationFailure = NSError(domain: "GleeLocalTests", code: 1)
        let registration = state.registration()
        await #expect(throws: NSError.self) { try await registration.register() }
        #expect(registration.status == .notRegistered)
        #expect(state.presentedRemoval.isEmpty)
    }

    @Test func setupEnablesOnlyAfterManifestAndHelperHealthAgree() async throws {
        let state = LocalInstallationState()
        var healthChecks = 0
        try await withService(state: state, health: {
            healthChecks += 1
            return (true, "Ready", false)
        }) { service, _ in
            service.enableAfterSetup()
            try await settle(service)
            #expect(service.needsApproval)
            #expect(!service.isEnabled)
            #expect(healthChecks == 0)
            state.installed = true; state.matches = true
            service.refresh()
            try await settle(service)
            #expect(service.isRegistered)
            #expect(!service.needsApproval)
            #expect(service.isEnabled)
            #expect(healthChecks == 1)
            service.setEnabled(false)
        }
    }

    @Test func cancellingSetupPreventsLaterInstallationFromAutoEnabling() async throws {
        let state = LocalInstallationState()
        try await withService(state: state, health: { (true, "Ready", false) }) { service, _ in
            service.enableAfterSetup()
            try await settle(service)
            service.cancelLocalSetup()
            #expect(!service.needsApproval)
            #expect(!service.isEnabled)
            state.installed = true; state.matches = true
            service.refresh()
            try await settle(service)
            #expect(service.isRegistered)
            #expect(!service.isEnabled)
        }
    }

    @Test func sameBuildRepairRechecksHealthAfterInstallerReturns() async throws {
        let state = LocalInstallationState(); state.installed = true; state.matches = true
        var healthy = false
        var healthChecks = 0
        try await withService(state: state, health: {
            healthChecks += 1
            return healthy ? (true, "Ready", false) : (false, "Not responding", true)
        }) { service, _ in
            try await settle(service)
            #expect(service.canRepair)
            service.enableAfterSetup()
            try await settle(service)
            #expect(state.presentedRemoval == [false])
            #expect(!service.isEnabled)
            let previousChecks = healthChecks
            healthy = true
            service.refresh()
            try await settle(service)
            #expect(healthChecks > previousChecks)
            #expect(service.isEnabled)
            #expect(!service.canRepair)
            service.setEnabled(false)
        }
    }

    @Test func mismatchedPinRemovalDoesNotRequireWorkingXPC() async throws {
        let state = LocalInstallationState(); state.installed = true
        var healthChecks = 0
        try await withService(state: state, health: {
            healthChecks += 1
            return (false, "No connection", true)
        }) { service, _ in
            #expect(!service.isRegistered)
            #expect(service.hasLocalInstallation)
            service.uninstall()
            try await settle(service)
            #expect(state.presentedRemoval == [true])
            #expect(service.needsApproval)
            #expect(!service.isEnabled)
            #expect(healthChecks == 0)
            state.installed = false
            service.refresh()
            #expect(!service.needsApproval)
            #expect(!service.hasLocalInstallation)
        }
    }
}
