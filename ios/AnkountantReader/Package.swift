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
    name: "AnkountantReader",
    // iOS 18 / macOS 15 because AnkountantReaderDictionary pulls in hoshidicts,
    // which itself requires macOS 15. The base AnkountantReader target is
    // pure-Swift and would happily run on lower minimums, but SPM
    // platform requirements are per-package, not per-target.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AnkountantReader", targets: ["AnkountantReader"]),
        .library(name: "AnkountantReaderDictionary", targets: ["AnkountantReaderDictionary"]),
    ],
    dependencies: [
        // hoshidicts: Yomitan-compatible offline dictionary engine.
        // Pin matches DreamAfar's verified revision so we get the same
        // ABI / generated bindings. C++ interop ships in this dependency,
        // so its consumer (AnkountantReaderDictionary below) needs Cxx mode.
        .package(
            url: "https://github.com/Manhhao/hoshidicts.git",
            revision: "e70589d33b6b346663278383b422e41f1ed05f3c"
        ),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    ],
    targets: [
        // Pure-Swift domain types for the Reader/Dictionary feature.
        // Deliberately has no Anki dependency: a "book" / "chapter" /
        // "dictionary lookup entry" exists independently of how we happen
        // to source them today (Anki notes). Anki-bridged loaders live in
        // the AnkiBridge package and import this one for the types.
        .target(
            name: "AnkountantReader",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        // Cxx-mode wrapper around hoshidicts. Isolated from the type
        // module so importing AnkountantReader (the common case) stays
        // Cxx-free. App code that wants dictionary lookup imports
        // AnkountantReaderDictionary explicitly.
        .target(
            name: "AnkountantReaderDictionary",
            dependencies: [
                "AnkountantReader",
                .product(name: "CHoshiDicts", package: "hoshidicts"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            swiftSettings: sharedSwiftSettings + [
                .interoperabilityMode(.Cxx),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
