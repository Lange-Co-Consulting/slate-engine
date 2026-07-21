// swift-tools-version: 6.0
import PackageDescription

// slate-engine — the open-source local-AI engine behind Slate (https://slate-app.org).
// Binary llama.cpp / stable-diffusion.cpp frameworks are hosted as GitHub Release
// assets (kept out of git); everything else is pure Swift. MIT-licensed.
let package = Package(
    name: "slate-engine",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SlateCore", targets: ["SlateCore"]),
        .library(name: "SlateLlama", targets: ["SlateLlama"]),
        .library(name: "SlateDiffusion", targets: ["SlateDiffusion"]),
        .library(name: "SlateSTT", targets: ["SlateSTT"]),
        .library(name: "SlateFlowCore", targets: ["SlateFlowCore"]),
        .library(name: "SlateFlowCleanup", targets: ["SlateFlowCleanup"]),
        .executable(name: "slatectl", targets: ["SlateCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/Lange-Co-Consulting/slate-engine/releases/download/v0.1.0/llama.xcframework.zip",
            checksum: "4f82551dec637196ab877574371379cbd520dec9e35361ff15f6db6d59e41cfa"),
        .binaryTarget(
            name: "sd",
            url: "https://github.com/Lange-Co-Consulting/slate-engine/releases/download/v0.1.0/sd.xcframework.zip",
            checksum: "750d4ff19002f456b69aa8f00b9ecf739c352f5393702ae3b45bc530a64535c9"),
        .target(name: "SlateCore"),
        .executableTarget(name: "SlateCLI", dependencies: ["SlateCore", "SlateSTT"],
                          path: "Tools/SlateCLI"),
        .target(name: "SlateLlama", dependencies: ["SlateCore", "llama"]),
        .target(name: "SlateDiffusion", dependencies: ["SlateCore", "sd"],
                linkerSettings: [
                    .linkedFramework("Metal"),
                    .linkedFramework("MetalKit"),
                    .linkedFramework("Foundation"),
                    .linkedFramework("Accelerate"),
                    .linkedLibrary("c++"),
                ]),
        .target(name: "SlateSTT", dependencies: [
            .product(name: "FluidAudio", package: "FluidAudio"),
        ]),
        .target(name: "SlateFlowCore", dependencies: ["SlateSTT", "SlateCore"]),
        .target(name: "SlateFlowCleanup", dependencies: ["SlateCore"]),
        .testTarget(name: "SlateCoreTests", dependencies: ["SlateCore"]),
        .testTarget(name: "SlateLlamaTests", dependencies: ["SlateLlama", "SlateFlowCleanup"]),
        .testTarget(name: "SlateDiffusionTests", dependencies: ["SlateDiffusion"]),
        .testTarget(name: "SlateFlowCoreTests", dependencies: ["SlateFlowCore"]),
        .testTarget(name: "SlateFlowCleanupTests", dependencies: ["SlateFlowCleanup"]),
        .testTarget(name: "SlateVoiceTests", dependencies: ["SlateSTT", "SlateCore"]),
    ],
    swiftLanguageModes: [.v6]
)
