// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! A8 — the sync-safe attempt store. Each gated Performance attempt is one
//! hidden "Attempt Log" note (no new SQLite table/column). Its card is
//! suspended so the study scheduler never serves it.

use anki_proto::scheduler::bury_or_suspend_cards_request::Mode as BuryOrSuspendMode;
use serde::Deserialize;
use serde::Serialize;

use super::notetypes::attempt_fields as f;
use crate::prelude::*;

/// The deck that holds Attempt Log notes; its cards are permanently suspended.
pub(crate) const ATTEMPT_LOG_DECK: &str = "Ankountant::Log";

/// A decoded Attempt Log note, used by the scoring queries (A3/A4).
#[derive(Debug, Clone)]
pub(crate) struct AttemptRecord {
    pub(crate) confusion_set_id: String,
    pub(crate) mode: String,
    #[allow(dead_code)]
    pub(crate) confidence: String,
    pub(crate) outcome: Outcome,
    pub(crate) sealed: bool,
    /// Retained for completeness/forward use; reads are already section-scoped.
    #[allow(dead_code)]
    pub(crate) section: String,
    /// Attempt timestamp (secs). Persisted for calibration/trailing-window
    /// analysis; consumed by the score tests today, reserved for the rollups.
    #[allow(dead_code)]
    pub(crate) ts: i64,
}

/// Decoded `outcome_json`. For confusion attempts, `credit` is 1.0/0.0; for TBS
/// attempts, `credit` is the fractional total and `steps` carries per-step
/// data.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(crate) struct Outcome {
    #[serde(default)]
    pub(crate) credit: f64,
    #[serde(default)]
    pub(crate) steps: Vec<OutcomeStep>,
    /// T1 AC2 — research "time-to-cite" (ms), a reported secondary signal only.
    /// `#[serde(default)]` keeps old `outcome_json` (no key) deserializing, and
    /// `skip_serializing_if` keeps non-research outcomes byte-identical to
    /// before (sync-safe: no new field on the wire when absent).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) elapsed_ms: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(crate) struct OutcomeStep {
    pub(crate) id: String,
    pub(crate) correct: bool,
    pub(crate) weight: f64,
}

/// Everything needed to persist one attempt.
pub(crate) struct NewAttempt {
    pub(crate) item_ref: NoteId,
    pub(crate) confusion_set_id: String,
    pub(crate) mode: String,
    pub(crate) confidence: String,
    pub(crate) latency_ms: u32,
    pub(crate) outcome: Outcome,
    pub(crate) section: String,
    pub(crate) sealed: bool,
}

impl Collection {
    /// Persist one Attempt Log note. MUST be called inside a transaction (it
    /// mutates notes + suspends the created card). Returns the new note id.
    pub(crate) fn ankountant_write_attempt(&mut self, attempt: &NewAttempt) -> Result<NoteId> {
        let nt = self.ankountant_attempt_log_notetype()?;
        let deck_id = self.ankountant_get_or_create_deck_inner(ATTEMPT_LOG_DECK)?;
        let mut note = nt.new_note();
        let outcome_json = serde_json::to_string(&attempt.outcome)?;
        note.set_field(f::ITEM_REF, attempt.item_ref.0.to_string())?;
        note.set_field(f::CONFUSION_SET_ID, &attempt.confusion_set_id)?;
        note.set_field(f::MODE, &attempt.mode)?;
        note.set_field(f::CONFIDENCE, &attempt.confidence)?;
        note.set_field(f::LATENCY_MS, attempt.latency_ms.to_string())?;
        note.set_field(f::OUTCOME_JSON, &outcome_json)?;
        note.set_field(f::TS, TimestampSecs::now().0.to_string())?;
        note.set_field(f::SECTION, &attempt.section)?;
        note.set_field(f::SEALED, if attempt.sealed { "1" } else { "0" })?;
        self.add_note_inner(&mut note, deck_id)?;

        // Suspend the generated card(s) so the study scheduler never serves the
        // hidden log note (A8 AC3 / A29).
        let cids = self.storage.card_ids_of_notes(&[note.id])?;
        let cards = self.all_cards_for_ids(&cids, false)?;
        self.bury_or_suspend_cards_inner(cards, BuryOrSuspendMode::Suspend)?;

        Ok(note.id)
    }

    /// Read all Attempt Log records for a section (unordered read, no txn).
    pub(crate) fn ankountant_attempts(&mut self, section: &str) -> Result<Vec<AttemptRecord>> {
        let Some(nt) = self.get_notetype_by_name(super::notetypes::ATTEMPT_LOG_NOTETYPE)? else {
            return Ok(vec![]);
        };
        let nids = self.search_notes_unordered(nt.id)?;
        let mut out = Vec::with_capacity(nids.len());
        for nid in nids {
            let Some(note) = self.storage.get_note(nid)? else {
                continue;
            };
            let fields = note.fields();
            let section_val = fields.get(f::SECTION).cloned().unwrap_or_default();
            if section_val != section {
                continue;
            }
            let outcome: Outcome = fields
                .get(f::OUTCOME_JSON)
                .and_then(|s| serde_json::from_str(s).ok())
                .unwrap_or_default();
            out.push(AttemptRecord {
                confusion_set_id: fields.get(f::CONFUSION_SET_ID).cloned().unwrap_or_default(),
                mode: fields.get(f::MODE).cloned().unwrap_or_default(),
                confidence: fields.get(f::CONFIDENCE).cloned().unwrap_or_default(),
                outcome,
                sealed: fields.get(f::SEALED).map(|s| s == "1").unwrap_or(false),
                section: section_val,
                ts: fields
                    .get(f::TS)
                    .and_then(|s| s.parse::<i64>().ok())
                    .unwrap_or(0),
            });
        }
        Ok(out)
    }
}
