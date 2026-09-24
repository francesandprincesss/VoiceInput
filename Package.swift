// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VoiceInput", targets: ["VoiceInput"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.15.5"
        )
    ],
    targets: [
        .executableTarget(
            name: "VoiceInput",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/VoiceInput"
        ),
        .testTarget(
            name: "VoiceInputTests",
            dependencies: ["VoiceInput"],
            path: "Tests/VoiceInputTests"
        )
    ]
)
