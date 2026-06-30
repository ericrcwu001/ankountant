// swift-tools-version: 6.2

import PackageDescription

let sharedSwiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .enableExperimentalFeature("IsolatedAny"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("FullTypedThrows"),
]

let package = Package(
    name: "AnkountantUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AnkountantTheme", targets: ["AnkountantTheme"]),
    ],
    targets: [
        .target(
            name: "AnkountantTheme",
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "AnkountantThemeTests",
            dependencies: ["AnkountantTheme"],
            swiftSettings: sharedSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
