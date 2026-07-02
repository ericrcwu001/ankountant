// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Sync-safe per-(section, key) settings, stored as hidden "Ankountant
//! Settings" notes rather than `col` config.
//!
//! Anki syncs `col` config as a single whole-blob, last-writer-wins snapshot
//! (see [`crate::sync::collection::changes`]: `changed_config` sends *all*
//! config when the local collection is newer, and the peer replaces its config
//! wholesale). That means a value edited on one device can be silently
//! clobbered by *unrelated* activity on another. Notes, by contrast, sync
//! per-object by USN and merge cleanly.
//!
//! So each `set` APPENDS a value note and each `get` returns the newest by
//! `updated_at`: concurrent offline edits converge on "latest write wins" with
//! no collateral loss of other settings. Exam date (A1) is the first consumer.

use anki_proto::scheduler::bury_or_suspend_cards_request::Mode as BuryOrSuspendMode;

use super::attempt_log::ATTEMPT_LOG_DECK;
use super::notetypes::settings_fields as f;
use super::notetypes::SETTINGS_NOTETYPE;
use crate::ops::Op;
use crate::prelude::*;

impl Collection {
    /// The newest value stored for (section, key), or `None`. Read-only.
    pub(crate) fn ankountant_get_setting(
        &mut self,
        section: &str,
        key: &str,
    ) -> Result<Option<String>> {
        let Some(nt) = self.get_notetype_by_name(SETTINGS_NOTETYPE)? else {
            return Ok(None);
        };
        let nids = self.search_notes_unordered(nt.id)?;
        // Newest wins, keyed by (updated_at_ms, note_id) so consecutive
        // sub-second sets — and cross-device ties — resolve deterministically.
        let mut best: Option<((i64, i64), String)> = None;
        for nid in nids {
            let Some(note) = self.storage.get_note(nid)? else {
                continue;
            };
            let fields = note.fields();
            if fields.get(f::SECTION).map(String::as_str) != Some(section)
                || fields.get(f::KEY).map(String::as_str) != Some(key)
            {
                continue;
            }
            let updated = fields
                .get(f::UPDATED_AT)
                .and_then(|s| s.parse::<i64>().ok())
                .unwrap_or(0);
            let rank = (updated, nid.0);
            if best.as_ref().map(|(r, _)| rank > *r).unwrap_or(true) {
                best = Some((rank, fields.get(f::VALUE).cloned().unwrap_or_default()));
            }
        }
        Ok(best.map(|(_, v)| v))
    }

    /// Append a (section, key) = value setting note (transactional). Because
    /// reads take the newest by `updated_at`, this is a merge-safe "set".
    pub(crate) fn ankountant_set_setting(
        &mut self,
        section: &str,
        key: &str,
        value: &str,
    ) -> Result<()> {
        // Ensure the note type exists before the write transaction (its own
        // creation is transactional; nesting would panic).
        self.ankountant_settings_notetype()?;
        self.transact(Op::AddNote, |col| {
            col.ankountant_write_setting(section, key, value)
        })?;
        Ok(())
    }

    fn ankountant_write_setting(&mut self, section: &str, key: &str, value: &str) -> Result<()> {
        let nt = self.ankountant_settings_notetype()?;
        let deck_id = self.ankountant_get_or_create_deck_inner(ATTEMPT_LOG_DECK)?;
        let mut note = nt.new_note();
        note.set_field(f::SECTION, section)?;
        note.set_field(f::KEY, key)?;
        note.set_field(f::VALUE, value)?;
        note.set_field(f::UPDATED_AT, TimestampMillis::now().0.to_string())?;
        self.add_note_inner(&mut note, deck_id)?;

        // Suspend the generated card so the study scheduler never serves this
        // hidden note (same firewall the Attempt Log uses).
        let cids = self.storage.card_ids_of_notes(&[note.id])?;
        let cards = self.all_cards_for_ids(&cids, false)?;
        self.bury_or_suspend_cards_inner(cards, BuryOrSuspendMode::Suspend)?;
        Ok(())
    }
}
