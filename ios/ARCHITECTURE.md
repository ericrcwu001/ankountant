# Architecture

This document describes how the Ankountant **iOS app** is structured, how the
Rust bridge works, and how data flows through the app. It is the iOS frontend of
this repo's shared Rust core — see the root `CLAUDE.md` Architecture Map for how
it relates to the desktop app, and `ios/CLAUDE.md` for working conventions.

## High-Level Overview

```
┌─────────────────────────────────────────────────┐
│                  SwiftUI Views                   │
│        (AnkountantApp/ — iOS app target)         │
├─────────────────────────────────────────────────┤
│           @DependencyClient structs              │
│              (Sources/AnkiClients/)              │
├─────────────────────────────────────────────────┤
│            Service layer + AnkiBackend           │
│   (Sources/AnkiServices/, Sources/AnkiBackend/)  │
│    invoke(service:method:request:) → Response    │
├─────────────────────────────────────────────────┤
│              C FFI (4 functions)                 │
│   anki_open_backend / anki_run_method /          │
│   anki_free_response / anki_close_backend        │
├─────────────────────────────────────────────────┤
│         Rust static library (.a)                 │
│      rslib/ (this monorepo's Rust core)          │
│  SQLite · Sync protocol · FSRS · Templates       │
└─────────────────────────────────────────────────┘
```

**Swift owns**: UI, navigation, dependency wiring, charts.
**Rust owns**: SQLite database, sync protocol, FSRS scheduling, card template rendering, statistics.

## Module Map

| Module                                 | Purpose                                                                                                                |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **AnkiKit**                            | Pure Swift domain types: `Rating`, `FSRSState`, `DeckInfo`, `CardRecord`, etc.                                         |
| **AnkiProto**                          | Generated Swift protobuf types from the 24 `.proto` service files                                                      |
| **AnkiBackend**                        | Swift wrapper around the Rust C FFI (`AnkiBackend` class) + hand-maintained service/method index enums                 |
| **AnkiServices**                       | Domain service layer (`DecksService`, `SchedulerService`, `NotesService`, …) translating UI requests into backend RPCs |
| **AnkiClients**                        | `@DependencyClient` structs with live implementations                                                                  |
| **AnkiSync**                           | `KeychainHelper` for credential storage                                                                                |
| **AnkountantCardWeb**                  | Card HTML rewriting + MathJax for `WKWebView` rendering                                                                |
| **AnkountantReader** (sibling package) | Reader/dictionary domain types (hoshidicts C++ engine). **Ankountant-specific feature, not in the official client**    |

All library modules live in the SPM package (`Package.swift`, package name
"AnkiBridge"). The iOS app target (`AnkountantApp/`) is a separate Xcode project
(`AnkountantApp.xcodeproj`, regenerated from `project.yml` by xcodegen).

## The Rust Bridge

### Four C Functions

The entire bridge surface is four C functions (declared in
`anki-bridge-rs/include/anki_bridge.h`, implemented in `anki-bridge-rs/src/lib.rs`):

| Function                                                                         | Purpose                                               |
| -------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `anki_open_backend(path, lang)`                                                  | Open a collection at the given path, returns a handle |
| `anki_run_method(handle, service, method, input, input_len, output, output_len)` | Run an RPC method                                     |
| `anki_free_response(ptr, len)`                                                   | Free a response buffer allocated by Rust              |
| `anki_close_backend(handle)`                                                     | Close the collection and free the handle              |

`anki_run_method` wraps `anki::backend::Backend::run_service_method()`. The
bridge crate depends directly on this monorepo's core: `anki = { path = "../../rslib" }`.

### Protobuf Serialization Flow

```
Swift request struct
    │  .serializedData()
    ▼
Raw bytes (Data)
    │  C FFI: anki_run_method()
    ▼
Rust deserializes → executes → serializes response
    │  raw bytes back to Swift
    ▼
Response struct  (init(serializedBytes:))
```

Every call is: encode protobuf → pass bytes through FFI → decode protobuf. No
Objective-C, no Swift-Rust interop crates — just C and bytes.

### Service and Method Dispatch

The Rust backend exposes services identified by numeric IDs. There are two dispatch layers:

- **Backend services** (odd IDs: 1, 3, 7, 13, 25, 27, 29, 41, …) handle backend-level
  operations (open collection, sync, etc.) and delegate to collection services.
- **Collection services** (even IDs) handle collection-level operations.

**Important**: backend services add their own methods _before_ delegating, so
method indices differ between the backend and collection layers. Example:
`getQueuedCards` is method **3** on `BackendSchedulerService` (ID 13) but method
**0** on the collection scheduler service. Always use the **backend dispatch
table** (odd service IDs).

**Source of truth & drift.** The indices are computed by descriptor order in
`rslib/proto_gen/src/lib.rs` and emitted into the desktop's generated
`out/pylib/anki/_backend_generated.py`. The Swift side has **no generator** (no
`swift.rs`, unlike Python/TS/Rust), so the `Service`/`*Method` enums in
`Sources/AnkiBackend/AnkiBackend.swift` are **maintained by hand**, re-derived
from `_backend_generated.py`. A `.proto` service/method add or reorder updates
Python/TS via `just check` but leaves Swift stale → calls hit the wrong method.
See `proto/CLAUDE.md`.

| Service ID | Name                        | Key Methods                                           |
| ---------- | --------------------------- | ----------------------------------------------------- |
| 1          | BackendSyncService          | 3=SyncLogin, 5=SyncCollection, 6=FullUploadOrDownload |
| 3          | BackendCollectionService    | 0=OpenCollection, 1=CloseCollection                   |
| 7          | BackendDecksService         | 8=GetDeckTree, 13=GetDeckNames                        |
| 13         | BackendSchedulerService     | 3=GetQueuedCards, 4=AnswerCard, 7=CountsForDeckToday  |
| 25         | BackendNotesService         | 5=GetNote                                             |
| 27         | BackendCardRenderingService | 6=RenderExistingCard                                  |
| 29         | BackendSearchService        | 0=SearchCards, 1=SearchNotes                          |

## Data Flows

### Sync

```
1. SyncLogin(username, password) → auth token
2. SyncCollection(auth) → SyncCollectionResponse
   - If FULL_DOWNLOAD or FULL_SYNC:
     3. FullUploadOrDownload(upload=false) → full collection download
   - If NORMAL_SYNC:
     3. Normal incremental sync (handled by Rust)
4. Collection is now up to date locally
```

### Study Session

```
1. SetCurrentDeck(deckId)                        — tell Rust which deck
2. GetQueuedCards(fetchLimit: 1)                 — next card + scheduling states
3. RenderExistingCard(cardId, browser: false)    — rendered HTML
4. Display card in WKWebView
5. User taps answer button
6. AnswerCard(cardId, currentState, newState, rating, millisTaken)
7. Go to step 2
```

The `QueuedCard` protobuf carries `SchedulingStates` (`current`, `again`, `hard`,
`good`, `easy`). The picked rating's state becomes `new_state` in `AnswerCard` —
pass these through exactly as received; do not reconstruct them.

### Browse / Search

```
1. SearchNotes(query) → note IDs
2. GetNote(noteId) per note (lazy-loaded in batches of 50)
3. Display in a scrollable list with on-demand loading
```

Deck filtering uses Anki search syntax: `deck:"English::Grammar"` includes subdecks.

### Statistics

```
1. Graphs(search: "deck:DeckName", daysToInclude: 365) → GraphsResponse
2. Parse review history / card counts / hourly breakdown
3. Render heatmap, streak, summary stats with SwiftUI Charts
```

### Reader / Dictionary (Ankountant-specific)

Books and chapters are stored as Anki notes; the reader loads them via
`ReaderBookClient` (in `AnkiClients`, backed by note search), and word lookups go
through the offline hoshidicts engine in the `AnkountantReader` package. Lookups
can spawn new cards. No desktop equivalent.

## Build Pipeline

### Rust Cross-Compilation

```
anki-bridge-rs/
├── src/lib.rs          — C FFI exports (crate-type = ["staticlib"])
├── Cargo.toml          — depends on this repo's rslib: anki = { path = "../../rslib" }
└── built via:
    cargo build --target aarch64-apple-ios         (device)
    cargo build --target aarch64-apple-ios-sim     (simulator arm64)
```

### XCFramework Packaging

`scripts/build-xcframework.sh` compiles the targets, builds a universal simulator
lib with `lipo`, then packages everything into `AnkiRust.xcframework`, consumed by
SPM as the `AnkiRustLib` binary target.

### Protobuf Generation

`scripts/generate-protos.sh` runs `protoc --swift_out` against the `.proto` files
in this repo's `proto/anki/` to produce Swift types in `Sources/AnkiProto/`, then
post-processes imports for Swift 6.2's `InternalImportsByDefault`.

## Key Design Decisions

- **Rust backend over pure Swift**: pure-Swift sync hit protocol issues (zstd, redirects, errors). The Rust backend is battle-tested by millions of users.
- **AGPL-3.0 license**: required by the `rslib` dependency.
- **Struct-closure DI**: Point-Free's `@DependencyClient` pattern — no protocols, no mock classes.
- **Protobuf over direct struct bridging**: the Rust backend already uses protobuf internally; reusing it avoids a second translation layer.
- **Vendored into this monorepo**: the iOS app links `rslib/` directly (`anki-bridge-rs` → `../../rslib`) rather than an external Anki release, so iOS and desktop share one core.
- **Rust owns the database**: Swift never reads SQLite directly; all data flows through Rust RPC calls for consistency.
