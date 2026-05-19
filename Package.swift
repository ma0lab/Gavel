// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeBar", targets: ["ClaudeBar"]),
        .executable(name: "claudebar-hook", targets: ["claudebar-hook"]),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeBar",
            path: "Sources/ClaudeBar",
            swiftSettings: [
                .unsafeFlags(["-enable-experimental-feature", "StrictConcurrency"])
            ]
        ),
        .executableTarget(
            name: "claudebar-hook",
            path: "Sources/claudebar-hook"
        ),
    ]
)
