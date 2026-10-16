// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import Testing
@testable import Glee

@Suite struct LaunchPresentationTests {
    @Test func manualLaunchShowsPopover() {
        #expect(LaunchPresentation.shouldShowPopover(for: openEvent()))
        #expect(LaunchPresentation.shouldShowPopover(for: nil))
    }

    @Test(arguments: [keyAELaunchedAsLogInItem, keyAELaunchedAsServiceItem])
    func backgroundLaunchStaysQuiet(reason: AEKeyword) {
        let event = openEvent()
        event.setParam(NSAppleEventDescriptor(enumCode: reason), forKeyword: keyAEPropData)
        #expect(!LaunchPresentation.shouldShowPopover(for: event))
    }

    private func openEvent() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: kCoreEventClass, eventID: kAEOpenApplication,
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }
}
