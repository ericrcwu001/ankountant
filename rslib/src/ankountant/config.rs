// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Sync-safe `col` config storage for Ankountant (FR-5): the exam date, the
//! CONFUSABLE map, and the cached readiness rollup all live under
//! `ankountant.<section>.*` config JSON keys — no new SQLite tables/columns.

use std::collections::BTreeMap;

use serde::Deserialize;
use serde::Serialize;

use crate::prelude::*;

/// `ankountant.<section>.exam.date` — ISO-8601 (YYYY-MM-DD) exam date. Stored
/// via the standard config-set RPC; there is no dedicated setter (A1 note).
pub(crate) fn exam_date_key(section: &str) -> String {
    format!("ankountant.{section}.exam.date")
}

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

    pub(crate) fn ankountant_exam_date(&self, section: &str) -> Option<String> {
        self.get_config_optional(exam_date_key(section).as_str())
    }

    /// Resolve a `ds::` tag to its confusion set_id, if the map assigns one.
    pub(crate) fn ankountant_set_for_tag(map: &ConfusableMap, tag: &str) -> Option<String> {
        map.iter()
            .find(|(_, set)| set.tags.iter().any(|t| t == tag))
            .map(|(id, _)| id.clone())
    }
}
