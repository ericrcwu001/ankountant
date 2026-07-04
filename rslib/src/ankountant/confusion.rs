// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! A3 — the confusion-set queue builder. Produces a label-stripped, interleaved
//! ordering that (a) mixes different `ds::` tags within a set, and (b) orders
//! sets by discrimination weakness (lowest per-set Attempt-Log accuracy first).

use std::collections::HashMap;

use anki_proto::scheduler::BuildConfusionQueueResponse;
use anki_proto::scheduler::ConfusionItem;

use super::logic;
use super::notetypes::tbs_fields;
use crate::prelude::*;

/// An item gathered for the confusion queue before interleaving.
struct RawItem {
    note_id: NoteId,
    prompt: String,
    tag: String,
    set_id: String,
}

impl Collection {
    /// A3 — build the confusion queue for a section.
    pub(crate) fn ankountant_build_confusion_queue(
        &mut self,
        section: &str,
        max_items: i32,
    ) -> Result<BuildConfusionQueueResponse> {
        if all_sections_requested(section) {
            let queues = super::SECTIONS
                .iter()
                .map(|section| self.build_confusion_queue_for_section(section))
                .collect::<Result<Vec<_>>>()?;
            let mut items = round_robin(queues);
            truncate(&mut items, max_items);
            return Ok(BuildConfusionQueueResponse { items });
        }

        let mut items = self.build_confusion_queue_for_section(section)?;
        truncate(&mut items, max_items);
        Ok(BuildConfusionQueueResponse { items })
    }

    fn build_confusion_queue_for_section(&mut self, section: &str) -> Result<Vec<ConfusionItem>> {
        let map = self.ankountant_confusable_map(section);
        if map.is_empty() {
            return Ok(vec![]);
        }

        // Per-set discrimination accuracy from confusion-mode Attempt Log notes.
        let accuracy = self.ankountant_set_accuracy(section)?;

        // Order sets by weakness (lowest accuracy first). Unseen sets (no
        // attempts) sort last-ish at accuracy 1.0 tie-broken by set id, so that
        // a demonstrably weak set is always practised before a strong one.
        let mut set_ids: Vec<String> = map.keys().cloned().collect();
        set_ids.sort_by(|a, b| {
            let aa = accuracy.get(a).copied().unwrap_or(1.0);
            let ba = accuracy.get(b).copied().unwrap_or(1.0);
            aa.partial_cmp(&ba)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| a.cmp(b))
        });

        let mut items: Vec<ConfusionItem> = Vec::new();
        for set_id in &set_ids {
            let set = &map[set_id];
            let raws = self.gather_set_items(section, set_id, set)?;
            if raws.is_empty() {
                continue;
            }
            // Interleave within the set so no tag runs 3+ in a row.
            let tags: Vec<String> = raws.iter().map(|r| r.tag.clone()).collect();
            let order = logic::interleave_by_tag(&tags);
            for idx in order {
                let raw = &raws[idx];
                items.push(ConfusionItem {
                    note_id: raw.note_id.0,
                    prompt: raw.prompt.clone(),
                    treatments: set.treatments.clone(),
                    set_id: raw.set_id.clone(),
                    // NOTE: no category/topic/deck label field — the DTO is
                    // label-stripped by construction (A3 AC3 / B2).
                });
            }
        }
        Ok(items)
    }

    /// Mean confusion-mode accuracy per set_id from the Attempt Log (A3 AC2).
    fn ankountant_set_accuracy(&mut self, section: &str) -> Result<HashMap<String, f64>> {
        let attempts = self.ankountant_attempts(section)?;
        let mut sums: HashMap<String, (f64, u32)> = HashMap::new();
        for a in attempts.into_iter().filter(|a| a.mode == "confusion") {
            let entry = sums.entry(a.confusion_set_id).or_insert((0.0, 0));
            entry.0 += if a.outcome.credit >= 0.5 { 1.0 } else { 0.0 };
            entry.1 += 1;
        }
        Ok(sums
            .into_iter()
            .filter(|(_, (_, n))| *n > 0)
            .map(|(k, (correct, n))| (k, correct / n as f64))
            .collect())
    }

    /// Gather the sealed items for a confusion set, tagged by their `ds::` tag.
    fn gather_set_items(
        &mut self,
        section: &str,
        set_id: &str,
        set: &super::config::ConfusionSet,
    ) -> Result<Vec<RawItem>> {
        let mut out = Vec::new();
        for tag in &set.tags {
            // Sealed items on this tag (firewall bank, A7).
            let search = format!("tag:{tag} deck:Ankountant::Sealed::{section}::*");
            let nids = self.search_notes_unordered(search.as_str())?;
            for nid in nids {
                let Some(note) = self.storage.get_note(nid)? else {
                    continue;
                };
                let prompt = self.item_prompt(&note);
                out.push(RawItem {
                    note_id: nid,
                    prompt,
                    tag: tag.clone(),
                    set_id: set_id.to_string(),
                });
            }
        }
        Ok(out)
    }

    /// Extract a client-facing prompt from a note without leaking labels.
    fn item_prompt(&mut self, note: &Note) -> String {
        // TBS notes carry a dedicated prompt field; other notes use field 0.
        if let Ok(Some(nt)) = self.get_notetype(note.notetype_id) {
            if nt.name == super::notetypes::TBS_NOTETYPE {
                return note
                    .fields()
                    .get(tbs_fields::PROMPT)
                    .cloned()
                    .unwrap_or_default();
            }
        }
        note.fields().first().cloned().unwrap_or_default()
    }
}

fn all_sections_requested(section: &str) -> bool {
    let section = section.trim();
    section == "*" || section.eq_ignore_ascii_case("ALL")
}

fn truncate(items: &mut Vec<ConfusionItem>, max_items: i32) {
    if max_items > 0 && items.len() > max_items as usize {
        items.truncate(max_items as usize);
    }
}

fn round_robin(queues: Vec<Vec<ConfusionItem>>) -> Vec<ConfusionItem> {
    let total = queues.iter().map(Vec::len).sum();
    let mut positions = vec![0; queues.len()];
    let mut out = Vec::with_capacity(total);
    while out.len() < total {
        let before = out.len();
        for (idx, queue) in queues.iter().enumerate() {
            if positions[idx] < queue.len() {
                out.push(queue[positions[idx]].clone());
                positions[idx] += 1;
            }
        }
        if out.len() == before {
            break;
        }
    }
    out
}
