# 1 — Sources & Licensing

[← Index](README.md) · Next: [Taxonomy →](02-taxonomy-and-blueprint.md)

The single most consequential constraint on this pipeline is **not technical —
it is copyright**. CPA content is dominated by works whose text we may _read and
cite_ but may **not** ingest, embed, and redistribute inside generated cards.
Getting this wrong doesn't just risk a takedown; under the assignment rule it
**zeroes the section** if a card's "source" can't be legitimately traced.

## The firewall: ingest-and-redistribute vs cite-only

We split every candidate source into two tiers.

### Tier A — Generation corpus (ingest, embed, ground, redistribute paraphrase)

Public-domain or openly-licensed material we can chunk, embed into LanceDB, and
quote/paraphrase in card text with attribution.

| Source                                                                            | License                                     | Covers                                                                   |
| --------------------------------------------------------------------------------- | ------------------------------------------- | ------------------------------------------------------------------------ |
| **OpenStax — Principles of Accounting, Vol. 1 (Financial) & Vol. 2 (Managerial)** | CC BY 4.0                                   | Core financial-accounting foundations → FAR, BAR                         |
| **OpenStax — Principles of Finance**                                              | CC BY 4.0                                   | TVM, valuation, capital → BAR                                            |
| **Internal Revenue Code (26 U.S.C.)**                                             | Public domain (U.S. Code)                   | REG, TCP                                                                 |
| **Treasury Regulations (26 C.F.R.)**                                              | Public domain                               | REG, TCP                                                                 |
| **IRS Publications, Forms & Instructions** (e.g. Pub 17, 334, 542, 946)           | Public domain (U.S. gov work)               | REG, TCP                                                                 |
| **PCAOB Auditing Standards** (AS 1000-series)                                     | Publicly published; usable with attribution | AUD                                                                      |
| **GAO "Yellow Book" (Government Auditing Standards)**                             | Public domain (U.S. gov work)               | AUD                                                                      |
| **SEC rules & interpretive releases (17 C.F.R.), Regulation S-X / S-K**           | Public domain                               | FAR, AUD, ISC                                                            |
| **SEC EDGAR filings** (real 10-Ks, footnotes)                                     | Public domain (gov-published)               | FAR, BAR (realistic exhibits)                                            |
| **U.S. federal court & Tax Court opinions**                                       | Public domain                               | REG, TCP                                                                 |
| **NIST SP 800-series, COSO summaries (public), CIS Controls**                     | Public / permissive                         | ISC                                                                      |
| **AICPA Uniform CPA Examination Blueprints**                                      | AICPA-published, public                     | **Taxonomy only** (see below) — cite, don't reproduce task text verbatim |

OpenStax is the backbone for financial-accounting concepts; the tax corpus is
almost entirely public domain, which is why REG/TCP are the _cheapest_ sections
to cover legitimately.

### Tier B — Citation-only (reference for grounding accuracy, never ingested)

Copyrighted standards we may _name and cite_ (e.g. "ASC 842-20-25-1") and whose
principle we may _paraphrase from a Tier-A explanation_, but whose **text we do
not ingest, embed, or reproduce**.

| Source                                                      | Why cite-only                                                                              |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| **FASB Accounting Standards Codification (ASC)**            | © Financial Accounting Foundation. "Basic View" is free to _view_, not to redistribute.    |
| **GASB Codification / Statements**                          | © GASB/FAF.                                                                                |
| **AICPA released/adaptive exam questions**                  | © AICPA. Using these as training/generation text risks derivative-work + leakage problems. |
| **Commercial review-course material (Becker, Wiley, etc.)** | © publishers. Off-limits entirely.                                                         |

**Rule:** a card may carry `source = "ASC 606-10-25-23"` as a _citation_ only
when the substantive grounding came from a Tier-A passage that explains that
principle (e.g. an OpenStax revenue-recognition section). The citation points a
studying candidate to the authoritative standard; the _card text_ derives from
the openly-licensed explanation. This keeps us grounded to the real standard
numbering while never redistributing FASB's copyrighted prose.

## Consequences for the pipeline

- **Grounding context = Tier A only.** The retriever indexes and returns Tier-A
  passages. Claude is instructed to derive card content from those passages and
  to attach both the Tier-A locator (for our audit trail) and, where applicable,
  the Tier-B standard citation (for the candidate).
- **Two-part provenance.** `source_passage` = the Tier-A passage actually
  retrieved (verbatim, for audit). The human-facing citation (ASC/IRC §) lives
  in the card body/answer. See [doc 6](06-provenance-output-and-ops.md).
- **Coverage gaps are honest.** Some exam-heavy niches live only in copyrighted
  standards with thin OpenStax coverage. Those topics get **fewer** cards, and
  we log the shortfall rather than hallucinate to hit a quota (ties to the
  "abstain over guess" ethos of the app itself).
- **Untrusted-input posture.** All ingested text — even public-domain — is
  treated as a prompt-injection surface; see the guardrails in
  [doc 6](06-provenance-output-and-ops.md).

## Open decision (needs sign-off)

The **cite-don't-ingest firewall around FASB ASC** is a legal posture, not an
engineering one. The alternative — licensing the ASC XBRL/API from FAF for
generation — buys tighter grounding but costs money and adds redistribution
terms. **Recommendation:** ship the public-corpus + citation approach; revisit a
FAF license only if eval shows FAR/BAR grounding quality is materially
capped by it. Candidate for an ADR.

Next: [Taxonomy & blueprint allocation →](02-taxonomy-and-blueprint.md)
