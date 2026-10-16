// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import GleeCore
import SwiftUI

@MainActor
struct SessionEndTimeEditor: View {
    @Binding var selection: Date

    var body: some View {
        VStack(spacing: 8) {
            NativeTimePicker(selection: Binding(
                get: { selection },
                set: { time in
                    if let end = SessionEndTime.nextOccurrence(of: time) { selection = end }
                }
            ))
            .fixedSize()
            .frame(maxWidth: .infinity, minHeight: 46)

            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(summary(at: context.date))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                shortcut("In 30 min", minutes: 30)
                shortcut("In 1 hour", minutes: 60)
                shortcut("In 2 hours", minutes: 120)
            }
        }
    }

    private func shortcut(_ title: String, minutes: Int) -> some View {
        Button {
            selection = SessionEndTime.preset(minutes: minutes)
        } label: {
            Text(title).font(.callout.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 20)
        }
        .awakeGlassButton()
        .buttonBorderShape(.capsule)
        .accessibilityHint("Set the session end time to \(minutes) minutes from now")
    }

    private func summary(at now: Date) -> String {
        guard SessionDuration.until(selection).isValid(at: now) else {
            return "Choose a future time within 24 hours."
        }
        let day = Calendar.current.isDate(selection, inSameDayAs: now) ? "Today" : "Tomorrow"
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        let remaining = formatter.string(from: ceil(selection.timeIntervalSince(now) / 60) * 60) ?? ""
        return "\(day) · in \(remaining)"
    }
}
