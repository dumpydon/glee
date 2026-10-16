// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

@MainActor
struct GeneralSettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var preferences = model.preferences
        SettingsScrollPage {
            SettingsGlassSection(title: "Startup", detail: "Glee opens in the menu bar. Sessions start when you choose.") {
                Toggle("Launch at login", isOn: Binding(get: { model.loginItem.isRegistered }, set: { model.loginItem.setEnabled($0) }))
                if model.loginItem.needsApproval {
                    Button("Allow in System Settings…") { model.loginItem.openSystemSettings() }
                        .awakeGlassButton()
                }
                if let error = model.loginItem.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SettingsGlassSection(title: "Sessions") {
                Toggle("Remember last duration", isOn: $preferences.rememberDuration)
                Divider()
                Toggle("Keep display awake", isOn: Binding(
                    get: { model.session.keepDisplayAwake }, set: { model.setDisplayAwake($0) }))
                    .help("Keeps the display awake during an active session.")
            }
            SessionPowerSettings(preferences: preferences, closedLidEnabled: model.closedLid.isEnabled || model.closedLid.isBusy)
            UpdateSettingsView(model: model)
            HStack {
                Link("Glee", destination: URL(string: "https://github.com/dumpydon/glee")!)
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
        .onChange(of: preferences.sessionPowerPolicy) { model.refreshPowerSettings() }
    }
}
