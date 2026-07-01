// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! F016 — the hand-authored FAR seed, sized to exercise every rubric and to
//! cross the abstain thresholds on demand (>= 4 CONFUSABLE sets, >= 24 sealed
//! items, >= 3 journal-entry + 2 numeric sealed TBS, plus rote/applied study
//! recall cards). Built entirely from ordinary Anki objects (FR-5).
//!
//! Reachable from the Rust test suite AND from the `LoadFarSeed` RPC (F016),
//! which the Playwright e2e fixture calls to prepare a throwaway collection
//! before each spec.

use anki_proto::scheduler::bury_or_suspend_cards_request::Mode as BuryOrSuspendMode;
use serde_json::json;

use super::config;
use super::config::ConfusableMap;
use super::config::ConfusionSet;
use super::notetypes::tbs_fields;
use super::TAG_COG_APPLIED;
use super::TAG_COG_ROTE;
use crate::prelude::*;

/// Summary of what the seed produced, for assertions.
#[derive(Debug, Clone, Default)]
pub(crate) struct SeedSummary {
    pub(crate) confusion_sets: usize,
    pub(crate) sealed_items: usize,
    pub(crate) sealed_je_tbs: usize,
    pub(crate) sealed_numeric_tbs: usize,
    pub(crate) study_recall_cards: usize,
    pub(crate) rote_cards: usize,
    /// Note ids of the playable sealed TBS notes (JE + numeric), so a client
    /// (the e2e fixture) can deep-link the B4 surface without a query RPC.
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

impl Collection {
    /// Load the FAR seed. Idempotent per collection is NOT guaranteed —
    /// intended for fresh collections / test fixtures.
    pub(crate) fn ankountant_load_far_seed(&mut self) -> Result<SeedSummary> {
        // Note types must exist before the write transaction (creating them is
        // itself transactional).
        self.ankountant_tbs_notetype()?;
        self.ankountant_attempt_log_notetype()?;
        self.ankountant_study_notetype()?;
        let out = self.transact(crate::ops::Op::AddNote, |col| col.load_far_seed_inner())?;
        Ok(out.output)
    }

    /// RPC entry point (F016): load the FAR seed and return the counts as the
    /// proto response the e2e fixture consumes.
    pub(crate) fn ankountant_load_far_seed_response(
        &mut self,
    ) -> Result<anki_proto::scheduler::LoadFarSeedResponse> {
        let summary = self.ankountant_load_far_seed()?;
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

    fn load_far_seed_inner(&mut self) -> Result<SeedSummary> {
        let section = super::DEFAULT_SECTION;
        let mut summary = SeedSummary::default();

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

        let study_deck = self
            .ankountant_get_or_create_deck_inner(&format!("Ankountant::Study::{section}::core"))?;
        let sealed_deck_base = format!("Ankountant::Sealed::{section}");

        let tbs_nt = self.ankountant_tbs_notetype()?;
        let study_nt = self.ankountant_study_notetype()?;

        for (set_idx, spec) in SETS.iter().enumerate() {
            let sealed_deck = self.ankountant_get_or_create_deck_inner(&format!(
                "{sealed_deck_base}::{}",
                spec.set_id
            ))?;

            // --- 3 study recall cards per set (mix rote/applied). ---
            for (i, tag) in spec.tags.iter().enumerate() {
                for rep in 0..2 {
                    let cog = if rep == 0 {
                        TAG_COG_ROTE
                    } else {
                        TAG_COG_APPLIED
                    };
                    let mut note = study_nt.new_note();
                    note.set_field(0, format!("Recall {}-{i}-{rep}", spec.set_id))?;
                    note.set_field(1, spec.treatments[i])?;
                    note.tags = vec![tag.to_string(), cog.to_string()];
                    self.add_note_inner(&mut note, study_deck)?;
                    summary.study_recall_cards += 1;
                    if cog == TAG_COG_ROTE {
                        summary.rote_cards += 1;
                    }
                }
            }

            // --- >= 6 sealed MCQs per set (single-choice TBS). ---
            for q in 0..6 {
                let tag = spec.tags[q % 2];
                let correct = spec.treatments[q % 2];
                let steps = json!([
                    {"id":"choice","answer_key": correct, "weight": 1.0}
                ]);
                let mut note = tbs_nt.new_note();
                note.set_field(tbs_fields::TBS_TYPE, "numeric")?;
                note.set_field(
                    tbs_fields::PROMPT,
                    format!("Which treatment applies? ({} q{q})", spec.set_id),
                )?;
                note.set_field(tbs_fields::EXHIBITS_JSON, "[]")?;
                note.set_field(tbs_fields::STEPS_JSON, steps.to_string())?;
                note.set_field(tbs_fields::SCHEMA_TAG, tag)?;
                note.tags = vec![tag.to_string()];
                self.add_note_inner(&mut note, sealed_deck)?;
                self.suspend_note_cards(note.id)?;
                summary.sealed_items += 1;
            }

            // --- Sealed TBS: 1 JE per set for the first 3 sets, numeric for
            //     the remaining ones, so we get >= 3 JE + 2 numeric overall. ---
            if set_idx < 3 {
                let note_id = self.add_sealed_je_tbs(sealed_deck, spec)?;
                self.suspend_note_cards(note_id)?;
                summary.sealed_je_tbs += 1;
                summary.sealed_items += 1;
                summary.sealed_tbs_note_ids.push(note_id);
            } else {
                let note_id = self.add_sealed_numeric_tbs(sealed_deck, spec)?;
                self.suspend_note_cards(note_id)?;
                summary.sealed_numeric_tbs += 1;
                summary.sealed_items += 1;
                summary.sealed_tbs_note_ids.push(note_id);
            }
            // One more numeric TBS on the second set to reach >= 2 numeric.
            if set_idx == 1 {
                let note_id = self.add_sealed_numeric_tbs(sealed_deck, spec)?;
                self.suspend_note_cards(note_id)?;
                summary.sealed_numeric_tbs += 1;
                summary.sealed_items += 1;
                summary.sealed_tbs_note_ids.push(note_id);
            }
        }

        // Ensure >= 3 JE: sets 0,1,2 each contributed one JE => 3. Good.
        // Ensure >= 2 numeric TBS: set 3 + set 1 extra => 2. Good.

        // Stored-only shapes (A9 AC3): one research + one doc_review, unplayed.
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

        Ok(summary)
    }

    /// A sealed 4-line journal-entry TBS for a set.
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

    /// A sealed numeric (per-cell) TBS for a set.
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
