// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! F016 — the FAR demo seed. Two layers on ordinary Anki objects (FR-5):
//!
//! 1. **Content** (always): ~130 real CPA-FAR recall cards, real "which
//!    treatment?" MCQs for the four confusion sets, the anchor JE/numeric TBS
//!    the grading tests pin, plus a few extra worked TBS — all authored offline
//!    (a build-time author + independent fact-check pass; see
//!    `docs_ankountant/rag/`) and embedded from `seed_content.json`.
//! 2. **History** (opt-in, `with_history`): fake review revlog + sealed Attempt
//!    Log notes so the demo profile shows a running review loop, an honest
//!    readiness *band*, and the per-topic *give-up* rule (one set is left
//!    deliberately under-covered). Off by default so the e2e fixture and the
//!    A4/A5 threshold tests control history themselves.
//!
//! Reachable from the Rust test suite AND from the `LoadFarSeed` RPC (F016).

use anki_proto::scheduler::bury_or_suspend_cards_request::Mode as BuryOrSuspendMode;
use serde::Deserialize;
use serde_json::json;
use serde_json::Value;

use super::attempt_log::NewAttempt;
use super::attempt_log::Outcome;
use super::config;
use super::config::ConfusableMap;
use super::config::ConfusionSet;
use super::constants;
use super::logic;
use super::notetypes::tbs_fields;
use super::TAG_COG_APPLIED;
use super::TAG_COG_ROTE;
use crate::card::CardQueue;
use crate::card::CardType;
use crate::card::FsrsMemoryState;
use crate::prelude::*;
use crate::revlog::RevlogEntry;
use crate::revlog::RevlogId;
use crate::revlog::RevlogReviewKind;
use crate::timestamp::TimestampMillis;

/// The hand-authored + AI-drafted FAR content, embedded at build time. Shape is
/// asserted by `seed_content_parses` and by the F016 tests.
const SEED_CONTENT_JSON: &str = include_str!("seed_content.json");

/// Provenance stamp written to generated sealed items (never the anchor JE that
/// A34 asserts is blank).
const GEN_METHOD_SEED: &str = "far-seed-content workflow (Sonnet author + independent verify)";

/// One demo topic's tuned lived-in history. The numbers are chosen to read like
/// a real, months-deep study profile rather than a synthetic fixture: strong on
/// most of FAR (Memory & Performance both > 80) with a few genuine weak spots
/// (< 75) — deferred taxes, pensions/equity, and government/NFP, the areas real
/// FAR candidates most often struggle with.
///
/// Numbers are deliberately UN-clean: scores are spread out (not a flat 89-90
/// wall), sample sizes are lumpy (weak topics get ground harder), TBS credits are
/// real step fractions (quarters/thirds/fifths, never a tidy 0.85), and the
/// Memory↔Performance gap varies — some topics you can recite but can't apply
/// (big +gap), a couple you understand better than you've drilled lately
/// (-gap) — which is the whole point of tracking the two signals separately.
///
/// - `mem` = (correct, total) trailing-window recall reps → Memory = correct/total.
/// - `mcq` = (correct, total) sealed discrimination attempts.
/// - `tbs` = sealed partial-credit TBS attempts.
///   Performance = mean(mcq pass/fail) blended 50/50 with mean(tbs credit).
struct DemoTopic {
    set_id: &'static str,
    mem: (u32, u32),
    mcq: (u32, u32),
    tbs: &'static [f64],
}

/// The lived-in demo profile: every FAR topic has been worked (a good majority
/// of the study pile reviewed), 10 strong and 3 weak, so Home shows a believable
/// summit range with a handful of topics still below the CPA pass line.
#[rustfmt::skip]
const DEMO_TOPICS: [DemoTopic; 13] = [
    // --- Strong: Memory & Performance both > 80, with organic spread + gaps ---
    // conceptual: can recite the framework, weaker at applying it (mem>>perf).
    DemoTopic { set_id: "conceptual_framework",       mem: (27, 29), mcq: (12, 13), tbs: &[0.75, 0.667] },
    DemoTopic { set_id: "capitalize_vs_expense",      mem: (26, 29), mcq: (12, 13), tbs: &[1.0, 0.75, 0.75] },
    DemoTopic { set_id: "cash_receivables",           mem: (24, 27), mcq: (11, 12), tbs: &[1.0, 0.8] },
    DemoTopic { set_id: "revrec_step_selection",      mem: (25, 28), mcq: (11, 12), tbs: &[0.833, 0.75] },
    // leases: solid recall, application still lags (a real "recognize the gap" story).
    DemoTopic { set_id: "operating_vs_finance_lease", mem: (26, 28), mcq: (10, 12), tbs: &[0.833, 0.75] },
    DemoTopic { set_id: "debt_extinguishment",        mem: (23, 27), mcq: (9, 10),  tbs: &[0.75, 0.833] },
    // statements: drilled less lately, but genuinely gets it (perf>mem reversal).
    DemoTopic { set_id: "financial_statements",       mem: (22, 27), mcq: (11, 12), tbs: &[1.0, 0.833] },
    DemoTopic { set_id: "inventory_valuation",        mem: (23, 27), mcq: (9, 10),  tbs: &[0.75, 0.8] },
    DemoTopic { set_id: "trading_afs_htm",            mem: (21, 26), mcq: (9, 10),  tbs: &[0.833, 0.75] },
    DemoTopic { set_id: "intangibles_impairment",     mem: (22, 26), mcq: (10, 11), tbs: &[0.75, 0.833] },
    // --- Weak: Memory & Performance both < 75 (real FAR pain points) ---
    // deferred taxes: memorized the rule, TBS computations sink them (big gap),
    // and they've ground a lot of MCQs without it clicking.
    DemoTopic { set_id: "tax_timing",                 mem: (18, 25), mcq: (4, 16),  tbs: &[0.25, 0.333, 0.25] },
    DemoTopic { set_id: "pensions_equity",            mem: (16, 24), mcq: (9, 14),  tbs: &[0.667, 0.6] },
    DemoTopic { set_id: "government_nfp",             mem: (15, 24), mcq: (9, 14),  tbs: &[0.667, 0.75] },
];

/// True `correct` times out of `total`, spread as evenly as possible across the
/// sequence (so a card's history interleaves right/wrong instead of "all the
/// misses first" — a synthetic tell). Rep `i` is correct iff the running count
/// ticks up at `i`.
fn is_correct_rep(i: u32, total: u32, correct: u32) -> bool {
    if total == 0 {
        return false;
    }
    ((i + 1) * correct) / total > (i * correct) / total
}

/// Split `total` items across `n` buckets as evenly as possible: bucket `i` gets
/// the base share, plus one more for the first `total % n` buckets. Guarantees
/// `share(correct) <= share(total)` per bucket when `correct <= total`, so a
/// card is never assigned more correct reps than reps.
fn per_card_share(total: usize, n: usize, i: usize) -> u32 {
    if n == 0 {
        return 0;
    }
    (total / n + usize::from(i < total % n)) as u32
}

#[derive(Debug, Deserialize)]
struct SeedContent {
    recall: Vec<RecallCard>,
    mcqs: std::collections::BTreeMap<String, Vec<McqItem>>,
    tbs: Vec<TbsItem>,
    /// Section-agnostic, typed-and-validated TBS items (ADR 0008 / D9):
    /// research, doc_review, numeric, journal_entry across all six CPA
    /// sections.
    #[serde(default)]
    section_items: Vec<SectionItem>,
}

#[derive(Debug, Deserialize)]
struct RecallCard {
    front: String,
    back: String,
    cog: String,
    ds_tag: String,
    topic_tag: String,
    source: String,
}

#[derive(Debug, Deserialize)]
struct McqItem {
    prompt: String,
    correct_treatment: String,
    ds_tag: String,
    source: String,
}

#[derive(Debug, Deserialize)]
struct TbsItem {
    kind: String,
    prompt: String,
    set_id: String,
    #[serde(default)]
    exhibits: Vec<Exhibit>,
    steps: Vec<Value>,
    source: String,
}

#[derive(Debug, Deserialize, serde::Serialize)]
struct Exhibit {
    title: String,
    body: String,
}

// --- D9: first-class typed schemas for section-agnostic TBS items. These are
// parsed from `seed_content.json` and VALIDATED at seed time (no reliance on
// the "unknown keys ignored" trick). They are transformed into the grader's
// stored `steps_json` / `exhibits_json` shape by `section_item_steps` / serde.

/// Typed exhibit model (D9): shared by every shape. `role:"document"` marks the
/// doc-review primary document whose `body` carries `<blank
/// step="id">…</blank>` markers; `kind:"table"` carries `columns`/`rows`.
#[derive(Debug, Deserialize, serde::Serialize)]
struct SeedExhibit {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    id: Option<String>,
    title: String,
    #[serde(default = "default_exhibit_kind")]
    kind: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    role: Option<String>,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    body: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    columns: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    rows: Vec<Vec<String>>,
}

const SEED_EXHIBIT_KINDS: &[&str] = &[
    "text",
    "email",
    "invoice",
    "table",
    "statement",
    "memo",
    "document",
    "stamp",
];

fn default_exhibit_kind() -> String {
    "text".to_string()
}

/// One selectable option for a doc-review blank (label-stripped for the
/// client).
#[derive(Debug, Deserialize, serde::Serialize)]
struct SeedOption {
    id: String,
    text: String,
    /// "keep" (Retain the original text) | "delete" | "replace".
    #[serde(default = "default_option_kind")]
    kind: String,
}

const SEED_OPTION_KINDS: &[&str] = &["keep", "delete", "replace"];

fn default_option_kind() -> String {
    "replace".to_string()
}

/// Typed step, a union discriminated by `kind` (D9). The grader still reads
/// only `id`/`answer_key`/`weight`/`tolerance` from the stored JSON; this typed
/// layer validates the rest and drives the clients.
#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum SeedStep {
    /// research: one citation step; `accepted` is the multi-valued answer key.
    Citation {
        id: String,
        #[serde(default)]
        label: String,
        #[serde(default)]
        weight: Option<f64>,
        accepted: Vec<String>,
        #[serde(default)]
        corpus_refs: Vec<String>,
        #[serde(default)]
        granularity: Option<String>,
    },
    /// doc_review blank: `answer_key` is the correct OPTION id.
    Blank {
        id: String,
        #[serde(default)]
        label: String,
        #[serde(default)]
        weight: Option<f64>,
        answer_key: String,
        options: Vec<SeedOption>,
        #[serde(default)]
        confusion_set_id: String,
        #[serde(default)]
        original_text: Option<String>,
        #[serde(default)]
        exhibit_refs: Vec<String>,
    },
    /// journal-entry line.
    Je {
        id: String,
        #[serde(default)]
        weight: Option<f64>,
        account: String,
        side: String,
        amount: f64,
    },
    /// numeric cell (signed values allowed).
    Numeric {
        id: String,
        #[serde(default)]
        label: String,
        #[serde(default)]
        weight: Option<f64>,
        answer_key: f64,
        #[serde(default)]
        tolerance: Option<f64>,
    },
}

/// A section-agnostic TBS item (ADR 0008). `section` + `tbs_type` together
/// discriminate the union note type; `set_id` places it in the sealed bank and
/// resolves its confusion set.
#[derive(Debug, Deserialize)]
struct SectionItem {
    section: String,
    tbs_type: String,
    set_id: String,
    #[serde(default)]
    schema_version: Option<u32>,
    prompt: String,
    #[serde(default)]
    exhibits: Vec<SeedExhibit>,
    steps: Vec<SeedStep>,
    source: String,
}

fn seed_content() -> SeedContent {
    serde_json::from_str(SEED_CONTENT_JSON).expect("embedded seed_content.json must parse")
}

/// Summary of what the seed produced, for assertions.
#[derive(Debug, Clone, Default)]
pub(crate) struct SeedSummary {
    pub(crate) confusion_sets: usize,
    pub(crate) sealed_items: usize,
    pub(crate) sealed_je_tbs: usize,
    pub(crate) sealed_numeric_tbs: usize,
    pub(crate) study_recall_cards: usize,
    pub(crate) rote_cards: usize,
    /// Note ids of the playable sealed TBS notes (JE + numeric anchors, extra
    /// content TBS, then the section-agnostic research/doc_review/numeric
    /// items). Anchors are pushed first, so the e2e fixture can rely on
    /// index 0 being the 4-line anchor JE.
    pub(crate) sealed_tbs_note_ids: Vec<NoteId>,
    /// Section-agnostic TBS items seeded (ADR 0008), by shape.
    pub(crate) sealed_research_tbs: usize,
    pub(crate) sealed_doc_review_tbs: usize,
    /// Sections that received at least one sealed section-item (for coverage
    /// assertions across AUD/FAR/REG/BAR/ISC/TCP).
    pub(crate) sections_seeded: std::collections::BTreeSet<String>,
}

/// One confusion set's authoring spec.
struct SetSpec {
    set_id: &'static str,
    tags: [&'static str; 2],
    treatments: [&'static str; 2],
}

// The full FAR blueprint: one confusion set per Home topo topic (see
// `ts/.../far-topics.ts`). The first four are the "anchor" sets the grading +
// e2e tests pin by index (`SETS[1]` = lease JE, `SETS[2]` = revrec numeric), so
// their order must not change; the rest complete the 13-topic map so a lived-in
// demo profile can show a per-topic Memory/Performance score for every summit.
const SETS: [SetSpec; 13] = [
    SetSpec {
        set_id: "capitalize_vs_expense",
        tags: ["ds::cost::capitalize", "ds::cost::expense"],
        treatments: ["Capitalize", "Expense"],
    },
    SetSpec {
        set_id: "operating_vs_finance_lease",
        tags: ["ds::lease::operating", "ds::lease::finance"],
        treatments: ["Operating lease", "Finance lease"],
    },
    SetSpec {
        set_id: "revrec_step_selection",
        tags: ["ds::revrec::step4", "ds::revrec::step5"],
        treatments: ["Allocate price (Step 4)", "Recognize revenue (Step 5)"],
    },
    SetSpec {
        set_id: "trading_afs_htm",
        tags: ["ds::securities::trading", "ds::securities::htm"],
        treatments: [
            "Trading (FV through NI)",
            "Held-to-maturity (amortized cost)",
        ],
    },
    SetSpec {
        set_id: "inventory_valuation",
        tags: ["ds::inventory::lcm", "ds::inventory::lcnrv"],
        treatments: ["Lower of cost or market", "Lower of cost and NRV"],
    },
    SetSpec {
        set_id: "debt_extinguishment",
        tags: ["ds::debt::extinguish", "ds::debt::modify"],
        treatments: ["Extinguishment (derecognize)", "Modification (retain)"],
    },
    SetSpec {
        set_id: "intangibles_impairment",
        tags: ["ds::intangible::finite", "ds::intangible::indefinite"],
        treatments: ["Finite-life (amortize)", "Indefinite-life (test only)"],
    },
    SetSpec {
        set_id: "cash_receivables",
        tags: ["ds::ar::allowance", "ds::ar::writeoff"],
        treatments: ["Allowance method", "Direct write-off"],
    },
    SetSpec {
        set_id: "financial_statements",
        tags: ["ds::stmt::operating", "ds::stmt::financing"],
        treatments: ["Operating activity", "Financing activity"],
    },
    SetSpec {
        set_id: "conceptual_framework",
        tags: ["ds::concept::relevance", "ds::concept::faithful"],
        treatments: ["Relevance", "Faithful representation"],
    },
    SetSpec {
        set_id: "tax_timing",
        tags: ["ds::tax::temporary", "ds::tax::permanent"],
        treatments: ["Temporary difference", "Permanent difference"],
    },
    SetSpec {
        set_id: "pensions_equity",
        tags: ["ds::pension::service", "ds::pension::interest"],
        treatments: ["Service cost", "Interest cost"],
    },
    SetSpec {
        set_id: "government_nfp",
        tags: ["ds::govnfp::govtwide", "ds::govnfp::fund"],
        treatments: ["Government-wide (accrual)", "Fund (modified accrual)"],
    },
];

/// FAR study `topic_tag` → confusion `set_id`, mirroring the Home topo map. Used
/// to (1) tag recall cards authored without a `ds::` tag with their topic's set
/// so Memory becomes measurable per topic, and (2) let the lived-in history
/// seeder find the study cards backing each set.
const FAR_TOPIC_SETS: [(&str, &str); 13] = [
    ("far::ppe", "capitalize_vs_expense"),
    ("far::leases", "operating_vs_finance_lease"),
    ("far::revenue", "revrec_step_selection"),
    ("far::investments", "trading_afs_htm"),
    ("far::inventory", "inventory_valuation"),
    ("far::debt", "debt_extinguishment"),
    ("far::intangibles", "intangibles_impairment"),
    ("far::cash_ar", "cash_receivables"),
    ("far::statements", "financial_statements"),
    ("far::conceptual", "conceptual_framework"),
    ("far::taxes", "tax_timing"),
    ("far::pensions_equity", "pensions_equity"),
    ("far::gov_nfp", "government_nfp"),
];

/// The `SetSpec` a FAR recall `topic_tag` belongs to, if any.
fn far_set_for_topic(topic_tag: &str) -> Option<&'static SetSpec> {
    let set_id = FAR_TOPIC_SETS
        .iter()
        .find(|(t, _)| *t == topic_tag)
        .map(|(_, s)| *s)?;
    SETS.iter().find(|s| s.set_id == set_id)
}

// Multi-section confusion sets (ADR 0008 / D8). FAR keeps `SETS`; each other
// section that carries seeded TBS gets ≥1 set so doc-review blanks can reuse it
// and Performance attributes correctly. Config keys are
// `ankountant.confusable.<section>`.
const AUD_SETS: [SetSpec; 2] = [
    SetSpec {
        set_id: "aud_evidence_sufficiency",
        tags: ["ds::aud::sufficient", "ds::aud::insufficient"],
        treatments: ["Sufficient appropriate evidence", "Insufficient evidence"],
    },
    SetSpec {
        set_id: "aud_request_relevance",
        tags: ["ds::aud::retain", "ds::aud::revise"],
        treatments: ["Retain as drafted", "Revise the request"],
    },
];

const REG_SETS: [SetSpec; 1] = [SetSpec {
    set_id: "reg_capitalize_vs_deduct",
    tags: ["ds::reg::deduct", "ds::reg::capitalize"],
    treatments: ["Currently deductible", "Capitalize and recover over time"],
}];

const BAR_SETS: [SetSpec; 1] = [SetSpec {
    set_id: "bar_segment_reporting",
    tags: ["ds::bar::reportable", "ds::bar::not_reportable"],
    treatments: ["Reportable segment", "Not separately reportable"],
}];

const ISC_SETS: [SetSpec; 1] = [SetSpec {
    set_id: "isc_control_type",
    tags: ["ds::isc::preventive", "ds::isc::detective"],
    treatments: ["Preventive control", "Detective control"],
}];

const TCP_SETS: [SetSpec; 1] = [SetSpec {
    set_id: "tcp_cost_recovery",
    tags: ["ds::tcp::expense", "ds::tcp::capitalize"],
    treatments: ["Expense currently", "Capitalize and recover"],
}];

/// The confusion sets defined for a section (empty for an unseeded section).
fn section_sets(section: &str) -> &'static [SetSpec] {
    match section {
        "FAR" => &SETS,
        "AUD" => &AUD_SETS,
        "REG" => &REG_SETS,
        "BAR" => &BAR_SETS,
        "ISC" => &ISC_SETS,
        "TCP" => &TCP_SETS,
        _ => &[],
    }
}

/// Resolve a `(section, set_id)` to its `SetSpec`, if defined.
fn find_set(section: &str, set_id: &str) -> Option<&'static SetSpec> {
    section_sets(section).iter().find(|s| s.set_id == set_id)
}

/// Deterministic [0,1) PRNG (a splitmix64 finalizer) keyed by an integer. Lets
/// the demo history carry organic-looking jitter (varied volume, latencies,
/// button mix, review times) that is nonetheless byte-identical on every seed —
/// the determinism tests re-seed two collections and compare their scores.
fn rng01(seed: u64) -> f64 {
    let mut z = seed.wrapping_add(0x9E37_79B9_7F4A_7C15);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^= z >> 31;
    (z >> 11) as f64 / ((1u64 << 53) as f64)
}

/// Mix a few small stable indices (topic / card / rep) into a PRNG seed. Uses
/// stable INDICES, never card ids (which differ per seed), so it stays
/// deterministic across independently seeded collections.
fn mix(a: u64, b: u64, c: u64) -> u64 {
    a.wrapping_mul(0x0100_0000_01b3)
        ^ (b.wrapping_add(1)).wrapping_mul(0x9E37_79B9_7F4A_7C15)
        ^ (c.wrapping_add(1)).wrapping_mul(0x85EB_CA6B_02F5_1E1F)
}

/// A plausible whole-second time-of-day for a study rep, drawn from a few real
/// study windows (early morning, lunch, evening) so the Stats "Hourly Breakdown"
/// spreads across the day instead of a single synthetic bar.
fn session_tod_secs(seed: u64) -> i64 {
    // Evening-weighted study windows (repeats bias the draw), spread morning →
    // late evening so the Hourly Breakdown is a believable multi-hour shape.
    const HOURS: [i64; 12] = [7, 8, 8, 9, 12, 13, 13, 19, 20, 21, 21, 22];
    let hour = HOURS[(rng01(mix(seed, 101, 0)) * HOURS.len() as f64) as usize % HOURS.len()];
    let minute = (rng01(mix(seed, 102, 0)) * 60.0) as i64;
    let second = (rng01(mix(seed, 103, 0)) * 60.0) as i64;
    (hour * 60 + minute) * 60 + second
}

/// Places seeded revlog rows on specific past days at realistic times of day,
/// keeping every id unique. Ids are `midnight(days_ago) + time_of_day` with a
/// per-day tie-breaker in the low milliseconds (whole-second base + a <1000 tie
/// can never collide within a day, and distinct days never share a midnight).
struct RevlogClock {
    today_midnight_ms: i64,
    day_counts: std::collections::HashMap<i64, i64>,
    /// Global cursor for back-dated card-creation ids (see `card_id`).
    card_seq: i64,
}

impl RevlogClock {
    fn new() -> Self {
        let now = TimestampMillis::now().0;
        RevlogClock {
            today_midnight_ms: now - now.rem_euclid(86_400_000),
            day_counts: std::collections::HashMap::new(),
            card_seq: 0,
        }
    }

    /// A unique revlog id `days_ago` days back at `tod_secs` time of day.
    fn id(&mut self, days_ago: i64, tod_secs: i64) -> i64 {
        let tie = self.day_counts.entry(days_ago).or_insert(0);
        let this = *tie;
        *tie += 1;
        self.today_midnight_ms - days_ago * 86_400_000 + tod_secs.clamp(0, 86_399) * 1_000 + this
    }

    /// A unique, back-dated card-creation id: 06:00 on the card's first-study day
    /// plus a global sequence offset (< the 07:00 earliest review, so creation
    /// always precedes the card's history). Distinct days differ by their
    /// midnight; same-day cards differ by the sequence — never a collision. This
    /// spreads Anki's "Added" stats graph across the real study window instead of
    /// piling every card onto today.
    fn card_id(&mut self, creation_day: i64) -> i64 {
        let s = self.card_seq;
        self.card_seq += 1;
        self.today_midnight_ms - creation_day * 86_400_000 + 6 * 3_600_000 + s
    }
}

impl Collection {
    /// Load the FAR seed. `with_history` also injects the demo review/attempt
    /// history (see module docs). Idempotent per collection is NOT guaranteed —
    /// intended for fresh collections / test fixtures.
    pub(crate) fn ankountant_load_far_seed(&mut self, with_history: bool) -> Result<SeedSummary> {
        // Note types must exist before the write transaction (creating them is
        // itself transactional).
        self.ankountant_tbs_notetype()?;
        self.ankountant_attempt_log_notetype()?;
        self.ankountant_study_notetype()?;
        let out = self.transact(crate::ops::Op::AddNote, |col| {
            col.load_far_seed_inner(with_history)
        })?;
        if with_history {
            let exam_iso = (chrono::Local::now().date_naive()
                + chrono::Duration::days(constants::SEED_EXAM_OFFSET_DAYS))
            .format("%Y-%m-%d")
            .to_string();
            self.ankountant_set_exam_date(super::DEFAULT_SECTION, &exam_iso)?;
        } else if self.ankountant_exam_date(super::DEFAULT_SECTION)?.is_some() {
            self.ankountant_set_exam_date(super::DEFAULT_SECTION, "")?;
        }
        Ok(out.output)
    }

    /// RPC entry point (F016): load the FAR seed and return the counts as the
    /// proto response the e2e fixture consumes.
    pub(crate) fn ankountant_load_far_seed_response(
        &mut self,
        with_history: bool,
    ) -> Result<anki_proto::scheduler::LoadFarSeedResponse> {
        let summary = self.ankountant_load_far_seed(with_history)?;
        Ok(anki_proto::scheduler::LoadFarSeedResponse {
            confusion_sets: summary.confusion_sets as u32,
            sealed_items: summary.sealed_items as u32,
            sealed_je_tbs: summary.sealed_je_tbs as u32,
            sealed_numeric_tbs: summary.sealed_numeric_tbs as u32,
            study_recall_cards: summary.study_recall_cards as u32,
            rote_cards: summary.rote_cards as u32,
            sealed_tbs_note_ids: summary.sealed_tbs_note_ids.iter().map(|n| n.0).collect(),
        })
    }

    fn load_far_seed_inner(&mut self, with_history: bool) -> Result<SeedSummary> {
        let section = super::DEFAULT_SECTION;
        // Idempotency: wipe any prior FAR seed first, so re-running "Load FAR
        // demo content" REPLACES the demo profile instead of stacking a second
        // copy of every deck/card on top of the old one.
        self.wipe_prior_far_seed()?;
        let mut summary = SeedSummary::default();
        let content = seed_content();

        // --- CONFUSABLE map in col config, PER SECTION (A3/A6; ADR 0008). ---
        // FAR keeps its four sets; AUD/REG/BAR/ISC/TCP get their own so
        // doc-review blanks reuse them and Performance attributes per section.
        let mut total_sets = 0usize;
        for sec in super::SECTIONS {
            let specs = section_sets(sec);
            if specs.is_empty() {
                continue;
            }
            let mut map: ConfusableMap = ConfusableMap::new();
            for spec in specs {
                map.insert(
                    spec.set_id.to_string(),
                    ConfusionSet {
                        tags: spec.tags.iter().map(|s| s.to_string()).collect(),
                        treatments: spec.treatments.iter().map(|s| s.to_string()).collect(),
                    },
                );
            }
            total_sets += map.len();
            self.set_config(config::confusable_key(sec).as_str(), &map)?;
        }
        summary.confusion_sets = total_sets;

        let sealed_deck_base = format!("Ankountant::Sealed::{section}");
        let study_nt = self.ankountant_study_notetype()?;
        let tbs_nt = self.ankountant_tbs_notetype()?;

        // --- 1) Real recall cards -> study pile (per blueprint topic deck). ---
        // Track card ids per ds:: tag so the memory history can target them.
        let mut ds_cards: std::collections::HashMap<String, Vec<CardId>> =
            std::collections::HashMap::new();
        // Per-topic cursor so recall cards without an authored ds:: tag get
        // alternated across their set's two sides (an even split).
        let mut topic_ds_counter: std::collections::HashMap<String, usize> =
            std::collections::HashMap::new();
        let mut study_decks: std::collections::HashMap<String, DeckId> =
            std::collections::HashMap::new();
        for card in &content.recall {
            let suffix = card.topic_tag.strip_prefix("far::").unwrap_or("core");
            let deck_name = format!("Ankountant::Study::{section}::{suffix}");
            let deck = match study_decks.get(&deck_name) {
                Some(d) => *d,
                None => {
                    let d = self.ankountant_get_or_create_deck_inner(&deck_name)?;
                    study_decks.insert(deck_name, d);
                    d
                }
            };
            let cog = if card.cog == "applied" {
                TAG_COG_APPLIED
            } else {
                TAG_COG_ROTE
            };
            let mut note = study_nt.new_note();
            note.set_field(0, &card.front)?;
            // Hand-authored recall keeps the human-readable Source in the
            // answer and leaves the dedicated provenance fields
            // (study_fields::SOURCE_PASSAGE / GEN_METHOD / CHECKER_STATUS)
            // blank — those are reserved for Phase-2a RAG-generated recall
            // cards (doc 6). new_note() zero-fills them, so setting only
            // Front/Back here is enough.
            note.set_field(1, format!("{}\n\nSource: {}", card.back, card.source))?;
            // Effective discrimination tag: honour an authored ds:: tag, else
            // place the card in its topic's confusion set (alternating the two
            // sides) so Memory can be measured for every topic — not just the
            // four originally authored as discrimination pairs.
            let ds_tag = if !card.ds_tag.is_empty() {
                card.ds_tag.clone()
            } else if let Some(spec) = far_set_for_topic(&card.topic_tag) {
                let n = topic_ds_counter.entry(card.topic_tag.clone()).or_default();
                let tag = spec.tags[*n % 2].to_string();
                *n += 1;
                tag
            } else {
                String::new()
            };
            let mut tags = vec![cog.to_string(), card.topic_tag.clone()];
            if !ds_tag.is_empty() {
                tags.push(ds_tag.clone());
            }
            note.tags = tags;
            self.add_note_inner(&mut note, deck)?;
            summary.study_recall_cards += 1;
            if cog == TAG_COG_ROTE {
                summary.rote_cards += 1;
            }
            if !ds_tag.is_empty() {
                let cids = self.storage.card_ids_of_notes(&[note.id])?;
                ds_cards.entry(ds_tag).or_default().extend(cids);
            }
        }

        // --- 2) Sealed bank per set: real, varied single-choice MCQs. ---
        let mut set_mcq_ids: std::collections::HashMap<String, Vec<NoteId>> =
            std::collections::HashMap::new();
        for spec in SETS.iter() {
            let sealed_deck = self.ankountant_get_or_create_deck_inner(&format!(
                "{sealed_deck_base}::{}",
                spec.set_id
            ))?;
            let items = content
                .mcqs
                .get(spec.set_id)
                .or_invalid(format!("missing authored MCQs for {}", spec.set_id))?;
            require!(
                items.len() >= 6,
                "expected at least 6 authored MCQs for {}, got {}",
                spec.set_id,
                items.len()
            );
            for it in items {
                require!(
                    spec.treatments.contains(&it.correct_treatment.as_str()),
                    "unknown treatment {:?} for {}",
                    it.correct_treatment,
                    spec.set_id
                );
                require!(
                    spec.tags.contains(&it.ds_tag.as_str()),
                    "unknown ds_tag {:?} for {}",
                    it.ds_tag,
                    spec.set_id
                );
                let steps = json!([
                    {"id": "choice", "answer_key": it.correct_treatment.clone(), "weight": 1.0}
                ]);
                let mut note = tbs_nt.new_note();
                note.set_field(tbs_fields::TBS_TYPE, "mcq")?;
                note.set_field(tbs_fields::PROMPT, &it.prompt)?;
                note.set_field(tbs_fields::EXHIBITS_JSON, "[]")?;
                note.set_field(tbs_fields::STEPS_JSON, steps.to_string())?;
                note.set_field(tbs_fields::SCHEMA_TAG, &it.ds_tag)?;
                if !it.source.is_empty() {
                    note.set_field(tbs_fields::SOURCE_PASSAGE, &it.source)?;
                    note.set_field(tbs_fields::GEN_METHOD, GEN_METHOD_SEED)?;
                    note.set_field(tbs_fields::CHECKER_STATUS, "pass")?;
                }
                note.tags = vec![it.ds_tag.clone()];
                self.add_note_inner(&mut note, sealed_deck)?;
                self.suspend_note_cards(note.id)?;
                summary.sealed_items += 1;
                set_mcq_ids
                    .entry(spec.set_id.to_string())
                    .or_default()
                    .push(note.id);
            }
        }

        // --- 2b) The two PINNED anchor TBS: exactly ONE journal-entry and ONE
        // numeric. The grading tests locate them by prompt ("Record the entry*"
        // / "Compute the amounts*") and pin their steps, and the e2e fixture
        // needs sealedTbsNoteIds[0] to be the journal entry — so the JE is
        // created first. Every OTHER TBS is a real, varied worked example from
        // seed_content.json (section 3), so the sealed bank is no longer a stack
        // of copy-paste anchors. The JE lives in the lease set (a lease entry
        // fits there); the numeric in the revenue-recognition set.
        let je_spec = &SETS[1]; // operating_vs_finance_lease
        let je_deck = self.ankountant_get_or_create_deck_inner(&format!(
            "{sealed_deck_base}::{}",
            je_spec.set_id
        ))?;
        let je_id = self.add_sealed_je_tbs(je_deck, je_spec)?;
        self.suspend_note_cards(je_id)?;
        summary.sealed_je_tbs += 1;
        summary.sealed_items += 1;
        summary.sealed_tbs_note_ids.push(je_id);

        let num_spec = &SETS[2]; // revrec_step_selection
        let num_deck = self.ankountant_get_or_create_deck_inner(&format!(
            "{sealed_deck_base}::{}",
            num_spec.set_id
        ))?;
        let num_id = self.add_sealed_numeric_tbs(num_deck, num_spec)?;
        self.suspend_note_cards(num_id)?;
        summary.sealed_numeric_tbs += 1;
        summary.sealed_items += 1;
        summary.sealed_tbs_note_ids.push(num_id);

        // --- 3) Extra worked TBS from content (real numbers + provenance). ---
        for t in &content.tbs {
            let spec = SETS.iter().find(|s| s.set_id == t.set_id);
            let (deck, tag) = match spec {
                Some(sp) => (
                    self.ankountant_get_or_create_deck_inner(&format!(
                        "{sealed_deck_base}::{}",
                        sp.set_id
                    ))?,
                    sp.tags[0].to_string(),
                ),
                None => (
                    self.ankountant_get_or_create_deck_inner(&format!("{sealed_deck_base}::misc"))?,
                    String::new(),
                ),
            };
            let steps = content_tbs_steps(t);
            let mut note = tbs_nt.new_note();
            note.set_field(tbs_fields::TBS_TYPE, &t.kind)?;
            note.set_field(tbs_fields::PROMPT, &t.prompt)?;
            note.set_field(
                tbs_fields::EXHIBITS_JSON,
                serde_json::to_string(&t.exhibits)?,
            )?;
            note.set_field(tbs_fields::STEPS_JSON, steps.to_string())?;
            note.set_field(tbs_fields::SCHEMA_TAG, &tag)?;
            note.set_field(tbs_fields::SOURCE_PASSAGE, &t.source)?;
            note.set_field(tbs_fields::GEN_METHOD, GEN_METHOD_SEED)?;
            note.set_field(tbs_fields::CHECKER_STATUS, "pass")?;
            if !tag.is_empty() {
                note.tags = vec![tag];
            }
            self.add_note_inner(&mut note, deck)?;
            self.suspend_note_cards(note.id)?;
            if t.kind == "journal_entry" {
                summary.sealed_je_tbs += 1;
            } else {
                summary.sealed_numeric_tbs += 1;
            }
            summary.sealed_items += 1;
            summary.sealed_tbs_note_ids.push(note.id);
        }

        // --- 4) Section-agnostic TBS items (ADR 0008 / D9): real research,
        //         doc_review, and numeric items across AUD/FAR/REG/BAR/ISC/TCP,
        //         parsed from typed schemas and VALIDATED before seeding. Each is
        //         sealed (suspended, in `Ankountant::Sealed::<section>::<set_id>`)
        //         and carries a `sec::<section>` tag so submit resolves its
        //         section. Replaces the old stored-only stubs. ---
        for item in &content.section_items {
            validate_section_item(item)?;
            let (deck, schema_tag) = match find_set(&item.section, &item.set_id) {
                Some(spec) => (
                    self.ankountant_get_or_create_deck_inner(&format!(
                        "Ankountant::Sealed::{}::{}",
                        item.section, spec.set_id
                    ))?,
                    spec.tags[0].to_string(),
                ),
                None => (
                    self.ankountant_get_or_create_deck_inner(&format!(
                        "Ankountant::Sealed::{}::misc",
                        item.section
                    ))?,
                    String::new(),
                ),
            };
            let steps = section_item_steps(item);
            let mut note = tbs_nt.new_note();
            note.set_field(tbs_fields::TBS_TYPE, &item.tbs_type)?;
            note.set_field(tbs_fields::PROMPT, &item.prompt)?;
            note.set_field(
                tbs_fields::EXHIBITS_JSON,
                serde_json::to_string(&item.exhibits)?,
            )?;
            note.set_field(tbs_fields::STEPS_JSON, steps.to_string())?;
            note.set_field(tbs_fields::SCHEMA_TAG, &schema_tag)?;
            note.set_field(tbs_fields::SOURCE_PASSAGE, &item.source)?;
            note.set_field(tbs_fields::GEN_METHOD, GEN_METHOD_SEED)?;
            note.set_field(tbs_fields::CHECKER_STATUS, "pass")?;
            let mut tags = vec![format!("{}{}", super::SEC_TAG_PREFIX, item.section)];
            if !schema_tag.is_empty() {
                tags.push(schema_tag.clone());
            }
            note.tags = tags;
            self.add_note_inner(&mut note, deck)?;
            self.suspend_note_cards(note.id)?;
            match item.tbs_type.as_str() {
                "research" => summary.sealed_research_tbs += 1,
                "doc_review" => summary.sealed_doc_review_tbs += 1,
                "numeric" => summary.sealed_numeric_tbs += 1,
                "journal_entry" => summary.sealed_je_tbs += 1,
                _ => {}
            }
            summary.sealed_items += 1;
            summary.sealed_tbs_note_ids.push(note.id);
            summary.sections_seeded.insert(item.section.clone());
        }

        // --- 5) Demo history (opt-in): a lived-in profile, not a clean slate. ---
        if with_history {
            // FSRS on so the seeded memory states + retrievability are live.
            self.set_config(BoolKey::Fsrs, &true)?;

            // A shared clock places every seeded revlog row on a real past
            // day-and-time while keeping ids unique.
            let mut clock = RevlogClock::new();
            let today = self.timing_today()?.days_elapsed as i32;
            let decay = crate::scheduler::fsrs::memory_state::get_decay_from_params(&[]);

            // Every FAR topic gets a per-topic Memory + Performance history tuned
            // by DEMO_TOPICS (10 strong, 3 weak). A couple of cards per topic are
            // left untouched (New) so there is still a fresh pile to work through;
            // each studied card gets its own months-long expanding-interval walk.
            for (ti, topic) in DEMO_TOPICS.iter().enumerate() {
                let spec = SETS.iter().find(|s| s.set_id == topic.set_id).unwrap();
                let mut cids: Vec<CardId> = Vec::new();
                for tag in spec.tags {
                    if let Some(v) = ds_cards.get(tag) {
                        cids.extend(v.iter().copied());
                    }
                }
                // Leave a few cards New; study the rest.
                let leave_new = constants::SEED_NEW_PER_TOPIC.min(cids.len().saturating_sub(1));
                let split = cids.len().saturating_sub(leave_new);
                let studied = &cids[..split];
                let n = studied.len().max(1);

                // Distribute this topic's trailing-window recall reps across its
                // studied cards, hitting (mem.0 correct / mem.1 total) EXACTLY so
                // Memory is controlled while each card's own history stays organic.
                let (mem_correct, mem_total) = (topic.mem.0 as usize, topic.mem.1 as usize);
                for (ci, &cid) in studied.iter().enumerate() {
                    let win_reps = per_card_share(mem_total, n, ci);
                    let win_correct = per_card_share(mem_correct, n, ci);
                    let older = 2 + (rng01(mix(ti as u64, ci as u64, 7)) * 4.0) as u32; // 2..5
                    self.simulate_card_history(
                        cid,
                        mix(ti as u64, ci as u64, 0),
                        win_reps,
                        win_correct,
                        older,
                        today,
                        decay,
                        &mut clock,
                    )?;
                }

                // Sealed attempts define this topic's Performance.
                let items = set_mcq_ids.get(topic.set_id).cloned().unwrap_or_default();
                self.seed_performance_history(
                    section,
                    topic.set_id,
                    ti as u64,
                    topic.mcq.0,
                    topic.mcq.1,
                    topic.tbs,
                    &items,
                )?;
            }
        }

        Ok(summary)
    }

    /// Idempotency helper: remove everything a previous FAR seed created so a
    /// re-seed is a clean REPLACE, not an append. Two passes, both inside the
    /// seed transaction:
    ///
    /// 1. All notes of the seed's hidden notetypes (Study / TBS / Attempt Log),
    ///    which also drops their cards + revlog — clearing the study pile, the
    ///    sealed MCQ/TBS bank, and the attempt history wherever they live.
    /// 2. The now-empty `Ankountant::` deck tree (parent + all descendants), so
    ///    a stale/renamed topic subdeck from an earlier seed cannot linger.
    ///
    /// User-authored decks and notes of other notetypes are untouched; the
    /// CONFUSABLE map, exam date, and FSRS flag are overwritten by the seed
    /// itself, so they need no explicit reset here.
    fn wipe_prior_far_seed(&mut self) -> Result<()> {
        let usn = self.usn()?;
        for nt_name in [
            super::notetypes::STUDY_NOTETYPE,
            super::notetypes::TBS_NOTETYPE,
            super::notetypes::ATTEMPT_LOG_NOTETYPE,
        ] {
            if let Some(nt) = self.get_notetype_by_name(nt_name)? {
                let nids = self.search_notes_unordered(nt.id)?;
                if !nids.is_empty() {
                    self.remove_notes_inner(&nids, usn)?;
                }
            }
        }
        if let Some(did) = self.get_deck_id("Ankountant")? {
            if let Some(deck) = self.storage.get_deck(did)? {
                let children = self.storage.child_decks(&deck)?;
                self.remove_single_deck(&deck, usn)?;
                for child in children {
                    self.remove_single_deck(&child, usn)?;
                }
            }
        }
        Ok(())
    }

    /// Write one seeded revlog row with an explicit id / kind / intervals.
    #[allow(clippy::too_many_arguments)]
    fn add_seed_revlog(
        &mut self,
        cid: CardId,
        id: i64,
        last_interval: i32,
        interval: i32,
        button: u8,
        kind: RevlogReviewKind,
        taken_millis: u32,
    ) -> Result<()> {
        self.storage.add_revlog_entry(
            &RevlogEntry {
                id: RevlogId(id),
                cid,
                usn: Usn(-1),
                button_chosen: button,
                review_kind: kind,
                interval,
                last_interval,
                ease_factor: 2_500,
                taken_millis,
            },
            false,
        )?;
        Ok(())
    }

    /// Simulate one studied card's full review history — an expanding-interval
    /// walk from a back-dated first study up to today — then set the card's live
    /// state from what actually happened. Writes realistic revlog rows:
    /// Learning → Review, Relearning after a lapse; per-row `last_ivl → ivl`
    /// growth; spread across real times of day with log-normal latencies.
    ///
    /// The trailing-window reps (`win_reps`, `win_correct` of them a pass) DEFINE
    /// this card's contribution to its topic's Memory and are kept EXACT; the
    /// `older` reps are extra out-of-window history purely for a lived-in heatmap
    /// / retention chart and never touch the 30-day Memory window. Jitter is
    /// drawn from `seed` (a stable topic/card index), so it is organic-looking
    /// yet identical on every re-seed.
    #[allow(clippy::too_many_arguments)]
    fn simulate_card_history(
        &mut self,
        cid: CardId,
        seed: u64,
        win_reps: u32,
        win_correct: u32,
        older: u32,
        today: i32,
        decay: f32,
        clock: &mut RevlogClock,
    ) -> Result<()> {
        // --- Build the review schedule as (days_ago, correct), oldest first. ---
        let mut reps: Vec<(i64, bool)> = Vec::new();
        // Older, out-of-window reps: a first study up to ~4 months ago, then a
        // few early reviews down toward (but never inside) the 30-day window.
        // Mostly correct — these are cards the user has already learned.
        let first_day = constants::SEED_BACKFILL_START_DAY
            + 9
            + (rng01(mix(seed, 20, 0)) * (constants::SEED_BACKFILL_SPREAD_DAYS - 10) as f64) as i64;
        for r in 0..older {
            let t = if older <= 1 {
                0.0
            } else {
                r as f64 / (older - 1) as f64
            };
            let base =
                first_day - (t * (first_day - constants::SEED_BACKFILL_START_DAY) as f64) as i64;
            let jit = ((rng01(mix(seed, 21, r as u64)) - 0.5) * 6.0) as i64;
            let day = (base + jit).clamp(constants::SEED_BACKFILL_START_DAY, first_day + 3);
            // Cards being reviewed months ago are mostly remembered (~88%).
            let correct = rng01(mix(seed, 22, r as u64)) > 0.12;
            reps.push((day, correct));
        }
        // In-window reps: days 1..=SEED_MEMORY_SPREAD_DAYS, weighted toward
        // recent (u² bias), with the EXACT correct/total split for Memory.
        for r in 0..win_reps {
            let u = rng01(mix(seed, 23, r as u64));
            let day = 1 + (u * u * (constants::SEED_MEMORY_SPREAD_DAYS - 1) as f64) as i64;
            let correct = is_correct_rep(r, win_reps, win_correct);
            reps.push((day.clamp(1, constants::SEED_MEMORY_SPREAD_DAYS), correct));
        }
        reps.sort_by_key(|r| std::cmp::Reverse(r.0));

        // --- Walk the schedule, writing rows + evolving the interval. ---
        let mut ivl: i32 = 0;
        let mut n_reps: u32 = 0;
        let mut lapses: u32 = 0;
        let mut prev_again = false;
        for (idx, &(days_ago, correct)) in reps.iter().enumerate() {
            let last_ivl = ivl;
            let rs = mix(seed, 30, idx as u64);
            let button: u8 = if correct {
                let u = rng01(rs);
                if u < 0.16 {
                    2 // Hard (still a pass)
                } else if u > 0.86 {
                    4 // Easy
                } else {
                    3 // Good
                }
            } else {
                1 // Again
            };
            let kind = if n_reps == 0 {
                RevlogReviewKind::Learning
            } else if prev_again {
                RevlogReviewKind::Relearning
            } else {
                RevlogReviewKind::Review
            };
            // Evolve the interval the way a scheduler would, so `last_ivl != ivl`
            // and the True-Retention young/mature split is real.
            ivl = match button {
                1 => 0,
                2 => ((last_ivl as f64) * 1.2).max(1.0) as i32,
                4 => {
                    if last_ivl == 0 {
                        4
                    } else {
                        ((last_ivl as f64) * 3.3) as i32
                    }
                }
                _ => {
                    if last_ivl == 0 {
                        1 + (rng01(mix(rs, 5, 0)) * 2.0) as i32
                    } else {
                        ((last_ivl as f64) * 2.4) as i32
                    }
                }
            }
            .min(365);
            let recorded_ivl = if button == 1 { 0 } else { ivl.max(1) };
            // Log-normal-ish latency with a fat tail; slower on Again/Hard.
            let u = rng01(mix(rs, 6, 0));
            let mut latency = 900.0 + u * u * u * 38_000.0;
            if button <= 2 {
                latency *= 1.4;
            }
            let taken = latency.min(60_000.0) as u32;
            let tod = session_tod_secs(mix(seed, 40, idx as u64));
            let id = clock.id(days_ago, tod);
            self.add_seed_revlog(cid, id, last_ivl, recorded_ivl, button, kind, taken)?;
            prev_again = button == 1;
            if button == 1 {
                lapses += 1;
            }
            n_reps += 1;
        }

        // --- Set the card's live state from what actually happened. ---
        let Some(original) = self.storage.get_card(cid)? else {
            return Ok(());
        };
        let usn = self.usn()?;
        let mut card = original.clone();
        card.ease_factor = 2_100 + (rng01(mix(seed, 50, 0)) * 700.0) as u16; // ~2100..2800
        card.desired_retention = Some(0.88 + rng01(mix(seed, 51, 0)) as f32 * 0.06);
        card.decay = Some(decay);
        card.reps = n_reps;
        card.lapses = lapses;
        card.remaining_steps = 0;
        let last_days_ago = reps.last().map(|r| r.0).unwrap_or(1);
        if prev_again || ivl == 0 {
            // Ended on a lapse -> relearning, due today.
            card.ctype = CardType::Relearn;
            card.queue = CardQueue::Learn;
            card.interval = 1;
            card.remaining_steps = 1;
            card.due = (clock.today_midnight_ms / 1_000) as i32;
            card.memory_state = Some(FsrsMemoryState {
                stability: 1.5 + rng01(mix(seed, 52, 0)) as f32 * 2.0,
                difficulty: 6.5 + rng01(mix(seed, 53, 0)) as f32 * 2.0,
            });
        } else {
            card.ctype = CardType::Review;
            card.queue = CardQueue::Review;
            card.interval = ivl.max(1) as u32;
            // Next due = last review + interval, so some are overdue, some ahead.
            card.due = today - last_days_ago as i32 + ivl.max(1);
            let stability = ivl as f32 * (0.9 + rng01(mix(seed, 54, 0)) as f32 * 0.4) + 2.0;
            card.memory_state = Some(FsrsMemoryState {
                stability: stability.max(1.0),
                difficulty: 3.0 + rng01(mix(seed, 55, 0)) as f32 * 5.0,
            });
        }
        card.last_review_time = Some(
            TimestampSecs(clock.today_midnight_ms / 1_000).adding_secs(-last_days_ago * 86_400),
        );
        self.update_card_inner(&mut card, original, usn)?;

        // Back-date the card's creation (its id) to just before its first review,
        // so Anki's "Added" stats graph reflects the months of study instead of
        // showing every card created today. `revlog.cid` is repointed in lock
        // step. (Demo seed on a throwaway profile; card ids carry no meaning to
        // sync/undo here.)
        let creation_day = reps.first().map(|r| r.0).unwrap_or(1);
        let new_id = clock.card_id(creation_day);
        if new_id < cid.0 {
            self.storage
                .db
                .execute("UPDATE cards SET id=?1 WHERE id=?2", [new_id, cid.0])?;
            self.storage
                .db
                .execute("UPDATE revlog SET cid=?1 WHERE cid=?2", [new_id, cid.0])?;
        }
        Ok(())
    }

    /// Write a topic's sealed confusion + TBS attempts so its Performance (and
    /// the aggregate readiness band) has real evidence: `mcq_total` single-choice
    /// discrimination attempts (`mcq_correct` right, interleaved) plus one
    /// partial-credit TBS attempt per credit in `tbs_credits`. `topic_seed`
    /// drives the confidence + latency jitter deterministically.
    #[allow(clippy::too_many_arguments)]
    fn seed_performance_history(
        &mut self,
        section: &str,
        set_id: &str,
        topic_seed: u64,
        mcq_correct: u32,
        mcq_total: u32,
        tbs_credits: &[f64],
        item_ids: &[NoteId],
    ) -> Result<()> {
        let pick = |i: usize| -> NoteId {
            item_ids
                .get(i % item_ids.len().max(1))
                .copied()
                .unwrap_or(NoteId(1))
        };
        for i in 0..mcq_total {
            let correct = is_correct_rep(i, mcq_total, mcq_correct);
            // Confidence is NOT a mirror of correctness: a real learner is
            // sometimes confidently wrong and sometimes unsure-but-right.
            let u = rng01(mix(topic_seed, 60, i as u64));
            let confidence = if correct {
                if u < 0.25 {
                    "unsure"
                } else {
                    "confident"
                }
            } else if u < 0.18 {
                "confident"
            } else {
                "guess"
            };
            self.ankountant_write_attempt(&NewAttempt {
                item_ref: pick(i as usize),
                confusion_set_id: set_id.to_string(),
                mode: "confusion".to_string(),
                confidence: confidence.to_string(),
                latency_ms: 2_400 + (rng01(mix(topic_seed, 61, i as u64)) * 7_000.0) as u32,
                outcome: Outcome {
                    credit: if correct { 1.0 } else { 0.0 },
                    steps: vec![],
                    elapsed_ms: None,
                },
                section: section.to_string(),
                sealed: true,
            })?;
        }
        // Partial-credit TBS attempts (blend 50/50 into Performance).
        for (i, &credit) in tbs_credits.iter().enumerate() {
            let u = rng01(mix(topic_seed, 62, i as u64));
            let confidence = if credit >= 0.8 {
                if u < 0.2 {
                    "unsure"
                } else {
                    "confident"
                }
            } else if u < 0.3 {
                "confident"
            } else {
                "unsure"
            };
            self.ankountant_write_attempt(&NewAttempt {
                item_ref: pick(i),
                confusion_set_id: set_id.to_string(),
                mode: "tbs".to_string(),
                confidence: confidence.to_string(),
                latency_ms: 30_000 + (rng01(mix(topic_seed, 63, i as u64)) * 40_000.0) as u32,
                outcome: Outcome {
                    credit,
                    steps: vec![],
                    elapsed_ms: None,
                },
                section: section.to_string(),
                sealed: true,
            })?;
        }
        Ok(())
    }

    /// A sealed 4-line journal-entry TBS for a set. The lease worked example is
    /// pinned by the A10/A28/A35 grading tests and the e2e JE spec — keep the
    /// four lines + amounts stable, and leave provenance blank (A34).
    fn add_sealed_je_tbs(&mut self, deck: DeckId, spec: &SetSpec) -> Result<NoteId> {
        let tbs_nt = self.ankountant_tbs_notetype()?;
        let steps = json!([
            {"id":"l1","answer_key":{"account":"ROU Asset","side":"dr","amount":10000},"weight":0.25},
            {"id":"l2","answer_key":{"account":"Lease Liability","side":"cr","amount":10000},"weight":0.25},
            {"id":"l3","answer_key":{"account":"Interest Expense","side":"dr","amount":500},"weight":0.25},
            {"id":"l4","answer_key":{"account":"Cash","side":"cr","amount":500},"weight":0.25}
        ]);
        let mut note = tbs_nt.new_note();
        note.set_field(tbs_fields::TBS_TYPE, "journal_entry")?;
        note.set_field(
            tbs_fields::PROMPT,
            format!("Record the entry ({})", spec.set_id),
        )?;
        note.set_field(
            tbs_fields::EXHIBITS_JSON,
            json!([{"title":"Lease schedule","body":"See amortization table."}]).to_string(),
        )?;
        note.set_field(tbs_fields::STEPS_JSON, steps.to_string())?;
        note.set_field(tbs_fields::SCHEMA_TAG, spec.tags[0])?;
        note.tags = vec![spec.tags[0].to_string()];
        self.add_note_inner(&mut note, deck)?;
        Ok(note.id)
    }

    /// A sealed numeric (per-cell) TBS for a set. Pinned by the A10/e2e numeric
    /// specs (250000 / 12500 within tolerance).
    fn add_sealed_numeric_tbs(&mut self, deck: DeckId, spec: &SetSpec) -> Result<NoteId> {
        let tbs_nt = self.ankountant_tbs_notetype()?;
        let steps = json!([
            {"id":"c1","answer_key":250000,"weight":0.5,"tolerance":1.0},
            {"id":"c2","answer_key":12500,"weight":0.5,"tolerance":1.0}
        ]);
        let mut note = tbs_nt.new_note();
        note.set_field(tbs_fields::TBS_TYPE, "numeric")?;
        note.set_field(
            tbs_fields::PROMPT,
            format!("Compute the amounts ({})", spec.set_id),
        )?;
        note.set_field(tbs_fields::EXHIBITS_JSON, "[]")?;
        note.set_field(tbs_fields::STEPS_JSON, steps.to_string())?;
        note.set_field(tbs_fields::SCHEMA_TAG, spec.tags[1])?;
        note.tags = vec![spec.tags[1].to_string()];
        self.add_note_inner(&mut note, deck)?;
        Ok(note.id)
    }

    /// Suspend a note's cards (used for the sealed firewall bank, A7).
    pub(crate) fn suspend_note_cards(&mut self, nid: NoteId) -> Result<()> {
        let cids = self.storage.card_ids_of_notes(&[nid])?;
        let cards = self.all_cards_for_ids(&cids, false)?;
        self.bury_or_suspend_cards_inner(cards, BuryOrSuspendMode::Suspend)?;
        Ok(())
    }
}

/// Transform a content TBS item's flat steps into the graded `steps_json`
/// shape (`grading::GradableStep`): JE lines wrap `{account,side,amount}` under
/// `answer_key`; numeric cells carry a scalar `answer_key` + `tolerance`.
fn content_tbs_steps(t: &TbsItem) -> Value {
    // Content always supplies these keys (validated at authoring time); a null
    // default is a cheap, clippy-clean fallback that grading treats as absent.
    let field = |s: &Value, k: &str| s.get(k).cloned().unwrap_or(Value::Null);
    let steps: Vec<Value> = t
        .steps
        .iter()
        .map(|s| {
            let id = field(s, "id");
            let weight = field(s, "weight");
            if t.kind == "journal_entry" {
                json!({
                    "id": id,
                    "answer_key": {
                        "account": field(s, "account"),
                        "side": field(s, "side"),
                        "amount": field(s, "amount"),
                    },
                    "weight": weight,
                })
            } else {
                json!({
                    "id": id,
                    "answer_key": field(s, "answer_key"),
                    "weight": weight,
                    "tolerance": field(s, "tolerance"),
                })
            }
        })
        .collect();
    Value::Array(steps)
}

/// Transform a typed [`SectionItem`]'s steps into the grader's stored
/// `steps_json` array. `answer_key`/`weight`/`tolerance` land where the grader
/// reads them; the client-only extras (kind, options, accepted, corpus_refs,
/// confusion_set_id, …) ride along and are ignored by `GradableStep`.
fn section_item_steps(item: &SectionItem) -> Value {
    let n = item.steps.len();
    let default_w = if n > 0 { 1.0 / n as f64 } else { 0.0 };
    let steps: Vec<Value> = item
        .steps
        .iter()
        .map(|s| match s {
            SeedStep::Citation {
                id,
                label,
                weight,
                accepted,
                corpus_refs,
                granularity,
            } => json!({
                "id": id,
                "kind": "citation",
                "answer_key": accepted,
                "weight": weight.unwrap_or(default_w),
                "label": label,
                "corpus_refs": corpus_refs,
                "granularity": granularity,
            }),
            SeedStep::Blank {
                id,
                label,
                weight,
                answer_key,
                options,
                confusion_set_id,
                original_text,
                exhibit_refs,
            } => json!({
                "id": id,
                "kind": "blank",
                "answer_key": answer_key,
                "weight": weight.unwrap_or(default_w),
                "label": label,
                "options": options,
                "confusion_set_id": confusion_set_id,
                "original_text": original_text,
                "exhibit_refs": exhibit_refs,
            }),
            SeedStep::Je {
                id,
                weight,
                account,
                side,
                amount,
            } => json!({
                "id": id,
                "kind": "je",
                "answer_key": { "account": account, "side": side, "amount": amount },
                "weight": weight.unwrap_or(default_w),
            }),
            SeedStep::Numeric {
                id,
                label,
                weight,
                answer_key,
                tolerance,
            } => json!({
                "id": id,
                "kind": "numeric",
                "answer_key": answer_key,
                "weight": weight.unwrap_or(default_w),
                "label": label,
                "tolerance": tolerance.unwrap_or(constants::DEFAULT_NUMERIC_TOLERANCE),
            }),
        })
        .collect();
    Value::Array(steps)
}

/// Return `Err(InvalidInput)` unless `cond` holds — the seed-time validation
/// primitive (D9: correctness is validated, not assumed).
fn check(cond: bool, msg: impl Into<String>) -> Result<()> {
    cond.then_some(()).or_invalid(msg)
}

/// D9 — validate one typed section item before it is seeded. Enforces the
/// section/shape vocabulary, the per-shape step invariants, and that a
/// doc-review's blanks are each anchored by a marker in its document exhibit.
fn validate_section_item(item: &SectionItem) -> Result<()> {
    check(
        super::SECTIONS.contains(&item.section.as_str()),
        format!("unknown section {:?}", item.section),
    )?;
    check(
        matches!(
            item.tbs_type.as_str(),
            "research" | "doc_review" | "numeric" | "journal_entry"
        ),
        format!("unknown tbs_type {:?} ({})", item.tbs_type, item.section),
    )?;
    check(
        !item.set_id.trim().is_empty(),
        format!("empty set_id ({} {})", item.section, item.tbs_type),
    )?;
    check(
        !item.prompt.trim().is_empty(),
        format!("empty prompt ({} {})", item.section, item.tbs_type),
    )?;
    check(
        !item.steps.is_empty(),
        format!("no steps ({} {})", item.section, item.tbs_type),
    )?;
    if let Some(v) = item.schema_version {
        check(v == 1, format!("unsupported schema_version {v}"))?;
    }
    for ex in &item.exhibits {
        check(!ex.title.trim().is_empty(), "exhibit is missing a title")?;
        check(
            SEED_EXHIBIT_KINDS.contains(&ex.kind.as_str()),
            format!("exhibit {:?} has unknown kind {:?}", ex.title, ex.kind),
        )?;
        if ex.kind == "table" {
            check(
                !ex.rows.is_empty(),
                format!("table exhibit {:?} has no rows", ex.title),
            )?;
        }
    }

    match item.tbs_type.as_str() {
        "research" => {
            check(
                item.steps.len() == 1,
                "research item must have exactly one citation step",
            )?;
            match &item.steps[0] {
                SeedStep::Citation { id, accepted, .. } => {
                    check(id == "citation", "research step id must be \"citation\"")?;
                    check(
                        !accepted.is_empty(),
                        "research citation needs >=1 accepted variant",
                    )?;
                    for a in accepted {
                        check(
                            !logic::citation_normalize(a).is_empty(),
                            format!("un-normalizable citation {a:?}"),
                        )?;
                    }
                }
                _ => check(false, "research step must be kind:citation")?,
            }
        }
        "doc_review" => {
            let doc_body = item
                .exhibits
                .iter()
                .find(|e| e.role.as_deref() == Some("document"))
                .map(|e| e.body.clone());
            check(
                doc_body.is_some(),
                "doc_review needs an exhibit with role:\"document\"",
            )?;
            let doc_body = doc_body.unwrap_or_default();
            for s in &item.steps {
                match s {
                    SeedStep::Blank {
                        id,
                        answer_key,
                        options,
                        ..
                    } => {
                        check(options.len() >= 2, format!("blank {id} needs >=2 options"))?;
                        check(
                            options.iter().any(|o| &o.id == answer_key),
                            format!("blank {id} answer_key {answer_key:?} is not an option id"),
                        )?;
                        let mut seen = std::collections::HashSet::new();
                        for o in options {
                            check(
                                !o.id.trim().is_empty(),
                                format!("blank {id} has an option with empty id"),
                            )?;
                            check(
                                !o.text.trim().is_empty(),
                                format!("blank {id} option {:?} has empty text", o.id),
                            )?;
                            check(
                                SEED_OPTION_KINDS.contains(&o.kind.as_str()),
                                format!(
                                    "blank {id} option {:?} has unknown kind {:?}",
                                    o.id, o.kind
                                ),
                            )?;
                            check(
                                seen.insert(o.id.as_str()),
                                format!("blank {id} has duplicate option id {:?}", o.id),
                            )?;
                        }
                        check(
                            doc_body.contains(&format!("step=\"{id}\""))
                                || doc_body.contains(&format!("[[{id}]]")),
                            format!("blank {id} has no marker in the document exhibit"),
                        )?;
                    }
                    _ => check(false, "doc_review steps must be kind:blank")?,
                }
            }
        }
        "numeric" => {
            for s in &item.steps {
                check(
                    matches!(s, SeedStep::Numeric { .. }),
                    "numeric item steps must be kind:numeric",
                )?;
            }
        }
        "journal_entry" => {
            for s in &item.steps {
                match s {
                    SeedStep::Je { side, .. } => check(
                        matches!(side.to_lowercase().as_str(), "dr" | "cr"),
                        format!("je side must be dr/cr, got {side:?}"),
                    )?,
                    _ => check(false, "journal_entry steps must be kind:je")?,
                }
            }
        }
        _ => {}
    }
    Ok(())
}

/// Parse + validate a `section_items` JSON array. Test hook for the typed
/// schema (D9): serde structure errors and every validation rule surface here.
/// (The seed itself validates each item inline via [`validate_section_item`].)
#[cfg(test)]
pub(crate) fn validate_section_items_json(json: &str) -> Result<usize> {
    let items: Vec<SectionItem> =
        serde_json::from_str(json).or_invalid("invalid section_items json")?;
    for item in &items {
        validate_section_item(item)?;
    }
    Ok(items.len())
}
