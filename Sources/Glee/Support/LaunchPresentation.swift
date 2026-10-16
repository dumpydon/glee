// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit

enum LaunchPresentation {
    static func shouldShowPopover(for event: NSAppleEventDescriptor?) -> Bool {
        guard event?.eventID == kAEOpenApplication else { return true }
        // macOS describes login/service launches in the open-application event.
        let launchReason = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        return launchReason != keyAELaunchedAsLogInItem && launchReason != keyAELaunchedAsServiceItem
    }
}
