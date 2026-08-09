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
        // Sparkle auto-update, pinned to 2.9.4. Populate via: scripts/fetch-sparkle.sh
        // (vendor/ is gitignored). Local-path binaryTarget for the same reason as llama:
        // keeps the package free of remote dependencies.
        .binaryTarget(name: "Sparkle", path: "vendor/Sparkle.xcframework"),
        .target(name: "SeerInference", dependencies: ["SeerModel", "SeerSupport", "llama"]),
        .executableTarget(name: "SeerBench", dependencies: ["SeerModel", "SeerInference", "SeerSupport"]),
        .testTarget(name: "SeerModelTests", dependencies: ["SeerModel"]),
        .testTarget(name: "SeerInferenceTests", dependencies: ["SeerInference"]),
        .testTarget(name: "SeerSupportTests", dependencies: ["SeerSupport"]),
        .target(name: "SeerCapture", dependencies: ["SeerModel", "SeerSupport"]),
        .executableTarget(name: "SeerCaptureProbe", dependencies: ["SeerCapture", "SeerModel"]),
        .testTarget(name: "SeerCaptureTests", dependencies: ["SeerCapture"]),
        .target(name: "SeerOverlay", dependencies: ["SeerModel", "SeerSupport"]),
        .testTarget(name: "SeerOverlayTests", dependencies: ["SeerOverlay"]),
        .executableTarget(name: "SeerOverlayProbe",
                          dependencies: ["SeerOverlay", "SeerCapture", "SeerInference", "SeerModel", "SeerSupport"]),
        .target(name: "SeerInput", dependencies: ["SeerModel"]),
        .testTarget(name: "SeerInputTests", dependencies: ["SeerInput"]),
        .target(name: "SeerInsertion"),
        .testTarget(name: "SeerInsertionTests", dependencies: ["SeerInsertion"]),
        .target(name: "SeerCoordinator",
                dependencies: ["SeerModel", "SeerSupport", "SeerCapture", "SeerInference", "SeerOverlay", "SeerInput", "SeerInsertion", "SeerPersonalization"]),
        .testTarget(name: "SeerCoordinatorTests", dependencies: ["SeerCoordinator", "SeerOverlay", "SeerPersonalization"]),
        // SeerModel was already a transitive dep via SeerCapture/SeerInput; CoordinatorTuning
        // (and its SamplingParams) make it a direct one, so declare it — same rationale as the
        // probe/bench targets. SeerModel is a dependency-free leaf, so this adds no edge.
        .target(name: "SeerAppKit", dependencies: ["SeerModel", "SeerCapture", "SeerInput"]),
        // SeerOverlay is a TEST-ONLY dependency: the drift-guard test asserts AppSettings'
        // mirrored font bounds equal OverlayFont's. Production SeerAppKit stays overlay-free.
        .testTarget(name: "SeerAppKitTests", dependencies: ["SeerAppKit", "SeerModel", "SeerOverlay"]),
        // §7 personalization: pure profile/tone/descriptor logic + sealed vault. Depends only
        // on SeerModel (a dependency-free leaf) — never on the engine or AppKit layers.
        .target(name: "SeerPersonalization", dependencies: ["SeerModel"]),
        .testTarget(name: "SeerPersonalizationTests", dependencies: ["SeerPersonalization"]),
        .executableTarget(name: "SeerAgent",
                          dependencies: ["SeerCoordinator", "SeerModel", "SeerInference", "SeerCapture", "SeerInput", "SeerAppKit", "SeerSupport", "SeerPersonalization", "Sparkle"]),
    ]
)
