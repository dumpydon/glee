// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

enum ClosedLidSetupAction: Equatable {
    case setUp, approve, repair

    init?(signedBuild: Bool, isRegistered: Bool, needsApproval: Bool, canRepair: Bool) {
        guard signedBuild else { return nil }
        // Approval and first-time setup take precedence over a stale repair flag.
        if needsApproval { self = .approve }
        else if !isRegistered { self = .setUp }
        else if canRepair { self = .repair }
        else { return nil }
    }

    var title: String {
        switch self {
        case .setUp: "Set up closed-lid mode…"
        case .approve: "Allow in System Settings…"
        case .repair: "Try setup again"
        }
    }

    var compactTitle: String {
        switch self {
        case .setUp: "Set up…"
        case .approve: "Allow…"
        case .repair: "Try again"
        }
    }
}
