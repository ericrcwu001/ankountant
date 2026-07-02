// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! T2 / D10 — the build-embedded, per-section authoritative-literature corpus.
//!
//! One loader, multiple bodies (ADR 0008 / ADR 0006):
//!
//! - **FAR / BAR** (FASB ASC) — `verbatim = false`: the committed `body` is OUR
//!   paraphrase plus a `deep_link` to `asc.fasb.org`. Verbatim ASC prose is
//!   NEVER committed (the Tier-B firewall). A runtime overlay can layer real
//!   excerpts from the uncommitted Anki media folder if the user drops them in.
//! - **REG / TCP** (IRC / Treasury / IRS), **AUD** (PCAOB / SEC eCFR), **ISC**
//!   (NIST) — `verbatim = true`: these bodies are U.S. public domain, so the
//!   committed `body` IS the real text.
//!
//! Search is client-side over this data (OQ-3); the backend only serves the
//! corpus (data-only, no `SearchLiterature` RPC).
//!
//! The loader interface is consumed by the desktop/iOS research surfaces
//! (Workstream B/C) and the test suite; it is `#[allow(dead_code)]` here
//! because Workstream A ships only the data + loader, not yet a caller in the
//! library.

#![allow(dead_code)]

use std::collections::BTreeMap;

use serde::Deserialize;
use serde::Serialize;

use crate::prelude::*;

/// The committed corpus, embedded at build time (zero sync bytes). Keyed by
/// section (`FAR`, `AUD`, …) → its passages.
const SEED_LITERATURE_JSON: &str = include_str!("seed_literature.json");

/// The file (under the uncommitted Anki media folder) an advanced user can drop
/// in to overlay real verbatim excerpts onto the cite-only (ASC) bodies. Shape:
/// `{ "<SECTION>": { "<passage id or citation>": "<verbatim excerpt>" } }`.
const OVERLAY_FILE: &str = "_ankountant_literature.json";

/// One authoritative-literature passage the research/doc-review surfaces cite.
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub(crate) struct LiteraturePassage {
    /// Stable corpus id (referenced by a research step's `corpus_refs`).
    pub(crate) id: String,
    /// The authoritative citation, e.g. `ASC 842-20-25-1`, `IRC §162(a)`.
    pub(crate) citation: String,
    pub(crate) title: String,
    /// Cite-only: OUR paraphrase. Public-domain: the real verbatim text.
    pub(crate) body: String,
    /// Deep link to the authority (e.g. `asc.fasb.org`, `law.cornell.edu`).
    #[serde(default)]
    pub(crate) deep_link: String,
    #[serde(default)]
    pub(crate) tags: Vec<String>,
    /// True when `body` is real public-domain text; false for cite-only bodies.
    #[serde(default)]
    pub(crate) verbatim: bool,
    #[serde(default)]
    pub(crate) source: String,
    /// Runtime-only: a verbatim excerpt layered from the uncommitted media
    /// overlay (ADR 0006). NEVER present in the committed corpus for cite-only
    /// bodies — the firewall test asserts this.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) overlay_excerpt: Option<String>,
}

type Corpus = BTreeMap<String, Vec<LiteraturePassage>>;

/// Parse the whole committed corpus (panics on a malformed embedded file, like
/// `seed_content.json`).
pub(crate) fn committed_corpus() -> Corpus {
    serde_json::from_str(SEED_LITERATURE_JSON).expect("embedded seed_literature.json must parse")
}

/// The committed passages for one section (empty if the section is unseeded).
pub(crate) fn committed_corpus_for_section(section: &str) -> Vec<LiteraturePassage> {
    committed_corpus().remove(section).unwrap_or_default()
}

impl Collection {
    /// The literature corpus for a section: the committed passages, plus (for
    /// cite-only ASC bodies) any verbatim excerpts the user has dropped into
    /// the uncommitted media overlay. Data-only; search is client-side.
    pub(crate) fn ankountant_literature(&self, section: &str) -> Result<Vec<LiteraturePassage>> {
        let mut passages = committed_corpus_for_section(section);
        self.overlay_media_excerpts(section, &mut passages);
        Ok(passages)
    }

    /// Best-effort overlay: if `<media>/_ankountant_literature.json` exists and
    /// parses, layer its verbatim excerpts onto matching passages (matched by
    /// id, else by normalized citation). Silently ignored when absent/malformed
    /// so a missing overlay never breaks the cite-only corpus.
    fn overlay_media_excerpts(&self, section: &str, passages: &mut [LiteraturePassage]) {
        let path = self.media_folder.join(OVERLAY_FILE);
        let Ok(text) = std::fs::read_to_string(&path) else {
            return;
        };
        let Ok(overlay) = serde_json::from_str::<BTreeMap<String, BTreeMap<String, String>>>(&text)
        else {
            return;
        };
        let Some(section_overlay) = overlay.get(section) else {
            return;
        };
        for p in passages.iter_mut() {
            if let Some(excerpt) = section_overlay.get(&p.id) {
                p.overlay_excerpt = Some(excerpt.clone());
            } else if let Some((_, excerpt)) = section_overlay
                .iter()
                .find(|(k, _)| super::logic::citation_matches(k, &p.citation))
            {
                p.overlay_excerpt = Some(excerpt.clone());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_seeded_section_has_a_corpus() {
        let corpus = committed_corpus();
        for section in ["FAR", "AUD", "REG"] {
            assert!(
                corpus.get(section).is_some_and(|v| !v.is_empty()),
                "section {section} should have committed literature"
            );
        }
    }

    #[test]
    fn cite_only_sections_never_commit_verbatim_prose() {
        // Tier-B firewall (ADR 0006): FASB-ASC sections carry paraphrase + link
        // ONLY — never verbatim text, and never a committed overlay excerpt.
        let corpus = committed_corpus();
        for section in ["FAR", "BAR"] {
            for p in corpus.get(section).into_iter().flatten() {
                assert!(!p.verbatim, "{}: ASC body must not be verbatim", p.citation);
                assert!(
                    p.overlay_excerpt.is_none(),
                    "{}: committed corpus must not ship an overlay excerpt",
                    p.citation
                );
                assert!(
                    p.deep_link.contains("asc.fasb.org"),
                    "{}: cite-only body must carry an ASC deep link",
                    p.citation
                );
                assert!(
                    !p.body.trim().is_empty(),
                    "{}: empty paraphrase",
                    p.citation
                );
            }
        }
    }

    #[test]
    fn public_domain_sections_bundle_real_text() {
        // D10: IRC / PCAOB / NIST bodies are public domain, bundled verbatim.
        let corpus = committed_corpus();
        for section in ["REG", "AUD", "ISC", "TCP"] {
            for p in corpus.get(section).into_iter().flatten() {
                assert!(
                    p.verbatim,
                    "{} ({section}): public-domain body should be verbatim",
                    p.citation
                );
                assert!(
                    !p.body.trim().is_empty(),
                    "{}: verbatim body must not be empty",
                    p.citation
                );
            }
        }
    }

    #[test]
    fn passage_ids_are_unique_within_a_section() {
        for (section, passages) in committed_corpus() {
            let mut seen = std::collections::HashSet::new();
            for p in &passages {
                assert!(
                    seen.insert(p.id.clone()),
                    "duplicate corpus id {} in {section}",
                    p.id
                );
            }
        }
    }
}
