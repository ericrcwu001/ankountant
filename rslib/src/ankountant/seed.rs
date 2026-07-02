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
use crate::search::SortMode;
use crate::timestamp::TimestampMillis;

/// The hand-authored + AI-drafted FAR content, embedded at build time. Shape is
/// asserted by `seed_content_parses` and by the F016 tests.
const SEED_CONTENT_JSON: &str = include_str!("seed_content.json");

/// Provenance stamp written to generated sealed items (never the anchor JE that
/// A34 asserts is blank).
const GEN_METHOD_SEED: &str = "far-seed-content workflow (Sonnet author + independent verify)";

/// Confusion sets that receive fake history in a demo profile. The fourth set
/// (`trading_afs_htm`) is deliberately left thin so its per-topic readiness
/// reads "insufficient" while the overall band still emits (coverage 3/4).
const COVERED_SETS: [&str; 3] = [
    "capitalize_vs_expense",
    "operating_vs_finance_lease",
    "revrec_step_selection",
];

// Fake-history volumes, tuned so the aggregate lands in an honest, provisional
// band (~40 sealed attempts @ ~60% => "Med" confidence) with a visible gap.
const MEMORY_REPS_PER_SET: u32 = 12;
const MEMORY_CORRECT_PER_SET: u32 = 9; // 75% recall accuracy
const CONFUSION_ATTEMPTS_PER_SET: u32 = 10;
const CONFUSION_CORRECT_PER_SET: u32 = 6; // 60% discrimination accuracy

#[derive(Debug, Deserialize)]
struct SeedContent {
    recall: Vec<RecallCard>,
    mcqs: std::collections::BTreeMap<String, Vec<McqItem>>,
    tbs: Vec<TbsItem>,
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
    /// Note ids of the playable sealed TBS notes (JE + numeric). Anchors first,
    /// then the extra content TBS, so the e2e fixture can rely on index 0 being
    /// the 4-line anchor JE.
    pub(crate) sealed_tbs_note_ids: Vec<NoteId>,
}

/// One confusion set's authoring spec.
struct SetSpec {
    set_id: &'static str,
    tags: [&'static str; 2],
    treatments: [&'static str; 2],
}

const SETS: [SetSpec; 4] = [
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
];

/// A shared cursor for placing seeded revlog rows on specific past days while
/// keeping every id unique across the whole seed. `seq` is decremented into the
/// id so same-day rows differ by a few ms and never collide.
struct RevlogClock {
    now_ms: i64,
    seq: i64,
}

impl RevlogClock {
    /// A unique revlog id `days_ago` days in the past (shifted by a few ms).
    fn id(&mut self, days_ago: i64) -> i64 {
        let id = self.now_ms - days_ago * 86_400_000 - self.seq;
        self.seq += 1;
        id
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

        // --- CONFUSABLE map in col config (A3/A6). ---
        let mut map: ConfusableMap = ConfusableMap::new();
        for spec in &SETS {
            map.insert(
                spec.set_id.to_string(),
                ConfusionSet {
                    tags: spec.tags.iter().map(|s| s.to_string()).collect(),
                    treatments: spec.treatments.iter().map(|s| s.to_string()).collect(),
                },
            );
        }
        self.set_config(config::confusable_key(section).as_str(), &map)?;
        summary.confusion_sets = map.len();

        let sealed_deck_base = format!("Ankountant::Sealed::{section}");
        let study_nt = self.ankountant_study_notetype()?;
        let tbs_nt = self.ankountant_tbs_notetype()?;

        // --- 1) Real recall cards -> study pile (per blueprint topic deck). ---
        // Track card ids per ds:: tag so the memory history can target them.
        let mut ds_cards: std::collections::HashMap<String, Vec<CardId>> =
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
            // Provenance rides in the answer for recall cards (the Study note
            // type has no dedicated fields).
            note.set_field(1, format!("{}\n\nSource: {}", card.back, card.source))?;
            let mut tags = vec![cog.to_string(), card.topic_tag.clone()];
            if !card.ds_tag.is_empty() {
                tags.push(card.ds_tag.clone());
            }
            note.tags = tags;
            self.add_note_inner(&mut note, deck)?;
            summary.study_recall_cards += 1;
            if cog == TAG_COG_ROTE {
                summary.rote_cards += 1;
            }
            if !card.ds_tag.is_empty() {
                let cids = self.storage.card_ids_of_notes(&[note.id])?;
                ds_cards
                    .entry(card.ds_tag.clone())
                    .or_default()
                    .extend(cids);
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

            // >= 6 sealed single-choice MCQs per set, real prompts from content
            // (fallback to a generic prompt only if content is missing).
            let items = content.mcqs.get(spec.set_id);
            let count = items.map(|v| v.len()).unwrap_or(0).max(6);
            for q in 0..count {
                let (prompt, correct, tag, source) = match items.and_then(|v| v.get(q)) {
                    Some(it) => (
                        it.prompt.clone(),
                        it.correct_treatment.clone(),
                        it.ds_tag.clone(),
                        it.source.clone(),
                    ),
                    None => {
                        let tag = spec.tags[q % 2].to_string();
                        (
                            format!("Which treatment applies? ({} q{q})", spec.set_id),
                            spec.treatments[q % 2].to_string(),
                            tag,
                            String::new(),
                        )
                    }
                };
                let steps = json!([{"id":"choice","answer_key": correct, "weight": 1.0}]);
                let mut note = tbs_nt.new_note();
                note.set_field(tbs_fields::TBS_TYPE, "mcq")?;
                note.set_field(tbs_fields::PROMPT, &prompt)?;
                note.set_field(tbs_fields::EXHIBITS_JSON, "[]")?;
                note.set_field(tbs_fields::STEPS_JSON, steps.to_string())?;
                note.set_field(tbs_fields::SCHEMA_TAG, &tag)?;
                if !source.is_empty() {
                    note.set_field(tbs_fields::SOURCE_PASSAGE, &source)?;
                    note.set_field(tbs_fields::GEN_METHOD, GEN_METHOD_SEED)?;
                    note.set_field(tbs_fields::CHECKER_STATUS, "pass")?;
                }
                note.tags = vec![tag];
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

        // --- 4) Stored-only shapes (A9 AC3): one research + one doc_review. ---
        let misc_deck =
            self.ankountant_get_or_create_deck_inner(&format!("{sealed_deck_base}::misc"))?;
        for shape in ["research", "doc_review"] {
            let mut note = tbs_nt.new_note();
            note.set_field(tbs_fields::TBS_TYPE, shape)?;
            note.set_field(tbs_fields::PROMPT, format!("Stored-only {shape} task"))?;
            note.set_field(tbs_fields::EXHIBITS_JSON, "[]")?;
            note.set_field(tbs_fields::STEPS_JSON, "[]")?;
            note.set_field(tbs_fields::SCHEMA_TAG, SETS[0].tags[0])?;
            self.add_note_inner(&mut note, misc_deck)?;
            self.suspend_note_cards(note.id)?;
        }

        // --- 5) Demo history (opt-in): a lived-in profile, not a clean slate. ---
        if with_history {
            // FSRS on so the seeded memory states + retrievability are live.
            self.set_config(BoolKey::Fsrs, &true)?;

            // Exam date ~SEED_EXAM_OFFSET_DAYS out lights up the Home countdown
            // and the deadline-anchored retention ramp (A1). Written with the
            // inner setter because we are already inside a transaction.
            let exam_iso = (chrono::Local::now().date_naive()
                + chrono::Duration::days(constants::SEED_EXAM_OFFSET_DAYS))
            .format("%Y-%m-%d")
            .to_string();
            let exam_key = config::exam_date_key(section);
            self.set_config(exam_key.as_str(), &exam_iso)?;

            // A shared clock keeps every seeded revlog id unique while placing
            // rows on specific past days.
            let mut clock = RevlogClock {
                now_ms: TimestampMillis::now().0,
                seq: 0,
            };

            // In-window recall reps back the readiness Memory metric for the
            // covered sets; the 4th set is left thin on purpose (give-up rule).
            for set_id in COVERED_SETS {
                let spec = SETS.iter().find(|s| s.set_id == set_id).unwrap();
                let mut cids: Vec<CardId> = Vec::new();
                for tag in spec.tags {
                    if let Some(v) = ds_cards.get(tag) {
                        cids.extend(v.iter().copied());
                    }
                }
                self.seed_memory_history(
                    &cids,
                    MEMORY_REPS_PER_SET,
                    MEMORY_CORRECT_PER_SET,
                    &mut clock,
                )?;
                let items = set_mcq_ids.get(set_id).cloned().unwrap_or_default();
                self.seed_performance_history(section, set_id, &items)?;
            }

            // Reshape the flat New pile into a realistic new/learning/young/
            // mature mix, and spread weeks of review activity for the stats
            // heatmap + streak.
            self.seed_lived_in_card_states(section, &mut clock)?;
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

    /// Inject `total` recall revlog rows across `cids` (`correct` of them a
    /// Good), spread over the trailing window so Memory can be measured for the
    /// set AND the rows land on many different days (heatmap/streak).
    fn seed_memory_history(
        &mut self,
        cids: &[CardId],
        total: u32,
        correct: u32,
        clock: &mut RevlogClock,
    ) -> Result<()> {
        if cids.is_empty() {
            return Ok(());
        }
        for i in 0..total {
            let cid = cids[i as usize % cids.len()];
            let button = if i < correct { 3 } else { 1 };
            // Spread across the trailing window (kept < MEMORY_WINDOW_DAYS via
            // SEED_MEMORY_SPREAD_DAYS) so every rep stays in-window but on a
            // different day.
            let days_ago =
                1 + (i as i64 * (constants::SEED_MEMORY_SPREAD_DAYS - 1)) / total.max(1) as i64;
            self.seed_revlog_row(cid, days_ago, button, 0, 0, clock)?;
        }
        Ok(())
    }

    /// Insert one recall revlog row `days_ago` days in the past, using the
    /// shared `clock` for a unique id that still lands on the intended day.
    fn seed_revlog_row(
        &mut self,
        cid: CardId,
        days_ago: i64,
        button: u8,
        last_interval: i32,
        interval: i32,
        clock: &mut RevlogClock,
    ) -> Result<()> {
        let taken_millis = 2_500 + (clock.seq as u32).wrapping_mul(97) % 8_000;
        let id = clock.id(days_ago);
        self.storage.add_revlog_entry(
            &RevlogEntry {
                id: RevlogId(id),
                cid,
                usn: Usn(-1),
                button_chosen: button,
                review_kind: RevlogReviewKind::Review,
                interval,
                last_interval,
                taken_millis,
                ..Default::default()
            },
            false,
        )?;
        Ok(())
    }

    /// Turn the flat New pile into a lived-in mix of new/learning/young/mature
    /// cards (so deck due badges + the card-count/interval/future-due/
    /// retrievability charts populate) and spread weeks of review activity for
    /// the heatmap + streak.
    ///
    /// Confusion-set study cards are reshaped for looks too, but get no
    /// activity revlog here, so the readiness Memory metric stays exactly
    /// what `seed_memory_history` produced and the thin 4th set stays
    /// insufficient.
    fn seed_lived_in_card_states(&mut self, section: &str, clock: &mut RevlogClock) -> Result<()> {
        let today = self.timing_today()?.days_elapsed as i32;
        let usn = self.usn()?;
        let decay = crate::scheduler::fsrs::memory_state::get_decay_from_params(&[]);

        // Study cards that belong to a confusion set (covered or the thin 4th):
        // reshaped, but excluded from the activity revlog below.
        let mut confusion_cids: std::collections::HashSet<CardId> =
            std::collections::HashSet::new();
        for spec in &SETS {
            for tag in spec.tags {
                let search = format!("tag:{tag} deck:Ankountant::Study::{section}::*");
                for cid in self.search_cards(search.as_str(), SortMode::NoOrder)? {
                    confusion_cids.insert(cid);
                }
            }
        }

        let all = self.search_cards(
            format!("deck:Ankountant::Study::{section}::*").as_str(),
            SortMode::NoOrder,
        )?;

        let new_end = constants::SEED_MIX_NEW;
        let learn_end = new_end + constants::SEED_MIX_LEARN;
        let young_end = learn_end + constants::SEED_MIX_YOUNG;
        let slots = young_end + constants::SEED_MIX_MATURE;

        // Non-confusion review cards that back the spread-out activity history.
        let mut pool: Vec<CardId> = Vec::new();
        for (i, &cid) in all.iter().enumerate() {
            let slot = (i as u32) % slots;
            if slot < new_end {
                continue; // leave a fresh New pile
            }
            let Some(original) = self.storage.get_card(cid)? else {
                continue;
            };
            let mut card = original.clone();
            card.ease_factor = 2_500;
            card.desired_retention = Some(0.9);
            card.decay = Some(decay);
            if slot < learn_end {
                // Intraday learning card, due now.
                card.ctype = CardType::Learn;
                card.queue = CardQueue::Learn;
                card.remaining_steps = 1;
                card.reps = 1 + (i as u32 % 3);
                card.due = (clock.now_ms / 1_000) as i32;
                card.memory_state = Some(FsrsMemoryState {
                    stability: 1.0 + (i % 3) as f32,
                    difficulty: 5.0,
                });
                card.last_review_time = Some(TimestampSecs::now());
            } else {
                let mature = slot >= young_end;
                let interval = if mature {
                    21 + (i as u32 * 13) % 70
                } else {
                    1 + (i as u32 * 7) % 20
                };
                // Young cards spread overdue..soon; mature cards mostly future.
                let offset = if mature {
                    i as i32 % 30
                } else {
                    (i as i32 % 12) - 4
                };
                let lapse_every = if mature { 7 } else { 5 };
                let stability = if mature {
                    interval as f32 * 1.6 + 10.0
                } else {
                    interval as f32 * 1.3 + 3.0
                };
                card.ctype = CardType::Review;
                card.queue = CardQueue::Review;
                card.interval = interval;
                card.due = today + offset;
                card.reps = if mature {
                    8 + i as u32 % 20
                } else {
                    3 + i as u32 % 7
                };
                card.lapses = (i as u32 % lapse_every == 0) as u32;
                card.remaining_steps = 0;
                card.memory_state = Some(FsrsMemoryState {
                    stability,
                    difficulty: 3.0 + (i % 6) as f32,
                });
                let last_days = (interval as i64 - offset as i64).max(0);
                card.last_review_time = Some(TimestampSecs::now().adding_secs(-last_days * 86_400));
                if !confusion_cids.contains(&cid) {
                    pool.push(cid);
                }
            }
            self.update_card_inner(&mut card, original, usn)?;
        }

        self.seed_activity_history(&pool, clock)?;
        Ok(())
    }

    /// Spread review rows over ~`SEED_ACTIVITY_SPREAD_DAYS` days across `pool`
    /// (non-confusion study cards), so the heatmap, reviews, buttons and
    /// true-retention charts look used and the streak is real. An occasional
    /// rest day keeps the heatmap from looking unnaturally solid.
    fn seed_activity_history(&mut self, pool: &[CardId], clock: &mut RevlogClock) -> Result<()> {
        if pool.is_empty() {
            return Ok(());
        }
        for d in 0..constants::SEED_ACTIVITY_SPREAD_DAYS {
            if d % 9 == 8 {
                continue; // a rest day now and then
            }
            let per_day = 2 + (d % 3);
            for k in 0..per_day {
                let idx = ((d * 7 + k * 3) as usize) % pool.len();
                let button = match (d + k) % 7 {
                    0 => 1, // Again
                    1 => 2, // Hard
                    _ => 3, // Good
                };
                // Mix young (<21) and mature (>=21) last intervals so the True
                // Retention grid has both rows.
                let last_interval = 1 + ((d + k) % 40) as i32;
                self.seed_revlog_row(pool[idx], d, button, last_interval, last_interval, clock)?;
            }
        }
        Ok(())
    }

    /// Write sealed confusion + TBS attempts for a set so its Performance (and
    /// the aggregate readiness band) has real evidence.
    fn seed_performance_history(
        &mut self,
        section: &str,
        set_id: &str,
        item_ids: &[NoteId],
    ) -> Result<()> {
        let pick = |i: usize| -> NoteId {
            item_ids
                .get(i % item_ids.len().max(1))
                .copied()
                .unwrap_or(NoteId(1))
        };
        for i in 0..CONFUSION_ATTEMPTS_PER_SET {
            let correct = i < CONFUSION_CORRECT_PER_SET;
            self.ankountant_write_attempt(&NewAttempt {
                item_ref: pick(i as usize),
                confusion_set_id: set_id.to_string(),
                mode: "confusion".to_string(),
                confidence: if correct { "confident" } else { "guess" }.to_string(),
                latency_ms: 3200,
                outcome: Outcome {
                    credit: if correct { 1.0 } else { 0.0 },
                    steps: vec![],
                },
                section: section.to_string(),
                sealed: true,
            })?;
        }
        // A couple of partial-credit TBS attempts (blends 50/50 into Performance).
        for credit in [0.5f64, 0.75] {
            self.ankountant_write_attempt(&NewAttempt {
                item_ref: pick(0),
                confusion_set_id: set_id.to_string(),
                mode: "tbs".to_string(),
                confidence: "unsure".to_string(),
                latency_ms: 45_000,
                outcome: Outcome {
                    credit,
                    steps: vec![],
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
