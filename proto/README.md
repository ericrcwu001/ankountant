Protobuf files defining the interface the frontend and backend components use to
talk to each other, and how Anki stores some of the data inside its SQLite
database. These files generate Rust, Python, and TypeScript bindings through the
main build, and Swift protobuf message types through `ios/scripts/generate-protos.sh`.
The iOS service/method dispatch IDs are still hand-maintained in
`ios/Sources/AnkiBackend/AnkiBackend.swift`; re-derive them from
`out/pylib/anki/_backend_generated.py` after proto changes.
