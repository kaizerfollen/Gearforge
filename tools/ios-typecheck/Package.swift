// swift-tools-version:5.9
// Linux typecheck harness for App/Sources (see README.md). Compiles the app against API stubs of the Apple
// frameworks it uses. Nothing here runs: every stub body is `_stub()` (fatalError). Swift 5 language mode,
// matching SWIFT_VERSION = 5.0 of the Xcode target.
import PackageDescription

let package = Package(
    name: "IOSTypecheck",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "GearforgeCore", path: "../../Core"),
    ],
    targets: [
        // Apple framework stubs. Module names must equal the real framework names.
        .target(name: "CoreGraphics", path: "Stubs/CoreGraphics"),
        .target(name: "simd", path: "Stubs/simd"),
        .target(name: "UIKit", dependencies: ["CoreGraphics"], path: "Stubs/UIKit"),
        .target(name: "Combine", path: "Stubs/Combine"),
        .target(name: "SwiftUI", dependencies: ["CoreGraphics", "UIKit", "Combine"], path: "Stubs/SwiftUI"),
        .target(name: "SpriteKit", dependencies: ["CoreGraphics", "UIKit", "SwiftUI"], path: "Stubs/SpriteKit"),
        .target(name: "AVFoundation", path: "Stubs/AVFoundation"),

        // Copy of App/Sources/** (refreshed by run.sh; not committed).
        .target(
            name: "AppTypecheck",
            dependencies: [
                "CoreGraphics", "simd", "UIKit", "Combine", "SwiftUI", "SpriteKit", "AVFoundation",
                .product(name: "FactoryCore", package: "GearforgeCore"),
            ],
            path: "Sources/AppTypecheck",
            swiftSettings: [.define("GEARFORGE_TYPECHECK")]
        ),

        // Sample usage of the stubs: a regression test for the stubs themselves (built by run.sh too).
        .target(
            name: "StubSamples",
            dependencies: ["CoreGraphics", "simd", "UIKit", "Combine", "SwiftUI", "SpriteKit", "AVFoundation"],
            path: "Tests/StubSamples"
        ),
    ]
)
