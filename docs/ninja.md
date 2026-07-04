Brief notes for people used to the existing Bazel build system:

- Put the ninja binary on your path: https://github.com/ninja-build/ninja/releases/tag/v1.11.1
  (on Windows, if you have it installed in msys, make sure the native binary occurs earlier on the path)
- Ensure Rust is installed via rustup: https://rustup.rs/
- Remove the .bazel and node_modules folders from your existing checkout

- Run with `just run`
- Run all checks with `just check`
- Run focused tests with `just test-rust`, `just test-py`, `just test-ts`, or
  `just test-e2e`
- Check or fix formatting with `just fmt` / `just fix-fmt`
- Fix auto-fixable lint issues with `just fix-lint`
- Use `just --list` for the current command surface. The underlying build graph
  still uses N2/Ninja, but project docs and agent workflows should go through
  `just`.
