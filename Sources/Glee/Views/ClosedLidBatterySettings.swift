// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import GleeCore
import SwiftUI

@MainActor
struct ClosedLidBatterySettings: View {
    @Bindable var preferences: Preferences
    let modeEnabled: Bool

    var body: some View {
        SettingsGlassSection(title: "On battery", detail: batteryExplanation) {
            Toggle("Keep running on battery", isOn: Binding(
                get: { preferences.allowClosedLidOnBattery && !preferences.requirePowerAdapter },
                set: { preferences.setClosedLidBatteryUse($0) }))
                .accessibilityLabel("Keep running with the lid closed on battery")
            Text("Applies to your session and closed-lid mode. No other switch is needed.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if preferences.allowClosedLidOnBattery {
                    Divider()
                    HStack {
                        Text("Stop at battery level")
                        Spacer()
                        Picker("Stop at battery level", selection: $preferences.closedLidBatteryCutoff) {
                            ForEach(ClosedLidPolicy.batteryCutoffs, id: \.self) { cutoff in
                                Text("\(cutoff)%").tag(cutoff)
                            }
                        }.labelsHidden().frame(width: 90)
                    }
                    Divider()
                    HStack {
                        Text("Time on battery")
                        Spacer()
                        Picker("Maximum time on battery", selection: $preferences.closedLidBatteryMinutes) {
                            Text("Use 4-hour limit").tag(ClosedLidPolicy.noBatteryTimeLimit)
                            ForEach(ClosedLidPolicy.batteryDurations, id: \.self) { minutes in
                                Text(durationLabel(minutes)).tag(minutes)
                            }
                        }.labelsHidden().frame(width: 145)
                    }
                }
                if modeEnabled {
                    Text("End the current session before changing battery limits.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
        }
        .disabled(modeEnabled)
    }

    private var batteryExplanation: String? {
        guard !preferences.requirePowerAdapter else { return "Connect your charger, or enable battery use here before starting." }
        guard preferences.allowClosedLidOnBattery else {
            return "Closed-lid mode turns off when you unplug."
        }
        if !preferences.closedLidPolicy.hasBatteryTimeLimit {
            return "Turns off at \(preferences.closedLidBatteryCutoff)% battery or at the 4-hour limit."
        }
        return "Turns off at \(preferences.closedLidBatteryCutoff)% battery or after \(durationLabel(preferences.closedLidBatteryMinutes)) on battery, whichever comes first."
    }

    private func durationLabel(_ minutes: Int) -> String {
        switch minutes {
        case 60: "1 hour"
        case 90: "1½ hours"
        case 120: "2 hours"
        default: "\(minutes) minutes"
        }
    }
}
