// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Security

@objc public protocol GleeHelperProtocol {
    /// Read-only startup check. It never creates or extends a sleep lease.
    func checkHealth(reply: @escaping @Sendable (Bool, String) -> Void)
    // Retained for older signed apps. It always uses adapter-only defaults.
    func renew(reply: @escaping @Sendable (Bool, String) -> Void)
    func renewWithPolicy(allowsBattery: Bool, minimumBatteryPercent: Int, maximumBatteryMinutes: Int,
                         reply: @escaping @Sendable (Bool, String) -> Void)
    func releaseLease(reply: @escaping @Sendable (Bool, String) -> Void)
}

public enum HelperIdentity {
    public static let app = "com.dumpydon.glee"
    public static let service = "com.dumpydon.glee.helper"
    public static let plist = "com.dumpydon.glee.helper.plist"
    public static var teamID: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var details: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &details) == errSecSuccess,
              let values = details as? [String: Any],
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else { return nil }
        return team
    }
    public static func requirement(identifier: String, team: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// A locally built app can request a Mac-admin-approved pinned installation.
    /// This only exposes setup; root IPC still requires the installed manifest.
    public static var canPrepareLocalHelper: Bool {
        guard teamID == nil, LocalHelperIdentity.currentCodeHash != nil else { return false }
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var details: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &details) == errSecSuccess,
              let values = details as? [String: Any] else { return false }
        return values[kSecCodeInfoIdentifier as String] as? String == app
    }

    public static var helperRequirementForCurrentApp: String? {
        if let team = teamID { return requirement(identifier: service, team: team) }
        guard let local = LocalHelperIdentity.load(), local.acceptsCurrentApp else { return nil }
        return local.helperRequirement
    }

    public static var currentHelperClientPolicy: (requirement: String, ownerUID: UInt32?)? {
        if let team = teamID { return (requirement(identifier: app, team: team), nil) }
        guard let local = LocalHelperIdentity.load(), local.acceptsCurrentHelper else { return nil }
        return (local.appRequirement, local.ownerUID)
    }
}
