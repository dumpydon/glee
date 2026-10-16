// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import GleeCore
import SwiftUI

@MainActor
struct SessionPowerSettings: View {
    @Bindable var preferences: Preferences
    let closedLidEnabled: Bool

    var body: some View {
        SettingsGlassSection(title: "Battery & Power", detail: "Closed-lid mode uses the same battery level.") {
            Toggle("Require a power adapter", isOn: $preferences.requirePowerAdapter)
                .help("Ends the session when you unplug. Turn off to allow sessions on battery.")
            Text(preferences.requirePowerAdapter ? "Sessions end when you unplug." : "Sessions can continue on battery.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("End sessions on low battery", isOn: $preferences.endSessionOnLowBattery)
            Divider()
            HStack {
                Text("Battery cutoff")
                Spacer()
                Picker("Battery cutoff", selection: $preferences.closedLidBatteryCutoff) {
                    ForEach(ClosedLidPolicy.batteryCutoffs, id: \.self) { cutoff in
                        Text("\(cutoff)%").tag(cutoff)
                    }
                }
                .labelsHidden().frame(width: 90)
                .disabled(closedLidEnabled)
            }
            if closedLidEnabled {
                Text("Turn off closed-lid mode to change the battery level.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
