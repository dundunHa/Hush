// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hush",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HushApp", targets: ["HushApp"]),
        .library(name: "HushCore", targets: ["HushCore"]),
        .library(name: "HushProviders", targets: ["HushProviders"]),
        .library(name: "HushSettings", targets: ["HushSettings"])
    ],
    targets: [
        .target(name: "HushCore"),
        .target(
            name: "HushProviders",
            dependencies: ["HushCore"]
        ),
        .target(
            name: "HushSettings",
            dependencies: ["HushCore"]
        ),
        .executableTarget(
            name: "HushApp",
            dependencies: ["HushCore", "HushProviders", "HushSettings"]
        ),
        .testTarget(
            name: "HushCoreTests",
            dependencies: ["HushCore", "HushProviders", "HushSettings", "HushApp"]
        )
    ]
)

