// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit

@main
@MainActor
struct GleeApp {
    static func main() {
        // AppKit owns one status item. No SwiftUI window scenes can be opened
        // or restored independently of its popover.
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
