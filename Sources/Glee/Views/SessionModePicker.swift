// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

@MainActor
struct SessionModePicker: View {
    @Binding var selection: SessionMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let modes: [SessionMode] = [.duration, .untilTime, .untilStopped]

    var body: some View {
        #if GLEE_LIQUID_GLASS
        if #available(macOS 26, *) {
            GeometryReader { geometry in
                let segmentWidth = (geometry.size.width - 8) / 3
                let selectedIndex = CGFloat(modes.firstIndex(of: selection) ?? 0)

                GlassEffectContainer {
                    // Keep one glass shape on a fixed horizontal track.
                    Capsule().fill(.clear)
                        .frame(width: segmentWidth, height: 30)
                        .glassEffect(.regular, in: .capsule)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.25)) { capsule in
                            capsule.offset(x: selectedIndex * (segmentWidth + 4), y: 0)
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                // Labels sit above the glass container, so they stay stationary
                // and readable while the capsule slides underneath them.
                .overlay {
                    HStack(spacing: 4) {
                        ForEach(modes, id: \.self) { mode in
                            Button { select(mode) } label: {
                                Text(title(mode))
                                    .font(.callout.weight(selection == mode ? .semibold : .medium))
                                    .foregroundStyle(selection == mode ? .primary : .secondary)
                                    .frame(width: segmentWidth, height: 30)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selection == mode ? .isSelected : [])
                        }
                    }
                }
            }
            .frame(height: 30)
            .padding(4)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Session type")
            .onMoveCommand { direction in
                guard let index = modes.firstIndex(of: selection) else { return }
                if direction == .left { select(modes[max(0, index - 1)]) }
                if direction == .right { select(modes[min(modes.count - 1, index + 1)]) }
            }
        } else {
            Picker("Session type", selection: $selection) {
                ForEach(modes, id: \.self) { mode in Text(title(mode)).tag(mode) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.regular)
        }
        #else
            Picker("Session type", selection: $selection) {
                ForEach(modes, id: \.self) { mode in Text(title(mode)).tag(mode) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.regular)
        #endif
    }

    private func select(_ mode: SessionMode) {
        selection = mode
    }

    private func title(_ mode: SessionMode) -> String {
        switch mode {
        case .duration: "Timer"
        case .untilTime: "Until"
        case .untilStopped: "Unlimited"
        }
    }
}
