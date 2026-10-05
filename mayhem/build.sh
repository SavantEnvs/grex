#!/usr/bin/env bash
#
# mayhem/build.sh — grex: build the cargo-fuzz target (sanitized libFuzzer binary)
# plus the upstream test suite (normal flags) so mayhem/test.sh only RUNS it.
#
# Runs inside the commit image (RUST mayhem/Dockerfile) as `mayhem` in /mayhem.
# The Rust toolchain + cargo registry live at $CARGO_HOME=/opt/toolchains/rust/cargo
# (pinned by the Dockerfile ENV — absolute, $HOME-independent).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
#   - This FIRST build (in CI, online) populates the cargo registry under $CARGO_HOME.
#   - The PATCH re-run resolves crates from that cache; the rlenv runtime exports
#     CARGO_NET_OFFLINE=true for the re-run, so do NOT hard-code `--offline` here.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# Debug-info contract (SPEC §6.2 item 10): DWARF < 4 on the fuzz binaries.
: "${RUST_DEBUG_FLAGS:=-Cdebuginfo=1 -Zdwarf-version=3 -Cforce-frame-pointers}"

cd "$SRC"

# Sanitizer contract: rustc ignores the clang $SANITIZER_FLAGS from the base ENV;
# the Rust equivalent is ASan via RUSTFLAGS (-Zsanitizer=address, the OSS-Fuzz Rust
# path) — that instruments the grex library code itself, not just the harness.
# DWARF<4 contract on the C parts too: libfuzzer-sys compiles the C++ libFuzzer
# runtime with cc, which reads CFLAGS/CXXFLAGS (clang's plain -g emits DWARF-5).
export CFLAGS="${CFLAGS:-} -gdwarf-3"
export CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"
FUZZ_RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address $RUST_DEBUG_FLAGS"

# Additive fuzz crate (upstream ships no fuzz/); ports the fork's original
# fuzz_builder harness to the current grex public API.
FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

# Discover every target from the crate's fuzz_targets/ dir (one binary per target).
FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$FUZZ_RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

# Use the image's DEFAULT toolchain (the Dockerfile pinned it).
for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  RUSTFLAGS="$FUZZ_RUSTFLAGS" cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Build the upstream test suite with the project's NORMAL flags (clean, unsanitized
# build in the default ./target dir) so mayhem/test.sh only RUNS it. This compiles
# the lib/bin plus the native integration tests (cli/lib/property); the wasm and
# python test files are cfg'd/skipped on this target.
echo "=== cargo test --no-run (upstream suite, normal flags) ==="
cargo test --no-run

echo "build.sh complete"
