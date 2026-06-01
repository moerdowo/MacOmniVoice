// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacOmniVoice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacOmniVoice", targets: ["MacOmniVoice"])
    ],
    targets: [
        .executableTarget(
            name: "MacOmniVoice",
            path: "Sources/MacOmniVoice",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
