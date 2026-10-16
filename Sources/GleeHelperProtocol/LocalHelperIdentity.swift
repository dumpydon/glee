// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import Darwin
import Foundation
import Security

/// A separate, administrator-installed trust policy for one local Glee build.
/// This does not provide Apple developer-team authentication or notarization.
public struct LocalHelperIdentity: Codable, Sendable, Equatable {
    public static let manifestPath = "/Library/Application Support/Glee/LocalHelper/identity.plist"
    public static let appIdentifier = "com.dumpydon.glee"
    public static let helperIdentifier = "com.dumpydon.glee.helper"
    static let maximumFileSize = 16 * 1024

    public let formatVersion: Int
    public let ownerUID: UInt32
    public let appCodeHashes: [String]
    public let helperCodeHashes: [String]

    public init?(formatVersion: Int = 1, ownerUID: UInt32,
                 appCodeHashes: [String], helperCodeHashes: [String]) {
        guard formatVersion == 1, ownerUID > 0,
              Self.validHashes(appCodeHashes), Self.validHashes(helperCodeHashes) else { return nil }
        self.formatVersion = formatVersion
        self.ownerUID = ownerUID
        self.appCodeHashes = appCodeHashes
        self.helperCodeHashes = helperCodeHashes
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, ownerUID, appCodeHashes, helperCodeHashes
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .formatVersion)
        let owner = try values.decode(UInt32.self, forKey: .ownerUID)
        let appHashes = try values.decode([String].self, forKey: .appCodeHashes)
        let helperHashes = try values.decode([String].self, forKey: .helperCodeHashes)
        guard let identity = Self(formatVersion: version, ownerUID: owner,
                                  appCodeHashes: appHashes, helperCodeHashes: helperHashes) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                   debugDescription: "Invalid local helper identity policy."))
        }
        self = identity
    }

    public static func parse(_ data: Data) -> Self? {
        guard !data.isEmpty, data.count <= maximumFileSize else { return nil }
        return try? PropertyListDecoder().decode(Self.self, from: data)
    }

    /// The only public file-loading entry point. Its path and root ownership
    /// policy cannot be selected by app preferences or an XPC request.
    public static func load() -> Self? {
        secureLoad(path: manifestPath, trustedUID: 0, protectedRoot: "/")
    }

    public var appRequirement: String { Self.requirement(identifier: Self.appIdentifier, hashes: appCodeHashes) }
    public var helperRequirement: String { Self.requirement(identifier: Self.helperIdentifier, hashes: helperCodeHashes) }

    public func acceptsApp(codeHash: String?, uid: UInt32) -> Bool {
        guard uid == ownerUID, let codeHash else { return false }
        return appCodeHashes.contains(codeHash)
    }

    public func acceptsHelper(codeHash: String?) -> Bool {
        guard let codeHash else { return false }
        return helperCodeHashes.contains(codeHash)
    }

    public var acceptsCurrentApp: Bool {
        getuid() == ownerUID && geteuid() == ownerUID
            && acceptsApp(codeHash: Self.currentCodeHash, uid: getuid())
    }

    public var acceptsCurrentHelper: Bool {
        getuid() == 0 && geteuid() == 0 && acceptsHelper(codeHash: Self.currentCodeHash)
    }

    /// Obtain the running process's verified code-directory hash rather than
    /// accepting a hash supplied by a caller or calculating it from a path.
    public static var currentCodeHash: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var details: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &details) == errSecSuccess,
              let values = details as? [String: Any],
              let hash = values[kSecCodeInfoUnique as String] as? Data, hash.count == 20 else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func validHashes(_ hashes: [String]) -> Bool {
        guard (1...4).contains(hashes.count), Set(hashes).count == hashes.count else { return false }
        return hashes.allSatisfy { hash in
            hash.utf8.count == 40 && hash.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            }
        }
    }

    private static func requirement(identifier: String, hashes: [String]) -> String {
        let pinnedHashes = hashes.map { "cdhash H\"\($0)\"" }.joined(separator: " or ")
        return "identifier \"\(identifier)\" and (\(pinnedHashes))"
    }

    /// Internal observation policy for filesystem tests. Production always
    /// starts at / and trusts UID 0; tests can use a private temporary tree and
    /// the test user's UID without creating or modifying root-owned files.
    static func secureLoad(path: String, trustedUID: uid_t, protectedRoot: String) -> Self? {
        guard protectedRoot.hasPrefix("/"), protectedRoot == "/" || !protectedRoot.hasSuffix("/") else { return nil }
        let prefix = protectedRoot == "/" ? "/" : protectedRoot + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let components = path.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else { return nil }

        var directory = open(protectedRoot, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { return nil }
        defer { close(directory) }
        guard trustedDirectory(directory, uid: trustedUID) else { return nil }
        for component in components.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { return nil }
            guard trustedDirectory(next, uid: trustedUID) else { close(next); return nil }
            close(directory)
            directory = next
        }

        guard let name = components.last else { return nil }
        // O_NONBLOCK prevents a hostile FIFO/device from blocking before fstat
        // can reject it. Normal regular-file reads are unaffected.
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard file >= 0 else { return nil }
        defer { close(file) }
        var before = stat()
        guard fstat(file, &before) == 0, trustedFile(before, uid: trustedUID),
              hasNoACLWriteGrants(file) else { return nil }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            guard data.count + count <= maximumFileSize else { return nil }
            data.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard fstat(file, &after) == 0, trustedFile(after, uid: trustedUID), hasNoACLWriteGrants(file),
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size, data.count == Int(after.st_size),
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { return nil }
        return parse(data)
    }

    private static func trustedDirectory(_ descriptor: Int32, uid: uid_t) -> Bool {
        var info = stat()
        return fstat(descriptor, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
            && info.st_uid == uid && info.st_mode & 0o022 == 0 && hasNoACLWriteGrants(descriptor)
    }

    private static func trustedFile(_ info: stat, uid: uid_t) -> Bool {
        info.st_mode & S_IFMT == S_IFREG && info.st_uid == uid
            && info.st_mode & 0o022 == 0 && info.st_nlink == 1
            && info.st_size > 0 && info.st_size <= maximumFileSize
    }

    /// macOS ACL grants can permit mutation even when POSIX mode bits are 0644
    /// or 0755. Refuse any mutating ALLOW entry; read grants and DENY entries do
    /// not weaken the root-only write policy. Unknown ACL state fails closed.
    private static func hasNoACLWriteGrants(_ descriptor: Int32) -> Bool {
        // On APFS an existing, verified descriptor without an extended ACL
        // reports ENOENT. Other retrieval errors leave the trust state unknown.
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else { return errno == ENOENT }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { return false }
        let mutations: [acl_perm_t] = [ACL_WRITE_DATA, ACL_APPEND_DATA, ACL_DELETE, ACL_DELETE_CHILD,
                                        ACL_WRITE_ATTRIBUTES, ACL_WRITE_EXTATTRIBUTES,
                                        ACL_WRITE_SECURITY, ACL_CHANGE_OWNER]
        for index in 0...ACL_MAX_ENTRIES {
            var entry: acl_entry_t?
            if acl_get_entry(acl, index, &entry) != 0 {
                // Darwin reports EINVAL on the first index beyond a valid ACL.
                return errno == EINVAL
            }
            guard let entry else { return false }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0 else { return false }
            if tag == ACL_EXTENDED_DENY { continue }
            guard tag == ACL_EXTENDED_ALLOW else { return false }
            var permissions: acl_permset_t?
            guard acl_get_permset(entry, &permissions) == 0, let permissions else { return false }
            for permission in mutations {
                let granted = acl_get_perm_np(permissions, permission)
                guard granted == 0 else { return false }
            }
        }
        return false
    }
}
