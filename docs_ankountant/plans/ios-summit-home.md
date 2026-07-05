# iOS "Summit" Home — CPA Section Flow

> Branch: working tree UI overhaul · Scope: **iOS + shared exam-date protobuf/client dispatch** ·
> Status: **implemented 2026-07-03**
>
> The original plan below described a five-section summit overview. The shipped
> implementation follows that inclusive CPA framing: a section-aware hero range,
> topic list, topic detail flow, pre-reveal confidence check, and Progress
> summary.

## Implementation Update

Implemented iOS surfaces:

- `HomeView` now renders the CPA summit hero, countdown/readiness cards, sync-safe exam-date control, active-section topic list, phase-aware study CTA, and confusion practice entry.
- `FarTopicDetailView` shows a selected topic's Memory, Performance, Gap, Memory range, Performance range, and confusion-set tokens.
- `ReviewView` requires a Guess/Unsure/Confident selection before answer reveal.
- `ContentView` now uses the supplied Home/Study/Review/Analytics/More tab shell while preserving the Reader, Browse/Review, Stats, and Settings destinations.
- `StatsDashboardView` now starts with a Progress summary card while preserving the existing full chart stack.

Data/feature preservation:

- Home still uses `DeckListView`, so deck browsing, import, sync, profile picker, and pull-to-refresh behavior stay in the existing app shell.
- Exam date now uses the backend `setExamDate`/`getExamDate` RPCs through `ExamConfigClient+Live`, matching desktop and avoiding local-only app storage.
- Readiness and topic values are live from `schedulerService.getReadiness`; insufficient data renders as withheld/insufficient instead of invented scores.

Verification:

- Built successfully with `xcodebuild build -project ios/AnkountantApp/AnkountantApp.xcodeproj -scheme AnkountantApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -quiet`.
- Computer Use visual QA inspected the rebuilt simulator Home screen and saved `work/ios-home-computer-use-final.png`.

---

The archived original plan follows for design history.

---

## 1. Goal & locked decisions

Reimagine the iOS **Home** as a **topographic "range"**: a horizontal mountain range
where **each CPA section is a peak**, its height is that section's projected exam
readiness, and a dashed **pass line at 75** runs across the range. Tapping a peak (or
its list row) drills into that section's per-topic Memory/Performance breakdown. This
is the mobile translation of the desktop "summit" mock the user selected — **no
vertical-ascent variant**.

**Locked decisions (do not relitigate during implementation):**

| #  | Decision                                                                                                                                                                                                                                                | Rationale                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| -- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1 | **Peaks = 5 sections: FAR, AUD, REG, TCP, ISC** (FAR first). BAR excluded.                                                                                                                                                                              | Explicit user choice. 3 Core (AUD/FAR/REG) + 2 Disciplines (TCP/ISC); BAR is the discipline dropped.                                                                                                                                                                                                                                                                                                                                          |
| D2 | **Peak height = section `ReadinessBand.pointEstimate` on the CPA 0–99 scale.** Pass line at **75**. Above iff `pointEstimate >= 75`.                                                                                                                    | The only section-level scalar the backend exposes; it is Performance-derived and lands 75 on the _real_ CPA pass line, making Constraint 1 literally true.                                                                                                                                                                                                                                                                                    |
| D3 | **Label the height axis "Projected CPA score (0–99)", NEVER "Performance."**                                                                                                                                                                            | "Performance" is a _different_ per-topic metric in this app; the ADR-0005 transform + abstain gate mean the height is a _projection_, not raw performance. (Honesty review.)                                                                                                                                                                                                                                                                  |
| D4 | **Unproven is gated on `band.abstain`, NEVER on height.**                                                                                                                                                                                               | On abstain the backend returns `pointEstimate = 0.0` (`..Default::default()`); plotting it as height would masquerade as a real score of 0.                                                                                                                                                                                                                                                                                                   |
| D5 | **The mountain is navy-only.** Above/below is signaled by **position vs the labeled dashed pass line + a neutral hollow-triangle glyph + a neutral tabular number**. The only semantic hue is a `warning` chip **off** the mountain.                    | Ledger firewall: navy is the sanctioned readiness-band color; scores are never painted in pass/fail hues; color-never-alone.                                                                                                                                                                                                                                                                                                                  |
| D6 | **Rendering = Swift Charts**, with the ≥75 guarantee living in a **pure, unit-tested** `TopoScale`/`passStanding` in `AnkiKit`.                                                                                                                         | Repo already uses Swift Charts with pinned axes + `RuleMark` precedent (`Stats/*`); Canvas text is invisible to VoiceOver and a `GeometryReader`-in-List row risks sizing loops. The invariant is a scalar comparison, so it's engine-independent as long as classification happens in the model and the y-domain is pinned. (Do **not** copy the semantic-colored gradients some Stats charts use, e.g. `ForecastChart`'s `.blue.gradient`.) |
| D7 | **The iOS range is a Home _overview/roadmap_ layer, not the canonical Readiness dashboard.** Canonical Readiness stays **per-confusion-set** (mirroring the desktop `ankountant-dashboard`); the iOS `SectionDetailView` mirrors that desktop drill-in. | Prevents cross-client mental-model drift: desktop = FAR diagnostic rows; iOS Home = a section-level overview that _links into_ the same per-topic diagnosis. A desktop "range" mirror is possible future work, out of scope here.                                                                                                                                                                                                             |

**The three hard constraints and where they're satisfied:**

1. **≥75 above / <75 below is real, not decorative** → §5 (pinned `0...99` domain, pure `passStanding`, marker at `y(point)`, unit tests).
2. **Memory & Performance bands per topic remain viewable** → §6 (`SectionDetailView` → `TopicBreakdownList`, now including the per-set **Gap**).
3. **Main Readiness stays the hero headline** → §7 (FAR CPA 0–99 Wilson band, abstain-aware, remains the largest readiness element).

---

## 2. Readiness data reality (verified against Rust)

`schedulerService.getReadiness(section) -> ReadinessSummary { band: ReadinessBand, topics: [TopicScoreModel] }`
(`ios/Sources/AnkiServices/SchedulerService.swift`, types in `ios/Sources/AnkiKit/SchedulerTypes.swift`).
Backed by `rslib/src/ankountant/readiness.rs`.

- **Never errors on missing data** — an empty/absent confusable map returns `Ok` with
  `topics: []`, `abstain: true`, `reason: "insufficient volume"`, `coverage: 0`,
  `pointEstimate: 0`. (It _can_ still throw on real SQLite/FFI failure; Swift's `try?`
  degrades that to the abstain UI.)
- **Abstain thresholds** (`constants.rs`): `ABSTAIN_MIN_ATTEMPTS = 20` sealed attempts,
  `ABSTAIN_MIN_COVERAGE = 0.60`, `MEMORY_MIN_REPS = 5`.
- **CPA transform** (`logic::cpa_scale_from_accuracy`, ADR-0005): monotonic, **caps at 99**
  (not 100) → the y-domain must be **`0...99`**. Below the line the CPA point equals
  `accuracy × 100` exactly (so a below-pass "60" peak and a "60%" topic meter _look_
  identical but mean different things — see the "two 75s" trap, §8).
- **Section point is pooled, attempt-weighted** (`sealed_correct / sealed_total`) — it is
  **not** the mean of the drill-in bars and **not** FR-1's 50/50 MCQ/TBS blend (that
  weighting applies only to the per-topic bars). Never present the peak as "the average
  of these topics."

**What each section shows today** (after loading the inclusive CPA demo profile):

| Section | Confusable map   | Seeded user data                                    | `getReadiness` result                                 |
| ------- | ---------------- | --------------------------------------------------- | ----------------------------------------------------- |
| **FAR** | seed sets        | recall history + sealed attempts                    | emits a readiness band when loaded with history       |
| AUD     | seed/import sets | sealed attempts + available study/community history | emits or abstains from the same evidence rules as FAR |
| REG     | seed/import sets | review history + sealed attempts                    | emits or abstains from the same evidence rules as FAR |
| TCP     | seed/import sets | review history + sealed attempts                    | emits or abstains from the same evidence rules as FAR |
| ISC     | seed/import sets | sealed attempts + available study/community history | emits or abstains from the same evidence rules as FAR |

Corrections the cross-check forced into this plan:

- **All visible sections are seeded with maps, sealed content, and/or imported study content**;
  they follow the same abstain rules, so the detail screen is not empty and no section is
  hardcoded as the always-real peak.
- **A section produces a band only when it has enough seeded or user-created evidence.**
  Content-only or a fresh collection → every section may abstain. The range must render
  gracefully when **all five abstain** (fresh install = five ghosts, never five zero-height
  peaks).
- **All 5 sections are real — verified against `cursor/cpa-online-cards`** (worktree
  `../ankountant-cpa-online`, currently uncommitted). It adds card-generation tooling
  (`tools/cardgen/scripts/{harvest_online,triage_online,emit_online}.py`, `fetch_ankiweb.mjs`)
  that harvests + LLM-triages online/AnkiWeb cards and emits scored Basic/Cloze candidates
  under `tools/cardgen/out/online/`. The current committed importable deck is still
  `tools/cardgen/out/tmpl4/cpa_bank.apkg`; no separate `online_bank.apkg` is present in this
  checkout. The online harvest changes **no `proto`, `rslib/src/ankountant`, or `ios` code**
  (only `tools/cardgen`, `docs_ankountant/rag`, and the desktop `qt/aqt/main.py` loader) → the
  iOS plan's data model and readiness math are unaffected.
- **Nuance (don't over-promise the peaks):** community cards are **study-pile (Memory)
  content**, while sealed **Performance** evidence comes from seeded/imported TBS items and
  logged attempts. Importing the bank plus the demo seeding gives all 5 visible sections real
  data, but each section still follows the same ≥20 sealed-attempt and ≥60% coverage gates.
  Net: **show all 5 peaks; each peak lights up only when its own evidence supports it.**

---

## 3. Canonical types & architecture

### 3.1 One section type, one state model (in `AnkiKit`)

Reuse the existing `ReadinessSummary` / `ReadinessBand` / `TopicScoreModel`. Add **only**:

```swift
// ios/Sources/AnkiKit/CPASection.swift
public enum CPASection: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case aud = "AUD", far = "FAR", reg = "REG", bar = "BAR", isc = "ISC", tcp = "TCP" // parity w/ Rust SECTIONS
    public var id: String { rawValue }
    public var code: String { rawValue }              // string every RPC/tag uses
    public var displayName: String {
        switch self {
        case .far: "Financial Accounting and Reporting"
        case .aud: "Auditing and Attestation"
        case .reg: "Regulation"
        case .tcp: "Tax Compliance and Planning"       // FIX: not "Technology & Controls"
        case .isc: "Information Systems and Controls"
        case .bar: "Business Analysis and Reporting"
        }
    }
    /// The 5 peaks shown on Home, FAR first. BAR intentionally excluded (D1).
    public static let homeOrder: [CPASection] = [.far, .aud, .reg, .tcp, .isc]
    public init?(code: String) { self.init(rawValue: code) }
}
```

Keeping all 6 cases preserves parity with Rust `SECTIONS` / `TBS_SECTIONS` and gives a safe
`init?(code:)`; `homeOrder` encodes the user's 5-peak display choice. (Resolves the
"5 vs 6" conflict: enum = 6 for correctness, display = 5.)

```swift
// ios/Sources/AnkiKit/ReadinessTopo.swift  (pure, no SwiftUI → unit-testable)
public enum PassStanding: Sendable, Equatable { case unproven, below, above }

public enum TopoScale {
    public static let domainMax: Double = 99          // ADR-0005 cap
    public static let passScore: Double = 75
    /// Strictly DECREASING affine map: 99 -> 0 (top), 0 -> H (base). Clamped.
    public static func y(_ score: Double, plotHeight H: CGFloat) -> CGFloat {
        let s = min(max(score, 0), domainMax)
        return H * (1 - CGFloat(s / domainMax))
    }
    public static func passLineY(plotHeight H: CGFloat) -> CGFloat { y(passScore, plotHeight: H) }
}

/// AUTHORITATIVE classifier — scalar, never pixels. Gate on abstain FIRST (D4).
public func passStanding(_ band: ReadinessBand) -> PassStanding {
    guard !band.abstain else { return .unproven }
    return band.pointEstimate >= TopoScale.passScore ? .above : .below
}

public struct SectionReadiness: Sendable, Equatable, Identifiable {
    public let section: CPASection
    public let summary: ReadinessSummary?             // nil = RPC failed → treat as unproven
    public var id: CPASection { section }
    public var band: ReadinessBand? { summary?.band }
    public var standing: PassStanding { band.map(passStanding) ?? .unproven }
    /// CPA point for plotting; nil when abstaining (render at base gutter, never height).
    public var heightPoint: Double? {
        guard let b = band, !b.abstain else { return nil }
        return b.pointEstimate
    }
}
```

Also **move these pure formatters** out of `HomeView` into `ReadinessTopo.swift` so they're
shared and testable: `scoreWithRange`, `pct`, `bandLabel`, `gapsToClose`,
`performanceInsufficient` (+ `TopicScoreModel.gapWarning = gap >= 0.25`, `displayName`).

> **Dropped duplicate names** from Wave 1 (collisions resolved): `SummitReadinessSnapshot`,
> `SectionPeak`, the `CpaSection` _struct_ → all replaced by the single `CPASection` enum +
> `SectionReadiness` value type above.

### 3.2 Presentation & navigation

- Home stays in **ContentView's `NavigationStack`** (push works). Study entry remains the
  tab-level `fullScreenCover(item: $pendingReviewDeckId)` — unchanged.
- Keep **`DeckListView` as the scroll host**, but make it **generic over `@ViewBuilder`
  slots** instead of taking `AnyView` (SwiftUI review: avoid `AnyView`; migrate the existing
  `header` too):

  ```swift
  struct DeckListView<Header: View, Middle: View>: View {
      @ViewBuilder var header: () -> Header       // hero
      @ViewBuilder var middle: () -> Middle       // section rows as REAL List Section(s)
      var onAdditionalRefresh: (() async -> Void)? = nil
      var navigationTitle: String = "Decks"
      // header Section, then middle Section(s), then existing deck sections
  }
  ```
  Section rows render as **real `List` Section(s)** (not stuffed inside the header blob), so
  each row is a natural ≥44pt `NavigationLink(value: CPASection)`.
- **One** destination registration on Home, coexisting with the existing two (distinct
  types → no conflict):

  ```swift
  DeckListView(header: { hero }, middle: { sectionRows }, onAdditionalRefresh: load,
               navigationTitle: "Home")
      .task(id: demoSeedVersion) { await load() }
      .navigationDestination(isPresented: $showConfusion) { ConfusionDrillView() }
      .navigationDestination(for: CPASection.self) { SectionDetailView(section: $0) }  // NEW
  ```
  Both peak taps (in `header`) and row taps (in `middle`) emit the same `CPASection` value →
  the same `SectionDetailView`. Make the **chart decorative** (`.accessibilityHidden(true)`
  or a single summary label); the **list rows own navigation + VoiceOver + 44pt**.

### 3.3 Loading & threading (corrected)

The backend serializes **every** FFI call under one `NSLock` (`AnkiBackend.callRaw`), so a
`TaskGroup`/5× `Task.detached` fan-out gives **zero** real parallelism and just blocks
cooperative-pool threads on a mutex. Correct shape:

```swift
private func load() async {
    // capture the @Sendable closure in-context (keeps swift-dependencies test overrides)
    let getReadiness = schedulerService.getReadiness
    // 1) exam date (cheap) + FAR first for progressive paint
    if let far = try? await runOffMain({ try getReadiness(CPASection.far.code) }) {
        farReadiness = far; sections[.far] = SectionReadiness(section: .far, summary: far)
    }
    heroLoaded = true
    guard !Task.isCancelled else { return }               // detached ≠ cancelled w/ .task(id:)
    // 2) the rest, sequential (lock serializes anyway), publish as they arrive
    for s in CPASection.homeOrder where s != .far {
        let summary = try? await runOffMain({ try getReadiness(s.code) })
        guard !Task.isCancelled else { return }
        sections[s] = SectionReadiness(section: s, summary: summary)
    }
    // 3) FAR study deck id for the phase CTA — also off main
    farDeckId = ...
}
```

- `runOffMain` = a single `Task.detached`/`nonisolated` hop per call; **capture the
  `@Sendable` dependency closures in-context before hopping** (preserves swift-dependencies
  test overrides), use `.userInitiated` priority, and **guard `!Task.isCancelled` before
  publishing** to `@State` (assignment lands back on the MainActor after `await`). Move the
  **whole** load off-main (config read, readiness, deck tree) — the current code blocks the
  main actor — and move `saveExamDate` off-main too.
- **First paint must not block on 5 calls** — render the shell + FAR immediately, fill the
  rest progressively (per-row skeleton → abstain/real).
- **Refresh:** keep `.task(id: demoSeedVersion)`; add `onAdditionalRefresh` so
  pull-to-refresh reloads readiness **and** decks; also reload the **deck tree on reseed**
  (today `demoSeedVersion` re-runs Home's `.task` but not `DeckListView`'s → stale decks).
- **No batch RPC** for MVP (it would save ~4 FFI round-trips, not compute; FAR dominates).
- **Defensive:** in `SchedulerService.getReadiness`, treat `!resp.hasReadiness` as an
  abstaining band (guards a future `readiness = None` from rendering a fake 0-height peak).

### 3.4 File map (deduped)

**NEW — `AnkiKit` (SPM auto-includes):**

| Path                                              | Purpose                                                                                |
| ------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `ios/Sources/AnkiKit/CPASection.swift`            | 6-case enum + `code`/`displayName`/`homeOrder`/`init?(code:)`                          |
| `ios/Sources/AnkiKit/ReadinessTopo.swift`         | `SectionReadiness`, `PassStanding`, `TopoScale`, `passStanding`, moved pure formatters |
| `ios/Tests/AnkiKitTests/ReadinessTopoTests.swift` | Unit tests for the scale/classifier/formatters + `CPASection`                          |

**NEW — app target `AnkountantApp/Sources/Home/`:**

| Path                        | Purpose                                                                                                             |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `RangeHeroChart.swift`      | Swift Charts topographic range (5 peaks, pass-75 rule, Wilson bands, abstain ghosts); decorative for a11y           |
| `SectionReadinessRow.swift` | One section list row + `NavigationLink(value: CPASection)`                                                          |
| `ReadinessComponents.swift` | Shared `ReadinessBandView` + `TopicBreakdownList` + `TopicScoreRow` + `PositionMeter` (used by Home **and** detail) |
| `SectionDetailView.swift`   | Per-section detail; reuses the shared components; loads `getReadiness(section.code)`                                |

**MODIFY:**

| Path                                                 | Change                                                                                                                                                                                                                                                                                             |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ios/AnkountantApp/Sources/Home/HomeView.swift`      | Load `[CPASection: SectionReadiness]` (5, FAR-first, off-main); render `RangeHeroChart`; section rows as `middle`; add `.navigationDestination(for: CPASection.self)`; FAR-tag the readiness card; degrade to abstain when FAR abstains; swap internals to shared components; delete moved helpers |
| `ios/AnkountantApp/Sources/Decks/DeckListView.swift` | Generic `@ViewBuilder` `header`/`middle` slots (migrate off `AnyView`); `onAdditionalRefresh`; reseed-aware deck reload                                                                                                                                                                            |
| `ios/Sources/AnkiServices/SchedulerService.swift`    | Map `!resp.hasReadiness` → abstain band (defensive)                                                                                                                                                                                                                                                |

**Build note:** `project.yml` uses `type: group` for `Sources/`, so new files are picked up
on **`xcodegen generate`** (already part of the documented build). No `project.yml` edit; no
`.proto`/`AnkiBackend` index change (readiness RPC already wired).

---

## 4. Hero headline (Constraint 3)

New hero order (mirrors the mock): **(a) countdown → (b) FAR readiness band → (c) topographic
range → (d) section list → (e) actions.**

- **Keep verbatim:** `countdownCard` (numeral in neutral ink, DatePicker → `examConfigClient`),
  the phase-aware CTA + "View stats", and all derived helpers.
- **`readinessCard` stays the headline** and stays the **largest readiness element** (the
  range is supporting context, never the hero). Header string should use the active section
  code, e.g. **"REG · Exam-day projection"**, so the band unambiguously reads as scoped.
- **Degrade to abstain when the active section abstains** (already implemented for the single
  card — must be preserved; don't assume any section always yields a band).
- **Quick stats** ("Topics tracked" / "Gaps to close") count active-section confusion sets;
  relabel as section topics where needed.
- **`topicsCard` moves** into `SectionDetailView` (tapping a peak/row) to keep the hero from
  getting too tall; every section renders the same shared components.
- **Section switcher (fast-follow, now that all 5 are real):** repointing the headline
  countdown + readiness to a tapped section becomes worthwhile. Exam date is already stored
  **per section** (`ankountant.<section>.exam.date`), so no schema change is needed. MVP keeps
  **FAR as the fixed focus**; the switcher is a small, additive follow-up.

---

## 5. The topographic range (Constraint 1)

**Engine:** Swift Charts, `.chartYScale(domain: 0...99)` **pinned** (forgetting this makes
Charts autoscale to the data and the 75 line falls off — the one real footgun). Fixed
`.frame(height: ~200pt)` (self-sizing List rows need a definite chart height).

**Marks (all share the pinned scale):**

- **Pass line:** `RuleMark(y: .value("Pass", 75))`, dashed, `palette.textSecondary`
  (neutral, high-contrast over navy), with a visible **"Pass 75"** label (not aria-only).
- **Per-section peak:** navy `AreaMark`/`LineMark` at `pointEstimate`, graded opacity;
  **identical navy for all five** (never per-peak/semantic color).
- **Wilson band (the summit):** faded navy zone from `bandLow`→`bandHigh` (`RectangleMark`/
  `AreaMark`, soft gradient) — **never a crisp apex**; the marker (point) sits inside it.
- **Above/below:** encoded by the marker's **position relative to the labeled line** +
  a neutral **hollow triangle** glyph (`arrowtriangle.up`/`down`) + neutral tabular number.
- **Abstain ghost:** a **hatched, dashed, neutral** block in a base gutter with `square.dashed`
  - "Not enough data yet" — **no height, no band, no number.** Gated on `band.abstain` (D4).

**Correctness / testability (the actual Constraint-1 deliverable):** classification is the
scalar `passStanding(band)`, computed in `AnkiKit`, never read from pixels. `TopoScale.y` is a
strictly decreasing affine map, so `point >= 75 ⇔ y(point) <= y(75)` by construction. Unit
tests (in `AnkiKitTests`, run via `swift test` — no simulator):

```swift
#expect(passStanding(band(point: 84)) == .above)
#expect(passStanding(band(point: 61)) == .below)
#expect(passStanding(band(point: 75)) == .above)          // 75 = pass (inclusive)
#expect(passStanding(abstaining) == .unproven)            // even though pointEstimate == 0
#expect(TopoScale.y(84, plotHeight: 200) < TopoScale.passLineY(plotHeight: 200))
#expect(TopoScale.y(61, plotHeight: 200) > TopoScale.passLineY(plotHeight: 200))
for s in stride(from: 0.0, through: 99.0, by: 1) {         // exhaustive invariant
    #expect((s >= 75) == (TopoScale.y(s, plotHeight: 200) <= TopoScale.passLineY(plotHeight: 200)))
}
```

Classify on the **raw** double (accept that a raw 74.6 prints "75" but is `.below`).

---

## 6. Section list + detail (Constraint 2)

**Section row** (in `middle`): section code + `displayName`, the readiness **point** (tabular)
or an **"Unproven"** chip, a compact above/below indicator (mini pass-line position + hollow
glyph + text — never color-only), chevron. `NavigationLink(value: section)`.

**`SectionDetailView`:** header = section name + its readiness band (`ReadinessBandView`,
CPA 0–99, abstain-aware), then the **per-confusion-set breakdown** via `TopicBreakdownList` →
one `TopicScoreRow` per set, each showing **Memory** and **Performance** as **neutral
position-bar meters + Wilson range subtext** ("62% (54–70%)") and the **per-set Gap** with a
`warning` icon+label when `gap >= 0.25`. (iOS currently omits the per-row Gap that desktop
shows — add it.) Handles empty topics / all-insufficient / load-failure gracefully.

**Extraction:** lift `topicsCard`, `readinessCard`, `abstain`, and the helpers out of
`HomeView` into `ReadinessComponents.swift` (SwiftUI) + `ReadinessTopo.swift` (pure). One
definition, two call sites (Home-FAR and every SectionDetail) → zero divergence. **Meters
carry NO "75" line** (that's the CPA-scale pass, not a 75% accuracy target — the "two 75s"
trap, §8).

---

## 7. Aesthetics rulebook (Ledger)

All colors from `@Environment(\.palette)`; fonts via `ankountantFont`; spacing/radius from
tokens. **C2 rule (locked):** the mountain is navy-only; verdict = geometry + glyph + text;
the single semantic outlet is a `warning` chip off the mountain ("Below pass · +N to 75");
above/abstain chips are neutral; **green is never used** (a green "PASS ✓" dresses a
projection up as a measurement).

| Element                                        | Token                                                                                  | Font                | Light → Dark note                        |
| ---------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------- | ---------------------------------------- |
| Hero card                                      | `surfaceElevated` + `border`, `.e2` (via `ankountantCard(elevated:)`)                  | —                   | dual-scheme                              |
| Countdown numeral                              | `textPrimary` (**not** accent) + mono                                                  | `.displayHero`      | —                                        |
| FAR readiness band value (the one navy number) | `accent` + mono                                                                        | `.sectionHeading`   | L `#1F3A5F` / D `#7FA6D4`                |
| Contour lines (decoration)                     | L `border` / **D `borderStrong`**, ~0.6                                                | —                   | D must step up to stay ≥3:1              |
| Dashed pass line                               | `textSecondary`, dash `[5,4]`                                                          | —                   | neutral, reads over navy in both schemes |
| "Pass 75" label                                | `textSecondary` on chip                                                                | `.micro` uppercase  | the only "flag" allowed                  |
| Peak silhouette + marker                       | `accent` graded (body ~.14/.20, ridge ~.5/.6)                                          | —                   | identical for all 5                      |
| Wilson-band summit                             | `accent` vertical fade `bandLow…bandHigh`                                              | —                   | soft, **no crisp apex**                  |
| Peak point number                              | `textPrimary` (**neutral**) + mono                                                     | `.captionBold`      | navy reserved for the aggregate band     |
| Above/below glyph                              | `textSecondary` `arrowtriangle.up/down`                                                | `.caption`          | position + glyph + number                |
| Abstain ghost                                  | dashed `borderStrong` + 45° hatch (`border`/**`borderStrong`** dark) + `square.dashed` | `.caption`/`.micro` | hatch must survive dark                  |
| Section chip (only semantic outlet)            | below = `.ankountantStatusBadge(.warning)`; above/abstain = `.neutral`                 | `.captionBold`      | warning L `#8A5A12` / D `#F5B44E`        |

**Motion (feedback-only):** pass line fades in first, then peaks grow from baseline
(`AnkountantMotion.spring`/`.base`, staggered ~40ms). **No** confetti/sparkle/overshoot/
planted-flag/score-climb replay. **Reduce Motion** → peaks appear at final height with a
single ~100ms opacity fade (gate via `AnkountantMotion.animation(_:reduceMotion:)`).

**Accessibility:** every peak = position + glyph + neutral tabular number (color-never-alone);
the **section list is the accessible/interactive fallback** at large Dynamic Type (it carries
100% of the info); VoiceOver per row, e.g. _"FAR, projected 61, below pass line 75, medium
confidence"_ / _"AUD, not enough data yet."_; ≥44pt targets; 2px navy focus ring (never glow).

**Drop from the AI mock:** rainbow/per-peak colors (→ all navy), crisp apexes (→ faded band),
planted victory flags (→ dropped), any green PASS, `.blue.gradient`, gauge-style solid fills,
large navy per-peak numerals (→ neutral ink), and any height on an unproven section.

---

## 8. Honesty guardrails + final microcopy

**Guardrails (must hold):** unproven by `abstain` not height (D4); label "Projected CPA
score," never "Performance" (D3); **no "75" line on the 0..1 drill-in meters** (CPA-scale 75
≠ 75% accuracy — the "two 75s" trap); summit = faded band not apex; hero degrades to abstain
when FAR abstains; **no gamification** (no streaks/points/confetti/victory flags/"summit
reached"/"% climbed" — the mountain metaphor is the biggest creep vector, keep peaks a neutral
value-encoding); below-pass framed informatively (no PASS/FAIL, no red alarm); color-never-
alone on pass line / above-below / unproven; **the displayed score never reads an unqualified
"75" unless the section is actually ≥75** (near-pass display rule below).

**Final microcopy:**

- Axis title: `Projected CPA score (0–99)` · pass marker: `Pass 75` · caption: `Height = projected CPA score (0–99). Pass line at 75.`
- Hero disclaimer — **align to the desktop's existing string** (don't invent a new one; true cross-client unification would require editing `Dashboard.svelte`, out of scope here): `Rough projection on the CPA 0–99 scale (pass 75); the band is the confidence range, not an official AICPA score.`
- Above: `+{n} above the 75 pass line` · Below: `{n} below the 75 pass line` · Straddle: `range crosses the 75 pass line`
- **Empty state (uniform across all 5 sections):** an active-but-thin section (any of FAR/AUD/REG/TCP/ISC before enough evidence) → `Not enough data yet` + tooltip `Withheld until there's enough evidence — need ≥ 20 sealed attempts and ≥ 60% topic coverage.` (drivers from `band.reasons`). Renders as a neutral hatch/dashed ghost, never a height. All five are real sections (content lives across branches), so there is **no** "not in this version" state.
- Drill-in (accuracy %, **never** a "75"): `Memory 62% (54–70%)` · `Performance 48% (40–56%)` · `Gap 14 pts` · insufficient → `insufficient`.
- **Near-pass display rule:** classify on the raw `pointEstimate`, but clamp the _displayed_ integer so it never crosses the line versus the true standing — below-pass shows `min(round(point), 74)`, above-pass shows `max(round(point), 75)`. Stops a below-pass score from rendering as an unqualified "75" beside the `Pass 75` line.

---

## 9. Edge cases → required behavior

| Case                                                 | Behavior                                                                                                                 |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| FAR abstains (fresh / content-only / foundation)     | FAR peak = ghost; hero = abstain state. Never special-case FAR as proven.                                                |
| All 5 abstain (fresh install)                        | Five hatched ghosts in the gutter; **never** five zero-height peaks; quick stats "no projection yet," not "0/5 passing." |
| Genuinely low-but-proven (e.g. point 20)             | Real filled peak at 20 **with** band — visually distinct from a ghost (filled+band+on-scale vs hatched+gutter).          |
| `pointEstimate` exactly 75                           | `.above` (inclusive); marker on the line.                                                                                |
| Zero-width band (`bandLow == bandHigh`, non-abstain) | Marker only, no ribbon; guard against divide-by-zero/NaN.                                                                |
| Clamp                                                | Domain `0...99`; `TopoScale.y` clamps.                                                                                   |
| `getReadiness` throws (real error)                   | `try?` → `nil` summary → row/peak = unproven (acceptable; note it won't show the true error reason).                     |
| `!resp.hasReadiness`                                 | Treated as abstain (defensive map in the service).                                                                       |

---

## 10. Build / test / verify

> iOS is the documented exception to the repo's `just`-only rule — it has its own toolchain
> (`xcodegen` / `xcodebuild` / `swift test`); `just` builds the **desktop** only. Don't expect
> a `just` recipe to build or test iOS.

```bash
# from ios/  (only if the xcframework is missing — this feature is Swift-only)
./scripts/build-xcframework.sh
# REQUIRED: group-scan picks up new Sources/Home/*.swift
cd AnkountantApp && xcodegen generate && cd ..
xcodebuild build -project AnkountantApp/AnkountantApp.xcodeproj -scheme AnkountantApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
# pure logic (no simulator):
swift test --filter AnkiKitTests
```

**Manual QA:** FAR below-pass (demo seed); AUD/REG/TCP/ISC unproven; FAR-abstain (foundation)
→ hero + all peaks unproven; dark mode (contour/pass line/hatch contrast); Dynamic Type
(labels scale, list is the fallback); VoiceOver (peak + row announce standing, both push the
same detail); pull-to-refresh reloads readiness **and** decks; near-pass display (a below-pass
score never shows an unqualified "75"). **Regression on the `DeckListView` generic-slot
refactor:** `DeckDetailView` (DeckInfo) nav, ConfusionDrill, "View stats," deck
create/rename/delete, and the no-header default path.

---

## 11. Open product decisions (non-blocking; sensible defaults chosen)

1. **Non-FAR peak label — RESOLVED: show all 5 peaks, uniform "Not enough data yet."** The
   owner confirmed question content exists for **all five** sections (in a separate branch, to
   be integrated), so AUD/REG/TCP/ISC are **real, in-scope sections** — the audit's "Not in
   this version" framing is **withdrawn**. Every section shows a real readiness band once it
   has enough sealed attempts (≥20) and coverage (≥60%); until then it shows the same honest
   "Not enough data yet" ghost as a thin FAR. Uniform treatment, no special-casing.
2. **Section rows placement** — default **directly under the hero, above** the deck
   heatmap/list.
3. **Keep the deck list on Home** — default **yes** (least-risk; decks stay reachable).

---

## 12. Implementation sequence

1. `AnkiKit`: `CPASection`, `ReadinessTopo` (scale/classifier + moved formatters) + tests → `swift test`.
2. `SchedulerService`: defensive `hasReadiness` mapping.
3. `ReadinessComponents.swift`: extract `ReadinessBandView` / `TopicBreakdownList` / `TopicScoreRow` (+ per-set Gap).
4. `SectionDetailView.swift`.
5. `RangeHeroChart.swift` (Charts, pinned domain, marks, abstain ghosts, decorative a11y).
6. `SectionReadinessRow.swift`.
7. `DeckListView`: generic `@ViewBuilder` slots + `onAdditionalRefresh` + reseed reload.
8. `HomeView`: off-main progressive `load()`, new hero order, `RangeHeroChart` + rows, `navigationDestination(for:)`, FAR label, abstain degrade, delete moved helpers.
9. `xcodegen generate` → `xcodebuild` → manual QA (§10).

---

## 13. External audit (ChatGPT 5.5 max) — verdict & applied changes

An independent audit by a ChatGPT 5.5 (max reasoning) agent reviewed this plan from the
desktop, iOS, and shared-Rust perspectives (it ran the two client passes itself, as nested
subagents weren't available in its sandbox). **Verdict: ship with changes.** It confirmed the
Rust data claims (abstain → `pointEstimate 0`; CPA cap 99; thresholds 5 / 20 / 0.60; pooled
attempt-weighted section point). Changes it prompted, now folded in above:

- **Section framing → evidence-gated, not section-gated** (§11 #1): "Not enough data yet"
  means the section lacks enough evidence right now, not that the section is outside the
  product.
- **Cross-client framing (D7):** the iOS range is an _overview/roadmap_ layer; canonical
  Readiness stays per-confusion-set (the desktop model), which the iOS detail mirrors.
- **Near-pass display rule (§8):** a below-pass score must never render as an unqualified "75"
  beside the pass line.
- **Disclaimer aligned to the desktop's existing wording (§8)** instead of a new ADR variant
  ("unifying" both clients would require a desktop edit — out of scope).
- **Charts claim softened (D6):** "existing Swift Charts + pinned-axis/`RuleMark` precedent,"
  and explicitly don't copy the semantic-colored gradients some Stats charts use.
- **Threading specifics (§3.3):** capture `@Sendable` closures pre-hop, cancellation guard
  before publish, `saveExamDate` off-main.
- **Verification/build (§10):** added `DeckListView` refactor regression checks and an
  explicit note that iOS is the documented exception to the repo's `just`-only rule.

**Resolved after the audit:** the owner confirmed **show all 5 peaks** — question content for
all five sections exists in a separate branch (to be integrated), so AUD/REG/TCP/ISC are real,
in-scope sections. The "Not in this version" recommendation is **withdrawn**: all five use the
uniform "Not enough data yet" treatment while thin, and each shows a real readiness band once
it has attempts. `CPASection.homeOrder` stays at all five. **Verified:** the content branch
`cursor/cpa-online-cards` introduces **no `proto`/readiness/iOS changes** — it's card-generation
tooling that emits community study decks tagged `sec::<SECTION>` across all sections (§2). The
iOS plan is unaffected; non-FAR peaks stay honest "Not enough data yet" until their
sealed/attempt pipeline is populated (community study cards alone don't lift the band).
