// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Due",
    platforms: [
        .macOS("14.0") // @Observable + MenuBarExtra(.window); FluidAudio's floor is also 14
    ],
    dependencies: [
        // Parakeet ASR for lecture capture. Pin exact: pre-1.0, the API has changed across 0.x.
        // Same version LocalFlow ships, so both apps share the downloaded model cache.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.4"),
    ],
    targets: [
        // Pure logic: models, bucketing, parser, persistence, state. Fully unit-testable.
        .target(
            name: "DueCore",
            path: "Sources/DueCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Menu bar app: SwiftUI views, audio capture, on-device AI.
        .executableTarget(
            name: "Due",
            dependencies: [
                "DueCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
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
