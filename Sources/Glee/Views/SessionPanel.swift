// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import GleeCore
import SwiftUI

@MainActor
struct SessionPanel: View {
    let model: AppModel

    var body: some View {
        AwakeGlassGroup {
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    TimerActivityView(model: model)
                    SessionStatusMessage(message: model.session.statusMessage,
                                         attentionTrigger: model.blockedStartAttempts)
                }
                VStack(spacing: 10) {
                    ClosedLidControl(model: model) { settings(.closedLid) }
                    footer
                }
            }
            .padding(14)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.session.refresh(); model.closedLid.refresh() }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { settings(.general) } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.callout)
                    .frame(minHeight: 30)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)
            .help("Open Settings (⌘,)")
            Spacer()
            Button("Quit", systemImage: "power") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .help("Quit Glee (⌘Q)")
            Menu {
                Button("Closed-lid settings…", systemImage: "laptopcomputer") { settings(.closedLid) }
                Button("Check for Updates…", systemImage: "arrow.triangle.2.circlepath", action: model.updates.checkForUpdates)
                    .disabled(!model.canCheckForUpdates)
                Divider()
                Button("Quit Glee.app", systemImage: "power") { model.shutdown(); NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More options")
            .help("Updates and Quit")
        }
        .foregroundStyle(.secondary)
    }

    private func settings(_ tab: SettingsTab) {
        model.showSettings(tab)
    }
}
