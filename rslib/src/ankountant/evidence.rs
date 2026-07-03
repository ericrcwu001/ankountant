// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Reproducible evidence emitters for the readiness/scheduler honesty claims
//! (#4 determinism, #5 A2 ablation). The emitters themselves are `#[ignore]`d
//! tests in [`super::determinism`] and [`super::ablation`], run by
//! `just ankountant-evidence`; each recomputes its backing numbers and writes a
//! JSON record plus a self-contained HTML artifact (with the JSON inlined)
//! under `docs_ankountant/evidence/`. Nothing here runs in the normal `just
//! test-rust` suite, and nothing here is on any product code path.

use std::path::PathBuf;

use serde_json::Value;

/// Absolute path to `docs_ankountant/evidence`, derived from this crate's
/// manifest dir (`rslib/`) so the recipe is independent of the caller's CWD.
fn evidence_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("docs_ankountant")
        .join("evidence")
}

/// Write `data/<name>.json` and a self-contained `<name>.html` (with the JSON
/// spliced in) into the evidence dir. `template` must contain the literal token
/// `/*__DATA__*/` where the JSON is injected as a JS object.
pub(super) fn write_artifact(name: &str, template: &str, data: &Value) {
    let dir = evidence_dir();
    let data_dir = dir.join("data");
    std::fs::create_dir_all(&data_dir).unwrap();

    let pretty = serde_json::to_string_pretty(data).unwrap();
    std::fs::write(data_dir.join(format!("{name}.json")), &pretty).unwrap();

    let html = template.replace("/*__DATA__*/", &pretty);
    std::fs::write(dir.join(format!("{name}.html")), html).unwrap();

    // Surface the output path when run verbosely (`cargo test -- --nocapture`).
    println!(
        "wrote evidence artifact: {}",
        dir.join(format!("{name}.html")).display()
    );
}

pub(super) const DETERMINISM_TEMPLATE: &str = include_str!("evidence/determinism.template.html");
pub(super) const ABLATION_TEMPLATE: &str = include_str!("evidence/ablation.template.html");
pub(super) const PARAPHRASE_TEMPLATE: &str = include_str!("evidence/paraphrase.template.html");
