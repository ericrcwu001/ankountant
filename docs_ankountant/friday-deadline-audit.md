# Friday Deadline Audit

Date checked: 2026-07-03.

Source deadline: `docs_ankountant/Speedrun_ A Desktop + Mobile Study App Built on Anki.md`, section "Due Friday: AI added and checked; phone syncs".

## Desktop AI

| Requirement                                                        | Status      | Evidence                                                                                                                                                   |
| ------------------------------------------------------------------ | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Short note on what AI was built, why, and what was skipped         | Done        | `README.md` "AI: grounded card generation"; `docs_ankountant/rag/RAG_RUN_RESULTS.md`                                                                       |
| Every AI output traces to a named source                           | Done        | `source_passage`, `source_id`, `locator`, and `gen_method` are documented for shipped cards in `docs_ankountant/rag/RAG_RUN_RESULTS.md`                    |
| Eval before students see anything, with accuracy/wrong rate/cutoff | Done        | `proof3`: cutoff = ship only `correct_useful`; 181 correct+useful, 70 wrong, 12 bad-teaching                                                               |
| Side-by-side baseline win                                          | Done        | `proof3`: hybrid faithfulness 0.742 vs BM25 0.608 and vector 0.592 on n=120                                                                                |
| App still gives a score with AI switched off                       | Implemented | Runtime study/readiness is deterministic; card generation is build-time only; offline cardgen path has 71 keyless tests documented in `RAG_RUN_RESULTS.md` |

## Mobile

| Requirement                                                   | Status                          | Evidence                                                                                                                                                               |
| ------------------------------------------------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Phone builds and runs                                         | Done                            | `xcodebuild build -project ios/AnkountantApp/AnkountantApp.xcodeproj -scheme AnkountantApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -quiet` passes |
| Review on phone uses shared engine                            | Implemented                     | iOS uses `AnkiBackend` over C FFI and `ReviewSession`; build passes after the UI overhaul                                                                              |
| Two-way sync code path                                        | Implemented, proof still needed | `SyncCoordinator`, `SyncClient+Live`, `SyncService`, media sync, full-sync, merge flow, reconnect auto-sync, and state-machine tests exist                             |
| Offline review, then sync on reconnect                        | Implemented, proof still needed | Local collection review works offline by design; `SyncCoordinator` monitors reachability and auto-syncs on reconnect when a server is configured                       |
| Phone shows three scores with ranges and follows give-up rule | Implemented                     | Home shows Readiness with range/confidence or withheld; topic detail shows Memory and Performance ranges plus Gap; insufficient data renders withheld/insufficient     |

## UI Overhaul Verification

- Desktop Svelte check: `./yarn svelte-check:once` passes with 0 errors and 0 warnings.
- Desktop visual QA: Computer Use inspected the live Chrome render; `work/desktop-home-computer-use-slope-contours.png` captured the `ankountant-home` route with protobuf-shaped mocked `_anki` responses because the route correctly fails outside Qt without backend RPCs.
- iOS build: xcodebuild passes on iPhone 17 Pro Max simulator.
- iOS visual QA: Computer Use inspected the rebuilt Simulator Home screen and `work/ios-home-computer-use-final.png` captured the result.

## Remaining Friday Proof

These are not additional implementation tasks; they are evidence tasks that need a real sync server or two configured clients:

1. Record phone review syncing to desktop and desktop review syncing to phone.
2. Record offline phone reviews, reconnect, and show they sync without lost or duplicated reviews.
3. Record or log the same-card offline conflict rule. The merge flow exists, but the Speedrun asks for an explicit demonstration.
4. Capture the phone readiness/topic-detail screens after importing a deck with enough sealed evidence so the non-abstain Memory, Performance, and Readiness ranges are visible.
