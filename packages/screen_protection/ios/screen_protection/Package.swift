// swift-tools-version: 5.9
// Swift Package Manager manifest of the plugin; CocoaPods reads screen_protection.podspec instead.

import PackageDescription

let package = Package(
    name: "screen_protection",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "screen_protection", targets: ["screen_protection"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "screen_protection",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        ),
        // Run on an iOS simulator (the target imports Flutter): `xcodebuild test` on the generated project of an app.
        .testTarget(
            name: "screen_protection_tests",
            dependencies: ["screen_protection"]
        )
    ]
)
