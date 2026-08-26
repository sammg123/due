// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Due",
    platforms: [
        .macOS("14.0") // @Observable + MenuBarExtra(.window)
    ],
    targets: [
        // Pure logic: models, bucketing, parser, persistence, state. Fully unit-testable.
        .target(
            name: "DueCore",
            path: "Sources/DueCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Menu bar app: SwiftUI views only.
        .executableTarget(
            name: "Due",
            dependencies: ["DueCore"],
            path: "Sources/Due",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DueCoreTests",
            dependencies: ["DueCore"],
            path: "Tests/DueCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
