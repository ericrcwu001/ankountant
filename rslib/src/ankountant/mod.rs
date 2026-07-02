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
pub(crate) mod logic;
pub(crate) mod notetypes;
pub(crate) mod readiness;
pub(crate) mod schedule;
pub(crate) mod seed;
pub(crate) mod service;
#[cfg(test)]
mod tests;

/// The default section for the MVP.
pub(crate) const DEFAULT_SECTION: &str = "FAR";

/// Cognitive-demand tags (A6). Stored as native Anki tags.
pub(crate) const TAG_COG_ROTE: &str = "cog::rote";
pub(crate) const TAG_COG_APPLIED: &str = "cog::applied";
