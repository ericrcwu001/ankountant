// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use std::collections::BTreeMap;
use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

use anki_io::read_to_string;
use anki_io::write_file;
use anki_process::CommandExt;
use anyhow::Context;
use anyhow::Result;
use camino::Utf8Path;
use walkdir::WalkDir;

const IGNORED_FOLDERS: &[&str] = &[
    "./out",
    "./node_modules",
    "./qt/aqt/forms",
    "./tools/workspace-hack",
    "./target",
    ".mypy_cache",
    "./extra",
    "./ts/.svelte-kit",
    "./.venv",
    "./qt/installer/windows-template",
    "./qt/installer/mac-template",
    // Claude Code scratch worktrees: gitignored full checkouts of the repo,
    // not source to lint (they carry copied qt/aqt/forms/*.py etc.).
    "./.claude",
    // The iOS Rust bridge's cargo build output (generated .rs: prost protos,
    // thiserror/serde codegen, i18n strings) — mirror of the top-level ./target.
    "./ios/anki-bridge-rs/target",
    // SwiftPM build dir (gitignored): third-party dependency checkouts
    // (swift-protobuf, zstd, …) fetched by `swift build`/`xcodebuild`, not our
    // source to lint. minilints walks the FS, so it must be excluded explicitly.
    "./ios/.build",
    // Xcode SwiftPM build output for the app (gitignored): vendored dependency
    // checkouts (zstd, libdeflate, …) fetched by `xcodebuild`, not our source.
    "./ios/AnkountantApp/build",
];

fn main() -> Result<()> {
    let mut args = env::args();
    let want_fix = args.nth(1) == Some("fix".to_string());
    let stamp = args.next().unwrap();
    let mut ctx = LintContext::new(want_fix);
    ctx.check_contributors()?;
    ctx.check_rust_licenses()?;
    ctx.walk_folders(Path::new("."))?;
    if ctx.found_problems {
        std::process::exit(1);
    }
    write_file(stamp, "")?;

    Ok(())
}

struct LintContext {
    want_fix: bool,
    found_problems: bool,
}

impl LintContext {
    pub fn new(want_fix: bool) -> Self {
        Self {
            want_fix,
            found_problems: false,
        }
    }

    pub fn walk_folders(&mut self, root: &Path) -> Result<()> {
        let ignored_folders: HashSet<_> = IGNORED_FOLDERS.iter().map(Utf8Path::new).collect();
        let walker = WalkDir::new(root).into_iter();
        for entry in walker.filter_entry(|e| {
            !ignored_folders.contains(&Utf8Path::from_path(e.path()).expect("utf8"))
        }) {
            let entry = entry.unwrap();
            let path = Utf8Path::from_path(entry.path()).context("utf8")?;

            let exts: HashSet<_> = ["py", "ts", "rs", "svelte", "mjs"]
                .into_iter()
                .map(Some)
                .collect();
            if exts.contains(&path.extension()) && !sveltekit_temp_file(path.as_str()) {
                self.check_triple_slash(path)?;
            }
        }
        Ok(())
    }

    fn check_triple_slash(&mut self, path: &Utf8Path) -> Result<()> {
        if !matches!(path.extension(), Some("ts") | Some("svelte")) {
            return Ok(());
        }
        for line in fs::read_to_string(path)?.lines() {
            if line.contains("///") && !line.contains("/// <reference") {
                println!("not a docstring: {path}: {line}");
                self.found_problems = true;
            }
        }
        Ok(())
    }

    fn check_contributors(&self) -> Result<()> {
        let antispam = ", at the domain ";

        let last_author = String::from_utf8(
            Command::new("git")
                .args(["log", "-1", "--pretty=format:%ae"])
                .output()?
                .stdout,
        )?;

        let all_contributors = String::from_utf8(
            Command::new("git")
                .args(["log", "--pretty=format:%ae", "CONTRIBUTORS"])
                .output()?
                .stdout,
        )?;
        let all_contributors = all_contributors.lines().collect::<HashSet<&str>>();

        const BOT_EMAILS: &[&str] = &[
            "49699333+dependabot[bot]@users.noreply.github.com",
            "41898282+github-actions[bot]@users.noreply.github.com",
            "github-actions[bot]@users.noreply.github.com",
        ];

        if BOT_EMAILS.contains(&last_author.as_str())
            || all_contributors.contains(last_author.as_str())
        {
            return Ok(());
        }

        if let Ok(bypass) = std::env::var("CONTRIBUTORS_BYPASS_EMAILS") {
            if bypass
                .split(',')
                .any(|e| noreply_aware_match(e.trim(), &last_author))
            {
                println!("Author allowlisted via CONTRIBUTORS_BYPASS_EMAILS.");
                return Ok(());
            }
        }

        println!("All contributors:");
        println!("{}", {
            let mut contribs: Vec<_> = all_contributors
                .iter()
                .map(|s| s.replace('@', antispam))
                .collect();
            contribs.sort();
            contribs.join("\n")
        });

        println!(
            "Author {} NOT found in list",
            last_author.replace('@', antispam)
        );

        println!(
            "\nPlease make sure you modify the CONTRIBUTORS file using the email address you \
                are committing from. If you have GitHub configured to hide your email address, \
                you may need to make a change to the CONTRIBUTORS file using the GitHub UI, \
                then try again."
        );

        std::process::exit(1);
    }

    fn check_rust_licenses(&mut self) -> Result<()> {
        let license_path = Path::new("cargo/licenses.json");
        let licenses = generate_licences()?;
        let existing_licenses = read_to_string(license_path)?;
        if licenses != existing_licenses {
            if self.want_fix {
                check_cargo_deny()?;
                write_file(license_path, licenses)?;
            } else {
                println!("cargo/licenses.json is out of date; run ./ninja fix:minilints");
                self.found_problems = true;
            }
        }
        Ok(())
    }
}

fn noreply_aware_match(bypass_email: &str, commit_email: &str) -> bool {
    normalize_email(bypass_email) == normalize_email(commit_email)
}

/// GitHub noreply emails come in two forms:
/// - `user@users.noreply.github.com`
/// - `12345+user@users.noreply.github.com`
///
/// Normalize to just the username so both forms match.
fn normalize_email(email: &str) -> &str {
    email
        .strip_suffix("@users.noreply.github.com")
        .map(|local| local.split('+').next_back().unwrap_or(local))
        .unwrap_or(email)
}

/// Annoyingly, sveltekit writes temp files into ts/ folder when it's running.
fn sveltekit_temp_file(path: &str) -> bool {
    path.contains("vite.config.ts.timestamp")
}

fn check_cargo_deny() -> Result<()> {
    // Used by `fix:minilints` locally. CI uses EmbarkStudios/cargo-deny-action.
    Command::run("cargo install cargo-deny@0.19.2")?;
    Command::run("cargo deny check")?;
    Ok(())
}

fn generate_licences() -> Result<String> {
    Command::run("cargo install cargo-license@0.7.0")?;
    let output = Command::run_with_output([
        "cargo-license",
        "--features",
        "rustls",
        "--features",
        "native-tls",
        "--json",
        "--manifest-path",
        "rslib/Cargo.toml",
    ])?;

    let licenses: Vec<BTreeMap<String, serde_json::Value>> = serde_json::from_str(&output.stdout)?;

    let filtered: Vec<BTreeMap<String, serde_json::Value>> = licenses
        .into_iter()
        .map(|mut entry| {
            entry.remove("version");
            entry
        })
        .collect();

    Ok(serde_json::to_string_pretty(&filtered)?)
}
