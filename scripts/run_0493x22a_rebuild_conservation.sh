#!/usr/bin/env bash
# Regenerate the closed liquid-gas conservation source CSV for article Sec. 3.6.
# No physics change: this wraps the qualified historical x14ai-fix1 runner with
# visualization/recording/state dumps disabled.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2
BASE="$ROOT/scripts/run_0493x14ai_oscillating_drop_n2_device_closure.sh"
ANALYZER="$ROOT/scripts/analyze_0493x22a_conservation.py"
SRC="$ROOT/src/cuda_q6_resident_0400.cu"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
EXPECTED_SHA="${EXPECTED_SHA:-422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc}"

for f in "$BASE" "$ANALYZER" "$SRC" "$BIN"; do
  if [[ ! -f "$f" ]]; then echo "[0493x22a] ERROR missing $f" >&2; exit 2; fi
done
if ! grep -q '0493x14ai-fix1' "$SRC"; then
  echo '[0493x22a] ERROR x14ai-fix1 source marker missing' >&2; exit 2
fi
SHA="$(sha256sum "$BIN" | awk '{print $1}')"
if [[ "$SHA" != "$EXPECTED_SHA" ]]; then
  echo "[0493x22a] ERROR binary SHA mismatch" >&2
  echo " expected=$EXPECTED_SHA" >&2
  echo " actual=$SHA" >&2
  exit 2
fi

export BIN
export CASE_LABEL=0493x22a_article_conservation_rebuild
export SEED=493180
export CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x22a_article_conservation_rebuild}"
export STEPS=2000
export SUMMARY_EVERY=10
export DUMP_STATE_EVERY=0
export LIVE_VIS_ENABLE=0
export LIVE_VIS_HOLD_ON_EXIT=0
export FILTERED_RECORDING_ENABLE=0
export RECORD_ENABLE=false
export RECORD_EVERY=1000000
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
export CLEAN_RUN_ROOT=1
export RESTART=0
export MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=0

cat <<EOF
===== 0493x22a ARTICLE CONSERVATION REBUILD =====
purpose=regenerate species_runtime source for Sec.3.6
physics=qualified x14ai-fix1 oscillating drop, unchanged
binary=$BIN
binarySha256=$SHA
grid=400x400 L=1.5625x1.5625 h=1/256
seed=$SEED steps=$STEPS dt=0.002 tEnd=4
R/h=40 epsilon=0.04 sigma=2560
mL=1 mG=0.1 kBTL=0.02 kBTG=0.08
livevis=OFF recording=OFF stateDumps=OFF summaryEvery=10
campaign=$CAMPAIGN_ROOT
===================================================
EOF

bash "$BASE" || exit $?
if [[ "$PREFLIGHT_ONLY" == "1" ]]; then
  echo '[0493x22a] PREFLIGHT_ONLY complete'
  exit 0
fi

CSV="$CAMPAIGN_ROOT/output/species_runtime_0493x14x.csv"
if [[ ! -s "$CSV" ]]; then
  echo "[0493x22a] ERROR missing regenerated $CSV" >&2; exit 2
fi
python3 "$ANALYZER" --species-runtime "$CSV" --out-dir "$CAMPAIGN_ROOT/analysis" || exit $?

mkdir -p "$CAMPAIGN_ROOT/article_return"
cp "$CSV" "$CAMPAIGN_ROOT/article_return/species_runtime_0493x14x.csv"
cp "$CAMPAIGN_ROOT/analysis/conservation_timeseries.csv" "$CAMPAIGN_ROOT/article_return/"
cp "$CAMPAIGN_ROOT/analysis/conservation_summary.txt" "$CAMPAIGN_ROOT/article_return/"
cp "$CAMPAIGN_ROOT/analysis/conservation_summary.json" "$CAMPAIGN_ROOT/article_return/"
cp "$CAMPAIGN_ROOT/logs/environment_0493x14x.env" "$CAMPAIGN_ROOT/article_return/" 2>/dev/null || true
cp "$CAMPAIGN_ROOT/params/${CASE_LABEL}.kv" "$CAMPAIGN_ROOT/article_return/" 2>/dev/null || true
printf '%s  %s\n' "$SHA" "$BIN" > "$CAMPAIGN_ROOT/article_return/binary.sha256"
tar -czf "$CAMPAIGN_ROOT/0493x22a_article_conservation_rebuild.tar.gz" -C "$CAMPAIGN_ROOT" article_return

echo "[0493x22a] DONE"
echo "[0493x22a] summary=$CAMPAIGN_ROOT/analysis/conservation_summary.txt"
echo "[0493x22a] return=$CAMPAIGN_ROOT/0493x22a_article_conservation_rebuild.tar.gz"
