// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Darwin
import Foundation
import Security
import Testing
@testable import GleeHelperProtocol

@Suite struct LocalHelperIdentityTests {
    private let appHash = String(repeating: "1", count: 40)
    private let alternateAppHash = String(repeating: "a", count: 40)
    private let helperHash = String(repeating: "2", count: 40)

    private var payload: [String: Any] {
        ["formatVersion": 1, "ownerUID": 501,
         "appCodeHashes": [appHash, alternateAppHash], "helperCodeHashes": [helperHash]]
    }

    private func encoded(_ object: [String: Any], format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: format, options: 0)
    }

    private func identity() throws -> LocalHelperIdentity {
        try #require(LocalHelperIdentity.parse(encoded(payload)))
    }

    @Test(arguments: [PropertyListSerialization.PropertyListFormat.xml, .binary])
    func validManifestRoundTrips(_ format: PropertyListSerialization.PropertyListFormat) throws {
        let parsed = try #require(LocalHelperIdentity.parse(encoded(payload, format: format)))
        #expect(parsed.formatVersion == 1)
        #expect(parsed.ownerUID == 501)
        #expect(parsed.appCodeHashes == [appHash, alternateAppHash])
        #expect(parsed.helperCodeHashes == [helperHash])
        #expect(try PropertyListDecoder().decode(LocalHelperIdentity.self, from: PropertyListEncoder().encode(parsed)) == parsed)
    }

    @Test func ownerAndPinnedCodeBothRequiredForAppAccess() throws {
        let policy = try identity()
        #expect(policy.acceptsApp(codeHash: appHash, uid: 501))
        #expect(policy.acceptsApp(codeHash: alternateAppHash, uid: 501))
        #expect(!policy.acceptsApp(codeHash: appHash, uid: 0))
        #expect(!policy.acceptsApp(codeHash: appHash, uid: 502))
        #expect(!policy.acceptsApp(codeHash: helperHash, uid: 501))
        #expect(!policy.acceptsApp(codeHash: nil, uid: 501))
        #expect(policy.acceptsHelper(codeHash: helperHash))
        #expect(!policy.acceptsHelper(codeHash: appHash))
        #expect(!policy.acceptsHelper(codeHash: nil))
    }

    @Test func requirementPinsIdentifierAndEveryAllowedHash() throws {
        let policy = try identity()
        #expect(policy.appRequirement == "identifier \"com.dumpydon.glee\" and (cdhash H\"\(appHash)\" or cdhash H\"\(alternateAppHash)\")")
        #expect(policy.helperRequirement == "identifier \"com.dumpydon.glee.helper\" and (cdhash H\"\(helperHash)\")")
        for expression in [policy.appRequirement, policy.helperRequirement] {
            var requirement: SecRequirement?
            #expect(SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess)
            #expect(requirement != nil)
        }
    }

    @Test(arguments: [0, 2, -1, 100])
    func rejectsUnknownManifestVersions(_ version: Int) throws {
        var object = payload
        object["formatVersion"] = version
        #expect(LocalHelperIdentity.parse(try encoded(object)) == nil)
    }

    @Test(arguments: [Int64(0), -1, Int64(UInt32.max) + 1])
    func rejectsRootNegativeAndOutOfRangeOwner(_ uid: Int64) throws {
        var object = payload
        object["ownerUID"] = uid
        #expect(LocalHelperIdentity.parse(try encoded(object)) == nil)
    }

    @Test(arguments: ["", String(repeating: "a", count: 39), String(repeating: "a", count: 41),
                       String(repeating: "A", count: 40), String(repeating: "g", count: 40),
                       "\" or true or cdhash H\"000000000000000", String(repeating: "0", count: 39) + "\n"])
    func rejectsMalformedHashInEitherRole(_ hash: String) throws {
        for key in ["appCodeHashes", "helperCodeHashes"] {
            var object = payload
            object[key] = [hash]
            #expect(LocalHelperIdentity.parse(try encoded(object)) == nil)
        }
    }

    @Test func rejectsMissingFieldsAndWrongTypes() throws {
        for key in payload.keys {
            var object = payload
            object.removeValue(forKey: key)
            #expect(LocalHelperIdentity.parse(try encoded(object)) == nil)
        }
        for (key, value) in [("formatVersion", "1" as Any), ("ownerUID", "501"),
                             ("formatVersion", true), ("ownerUID", true),
                             ("appCodeHashes", appHash), ("helperCodeHashes", [1])] {
            var object = payload
            object[key] = value
            #expect(LocalHelperIdentity.parse(try encoded(object)) == nil)
        }
        #expect(LocalHelperIdentity.parse(Data("not a plist".utf8)) == nil)
        #expect(LocalHelperIdentity.parse(Data()) == nil)
        #expect(LocalHelperIdentity.parse(Data(repeating: 32, count: LocalHelperIdentity.maximumFileSize + 1)) == nil)
    }

    @Test func rejectsEmptyOversizedAndDuplicateHashLists() throws {
        let oversized = (0..<5).map { String(repeating: String($0), count: 40) }
        for key in ["appCodeHashes", "helperCodeHashes"] {
            for list in [[], [appHash, appHash], oversized] {
                var object = payload
                object[key] = list
                #expect(LocalHelperIdentity.parse(try encoded(object)) == nil)
            }
        }
    }

    @Test func supportsFourDistinctUniversalHashesInEachRole() throws {
        let hashes = (0..<4).map { String(repeating: String($0), count: 40) }
        let policy = try #require(LocalHelperIdentity(ownerUID: 501, appCodeHashes: hashes, helperCodeHashes: hashes))
        for hash in hashes {
            #expect(policy.acceptsApp(codeHash: hash, uid: 501))
            #expect(policy.acceptsHelper(codeHash: hash))
        }
    }

    private func withManifest(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("GleeIdentityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Application Support/Glee/LocalHelper", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent("identity.plist")
        try encoded(payload).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try body(root, file)
    }

    private func load(_ file: URL, root: URL, uid: uid_t = getuid()) -> LocalHelperIdentity? {
        LocalHelperIdentity.secureLoad(path: file.path, trustedUID: uid, protectedRoot: root.path)
    }

    @Test func secureLoaderAcceptsPrivateTrustedTree() throws {
        let expected = try identity()
        try withManifest { root, file in
            #expect(load(file, root: root) == expected)
        }
    }

    @Test func productionRootOwnershipPolicyRejectsUserOwnedFixture() throws {
        try withManifest { root, file in
            #expect(getuid() != 0)
            #expect(load(file, root: root, uid: 0) == nil)
            #expect(load(file, root: root, uid: getuid() + 1) == nil)
        }
    }

    @Test(arguments: [0o664, 0o646, 0o666])
    func rejectsGroupOrWorldWritableManifest(_ mode: Int) throws {
        try withManifest { root, file in
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
            #expect(load(file, root: root) == nil)
        }
    }

    private func addACL(_ expression: String, to target: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", "user:\(NSUserName()) \(expression)", target.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test(arguments: [false, true])
    func rejectsACLMutationGrantsDespiteSafePOSIXModes(_ directory: Bool) throws {
        try withManifest { root, file in
            let target = directory ? file.deletingLastPathComponent() : file
            try addACL(directory ? "allow add_file" : "allow write", to: target)
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            let mode = try #require(attributes[.posixPermissions] as? NSNumber).intValue
            #expect(mode & 0o022 == 0)
            #expect(load(file, root: root) == nil)
        }
    }

    @Test func permitsReadOnlyACLGrantsAndDenyEntries() throws {
        let expected = try identity()
        try withManifest { root, file in
            try addACL("allow read", to: file)
            try addACL("deny write", to: file)
            #expect(load(file, root: root) == expected)
        }
    }

    @Test(arguments: ["", "Application Support", "Application Support/Glee", "Application Support/Glee/LocalHelper"])
    func rejectsWritableDirectoryAtEveryProtectedLevel(_ relative: String) throws {
        try withManifest { root, file in
            let directory = relative.isEmpty ? root : root.appendingPathComponent(relative, isDirectory: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o775], ofItemAtPath: directory.path)
            #expect(load(file, root: root) == nil)
        }
    }

    @Test func rejectsManifestSymlink() throws {
        try withManifest { root, file in
            let actual = root.appendingPathComponent("actual.plist")
            try FileManager.default.moveItem(at: file, to: actual)
            try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: actual.path)
            #expect(load(file, root: root) == nil)
        }
    }

    @Test func rejectsParentSymlinkEvenWhenTargetIsOtherwiseTrusted() throws {
        try withManifest { root, file in
            let folder = root.appendingPathComponent("Application Support", isDirectory: true)
            let actual = root.appendingPathComponent("actual", isDirectory: true)
            try FileManager.default.moveItem(at: folder, to: actual)
            try FileManager.default.createSymbolicLink(atPath: folder.path, withDestinationPath: actual.path)
            #expect(load(file, root: root) == nil)
        }
    }

    @Test func rejectsManifestWithAdditionalHardLink() throws {
        try withManifest { root, file in
            try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("alias.plist"))
            #expect(load(file, root: root) == nil)
        }
    }

    @Test func rejectsNonregularManifestWithoutBlocking() throws {
        try withManifest { root, file in
            try FileManager.default.removeItem(at: file)
            #expect(mkfifo(file.path, 0o600) == 0)
            #expect(load(file, root: root) == nil)
        }
    }

    @Test func rejectsOversizedFileAndPathOutsideTrustedRoot() throws {
        try withManifest { root, file in
            try Data(repeating: 32, count: LocalHelperIdentity.maximumFileSize + 1).write(to: file)
            #expect(load(file, root: root) == nil)
            #expect(LocalHelperIdentity.secureLoad(path: file.path, trustedUID: getuid(),
                                                  protectedRoot: root.path + "-different") == nil)
            let traversal = root.path + "/Application Support/../Application Support/Glee/LocalHelper/identity.plist"
            #expect(LocalHelperIdentity.secureLoad(path: traversal, trustedUID: getuid(), protectedRoot: root.path) == nil)
        }
    }
}
