// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GearforgeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FactoryCore", targets: ["FactoryCore"]),
    ],
    targets: [
        .target(
            name: "FactoryCore",
            path: "Sources/FactoryCore",
            resources: [.copy("Resources/GameData.json")]
        ),
        .executableTarget(
            name: "FactoryBench",
            dependencies: ["FactoryCore"],
            path: "Sources/FactoryBench"
        ),
        .testTarget(
            name: "FactoryCoreTests",
            dependencies: ["FactoryCore"],
            path: "Tests/FactoryCoreTests"
        ),
    ]
)
