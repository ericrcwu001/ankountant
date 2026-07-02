// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! A8/A9 — the two Ankountant note types, created lazily and looked up by name.
//!
//! Both are *ordinary* Anki note types (sync-safe: no new SQLite table/column).
//! The Attempt Log note type lives in a dedicated never-queued deck; the TBS
//! note type holds all four shapes structurally (A9).

use std::sync::Arc;

use crate::notetype::Notetype;
use crate::notetype::NotetypeId;
use crate::prelude::*;

pub(crate) const ATTEMPT_LOG_NOTETYPE: &str = "Ankountant Attempt Log";
pub(crate) const TBS_NOTETYPE: &str = "Ankountant TBS";
pub(crate) const STUDY_NOTETYPE: &str = "Ankountant Study";
pub(crate) const SETTINGS_NOTETYPE: &str = "Ankountant Settings";

/// Field order for the Settings note type: a sync-safe per-(section, key) value
/// store (see `settings.rs`). Kept as notes (not `col` config) so each setting
/// merges per-object across devices instead of being clobbered by col config's
/// whole-blob last-writer-wins sync.
pub(crate) mod settings_fields {
    pub(crate) const SECTION: usize = 0;
    pub(crate) const KEY: usize = 1;
    pub(crate) const VALUE: usize = 2;
    pub(crate) const UPDATED_AT: usize = 3;
    pub(crate) const NAMES: &[&str] = &["section", "key", "value", "updated_at"];
}

/// Field order for the Attempt Log note type (A8). Indices are referenced by
/// `attempt_log.rs`, so keep them in sync.
pub(crate) mod attempt_fields {
    pub(crate) const ITEM_REF: usize = 0;
    pub(crate) const CONFUSION_SET_ID: usize = 1;
    pub(crate) const MODE: usize = 2;
    pub(crate) const CONFIDENCE: usize = 3;
    pub(crate) const LATENCY_MS: usize = 4;
    pub(crate) const OUTCOME_JSON: usize = 5;
    pub(crate) const TS: usize = 6;
    pub(crate) const SECTION: usize = 7;
    pub(crate) const SEALED: usize = 8;
    pub(crate) const NAMES: &[&str] = &[
        "item_ref",
        "confusion_set_id",
        "mode",
        "confidence",
        "latency_ms",
        "outcome_json",
        "ts",
        "section",
        "sealed",
    ];
}

/// Field order for the TBS note type (A9). `steps_json` carries the ordered,
/// weighted gradable steps; provenance fields are stored but unpopulated.
pub(crate) mod tbs_fields {
    pub(crate) const TBS_TYPE: usize = 0;
    pub(crate) const PROMPT: usize = 1;
    pub(crate) const EXHIBITS_JSON: usize = 2;
    pub(crate) const STEPS_JSON: usize = 3;
    pub(crate) const SCHEMA_TAG: usize = 4;
    // Provenance (stored, unpopulated — Phase 2a populates them). The fields
    // exist on the note type (see NAMES); these ordinal constants are reserved
    // for the Phase-2a population path and asserted by the A34 tests.
    #[allow(dead_code)]
    pub(crate) const SOURCE_PASSAGE: usize = 5;
    #[allow(dead_code)]
    pub(crate) const GEN_METHOD: usize = 6;
    #[allow(dead_code)]
    pub(crate) const CHECKER_STATUS: usize = 7;
    pub(crate) const NAMES: &[&str] = &[
        "tbs_type",
        "prompt",
        "exhibits_json",
        "steps_json",
        "schema_tag",
        "source_passage",
        "gen_method",
        "checker_status",
    ];
}

/// Field order for the Study (recall) note type. Front/Back carry the card; the
/// three provenance fields mirror `tbs_fields` so Phase-2a RAG-generated recall
/// cards can record where the card came from. Hand-authored seed recall cards
/// leave the provenance fields blank (see `seed.rs`); the ordinal constants are
/// reserved for the Phase-2a population path and asserted by the tests.
pub(crate) mod study_fields {
    #[allow(dead_code)]
    pub(crate) const FRONT: usize = 0;
    #[allow(dead_code)]
    pub(crate) const BACK: usize = 1;
    #[allow(dead_code)]
    pub(crate) const SOURCE_PASSAGE: usize = 2;
    #[allow(dead_code)]
    pub(crate) const GEN_METHOD: usize = 3;
    #[allow(dead_code)]
    pub(crate) const CHECKER_STATUS: usize = 4;
    pub(crate) const NAMES: &[&str] = &[
        "Front",
        "Back",
        "source_passage",
        "gen_method",
        "checker_status",
    ];
}

fn build_hidden_notetype(name: &str, field_names: &[&str]) -> Notetype {
    let mut nt = Notetype {
        name: name.to_string(),
        ..Default::default()
    };
    nt.config = Notetype::new_config();
    for f in field_names {
        nt.add_field(*f);
    }
    // A single minimal template so the note type passes validation. These notes
    // are never studied (hidden note type / suspended or never-queued deck), so
    // the rendering is irrelevant, but a valid q/a referencing the first field
    // is required.
    let first = field_names[0];
    nt.add_template(
        "Card 1",
        format!("{{{{{first}}}}}"),
        format!("{{{{FrontSide}}}}\n\n<hr id=answer>\n\n{{{{{first}}}}}"),
    );
    nt
}

impl Collection {
    /// Fetch (creating on first use) the Attempt Log note type.
    pub(crate) fn ankountant_attempt_log_notetype(&mut self) -> Result<Arc<Notetype>> {
        self.get_or_create_hidden_notetype(ATTEMPT_LOG_NOTETYPE, attempt_fields::NAMES)
    }

    /// Fetch (creating on first use) the TBS note type.
    /// Used by the seed builder + tests.
    pub(crate) fn ankountant_tbs_notetype(&mut self) -> Result<Arc<Notetype>> {
        self.get_or_create_hidden_notetype(TBS_NOTETYPE, tbs_fields::NAMES)
    }

    /// Fetch (creating on first use) the study-recall note type. Front/Back
    /// carry the card; three provenance fields (source_passage / gen_method /
    /// checker_status) mirror `tbs_fields` so Phase-2a RAG-generated recall
    /// cards can carry provenance. Hand-authored seed recall cards leave those
    /// blank. Adding fields to the note type is sync-safe (an ordinary object
    /// change — no new SQLite table/column). Unlike the others, its cards ARE
    /// queued for normal FSRS study, so a valid Front→Back template is used.
    pub(crate) fn ankountant_study_notetype(&mut self) -> Result<Arc<Notetype>> {
        self.get_or_create_hidden_notetype(STUDY_NOTETYPE, study_fields::NAMES)
    }

    /// Fetch (creating on first use) the Settings note type (sync-safe per-key
    /// settings store; see `settings.rs`).
    pub(crate) fn ankountant_settings_notetype(&mut self) -> Result<Arc<Notetype>> {
        self.get_or_create_hidden_notetype(SETTINGS_NOTETYPE, settings_fields::NAMES)
    }

    fn get_or_create_hidden_notetype(
        &mut self,
        name: &str,
        field_names: &[&str],
    ) -> Result<Arc<Notetype>> {
        if let Some(nt) = self.get_notetype_by_name(name)? {
            return Ok(nt);
        }
        let mut nt = build_hidden_notetype(name, field_names);
        self.add_notetype(&mut nt, true)?;
        self.get_notetype(nt.id)?.or_not_found(NotetypeId(nt.id.0))
    }

    /// Non-transacting variant of `get_or_create_normal_deck`, safe to call
    /// from inside an existing transaction (seed + attempt-log writers).
    pub(crate) fn ankountant_get_or_create_deck_inner(
        &mut self,
        human_name: &str,
    ) -> Result<DeckId> {
        let name = NativeDeckName::from_human_name(human_name);
        if let Some(did) = self.storage.get_deck_id(name.as_native_str())? {
            return Ok(did);
        }
        let usn = self.usn()?;
        let mut deck = Deck::new_normal();
        deck.name = name;
        self.add_deck_inner(&mut deck, usn)?;
        Ok(deck.id)
    }
}
