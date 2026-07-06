# 10 — iOS TBS Surfaces: As-Built Map

> Status: **Implemented** · Owner: eric · Last audited: 2026-07-06 · Scope:
> native SwiftUI research, document-review, journal-entry, numeric, and confusion
> simulation surfaces.
>
> Earlier versions of this file described research and document-review as future
> placeholders. That is no longer true: iOS now routes those shapes to real
> SwiftUI views and submits them through the shared Rust grading path.

## Current Behavior

| Shape | View | Client method | Submit mode | Scoring |
| --- | --- | --- | --- | --- |
| Journal entry | `TbsTaskView` | `submitTbs` | `tbs` | per-line partial credit |
| Numeric | `TbsTaskView` | `submitTbs` | `tbs` | per-cell partial credit |
| Research | `ResearchTaskView` | `submitResearch` | `research` | all-or-nothing citation; time-to-cite recorded |
| Document review | `DocReviewTaskView` | `submitDocReview` | `doc_review` | per-blank partial credit |
| Confusion | `ConfusionDrillView` | `submitConfusion` | `confusion` | treatment choice correctness |

All surfaces require a pre-submit confidence commit. Correctness is authoritative
on the Rust side; Swift parses only render-safe fields and never receives
`answer_key`.

## As-Built File Map

| Concern | Files |
| --- | --- |
| Swift domain model | `ios/Sources/AnkiKit/{TbsModels.swift,TbsParsing.swift,Literature.swift}` |
| Client facade and live impl | `ios/Sources/AnkiClients/{PerformanceClient.swift,PerformanceClient+Live.swift}` |
| Backend service wrapper | `ios/Sources/AnkiServices/SchedulerService.swift` |
| Hand-maintained dispatch IDs | `ios/Sources/AnkiBackend/AnkiBackend.swift` |
| Hub and shape chooser | `ios/AnkountantApp/Sources/Simulations/SimulationsHubView.swift` |
| JE/numeric host | `ios/AnkountantApp/Sources/Simulations/TbsTaskView.swift` |
| Research surface | `ios/AnkountantApp/Sources/Simulations/ResearchTaskView.swift` |
| Document-review surface | `ios/AnkountantApp/Sources/Simulations/DocReviewTaskView.swift` |
| Shared simulation components | `ConfidenceGateView.swift`, `SimulationSupportViews.swift`, `TbsLearningFeedbackUserAnswers.swift` |
| Learning feedback | `ios/Sources/AnkiClients/LearningFeedbackClient*.swift`, `ios/AnkountantApp/Sources/Shared/LearningFeedbackPanel*.swift` |
| Parsing/client tests | `ios/Tests/AnkiKitTests/TbsParsingTests.swift`, `LearningFeedbackTests.swift`, `ReadinessTopoTests.swift` |
| Core grading and seed | `rslib/src/ankountant/{service,grading,logic,readiness,seed}.rs` |

## Literature Search

Research uses a bundled, per-section client-side literature corpus. The Swift
resource is `ios/Sources/AnkiKit/Resources/seed_literature.json`, kept in sync
with `rslib/src/ankountant/seed_literature.json`. There is no
`SearchLiterature` RPC, so adding or editing literature content does not require
proto index resync unless a separate backend search feature is introduced.

## Proto / Dispatch Notes

The existing `SubmitPerformanceAttempt` RPC covers all current simulation
submits. No new RPC was needed for research or document-review. If a future
feature does append a scheduler RPC, the required sequence is:

1. Append the proto method at the end of `SchedulerService`.
2. Run `just check` so Rust/Python/TypeScript generated outputs update.
3. Re-derive the Swift backend method index from
   `out/pylib/anki/_backend_generated.py`.
4. Update `ios/Sources/AnkiBackend/AnkiBackend.swift`.
5. Regenerate Swift protobuf messages with `ios/scripts/generate-protos.sh`.
6. Rebuild `ios/AnkiRust.xcframework`.

## Remaining Work

- Broader section/content coverage and more realistic authoring examples.
- Additional XCTest around full view flows where practical.
- UX polish for keyboard/external-keyboard entry, dropdown blanks, and account
  selection.

## Verification

Use repo recipes and iOS build tools:

```bash
just test-ios
cd ios && swift test
cd ios/AnkountantApp && xcodegen generate && cd ../..
xcodebuild build -project ios/AnkountantApp/AnkountantApp.xcodeproj -scheme AnkountantApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```
