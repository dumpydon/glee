// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

@MainActor
struct ClosedLidControl: View {
    let model: AppModel
    var showsSettingsButton = true
    let openSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 17))
                    .accessibilityHidden(true)
                Text("Closed-lid mode").font(.callout.weight(.semibold))
                Spacer(minLength: 4)
                if showsSettingsButton { Button(action: openSetup) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Closed-lid settings")
                .help("Closed-lid and battery settings")
                }
                if let title = model.closedLid.compactSetupButtonTitle {
                    Button(title) {
                        model.setupClosedLid()
                    }
                    .controlSize(.small)
                    .disabled(model.closedLid.isBusy)
                } else if model.closedLid.isRegistered {
                    Toggle("Keep awake with lid closed", isOn: Binding(
                        get: { model.closedLid.isEnabled }, set: { model.setClosedLid($0) }))
                        .toggleStyle(AwakeGlassToggleStyle(showsLabel: false))
                        .disabled(model.closedLid.isBusy)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(statusTitle, systemImage: statusSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                Text(statusDetail)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .padding(12)
        .awakeGlassSurface()
    }

    private var confirmed: Bool {
        model.closedLid.isActive && model.closedLid.isEnabled && model.session.isActive
            && model.closedLid.isRegistered && !model.closedLid.needsApproval
            && model.closedLid.issueMessage == nil
    }

    private var statusTitle: String {
        if model.closedLid.needsApproval { return "One step left" }
        if confirmed { return "Ready to close the lid" }
        if model.closedLid.isBusy { return "Getting ready" }
        if model.closedLid.canRepair { return "Setup needs another try" }
        if model.closedLid.issueMessage != nil { return "Turned off" }
        if !model.closedLid.isRegistered { return "Not set up" }
        if !model.closedLid.isEnabled { return "Off" }
        return model.session.isActive ? "Getting ready" : "On for your next session"
    }

    private var statusDetail: String {
        if model.closedLid.needsApproval { return model.closedLid.approvalMessage }
        if confirmed { return "Stays awake within your battery and time limits." }
        if model.closedLid.isBusy { return "Keep the lid open for a moment while Glee gets ready." }
        if model.closedLid.canRepair { return "Keep the lid open, then try setup again." }
        if let issue = model.closedLid.issueMessage { return issue }
        if !model.closedLid.isRegistered { return model.closedLid.signedBuild ? "Set up once to keep your Mac awake with the lid closed." : "Open a complete build of Glee to set up this feature." }
        if model.closedLid.isEnabled && model.session.isActive {
            return "Keep the lid open until this says Ready to close the lid."
        }
        if model.closedLid.isEnabled { return "Start a session, then wait for Ready." }
        return "Your Mac sleeps when you close the lid."
    }

    private var statusSymbol: String {
        if confirmed { return "checkmark.circle.fill" }
        if model.closedLid.issueMessage != nil || model.closedLid.needsApproval { return "exclamationmark.triangle.fill" }
        return model.closedLid.isEnabled ? "clock" : "moon"
    }

    private var statusColor: Color {
        if confirmed { return .green }
        return .secondary
    }
}
