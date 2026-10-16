// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// One sampling group for the panel's related native glass controls.
@MainActor
struct AwakeGlassGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if GLEE_LIQUID_GLASS
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 4) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    @ViewBuilder
    func awakeGlassSurface(cornerRadius: CGFloat = 20) -> some View {
        #if GLEE_LIQUID_GLASS
        if #available(macOS 26, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    @ViewBuilder
    func awakeGlassButton(prominent: Bool = false) -> some View {
        #if GLEE_LIQUID_GLASS
        if #available(macOS 26.1, *) {
            if prominent { buttonStyle(.glass(.regular.tint(.accentColor))) }
            else { buttonStyle(.glass) }
        } else if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) }
            else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) }
            else { buttonStyle(.bordered) }
        }
        #else
        if prominent { buttonStyle(.borderedProminent) }
        else { buttonStyle(.bordered) }
        #endif
    }
}
