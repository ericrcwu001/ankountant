// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Sync-safe `col` config storage for Ankountant (FR-5): the CONFUSABLE map and
//! the cached readiness rollup live under `ankountant.<section>.*` config JSON
//! keys — no new SQLite tables/columns.
//!
//! NOTE: the **exam date** used to live here too, but `col` config syncs as one
//! whole-blob, last-writer-wins snapshot, so an exam date edited on one device
//! could be silently clobbered by unrelated activity on another. It now lives
//! in a per-object "Ankountant Settings" note (see `settings.rs`) that merges
//! by USN; the legacy config key below is only read as a migration fallback.

use std::collections::BTreeMap;

use serde::Deserialize;
use serde::Serialize;

use crate::prelude::*;

/// Legacy `ankountant.<section>.exam.date` config key — ISO-8601 (YYYY-MM-DD).
/// Read-only migration fallback for collections written before the exam date
/// moved to a sync-safe Settings note; new writes go through the note.
pub(crate) fn exam_date_key(section: &str) -> String {
    format!("ankountant.{section}.exam.date")
}

/// The Settings-note key (see `settings.rs`) under which the exam date is
/// stored per section.
pub(crate) const EXAM_DATE_SETTING_KEY: &str = "exam.date";

/// `ankountant.confusable.<section>` — the CONFUSABLE map (A3/A6): set_id ->
/// {tags, treatments}. `set_id` is derived from a note's `ds::` tag via this
/// map; it is never stored per note.
pub(crate) fn confusable_key(section: &str) -> String {
    format!("ankountant.confusable.{section}")
}

/// `ankountant.readiness.<section>` — cache key for the 3-score rollup (A4).
/// The rollup is currently recomputed on demand; this key reserves the
/// namespace for the cached manifest (Reader-precedent, forward-compat).
#[allow(dead_code)]
pub(crate) fn readiness_key(section: &str) -> String {
    format!("ankountant.readiness.{section}")
}

/// `ankountant.latency.rote` — cohort-wide EMA (milliseconds) of rote-card
/// recall latency. A2 uses it as the latency baseline until a card has enough
/// own reps to trust its trailing median (see `defund`).
pub(crate) fn latency_rote_key() -> &'static str {
    "ankountant.latency.rote"
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(crate) struct ConfusionSet {
    #[serde(default)]
    pub(crate) tags: Vec<String>,
    #[serde(default)]
    pub(crate) treatments: Vec<String>,
}

/// The CONFUSABLE map keyed by set_id, kept in a BTreeMap for deterministic
/// ordering when no accuracy signal breaks ties.
pub(crate) type ConfusableMap = BTreeMap<String, ConfusionSet>;

impl Collection {
    pub(crate) fn ankountant_confusable_map(&self, section: &str) -> ConfusableMap {
        self.get_config_optional(confusable_key(section).as_str())
            .unwrap_or_default()
    }

    /// A1 — the section's exam date (ISO-8601), or `None`. Reads the sync-safe
    /// Settings note (newest wins), falling back to the legacy `col` config key
    /// for collections written before the note-based store. Takes `&mut self`
    /// because reading the note requires a search.
    pub(crate) fn ankountant_exam_date(&mut self, section: &str) -> Result<Option<String>> {
        if let Some(v) = self.ankountant_get_setting(section, EXAM_DATE_SETTING_KEY)? {
            let v = v.trim().to_string();
            return Ok((!v.is_empty()).then_some(v));
        }
        // Legacy fallback: pre-migration collections stored it in col config.
        let legacy: Option<String> = self.get_config_optional(exam_date_key(section).as_str());
        Ok(legacy.and_then(|v| {
            let v = v.trim().to_string();
            (!v.is_empty()).then_some(v)
        }))
    }

    /// A1 — persist the section's exam date (ISO-8601; empty clears it) to the
    /// sync-safe Settings note. A lingering legacy config key, if any, is
    /// ignored on read once a note exists, so no explicit migration write is
    /// needed.
    pub(crate) fn ankountant_set_exam_date(&mut self, section: &str, date: &str) -> Result<()> {
        self.ankountant_set_setting(section, EXAM_DATE_SETTING_KEY, date.trim())
    }

    /// Resolve a `ds::` tag to its confusion set_id, if the map assigns one.
    pub(crate) fn ankountant_set_for_tag(map: &ConfusableMap, tag: &str) -> Option<String> {
        map.iter()
            .find(|(_, set)| set.tags.iter().any(|t| t == tag))
            .map(|(id, _)| id.clone())
    }
}
