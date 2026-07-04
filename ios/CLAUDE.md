# ios — Project Instructions

Read before editing `ios/`.

The native **iOS app** (Swift/SwiftUI) — one of the two frontends of this repo's
shared Rust core (see the root `CLAUDE.md` Architecture Map). It is an
offline-first Anki-compatible client that reuses this monorepo's `rslib/` Rust
backend (AGPL-3.0), compiled to a binary framework and bridged to Swift via a
C FFI + protobuf serialization. Deeper data-flow and build detail live in
`ios/ARCHITECTURE.md`.

> Build note: iOS has its own toolchain — Swift Package Manager + `xcodebuild` +
> the scripts in `ios/scripts/`. Use `just test-ios` for the app XCTest wrapper
> when validating iOS app changes.

## Architecture

```
SwiftUI Views (AnkountantApp/)
    ↓ @Dependency(\.xxxClient)
@DependencyClient structs (Sources/AnkiClients/)
    ↓ service layer (Sources/AnkiServices/)
    ↓ AnkiBackend.invoke(service:method:request:)
AnkiBackend Swift wrapper (Sources/AnkiBackend/)
    ↓ C FFI (4 functions)
Rust static library (ios/anki-bridge-rs/ → AnkiRust.xcframework)
    ↓ protobuf RPC
rslib/ — this monorepo's Rust core
```

**Rust owns**: SQLite database, sync protocol, FSRS scheduling, card template rendering.
**Swift owns**: SwiftUI views, `@DependencyClient` wiring, navigation, charts.

## Module Map

Library targets live in the SPM package `AnkiBridge` (`Package.swift`); the app
target is the separate Xcode project `AnkountantApp/`.

| Module                           | Purpose                                                                                                                                                           |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AnkiKit`                        | Pure Swift domain types (`Rating`, `CardRecord`, `DeckInfo`, `FSRSState`, …)                                                                                      |
| `AnkiProto`                      | Generated Swift protobuf types from `proto/anki/*.proto`                                                                                                          |
| `AnkiBackend`                    | Swift wrapper around the Rust C FFI (`AnkiBackend` class) + the hand-maintained `Service`/`*Method` index enums                                                   |
| `AnkiServices`                   | Domain service layer (`DecksService`, `SchedulerService`, `NotesService`, …) over the backend                                                                     |
| `AnkiClients`                    | `@DependencyClient` structs + live implementations                                                                                                                |
| `AnkiSync`                       | `KeychainHelper` for credential storage                                                                                                                           |
| `AnkountantCardWeb`              | Card HTML rewriting + MathJax injection for `WKWebView`                                                                                                           |
| `AnkountantReader` (sibling pkg) | Reader/dictionary domain types (hoshidicts C++); the Anki-bridged loader (`ReaderBookClient`) lives in `AnkiClients`. Ankountant-specific — no desktop equivalent |
| `AnkiRustLib` (binary target)    | Prebuilt `rslib/` as `AnkiRust.xcframework`                                                                                                                       |

App feature folders (`AnkountantApp/Sources/`): `Review`, `Browse`, `Decks`,
`Stats`, `Sync`, `Reader`, `Settings`, `Shared`, `Theme`, `Widgets`.

## Build Commands

```bash
# Build Rust XCFramework (required before the Xcode build)
./scripts/build-xcframework.sh

# Regenerate Swift protobuf types from the repo-root proto/anki/
./scripts/generate-protos.sh

# Build SPM package (macOS targets only — AnkiBackend needs iOS)
swift build

# Build the iOS app (xcodegen regenerates the project from project.yml)
cd AnkountantApp && xcodegen generate && cd ..
xcodebuild build -project AnkountantApp/AnkountantApp.xcodeproj -scheme AnkountantApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'

# Run tests
swift test
just test-ios
```

## Key Patterns

### Dependency Client (struct-closure DI)

```swift
@DependencyClient
public struct CardClient: Sendable {
    public var fetchDue: @Sendable (_ deckId: Int64) throws -> [CardRecord]
    public var answer: @Sendable (_ cardId: Int64, _ rating: Rating, _ timeSpent: Int32) throws -> Void
}
```

### Calling the Rust Backend

```swift
// Typed RPC: encode request protobuf → C FFI → decode response protobuf
let response: Anki_Decks_DeckTreeNode = try backend.invoke(
    service: AnkiBackend.Service.decks,
    method: AnkiBackend.DecksMethod.getDeckTree,
    request: Anki_Decks_DeckTreeRequest()
)
```

### Service / method dispatch (hand-maintained — drift risk)

Each RPC is addressed by a numeric `(service, method)` pair. The full table is
the `Service` / `*Method` enums in `Sources/AnkiBackend/AnkiBackend.swift`
(e.g. `sync=1`, `decks=7`, `scheduler=13`, `notes=25`, `search=29`,
`cardRendering=27`).

⚠️ **These indices have no code generator** — there is no `swift.rs` (unlike
Python/TS/Rust). They are copied by hand from the desktop's generated
`out/pylib/anki/_backend_generated.py` (indices ultimately computed in
`rslib/proto_gen/src/lib.rs` by descriptor order). When a `.proto` adds or
reorders a service/method, `just check` updates Python/TS automatically but
**not** Swift — re-derive the affected enums here, or calls dispatch to the
wrong Rust method. Backend services (odd IDs) prepend their own methods before
delegating to the collection service, so backend vs collection method indices
differ; always use the backend (odd) IDs. See `proto/CLAUDE.md`.

## Import Rules (Swift 6.2 + InternalImportsByDefault)

- `public import` for any module whose types appear in public API signatures
- `import` (internal) for modules used only within the file
- `@DependencyClient` files need `public import Dependencies`
- SwiftProtobuf methods (`serializedData`, `init(serializedBytes:)`) need `import SwiftProtobuf`

## Known Issues & Workarounds

- **DeckTree with counts fails on fresh sync**: use `now=0` to skip counts, fetch per-deck separately
- **SyncCollection returns FULL_DOWNLOAD for empty local DB**: must auto-download, not just return "complete"
- **SourceKit false positives**: the IDE shows errors that don't exist in real builds — trust `swift build` / `xcodebuild`
- **Apple Compression framework has no zstd**: Rust handles zstd internally; no Swift-side compression needed
- **XCFramework is iOS-only**: `swift build` on macOS can't build `AnkiBackend`; use `xcodebuild` for full builds
