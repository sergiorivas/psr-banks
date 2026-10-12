// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PSRBanks",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PSRBanks", targets: ["PSRBanks"]),
        .library(name: "PSRCore", targets: ["PSRCore"]),
    ],
    targets: [
        .target(
            name: "PSRCore",
            resources: [.copy("Resources/voices_e483.json"), .copy("Resources/default_header.bin")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PSRBanks",
            dependencies: ["PSRCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PSRCoreTests",
            dependencies: ["PSRCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
