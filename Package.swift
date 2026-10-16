// swift-tools-version: 6.0
import PackageDescription
import Foundation

// The original macOS 14/15 controls remain available to developers using CLT.
// Enable native Liquid Glass only when the selected SDK contains its APIs.
let sdkProbe = Process()
sdkProbe.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
sdkProbe.arguments = ["--sdk", "macosx", "--show-sdk-version"]
let sdkOutput = Pipe()
sdkProbe.standardOutput = sdkOutput
sdkProbe.standardError = FileHandle.nullDevice
let sdkVersion: [Int]
do {
    try sdkProbe.run()
    let data = sdkOutput.fileHandleForReading.readDataToEndOfFile()
    sdkProbe.waitUntilExit()
    sdkVersion = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").compactMap { Int($0) }
} catch {
    sdkVersion = []
}
let supportsGlass = (sdkVersion.first ?? 0) > 26
    || (sdkVersion.first == 26 && (sdkVersion.dropFirst().first ?? 0) >= 1)
// Local administrator-pinned builds use hardened library validation. Sparkle
// cannot be loaded ad-hoc without disabling that protection. Apple-signed
// distribution builds opt into the original updater, signed with the same team.
let enableSparkle = ProcessInfo.processInfo.environment["GLEE_ENABLE_SPARKLE"] == "1"
let uiSettings: [SwiftSetting] = (supportsGlass ? [.define("GLEE_LIQUID_GLASS")] : [])
    + (enableSparkle ? [.define("GLEE_SPARKLE")] : [])
let appDependencies: [Target.Dependency] = ["GleeCore", "GleeHelperProtocol"]
    + (enableSparkle ? [.product(name: "Sparkle", package: "Sparkle")] : [])

let package = Package(
    name: "Glee",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Glee", targets: ["Glee"]),
               .executable(name: "GleeHelper", targets: ["GleeHelper"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "GleeCore"),
        .target(name: "GleeHelperProtocol"),
        .executableTarget(name: "GleeHelper", dependencies: ["GleeCore", "GleeHelperProtocol"]),
        .executableTarget(
            name: "Glee",
            dependencies: appDependencies,
            swiftSettings: uiSettings,
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "GleeCoreTests", dependencies: ["GleeCore"]),
        .testTarget(name: "GleeHelperProtocolTests", dependencies: ["GleeHelperProtocol"]),
        .testTarget(name: "GleeTests", dependencies: ["Glee"])
    ]
)
