// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

@MainActor
struct GleeRootView: View {
    let model: AppModel

    var body: some View {
        if model.showingSettings {
            SettingsView(model: model)
        } else {
            SessionPanel(model: model)
        }
    }
}
