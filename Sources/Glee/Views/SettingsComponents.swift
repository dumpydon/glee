// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

@MainActor
struct SettingsScrollPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            AwakeGlassGroup {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toggleStyle(AwakeGlassToggleStyle())
        .font(.body)
    }
}

@MainActor
struct SettingsGlassSection<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 10) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .awakeGlassSurface()
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

@MainActor
struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(title)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
