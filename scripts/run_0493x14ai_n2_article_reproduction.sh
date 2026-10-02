#!/usr/bin/env bash
# Article reproduction wrapper for the historical 0493x14ai-fix1 two-phase n=2
# oscillating-drop validation.
#
# IMPORTANT:
# - This script DOES NOT reconstruct the x14ai physics from a list of flags.
# - It executes the exact historical runner already present in the repository.
# - It refuses to run if the historical runner or its historical n=2 analyzer
#   no longer match the hashes recorded in the project reference database.
# - No compilation and no C++/CUDA modification are performed.
#
# Historical quantitative reference (0 < t <= 4):
#   seed=493180, steps=2000, dt=0.002
#   omega=1.6375276, Gomega=0.9798833
#   beta=0.1694319, R2=0.997111
#   max total-momentum drift=5.08e-11
#
# Run from the repository root:
#   bash scripts/run_0493x14ai_n2_article_reproduction.sh

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

HIST_RUNNER="$ROOT/scripts/run_0493x14ai_oscillating_drop_n2_device_closure.sh"
HIST_ANALYZER="$ROOT/scripts/analyze_0493x14x_oscillating_drop_n2.py"
BIN="${BIN:-$ROOT/build/src_mpcd_base_cuda_q6_resident_livevis_0486}"

EXPECTED_RUNNER_SHA="acdf7bc0c829d26241539b7230bd4694f6ccf137295312f84a993bdf235fd45a"
EXPECTED_ANALYZER_SHA="3ff2a7b9cae62d2bde4d11323c0f3b1ac0be1a299c762ef5736b77defc7fcc74"

ARTICLE_RUN_ROOT="${ARTICLE_RUN_ROOT:-runs/0493x14ai_n2_article_reproduction_seed493180}"
PROVENANCE="$ARTICLE_RUN_ROOT/article_reproduction_provenance.txt"

fail() {
  echo "[x14ai-n2-article] ERROR: $*" >&2
  exit 2
}

[[ -f "$HIST_RUNNER" ]] || fail "missing historical runner: $HIST_RUNNER"
[[ -f "$HIST_ANALYZER" ]] || fail "missing historical analyzer: $HIST_ANALYZER"
[[ -x "$BIN" ]] || fail "frozen binary missing or not executable: $BIN"

sha_file() {
  sha256sum "$1" | awk '{print $1}'
}

RUNNER_SHA="$(sha_file "$HIST_RUNNER")"
ANALYZER_SHA="$(sha_file "$HIST_ANALYZER")"

[[ "$RUNNER_SHA" == "$EXPECTED_RUNNER_SHA" ]] || fail \
  "historical runner hash mismatch: got=$RUNNER_SHA expected=$EXPECTED_RUNNER_SHA"
[[ "$ANALYZER_SHA" == "$EXPECTED_ANALYZER_SHA" ]] || fail \
  "historical analyzer hash mismatch: got=$ANALYZER_SHA expected=$EXPECTED_ANALYZER_SHA"

# Structural guards: these are not replacements for the hash check.  They make
# the intended historical closure explicit in the execution record.
grep -q 'MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION' "$HIST_RUNNER" || \
  fail "historical runner does not reference x14ad local-face gauge projection"
grep -q 'MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE' "$HIST_RUNNER" || \
  fail "historical runner does not reference x14ai device-applied Q6 closure"

# Capture execution identity before the historical runner starts.  The runner
# may clean RUN_ROOT, so the persistent provenance file is written only after
# successful completion.
BINARY_SHA="$(sha_file "$BIN")"
GIT_HEAD="$(git rev-parse HEAD 2>/dev/null || echo unavailable)"
GIT_DESCRIBE="$(git describe --always --dirty --tags 2>/dev/null || echo unavailable)"
RUN_DATE="$(date -Is 2>/dev/null || date)"

echo "==============================================================="
echo "  0493x14ai-fix1 TWO-PHASE n=2 — ARTICLE REPRODUCTION"
echo "==============================================================="
echo "Historical runner SHA256 : $RUNNER_SHA"
echo "Historical analyzer SHA256: $ANALYZER_SHA"
echo "Binary                    : $BIN"
echo "Run root requested        : $ARTICLE_RUN_ROOT"
echo "Run                        : seed=493180, steps=2000"
echo "No compilation; no solver modification."
echo "==============================================================="

# Only historical run extent/seed and article-output controls are overridden.
# No physics or x14 closure flag is reconstructed here.
SEED=493180 \
STEPS=2000 \
RUN_ROOT="$ARTICLE_RUN_ROOT" \
CAMPAIGN_ROOT="$ARTICLE_RUN_ROOT" \
CLEAN_RUN_ROOT=1 \
LIVE_PROGRESS=1 \
LIVE_VIS_ENABLE=1 \
LIVE_VIS_EVERY=1 \
BIN="$BIN" \
bash "$HIST_RUNNER"

rc=$?
[[ $rc -eq 0 ]] || fail "historical runner returned rc=$rc"

# The requested root should contain the historical analyzer output.  If the
# historical runner chose a nested directory, find it strictly under this root.
REPORT="$(find "$ARTICLE_RUN_ROOT" -type f -name 'oscillating_drop_n2_report*.txt' -print 2>/dev/null | head -n 1)"
[[ -n "$REPORT" ]] || fail \
  "historical n=2 report not found under $ARTICLE_RUN_ROOT; do not infer a result from another run"

# Runtime provenance gate: the final historical closure must actually have been
# active.  Search text diagnostics only, never state dumps.
if ! grep -R -q \
    --include='*.log' --include='*.env' --include='*.txt' --include='*.csv' \
    'deviceAppliedQ6ResultantClosure=B1-exact-post-periodic-device-target' \
    "$ARTICLE_RUN_ROOT" 2>/dev/null; then
  fail "runtime marker for x14ai-fix1 B1-exact closure not found in this run"
fi

LOCAL_FACE_MARKER="not-found-as-literal"
if grep -R -q \
    --include='*.log' --include='*.env' --include='*.txt' \
    'MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1' \
    "$ARTICLE_RUN_ROOT" 2>/dev/null; then
  LOCAL_FACE_MARKER="found"
else
  echo "[x14ai-n2-article] WARNING: local-face-gauge env marker not found as literal text."
  echo "[x14ai-n2-article] The historical runner hash is exact, but inspect the run environment before publication."
fi

# Write provenance only now: CLEAN_RUN_ROOT in the historical runner cannot
# erase it after this point.
{
  echo "===== 0493x14ai n=2 ARTICLE REPRODUCTION PROVENANCE ====="
  echo "date=$RUN_DATE"
  echo "purpose=reproduce historical two-phase n=2 PASS for article figures"
  echo "historicalRunner=scripts/run_0493x14ai_oscillating_drop_n2_device_closure.sh"
  echo "historicalRunnerSha256=$RUNNER_SHA"
  echo "historicalAnalyzer=scripts/analyze_0493x14x_oscillating_drop_n2.py"
  echo "historicalAnalyzerSha256=$ANALYZER_SHA"
  echo "binary=$BIN"
  echo "binarySha256=$BINARY_SHA"
  echo "gitHead=$GIT_HEAD"
  echo "gitDescribe=$GIT_DESCRIBE"
  echo "seed=493180"
  echo "steps=2000"
  echo "historicalFitWindow=0<t<=4"
  echo "livevisControl=./livevis_control.kv (user-owned; not modified)"
  echo "runtimeReport=$REPORT"
  echo "runtimeClosureMarker=deviceAppliedQ6ResultantClosure=B1-exact-post-periodic-device-target"
  echo "runtimeLocalFaceGaugeLiteral=$LOCAL_FACE_MARKER"
  echo "runCompleted=1"
  echo "NOTE=physics and closure flags are defined by the historical x14ai runner, not by this wrapper"
} > "$PROVENANCE"

echo
echo "[x14ai-n2-article] historical reproduction complete"
echo "[x14ai-n2-article] report=$REPORT"
echo "[x14ai-n2-article] provenance=$PROVENANCE"
echo
echo "Article figures (from repository matlab/):"
echo "  analyze_0493x14ai_n2_article('../$ARTICLE_RUN_ROOT')"
