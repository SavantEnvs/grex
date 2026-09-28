#!/usr/bin/env bash
#
# mayhem/test.sh — RUN grex's OWN upstream test suite (already built by mayhem/build.sh
# via `cargo test --no-run`). Runs every native test binary: the lib unit tests plus the
# cli_integration_tests / lib_integration_tests / property_tests integration suites
# (behavioral assertions on generated regexes and CLI output). The wasm test files are
# cfg'd out on this target and the python bindings suite (pytest) is not runnable in
# this image — both are skipped, not silently dropped (see repos/grex.yaml notes).
#
# Emits a CTRF summary (file + `CTRF {...}` stdout marker); exits non-zero iff failed>0.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# RUN the pre-built suite. cargo test reuses the artifacts build.sh compiled; if they
# were missing it would try to rebuild — treat a non-runnable suite as a hard failure.
LOG=$(mktemp)
cargo test 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}

# Sum every per-binary "test result:" line:
#   test result: ok. 123 passed; 0 failed; 2 ignored; 0 measured; 0 filtered out; ...
passed=0; failed=0; ignored=0
while IFS= read -r line; do
  p=$(sed -n 's/.*test result: [a-zA-Z]*\. \([0-9]*\) passed.*/\1/p' <<<"$line")
  f=$(sed -n 's/.* \([0-9]*\) failed.*/\1/p' <<<"$line")
  i=$(sed -n 's/.* \([0-9]*\) ignored.*/\1/p' <<<"$line")
  passed=$(( passed + ${p:-0} )); failed=$(( failed + ${f:-0} )); ignored=$(( ignored + ${i:-0} ))
done < <(grep 'test result:' "$LOG")
rm -f "$LOG"

# A crashed/non-parsing run must fail loudly, not report 0/0 green.
if [ "$passed" -eq 0 ] && [ "$failed" -eq 0 ]; then
  echo "ERROR: no test results parsed from cargo test output" >&2
  emit_ctrf "cargo-test" 0 1 0
  exit 1
fi
[ "$status" -ne 0 ] && [ "$failed" -eq 0 ] && failed=1

emit_ctrf "cargo-test" "$passed" "$failed" "$ignored"
