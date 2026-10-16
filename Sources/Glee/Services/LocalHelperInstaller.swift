// Copyright (c) 2026 dumpydon.
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import Darwin
import Foundation

/// Prepares a per-build package; Apple's Installer owns administrator approval.
/// No password, root shell, or privileged command is exposed through app IPC.
@MainActor enum LocalHelperInstaller {
    private static var lastPackage: URL?

    static func present(uninstall: Bool = false) async throws {
        guard let builder = Bundle.main.url(forResource: "build_local_helper_pkg", withExtension: "py") else {
            throw Failure.missingBuilder
        }
        let app = Bundle.main.bundleURL
        let uid = getuid()
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("Glee/Installers/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let package = directory.appendingPathComponent(uninstall ? "Glee-Local-Helper-Uninstall.pkg" : "Glee-Local-Helper.pkg")
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [builder.path, uninstall ? "uninstall" : "build"]
                + (uninstall ? [] : [app.path, "--owner-uid", String(uid)])
                + ["--output", package.path]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw Failure.build(String(decoding: data.suffix(8192), as: UTF8.self))
            }
        }.value
        lastPackage = package
        guard NSWorkspace.shared.open(package) else { throw Failure.cannotOpen }
    }

    static func reopen() {
        if let lastPackage { NSWorkspace.shared.open(lastPackage) }
    }

    enum Failure: LocalizedError {
        case missingBuilder, cannotOpen, build(String)
        var errorDescription: String? {
            switch self {
            case .missingBuilder: "This copy of Glee is missing its local setup tool. Rebuild or reinstall Glee."
            case .cannotOpen: "Could not open the setup package in Installer. Try setup again."
            case .build(let details): "Could not prepare local setup. Keep the lid open and try again.\n\(details)"
            }
        }
    }
}
