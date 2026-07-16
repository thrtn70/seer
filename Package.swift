// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Seer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SeerSpikeCore"),
        .executableTarget(
            name: "SeerSpike",
            dependencies: ["SeerSpikeCore"]
        ),
        .executableTarget(
            name: "SeerSpikeCoreCheck",
            dependencies: ["SeerSpikeCore"]
        ),
        .target(name: "SeerModel"),
        .target(name: "SeerSupport"),
        // llama.cpp xcframework, pinned to tag b9763. Populate via: scripts/fetch-llama.sh
        // (vendor/ is gitignored — not committed; a fresh clone runs the script before building).
        .binaryTarget(name: "llama", path: "vendor/llama.xcframework"),
        .target(name: "SeerInference", dependencies: ["SeerModel", "SeerSupport", "llama"]),
        .executableTarget(name: "SeerBench", dependencies: ["SeerInference", "SeerSupport"]),
        .testTarget(name: "SeerModelTests", dependencies: ["SeerModel"]),
        .testTarget(name: "SeerInferenceTests", dependencies: ["SeerInference"]),
        .testTarget(name: "SeerSupportTests", dependencies: ["SeerSupport"]),
        .target(name: "SeerCapture", dependencies: ["SeerModel", "SeerSupport"]),
        .executableTarget(name: "SeerCaptureProbe", dependencies: ["SeerCapture"]),
        .testTarget(name: "SeerCaptureTests", dependencies: ["SeerCapture"]),
        .target(name: "SeerOverlay", dependencies: ["SeerModel", "SeerSupport"]),
        .testTarget(name: "SeerOverlayTests", dependencies: ["SeerOverlay"]),
        .executableTarget(name: "SeerOverlayProbe",
                          dependencies: ["SeerOverlay", "SeerCapture", "SeerInference", "SeerSupport"]),
        .target(name: "SeerInput", dependencies: ["SeerModel"]),
        .testTarget(name: "SeerInputTests", dependencies: ["SeerInput"]),
        .target(name: "SeerInsertion"),
        .testTarget(name: "SeerInsertionTests", dependencies: ["SeerInsertion"]),
        .target(name: "SeerCoordinator",
                dependencies: ["SeerModel", "SeerSupport", "SeerCapture", "SeerInference", "SeerOverlay", "SeerInput", "SeerInsertion"]),
        .testTarget(name: "SeerCoordinatorTests", dependencies: ["SeerCoordinator"]),
        .target(name: "SeerAppKit", dependencies: ["SeerCapture", "SeerInput"]),
        .testTarget(name: "SeerAppKitTests", dependencies: ["SeerAppKit"]),
        .executableTarget(name: "SeerAgent",
                          dependencies: ["SeerCoordinator", "SeerInference", "SeerCapture", "SeerInput", "SeerAppKit", "SeerSupport"]),
    ]
)
