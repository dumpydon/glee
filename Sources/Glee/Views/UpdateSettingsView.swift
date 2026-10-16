// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

@MainActor
struct UpdateSettingsView: View {
    let model: AppModel

    var body: some View {
        SettingsGlassSection(title: "Updates", detail: detail) {
            Toggle("Check automatically", isOn: Binding(
                get: { model.updates.automaticallyChecksForUpdates },
                set: { model.updates.setAutomaticChecks($0) }))
                .disabled(model.updates.startupError != nil)
            Divider()
            HStack {
                if let date = model.updates.lastCheckDate {
                    Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Checks daily").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("Check for Updates…", action: model.updates.checkForUpdates)
                    .awakeGlassButton()
                    .disabled(!model.canCheckForUpdates)
            }
        }
    }

    private var detail: String {
        if let error = model.updates.startupError { return error }
        if model.session.isActive { return "Updates wait until your session ends." }
        return "You choose when to install and restart."
    }
}
