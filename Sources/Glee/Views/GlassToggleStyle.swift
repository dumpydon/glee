// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// iOS-like proportions, rendered by the system glass material. The control
/// retains Toggle semantics and a native button's keyboard action.
struct AwakeGlassToggleStyle: ToggleStyle {
    var showsLabel = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        #if GLEE_LIQUID_GLASS
        if #available(macOS 26, *), !reduceTransparency {
            HStack(spacing: 16) {
                if showsLabel {
                    configuration.label
                    Spacer(minLength: 12)
                }
                Button { configuration.isOn.toggle() } label: {
                    Capsule()
                        .fill(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: 52, height: 30)
                        .overlay {
                            Circle().fill(.clear)
                                .frame(width: 24, height: 24)
                                .glassEffect(.regular.tint(.white.opacity(0.85)).interactive(), in: .circle)
                                .offset(x: configuration.isOn ? 11 : -11)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel { _ in configuration.label }
            .accessibilityValue(configuration.isOn ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            .accessibilityAction { if isEnabled { configuration.isOn.toggle() } }
            .opacity(isEnabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: configuration.isOn)
        } else {
            if showsLabel {
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .toggleStyle(.switch).controlSize(.large)
            } else {
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .labelsHidden().toggleStyle(.switch).controlSize(.large)
            }
        }
        #else
            if showsLabel {
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .toggleStyle(.switch).controlSize(.large)
            } else {
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .labelsHidden().toggleStyle(.switch).controlSize(.large)
            }
        #endif
    }
}
