// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Reproducible evidence artifact helpers for Ankountant rubric claims:
//! determinism, A2 ablation, paraphrase transfer, undo integrity, and latency.
//! Correctness emitters run through `just ankountant-evidence`; the optimized
//! latency emitter runs through `just ankountant-bench`. Each emitter writes a
//! JSON record plus a self-contained HTML artifact under
//! `docs_ankountant/evidence/`. Nothing here is on any product code path.

use std::path::PathBuf;

use serde::Serialize;
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

    // The `.json` sidecar is written with 4-space indentation and a trailing
    // newline so it is dprint-clean and reproducible: `just check` runs dprint
    // over these files, and the committed reference artifacts use that style.
    let mut buf = Vec::new();
    let formatter = serde_json::ser::PrettyFormatter::with_indent(b"    ");
    let mut serializer = serde_json::Serializer::with_formatter(&mut buf, formatter);
    data.serialize(&mut serializer).unwrap();
    let mut json_out = String::from_utf8(buf).unwrap();
    json_out.push('\n');
    std::fs::write(data_dir.join(format!("{name}.json")), &json_out).unwrap();

    // The HTML embeds a 2-space copy inline. dprint does not check HTML, and the
    // existing committed .html artifacts inline 2-space JSON — keeping this at
    // 2-space avoids spurious diffs on those files.
    let pretty = serde_json::to_string_pretty(data).unwrap();
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
pub(super) const UNDO_TEMPLATE: &str = include_str!("evidence/undo.template.html");
pub(super) const LATENCY_TEMPLATE: &str = include_str!("evidence/latency.template.html");
