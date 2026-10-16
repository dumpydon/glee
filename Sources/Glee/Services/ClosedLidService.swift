// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import GleeCore
import GleeHelperProtocol
import Foundation
import Observation
import OSLog
import ServiceManagement

@MainActor @Observable
final class ClosedLidService {
    private(set) var isEnabled = false
    private(set) var isActive = false
    private(set) var isRegistered = false
    private(set) var needsApproval = false
    private(set) var message = "Off. Normal lid behavior applies."
    private var operationBusy = false
    private var lifecycleBusy = false
    var isBusy: Bool { operationBusy || lifecycleBusy }
    private(set) var issueMessage: String?
    private(set) var canRepair = false
    let signedBuild: Bool
    @ObservationIgnored private let registration: HelperRegistration
    @ObservationIgnored private let log = Logger(subsystem: "com.dumpydon.glee", category: "Helper")
    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var lastRenewal = Date.distantPast
    @ObservationIgnored private var activeUntil = Date.distantPast
    @ObservationIgnored private var requestGeneration = UUID()
    @ObservationIgnored private var pendingRequest: UUID?
    @ObservationIgnored private var verifiedHelper = false
    @ObservationIgnored private var enableWhenReady = false
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private let healthCheck: (() async -> (Bool, String, Bool))?
    @ObservationIgnored private var healthReply: ((Bool, String, Bool) -> Void)?

    init(registration: HelperRegistration = HelperRegistration(),
         signedBuild: Bool = HelperIdentity.teamID != nil || HelperIdentity.canPrepareLocalHelper,
         healthCheck: (() async -> (Bool, String, Bool))? = nil) {
        self.registration = registration
        self.healthCheck = healthCheck
        self.signedBuild = signedBuild
        refresh()
        if signedBuild && (isRegistered || registration.system.status == .notFound || registration.hasPendingUpdate) { prepareHelper() }
    }

    func refresh() {
        let status = registration.system.status
        let wasAwaitingApproval = needsApproval
        let wasRegistered = isRegistered
        isRegistered = status == .enabled
        needsApproval = status == .requiresApproval
        if usesLocalSetup && wasRegistered && !isRegistered && !needsApproval && !enableWhenReady {
            message = "Helper removed."
            issueMessage = nil
        }
        if isRegistered && enableWhenReady && !isBusy
            && (wasAwaitingApproval || (usesLocalSetup && !verifiedHelper)) {
            prepareHelper()
        }
    }

    var usesLocalSetup: Bool { (registration.system as? SystemHelperRegistration)?.usesLocalSetup ?? false }
    var hasLocalInstallation: Bool {
        (registration.system as? SystemHelperRegistration)?.hasLocalInstallation ?? false
    }
    func cancelLocalSetup() {
        guard usesLocalSetup, !isBusy else { return }
        enableWhenReady = false
        (registration.system as? SystemHelperRegistration)?.cancelLocalOperation()
        refresh()
        message = "Setup cancelled. Normal lid behavior applies."
        issueMessage = nil
    }
    var approvalMessage: String {
        usesLocalSetup ? "Finish the Glee setup in Installer, then return here."
            : "Allow Glee in System Settings to continue."
    }
    var setupButtonTitle: String? {
        guard let action = setupAction else { return nil }
        return usesLocalSetup && action == .approve ? "Continue in Installer…" : action.title
    }
    var compactSetupButtonTitle: String? {
        guard let action = setupAction else { return nil }
        return usesLocalSetup && action == .approve ? "Continue…" : action.compactTitle
    }

    var setupDiagnostics: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let status: String
        switch registration.system.status {
        case .notRegistered: status = "Not registered"
        case .enabled: status = "Enabled"
        case .requiresApproval: status = "Waiting for approval"
        case .notFound: status = "Not found"
        @unknown default: status = "Unknown"
        }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return """
        Glee \(version) (\(build))
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        App architecture: \(architecture)
        Background service: \(status)
        Setup details: \(issueMessage ?? "No error reported.")
        """
    }

    nonisolated private static func errorDetails(_ error: Error) -> String {
        let failure = error as NSError
        return "\(failure.localizedDescription)\n\(failure.domain) (code \(failure.code))"
    }

    func install() {
        guard signedBuild, !isBusy else { return }
        lifecycleBusy = true
        issueMessage = nil
        preparation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await registration.install()
                try Task.checkCancellation()
                refresh()
                lifecycleBusy = false
                preparation = nil
                if needsApproval {
                    message = approvalMessage
                } else { prepareHelper() }
            } catch {
                lifecycleBusy = false
                preparation = nil
                refresh()
                message = needsApproval ? approvalMessage : Self.errorDetails(error)
                issueMessage = needsApproval ? nil : message
            }
        }
    }

    /// A single setup action carries the user's intent through macOS approval.
    func enableAfterSetup() {
        enableWhenReady = true
        if setupAction != nil { performSetupAction() }
        else { setEnabled(true) }
    }

    func openApprovalSettings() {
        if usesLocalSetup { LocalHelperInstaller.reopen() }
        else { SMAppService.openSystemSettingsLoginItems() }
    }

    var setupAction: ClosedLidSetupAction? {
        ClosedLidSetupAction(signedBuild: signedBuild, isRegistered: isRegistered,
                            needsApproval: needsApproval, canRepair: canRepair)
    }

    func performSetupAction() {
        guard !isBusy else { return }
        switch setupAction {
        case .setUp:
            // Resume an interrupted registration through the same recovery path.
            if canRepair { repair() } else { install() }
        case .approve: openApprovalSettings()
        case .repair: repair()
        case nil: break
        }
    }

    func repair() {
        guard signedBuild, !isBusy else { return }
        isEnabled = false
        if usesLocalSetup { install(); return }
        if registration.system.status == .notRegistered { install(); return }
        prepareHelper(force: true)
    }

    private func prepareHelper(force: Bool = false) {
        guard !isBusy, !isActive else { return }
        release()
        lifecycleBusy = true; verifiedHelper = false; canRepair = false; issueMessage = nil
        message = "Checking helper. Keep the lid open."
        preparation = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.preparation = nil; self.lifecycleBusy = false }
            do {
                try await self.registration.prepare(force: force)
                try Task.checkCancellation()
                self.refresh()
                guard self.isRegistered else {
                    self.operationBusy = false
                    self.message = self.needsApproval ? self.approvalMessage : "Install the helper to continue."
                    return
                }
                var result = await self.checkHealth()
                try Task.checkCancellation()
                // A cold/stale launch gets one bounded repair. A helper policy
                // rejection is not a transport failure and must not be retried.
                if !result.0 && result.2 && !force {
                    self.operationBusy = true
                    self.message = "Repairing helper registration. Keep the lid open."
                    try await self.registration.prepare(force: true)
                    try Task.checkCancellation()
                    self.refresh()
                    guard self.isRegistered else {
                        self.operationBusy = false
                        self.message = self.approvalMessage
                        return
                    }
                    result = await self.checkHealth()
                    try Task.checkCancellation()
                }
                self.operationBusy = false
                if result.0 {
                    self.verifiedHelper = true
                    if self.enableWhenReady { self.isEnabled = true; self.enableWhenReady = false }
                    self.registration.confirmedResponsive()
                    self.issueMessage = nil; self.canRepair = false
                    self.message = self.isEnabled ? "Ready. Starts with your session." : "Helper connected. Ready for closed-lid sessions."
                    self.log.info("Helper registration and health verified")
                } else {
                    self.isEnabled = false; self.issueMessage = result.1; self.message = result.1
                    self.canRepair = result.2
                    self.release(preservingMessage: true)
                }
            } catch is CancellationError {
                self.operationBusy = false
                self.refresh()
                if self.registration.hasPendingUpdate {
                    self.canRepair = true
                    self.message = "Setup paused. Keep the lid open and try again to finish."
                    self.issueMessage = self.message
                }
            } catch {
                self.operationBusy = false; self.isEnabled = false; self.canRepair = true
                self.refresh(); self.message = Self.errorDetails(error); self.issueMessage = self.message
                self.log.error("Helper preparation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func checkHealth() async -> (Bool, String, Bool) {
        if let healthCheck { return await healthCheck() }
        return await withCheckedContinuation { continuation in
            let request = UUID()
            pendingRequest = request
            healthReply = { success, description, transportFailure in
                continuation.resume(returning: (success, description, transportFailure))
            }
            guard let proxy = connect() else {
                finishHealth(false, "Closed-lid mode couldn’t connect. Keep the lid open and try setup again.", transportFailure: true)
                return
            }
            proxy.checkHealth { [weak self] success, description in
                Task { @MainActor in
                    guard let self, self.pendingRequest == request else { return }
                    self.finishHealth(success, description, transportFailure: false)
                }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard let self, self.pendingRequest == request else { return }
                self.failedConnection("Closed-lid mode couldn’t start. Keep the lid open and try setup again.")
            }
        }
    }

    private func finishHealth(_ success: Bool, _ description: String, transportFailure: Bool) {
        let reply = healthReply
        healthReply = nil; pendingRequest = nil
        reply?(success, description, transportFailure)
    }

    func setEnabled(_ enabled: Bool) {
        refresh()
        guard !enabled || (signedBuild && isRegistered && !isBusy) else { return }
        isEnabled = enabled; issueMessage = nil; canRepair = false
        if enabled {
            lastRenewal = .distantPast
            message = "Ready for your next closed-lid session."
            if !verifiedHelper && !isBusy { prepareHelper() }
        } else {
            enableWhenReady = false
            preparation?.cancel()
            release()
        }
    }

    func update(hasDemand: Bool, policy: ClosedLidPolicy, now: Date = .now) {
        if isActive && now >= activeUntil {
            failedConnection("Closed-lid mode lost its connection and turned off. Keep the lid open and try setup again.")
        }
        guard isEnabled, hasDemand else {
            if connection != nil && !isBusy { release() }
            return
        }
        guard verifiedHelper, !isBusy, now.timeIntervalSince(lastRenewal) >= 10 else { return }
        guard let proxy = connect() else { return }
        lastRenewal = now; operationBusy = true
        let generation = requestGeneration, request = UUID()
        pendingRequest = request
        proxy.renewWithPolicy(allowsBattery: policy.allowsBattery, minimumBatteryPercent: policy.minimumBatteryPercent,
                              maximumBatteryMinutes: policy.maximumBatteryMinutes) { [weak self] success, description in
            Task { @MainActor in
                guard let self, self.requestGeneration == generation, self.pendingRequest == request else { return }
                self.pendingRequest = nil; self.operationBusy = false
                // Bound confirmation from request time, never extend it on a late reply.
                self.isActive = success && self.isEnabled && Date.now < now.addingTimeInterval(25)
                self.activeUntil = now.addingTimeInterval(25)
                self.message = description; self.issueMessage = success ? nil : description
                if !success { self.isEnabled = false; self.release(preservingMessage: true) }
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.requestGeneration == generation, self.pendingRequest == request else { return }
            self.failedConnection("Closed-lid mode stopped responding. Keep the lid open and try setup again.")
        }
    }

    private func connect() -> (any GleeHelperProtocol)? {
        guard let requirement = HelperIdentity.helperRequirementForCurrentApp else { return nil }
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: HelperIdentity.service, options: .privileged)
            connection.setCodeSigningRequirement(requirement)
            connection.remoteObjectInterface = NSXPCInterface(with: GleeHelperProtocol.self)
            let generation = requestGeneration
            connection.invalidationHandler = { [weak self] in
                Task { @MainActor in
                    guard let self, self.requestGeneration == generation else { return }
                    self.failedConnection("Closed-lid mode lost its connection. Keep the lid open and try setup again.")
                }
            }
            connection.interruptionHandler = connection.invalidationHandler
            connection.resume(); self.connection = connection
        }
        let generation = requestGeneration
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            let description = Self.errorDetails(error)
            Task { @MainActor in
                guard let self, self.requestGeneration == generation else { return }
                self.failedConnection(description)
            }
        } as? any GleeHelperProtocol
    }

    private func failedConnection(_ description: String) {
        verifiedHelper = false
        if healthReply != nil {
            finishHealth(false, description, transportFailure: true)
            release(preservingMessage: true)
            return
        }
        message = description; isEnabled = false; canRepair = true
        issueMessage = description
        log.error("Helper connection failed: \(description, privacy: .public)")
        release(preservingMessage: true)
    }

    func release(preservingMessage: Bool = false) {
        requestGeneration = UUID(); pendingRequest = nil
        if healthReply != nil { finishHealth(false, "Helper check cancelled.", transportFailure: true) }
        let old = connection
        connection = nil; operationBusy = false; isActive = false
        if !preservingMessage { message = isEnabled ? "Ready for your next closed-lid session." : "Off. Normal sleep settings are being restored." }
        old?.invalidate()
        lastRenewal = .distantPast
    }

    func uninstall() {
        guard !isBusy else { return }
        isEnabled = false
        enableWhenReady = false
        if usesLocalSetup {
            // Removal must still be available after a rebuild changes the app pin,
            // or if the daemon cannot respond. The root installer checks sleep and
            // recovery state before stopping/removing any files.
            release()
            lifecycleBusy = true
            preparation = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.lifecycleBusy = false; self.preparation = nil }
                do {
                    try await self.registration.system.unregister()
                    self.verifiedHelper = false
                    self.refresh()
                    self.message = "Finish removing the Glee helper in Installer, then return here."
                    self.issueMessage = nil
                } catch {
                    self.message = Self.errorDetails(error)
                    self.issueMessage = self.message
                }
            }
            return
        }
        guard let proxy = connect() else { return }
        operationBusy = true
        let generation = requestGeneration, request = UUID()
        pendingRequest = request
        proxy.releaseLease { [weak self] success, description in
            Task { @MainActor in
                guard let self, self.requestGeneration == generation, self.pendingRequest == request else { return }
                guard success else {
                    self.message = description; self.issueMessage = description
                    self.release(preservingMessage: true)
                    return
                }
                self.release(); self.lifecycleBusy = true
                defer { self.lifecycleBusy = false }
                do {
                    try await self.registration.system.unregister()
                    self.verifiedHelper = false
                    self.refresh()
                    if self.usesLocalSetup && self.needsApproval {
                        self.message = "Finish removing the Glee helper in Installer, then return here."
                    } else {
                        self.registration.forget()
                        self.message = "Helper removed."
                    }
                    self.issueMessage = nil
                } catch { self.message = Self.errorDetails(error); self.issueMessage = self.message }
                self.operationBusy = false
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.requestGeneration == generation, self.pendingRequest == request else { return }
            self.failedConnection("Could not confirm sleep restoration. The helper was left installed to recover safely.")
        }
    }
}
