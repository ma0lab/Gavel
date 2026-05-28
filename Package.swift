// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gavel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Gavel", targets: ["Gavel"]),
        .executable(name: "gavel-hook", targets: ["gavel-hook"]),
    ],
    targets: [
        .executableTarget(
            name: "Gavel",
            path: "Sources/Gavel",
swiftSettings: [
                .unsafeFlags(["-enable-experimental-feature", "StrictConcurrency"])
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "gavel-hook",
            path: "Sources/gavel-hook"
        ),
    ]
)
