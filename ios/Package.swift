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
    name: "AnkiBridge",
    // Pinned to iOS 18 / macOS 15 because the sibling AnkountantReader package
    // depends on hoshidicts, which requires macOS 15+. The app target
    // already deploys iOS 18 so this is a no-op for users.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AnkiKit", targets: ["AnkiKit"]),
        .library(name: "AnkiProto", targets: ["AnkiProto"]),
        .library(name: "AnkiBackend", targets: ["AnkiBackend"]),
        .library(name: "AnkiServices", targets: ["AnkiServices"]),
        .library(name: "AnkiClients", targets: ["AnkiClients"]),
        .library(name: "AnkiSync", targets: ["AnkiSync"]),
        .library(name: "AnkountantCardWeb", targets: ["AnkountantCardWeb"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        // Reader/Dictionary domain types live in a sibling package so the
        // book/chapter/lookup model isn't entangled with Anki primitives.
        // The Anki-bridged loader (ReaderBookClient) lives in AnkiClients
        // and imports this package for its types.
        .package(path: "AnkountantReader"),
    ],
    targets: [
        // MARK: - Rust Bridge
        .binaryTarget(
            name: "AnkiRustLib",
            path: "AnkiRust.xcframework"
        ),
        .target(
            name: "AnkiProto",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "AnkiBackend",
            dependencies: [
                "AnkiRustLib",
                "AnkiProto",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        // MARK: - Libraries
        .target(
            name: "AnkiKit",
            // Bundled per-section authoritative-literature corpus for the
            // client-side research search (a verbatim copy of the Rust
            // rslib/src/ankountant/seed_literature.json — kept in sync).
            resources: [
                .process("Resources/seed_literature.json"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "AnkiServices",
            dependencies: [
                "AnkiKit",
                "AnkiBackend",
                "AnkiProto",
                "AnkiSync",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "AnkiClients",
            dependencies: [
                "AnkiKit",
                "AnkiBackend",
                "AnkiProto",
                "AnkiServices",
                "AnkiSync",
                .product(name: "AnkountantReader", package: "AnkountantReader"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "AnkiSync",
            dependencies: [
                "AnkiKit",
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "AnkountantCardWeb",
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "AnkountantCardWebTests",
            dependencies: ["AnkountantCardWeb"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "AnkiKitTests",
            dependencies: ["AnkiKit"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "AnkiServicesTests",
            dependencies: ["AnkiServices", "AnkiKit", "AnkiProto"],
            swiftSettings: sharedSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
