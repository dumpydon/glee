// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Initial source builds run without network checks until Glee owns a feed/key.
/// Never fall back to another application's update authority.
public struct UpdateConfiguration: Sendable, Equatable {
    public let feedURL: URL
    public let publicKey: String

    public init?(feedURL: String?, publicKey: String?) {
        guard let feedURL, let url = URL(string: feedURL), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              let publicKey, let bytes = Data(base64Encoded: publicKey), bytes.count == 32 else { return nil }
        self.feedURL = url
        self.publicKey = publicKey
    }

    public static let pendingMessage = "Automatic updates are not configured for this initial Glee build."
}
