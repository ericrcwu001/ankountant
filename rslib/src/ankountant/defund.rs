// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! A2 — latency-aware "too-easy" defunding for stable rote cards. After an
//! answer we set/clear the card's `cd.te` flag (consumed by the live scheduler
//! in `scheduler::answering::card_state_updater`) and fold the answer latency
//! into a rote cohort EMA baseline. All state lives in card `custom_data` +
//! `col` config, so it syncs natively with no new tables/columns (FR-5).

use super::config::latency_rote_key;
use super::constants;
use super::logic;
use super::TAG_COG_ROTE;
use crate::card::CardType;
use crate::prelude::*;
use crate::revlog::RevlogReviewKind;

impl Collection {
    /// A2 — after an answer on an Ankountant study card, set/clear the too-easy
    /// flag and update the rote latency cohort baseline. `pre_answer` is the
    /// card as it was shown (its interval decides "stable"); `card` is the
    /// post-answer card whose `custom_data` we mutate. Rote cards only.
    ///
    /// Must run inside the answer transaction (it writes `col` config).
    pub(crate) fn ankountant_apply_latency_defund(
        &mut self,
        card: &mut Card,
        pre_answer: &Card,
        rating: u8,
        taken_millis: u32,
    ) -> Result<()> {
        if !self.ankountant_note_is_rote(card.note_id)? {
            // A2 AC2 — a non-rote card must never carry the flag.
            self.set_card_too_easy(card, false)?;
            return Ok(());
        }

        let baseline_ms = self.ankountant_rote_latency_baseline(pre_answer.id)?;
        let confidence = logic::custom_data_confidence(&card.custom_data);
        let defund = logic::too_easy_defund(
            pre_answer.interval,
            taken_millis,
            baseline_ms,
            confidence.as_deref(),
            rating,
            true,
        );
        self.set_card_too_easy(card, defund)?;

        // Fold this answer's latency into the cohort baseline (recall reps only).
        if matches!(pre_answer.ctype, CardType::Review | CardType::Relearn) {
            self.ankountant_update_rote_latency_ema(taken_millis)?;
        }
        Ok(())
    }

    /// Set or clear the card's `cd.te` flag, revalidating when it changes.
    fn set_card_too_easy(&self, card: &mut Card, too_easy: bool) -> Result<()> {
        let updated = if too_easy {
            logic::custom_data_with_te(&card.custom_data)
        } else {
            logic::custom_data_without_te(&card.custom_data)
        };
        if updated != card.custom_data {
            card.custom_data = updated;
            card.validate_custom_data()?;
        }
        Ok(())
    }

    /// The A2 latency baseline (ms): the median of the card's trailing recall
    /// latencies once it has >= MIN_OWN_REPS_FOR_BASELINE own reps, else the
    /// rote cohort EMA, else 0.0 (no baseline yet -> the predicate can't fire).
    fn ankountant_rote_latency_baseline(&self, card_id: CardId) -> Result<f64> {
        let own = self.ankountant_trailing_recall_latencies(card_id)?;
        if own.len() >= constants::MIN_OWN_REPS_FOR_BASELINE {
            Ok(median(&own))
        } else {
            Ok(self.ankountant_rote_latency_ema().unwrap_or(0.0))
        }
    }

    /// The trailing (up to LATENCY_TRAILING_WINDOW) recall-rep latencies (ms)
    /// for a card, excluding the just-written current answer and manual
    /// reschedules, so the baseline reflects prior reps only.
    fn ankountant_trailing_recall_latencies(&self, card_id: CardId) -> Result<Vec<u32>> {
        let mut entries: Vec<_> = self
            .storage
            .get_revlog_entries_for_card(card_id)?
            .into_iter()
            .filter(|e| {
                e.button_chosen > 0
                    && matches!(
                        e.review_kind,
                        RevlogReviewKind::Review | RevlogReviewKind::Relearning
                    )
            })
            .collect();
        entries.sort_by_key(|e| e.id.0);
        // Drop the newest recall rep: the current answer was written before this.
        entries.pop();
        let start = entries
            .len()
            .saturating_sub(constants::LATENCY_TRAILING_WINDOW);
        Ok(entries[start..].iter().map(|e| e.taken_millis).collect())
    }

    pub(crate) fn ankountant_rote_latency_ema(&self) -> Option<f64> {
        self.get_config_optional(latency_rote_key())
    }

    /// Fold `taken_millis` into the rote latency cohort EMA (seed on first use).
    /// Non-transactional: must run inside an existing transaction.
    fn ankountant_update_rote_latency_ema(&mut self, taken_millis: u32) -> Result<()> {
        let sample = taken_millis as f64;
        let next = match self.ankountant_rote_latency_ema() {
            Some(prev) => {
                let a = constants::LATENCY_EMA_ALPHA;
                a * sample + (1.0 - a) * prev
            }
            None => sample,
        };
        self.set_config(latency_rote_key(), &next)?;
        Ok(())
    }

    fn ankountant_note_is_rote(&self, note_id: NoteId) -> Result<bool> {
        let Some(note) = self.storage.get_note(note_id)? else {
            return Ok(false);
        };
        Ok(note.tags.iter().any(|t| t == TAG_COG_ROTE))
    }
}

fn median(values: &[u32]) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    let mut v = values.to_vec();
    v.sort_unstable();
    let mid = v.len() / 2;
    if v.len() % 2 == 0 {
        (v[mid - 1] as f64 + v[mid] as f64) / 2.0
    } else {
        v[mid] as f64
    }
}
