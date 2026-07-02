// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! A1 — deadline-anchored scheduler. `ComputeExamSchedule` reads the exam date
//! (col config), ramps the desired retention toward exam day, and previews each
//! study card's next interval by feeding that retention through the *existing*
//! FSRS `next_states` (no post-multiply — FR/BUILD_NOTES).

use anki_proto::scheduler::CardSchedulePreview;
use anki_proto::scheduler::ComputeExamScheduleResponse;
use chrono::Local;
use chrono::NaiveDate;
use fsrs::FSRS;

use super::logic;
use crate::card::CardQueue;
use crate::prelude::*;
use crate::search::SortMode;

/// Parse an ISO-8601 (YYYY-MM-DD) date and return days from today (local),
/// negative if in the past.
pub(crate) fn days_to_exam(iso_date: &str) -> Option<i64> {
    let exam = NaiveDate::parse_from_str(iso_date.trim(), "%Y-%m-%d").ok()?;
    let today = Local::now().date_naive();
    Some((exam - today).num_days())
}

/// A1-live/A2 — derive the section from a deck's human name when it is an
/// `Ankountant::Study::<section>::…` study deck (the only decks the live
/// deadline ramp and latency-defunding touch). `None` for every other deck, so
/// normal Anki decks keep stock FSRS scheduling.
pub(crate) fn section_for_deck_name(human_name: &str) -> Option<String> {
    let rest = human_name.strip_prefix("Ankountant::Study::")?;
    let section = rest.split("::").next()?;
    (!section.is_empty()).then(|| section.to_string())
}

impl Collection {
    /// A1 — resolve the desired retention for a section: the deadline ramp when
    /// an exam date is set (or an explicit `exam_date` preview override),
    /// otherwise the deck/preset configured value (open-horizon fallback).
    pub(crate) fn ankountant_desired_retention(
        &mut self,
        section: &str,
        exam_date_override: &str,
    ) -> Result<f64> {
        let date = if exam_date_override.trim().is_empty() {
            self.ankountant_exam_date(section)
        } else {
            Some(exam_date_override.to_string())
        };
        match date.as_deref().and_then(days_to_exam) {
            Some(days) => Ok(logic::exam_desired_retention(days)),
            // Open horizon: fall back to the default preset's configured value.
            None => {
                let config = self
                    .storage
                    .get_deck_config(DeckConfigId(1))?
                    .unwrap_or_default();
                Ok(config.inner.desired_retention as f64)
            }
        }
    }

    /// A1 — full `ComputeExamSchedule` preview: the ramped retention plus a
    /// per-card next-interval estimate for the section's study cards.
    pub(crate) fn ankountant_compute_exam_schedule(
        &mut self,
        section: &str,
        exam_date_override: &str,
    ) -> Result<ComputeExamScheduleResponse> {
        let desired_retention = self.ankountant_desired_retention(section, exam_date_override)?;

        // Preview intervals for the section's non-suspended review cards.
        let search = format!("deck:Ankountant::Study::{section}::* -is:suspended");
        let cids = self
            .search_cards(search.as_str(), SortMode::NoOrder)
            .unwrap_or_default();

        let mut previews = Vec::new();
        for cid in cids {
            let Some(card) = self.storage.get_card(cid)? else {
                continue;
            };
            if card.queue == CardQueue::Suspended {
                continue;
            }
            let interval = self.preview_interval_for_card(&card, desired_retention as f32)?;
            previews.push(CardSchedulePreview {
                card_id: cid.0,
                next_interval_days: interval,
            });
        }

        Ok(ComputeExamScheduleResponse {
            desired_retention,
            cards: previews,
        })
    }

    /// Preview the "Good" next interval for a card at a given desired
    /// retention, through the real FSRS `next_states`. Read-only.
    pub(crate) fn preview_interval_for_card(
        &mut self,
        card: &Card,
        desired_retention: f32,
    ) -> Result<i32> {
        let config = self
            .storage
            .get_deck_config(DeckConfigId(1))?
            .unwrap_or_default();
        let params = config.fsrs_params();
        let fsrs = FSRS::new(Some(params))?;
        let days_elapsed = card
            .last_review_time
            .map(|t| TimestampSecs::now().elapsed_days_since(t) as u32)
            .unwrap_or(0);
        let states = fsrs.next_states(
            card.memory_state.map(Into::into),
            desired_retention,
            days_elapsed,
        )?;
        Ok(states.good.interval.round().max(1.0) as i32)
    }

    /// Test/preview helper: the "Good" next interval a hypothetical stable card
    /// (given memory state) would receive at `desired_retention`.
    #[cfg(test)]
    pub(crate) fn ankountant_preview_interval_for_memory(
        &mut self,
        stability: f32,
        difficulty: f32,
        desired_retention: f32,
    ) -> Result<f32> {
        let config = self
            .storage
            .get_deck_config(DeckConfigId(1))?
            .unwrap_or_default();
        let fsrs = FSRS::new(Some(config.fsrs_params()))?;
        let states = fsrs.next_states(
            Some(fsrs::MemoryState {
                stability,
                difficulty,
            }),
            desired_retention,
            0,
        )?;
        Ok(states.good.interval)
    }
}
