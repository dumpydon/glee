// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import GleeCore
import SwiftUI

@MainActor
struct DurationEditor: View {
    @Binding var draft: DurationDraft
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                field("Hours", maximum: 24, text: Binding(
                    get: { draft.hours }, set: { draft.editHours($0) }))
                Text(":")
                    .font(.system(size: 32, weight: .light, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(height: 46)
                    .accessibilityHidden(true)
                field("Minutes", maximum: draft.maximumMinuteComponent, text: Binding(
                    get: { draft.minutes }, set: { draft.editMinutes($0) }))
            }
            .frame(maxWidth: .infinity)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach([5, 15, 30, 60, 120, 240], id: \.self) { minutes in
                    Button {
                        draft = DurationDraft(totalMinutes: minutes)
                    } label: {
                        Text(SessionDuration.minutes(minutes).label)
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 20)
                    }
                    .awakeGlassButton(prominent: draft.duration == .minutes(minutes))
                    .buttonBorderShape(.capsule)
                    .accessibilityAddTraits(draft.duration == .minutes(minutes) ? [.isSelected] : [])
                }
            }
            if draft.duration == nil {
                Text("Choose 1 minute to 24 hours.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func field(_ label: String, maximum: Int, text: Binding<String>) -> some View {
        VStack(spacing: 2) {
            DurationNumberField(text: text, label: label, maximum: maximum, onSubmit: onSubmit)
                .frame(width: 80, height: 46)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
