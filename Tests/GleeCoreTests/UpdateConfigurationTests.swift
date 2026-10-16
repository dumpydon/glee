// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Testing
@testable import GleeCore

struct UpdateConfigurationTests {
    private let key = Data(repeating: 0x42, count: 32).base64EncodedString()

    @Test func unconfiguredBuildHasNoUpdateAuthority() {
        #expect(UpdateConfiguration(feedURL: nil, publicKey: key) == nil)
        #expect(UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: "") == nil)
        #expect(UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: nil) == nil)
    }

    @Test(arguments: ["http://example.com/feed", "file:///tmp/feed", "https://", "https://user:password@example.com/feed"])
    func rejectsUnsafeFeed(_ url: String) {
        #expect(UpdateConfiguration(feedURL: url, publicKey: key) == nil)
    }

    @Test(arguments: [0, 31, 33, 64])
    func rejectsWrongLengthKeys(_ length: Int) {
        #expect(UpdateConfiguration(feedURL: "https://example.com/feed",
                                    publicKey: Data(repeating: 1, count: length).base64EncodedString()) == nil)
    }

    @Test func acceptsAnIndependentSignedFeed() throws {
        let config = try #require(UpdateConfiguration(
            feedURL: "https://raw.githubusercontent.com/dumpydon/glee/main/appcast.xml", publicKey: key))
        #expect(config.feedURL.path == "/dumpydon/glee/main/appcast.xml")
        #expect(config.publicKey == key)
    }
}
