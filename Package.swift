// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var hardenedSettings: [SwiftSetting] = [.define("HARDENED")]
#if arch(arm64)
hardenedSettings.append(.define("ARCH_ARM64"))
#endif

let package = Package(
    name: "FluidVoice",
    platforms: [
        .macOS("15.0"),
    ],
    dependencies: [
        .package(url: "https://github.com/mxcl/AppUpdater.git", exact: "1.1.1"),
        .package(url: "https://github.com/altic-dev/FluidAudio.git", revision: "72625bbccf9f6c797a540a1f1cb66a4cb60753eb"),
        .package(url: "https://github.com/mxcl/PromiseKit", exact: "6.22.1"),
        .package(url: "https://github.com/altic-dev/DynamicNotchKit.git", revision: "708f31da5319436c64059ee7ae566953407063d7"),
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", exact: "1.2.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.10.2"),
    ],
    targets: [
        .executableTarget(
            name: "FluidVoice",
            dependencies: [
                "AppUpdater",
                "FluidAudio",
                "PromiseKit",
                "DynamicNotchKit",
                "SwiftWhisper",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/Fluid",
            resources: [.process("Resources"), .process("Assets.xcassets")],
            swiftSettings: hardenedSettings
        ),
    ]
)
