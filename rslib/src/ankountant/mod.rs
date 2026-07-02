// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Ankountant FAR MVP shared-core (Phase A: A1–A10 + FAR seed).
//!
//! Everything here is built on ordinary Anki objects (notes, cards, tags,
//! decks, `col` config JSON) so it syncs natively with no new SQLite
//! tables/columns (FR-5). The four new RPCs are appended to `SchedulerService`
//! and implemented in [`service`].

#[cfg(test)]
mod ablation;
pub(crate) mod attempt_log;
pub(crate) mod config;
pub(crate) mod confusion;
pub(crate) mod constants;
pub(crate) mod defund;
#[cfg(test)]
mod determinism;
#[cfg(test)]
mod evidence;
pub(crate) mod grading;
pub(crate) mod literature;
pub(crate) mod logic;
pub(crate) mod notetypes;
pub(crate) mod readiness;
pub(crate) mod schedule;
pub(crate) mod seed;
pub(crate) mod service;
#[cfg(test)]
mod tests;

/// The default section, used for items that predate the section dimension
/// (ADR 0008) so an untagged note still resolves to a valid section.
pub(crate) const DEFAULT_SECTION: &str = "FAR";

/// The CPA sections the section-agnostic TBS engine covers (ADR 0008 / D8). The
/// four TBS shapes are identical across all six; only the content, the
/// authoritative-literature body, and shape prevalence differ.
pub(crate) const SECTIONS: [&str; 6] = ["AUD", "FAR", "REG", "BAR", "ISC", "TCP"];

/// Native note-tag prefix that carries an item's `section` (D8). Sync-safe: it
/// is an ordinary tag, no new SQLite column. E.g. `sec::AUD`.
pub(crate) const SEC_TAG_PREFIX: &str = "sec::";

/// Resolve a TBS note's section from its `sec::<SECTION>` tag, falling back to
/// [`DEFAULT_SECTION`] for pre-section-dimension notes.
pub(crate) fn note_section(tags: &[String]) -> String {
    tags.iter()
        .find_map(|t| t.strip_prefix(SEC_TAG_PREFIX))
        .filter(|s| SECTIONS.contains(s))
        .map(|s| s.to_string())
        .unwrap_or_else(|| DEFAULT_SECTION.to_string())
}

/// Cognitive-demand tags (A6). Stored as native Anki tags.
pub(crate) const TAG_COG_ROTE: &str = "cog::rote";
pub(crate) const TAG_COG_APPLIED: &str = "cog::applied";
