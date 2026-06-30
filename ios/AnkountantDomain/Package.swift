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

// App-level domain types that aren't part of the Anki engine surface.
// Examples: dictionary lookup result shapes, reader book/chapter models,
// future study-mode metadata. Anything that's "Ankountant the app" rather than
// "Anki the engine" lives here.
//
// Mirrors the AnkountantUI package's split-out pattern: the AnkiBridge package
// stays focused on Anki engine/data/sync; this package owns app-domain
// types that future clients (DictionaryLookupClient, ReaderBookClient)
// will depend on.
let package = Package(
    name: "AnkountantDomain",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AnkountantDomain", targets: ["AnkountantDomain"]),
    ],
    targets: [
        .target(
            name: "AnkountantDomain",
            swiftSettings: sharedSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
