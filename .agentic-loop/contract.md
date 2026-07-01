# agentic-loop done-contract

> Hand-authored pre-seed (the rubrics in prd/rubrics-core.md + prd/rubrics-frontend.md
> were already 4-expert reviewed). IMMUTABLE during Build — a restart rebuilds FROM this
> file, it is not renegotiated. Every assertion is objective and mechanically checkable.
>
> SCOPE OF THIS CONTRACT (deliberate exclusions — do NOT add them here):
>
> - A2 (latency defunding, feature F002) is P1 / cut-first and is EXCLUDED so parking it
>   cannot fail the contract. Implement F002 only after all P0 features are green.
> - iOS acceptance criteria are a NON-GATED demo checklist (no Playwright/XCTest gate) and
>   are EXCLUDED — the objective contract is Rust + Python + desktop Playwright only.
> - Non-gating timing/perf ACs (A3-AC4, A4-AC4, NFR-1 <100ms) are EXCLUDED — do not gate ship on timing.
>
> Desktop-UI assertions are verified by their OWN Playwright spec (run via `just test-e2e`),
> NOT by the blanket testCmd (`just test-rust && just test-py && just test-ts`), which
> deliberately omits e2e (slow/flaky per iteration). The e2e fixture must load the FAR seed (F016).

## Assertions

A01. `just check` exits 0 (format + build + clippy/mypy/ruff/tsc/svelte all clean). — verify: `just check` exits 0 — features: F001,F006,F008,F009

A02. The Rust + Python + TS suites pass. — verify: `just test-rust && just test-py && just test-ts` all exit 0 with zero failures — features: F001,F003,F004,F005,F006,F007,F008,F009,F010

A03. desired_retention == 0.80 when the exam date is 90 days out (any d >= 60). — verify: `just test-rust` has a passing test asserting the ramp fn returns 0.80 at days_to_exam=90 — features: F001

A04. desired_retention == 0.875 when the exam date is 30 days out. — verify: `just test-rust` asserts ramp(30)==0.875 — features: F001

A05. desired_retention == 0.95 when the exam date is 0 or in the past. — verify: `just test-rust` asserts ramp(0)==0.95 and past dates clamp to 0.95 — features: F001

A06. With no exam date, desired_retention falls back to the deck/preset configured value (no dynamic override). — verify: `just test-rust` asserts the no-date path returns the configured preset retention — features: F001

A07. For the same stable review card, ComputeExamSchedule with a nearer exam date (30d, dr=0.875) yields a shorter next interval than a farther one (90d, dr=0.80). — verify: `just test-rust` asserts interval(30d) < interval(90d) for the same card — features: F001

A08. The new ComputeExamSchedule RPC is callable from Python after `just check`. — verify: `just test-py` invokes ComputeExamSchedule and receives a response — features: F001

A09. The exam date is read from `col` config `ankountant.exam.FAR.date`, set via the existing config-set RPC (no new setter RPC); changing it changes the ramp output. — verify: `just test-rust`/`just test-py` sets the col config and observes the retention change — features: F001

A10. BuildConfusionQueue returns an interleaved queue that never places 3+ consecutive items of the same `ds::` tag. — verify: `just test-rust` asserts no 3-in-a-row same-tag on a seeded lease set — features: F003,F006

A11. Confusion sets are ordered by discrimination weakness — a set at 40% historical accuracy ranks entirely before a set at 80% (from Attempt Log grouped by confusion_set_id). — verify: `just test-rust` asserts all 40%-set items precede all 80%-set items — features: F003,F008

A12. The client-facing ConfusionItem DTO has no populated category/topic/deck-label field. — verify: `just test-rust` asserts the DTO exposes no such populated field — features: F003

A13. GetReadiness returns, per topic, memory, performance, and gap with gap == memory - performance. — verify: `just test-rust` asserts the equality on seeded data — features: F004

A14. performance is computed ONLY from sealed-bank (A7) attempts; a study-only topic shows no study-pile leakage into performance. — verify: `just test-rust` seeds a study-only topic and asserts performance reflects no leakage — features: F004,F007

A15. TBS attempts contribute their partial-credit fraction (not pass/fail) to performance. — verify: `just test-rust` asserts a fractional TBS credit changes performance accordingly — features: F004,F010

A16. With < 20 sealed attempts, GetReadiness returns abstain==true with reason "insufficient volume". — verify: `just test-rust` — features: F005

A17. With >= 20 attempts but coverage < 60% (coverage = sets-with->=1-attempt / sets-defined), GetReadiness returns abstain==true with reason "insufficient coverage". — verify: `just test-rust` — features: F005

A18. With sufficient volume + coverage, abstain==false and band_low < band_high (never a single point) plus a confidence level. — verify: `just test-rust` — features: F005

A19. At fixed accuracy, halving the attempt volume widens the Wilson band ((H2-L2) > (H1-L1)). — verify: `just test-rust` asserts the band widens from 40 to 20 attempts at the same accuracy — features: F005

A20. A query returns all notes carrying a given `ds::...` tag. — verify: `just test-rust` — features: F006

A21. The CONFUSABLE map (`col` config `ankountant.confusable.FAR`) resolves each `ds::` tag to exactly one set_id (no tag in two sets). — verify: `just test-rust` — features: F006

A22. Cards are filterable by `cog::rote` / `cog::applied` tag. — verify: `just test-rust` — features: F006

A23. `ds::` and `cog::` tags round-trip unchanged through save/reopen. — verify: `just test-rust` — features: F006

A24. Sealed-bank cards (queue = -1) never appear in GetQueuedCards for normal study. — verify: `just test-rust` — features: F007

A25. A sealed item and a study item on the same topic are distinct notes (no shared note id). — verify: `just test-rust` — features: F007

A26. Attempts on sealed items feed Performance but never enter the FSRS study schedule. — verify: `just test-rust` — features: F007,F004

A27. A confusion answer creates exactly one Attempt Log note carrying confidence, latency_ms, confusion_set_id, and outcome. — verify: `just test-rust` — features: F008

A28. A TBS attempt creates one Attempt Log note whose outcome_json holds per-step credit. — verify: `just test-rust` — features: F008,F010

A29. Attempt Log notes are never returned by the normal study queue. — verify: `just test-rust` — features: F008

A30. `PRAGMA table_info` for notes/cards/revlog is identical before and after writing attempts + save/reopen (no new table/column) and attempts remain queryable. — verify: `just test-rust` — features: F008

A31. The `Ankountant TBS` note type validates & stores a journal-entry TBS (multi-line steps) and a numeric TBS (per-cell steps). — verify: `just test-rust`/`just test-py` — features: F009

A32. `steps_json` supports N gradable steps, each with an answer key + weight (weights default 1/N, sum 1.0). — verify: `just test-rust` — features: F009

A33. A doc_review and a research TBS can be stored without any schema change. — verify: `just test-rust` — features: F009

A34. Provenance fields (source_passage, gen_method, checker_status) exist on the TBS note type and default empty (stored, unpopulated). — verify: `just test-rust` — features: F009

A35. SubmitPerformanceAttempt on a 4-line JE with equal weights (0.25), lines 1-3 correct and line 4 amount wrong -> per_step == [ok,ok,ok,wrong] and total_credit == 0.75. — verify: `just test-rust` — features: F010

A36. A single wrong amount marks only that line wrong (partial credit), not the whole item. — verify: `just test-rust` — features: F010

A37. A numeric TBS is graded per cell with a configured tolerance. — verify: `just test-rust` — features: F010

A38. Every SubmitPerformanceAttempt call writes exactly one Attempt Log note. — verify: `just test-rust` — features: F010,F008

A39. SubmitPerformanceAttempt is callable from Python after `just check`. — verify: `just test-py` — features: F010

A40. The FAR seed loads >= 4 CONFUSABLE sets and >= 24 sealed items (so 20 sealed attempts and > 60% coverage are reachable), plus >= 3 journal-entry and 2 numeric sealed TBS. — verify: `just test-rust` or a fixture-load test asserts the counts — features: F016

A41. (desktop) The answer/back cannot be shown until a confidence is committed (reveal blocked pre-commit). — verify: Playwright spec (run via `just test-e2e`) asserts the back stays hidden until a confidence is chosen — features: F011

A42. (desktop) Committed confidence is persisted (Attempt Log for Performance modes; card.custom_data for recall) and visible to GetReadiness. — verify: Playwright spec + `just test-rust` — features: F011,F008

A43. (desktop) The three confidence levels (Guess/Unsure/Confident) render and are keyboard-selectable. — verify: Playwright spec — features: F011

A44. (desktop) The BuildConfusionQueue item DTO has no populated topic/category/deck-label field AND the gate renders no element with `data-testid="category-label"`. — verify: `just test-rust` on the DTO + Playwright spec asserting the element is absent — features: F012,F003

A45. (desktop) Selecting a treatment submits it and shows correct/incorrect scored on discrimination. — verify: Playwright spec — features: F012

A46. (desktop) The attempt appears in the Attempt Log and moves the topic's Performance/gap. — verify: Playwright spec + `just test-rust` — features: F012,F008

A47. (desktop) Entering confusion-set mode fetches and plays the interleaved queue; consecutive items are not all the same treatment. — verify: Playwright spec — features: F013

A48. (desktop) Each queue item runs the confidence capture (B1) + which-treatment gate (B2). — verify: Playwright spec — features: F013,F011,F012

A49. (desktop) Completing the queue updates the topic Performance shown on the dashboard. — verify: Playwright spec — features: F013,F015

A50. (desktop) A JE TBS renders an editable multi-row grid; a partially-correct submission shows per-line right/wrong and a partial-credit total matching the A10 value. — verify: Playwright spec reconciled with the A35 `just test-rust` value — features: F014,F010

A51. (desktop) A numeric TBS renders input cells graded per cell with tolerance. — verify: Playwright spec — features: F014

A52. (desktop) The TBS surface is NOT the flashcard reviewer and exposes NO Again/Hard/Good/Easy buttons. — verify: Playwright spec asserting those controls are absent — features: F014

A53. (desktop) Exhibits referenced by the TBS are visible alongside the task. — verify: Playwright spec — features: F014

A54. (desktop) With sufficient data the dashboard shows Memory, Performance, gap, and a Readiness band (low-high) + confidence — never a single number. — verify: Playwright spec — features: F015,F004

A55. (desktop) With thin data (A5 thresholds unmet) the dashboard shows the abstain message + reason and NO readiness number. — verify: Playwright spec — features: F015,F005

A56. (desktop) A gap >= 0.25 (e.g. memory 0.90, performance 0.65) renders the gap row with the `gap-warning` style class. — verify: Playwright spec asserting the class is present — features: F015

A57. (desktop) Readiness is labeled the exam-day projection tied to the set exam date (not "today"). — verify: Playwright spec — features: F015
