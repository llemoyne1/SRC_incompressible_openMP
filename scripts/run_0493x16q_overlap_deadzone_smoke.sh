#!/usr/bin/env bash
# Targeted reproduction of the x16p deformable/rest step-127 dead-zone event.
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
BASE="${BASE_RUN_ROOT:-runs/0493x16q_overlap_deadzone_smoke}"
for marker in 'q2Topology=x16p-boundary-root-trace' 'overlapTol=x16q-chi-1e-10h'; do
  grep -q "$marker" src/cuda_q6_resident_0400.cu || { echo "[0493x16q-smoke] ERROR source marker absent: $marker" >&2; exit 2; }
done
rm -rf "$BASE"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
BASE_RUN_ROOT="$BASE" \
CASE_LABEL=0493x16q_deform_rest_smoke \
COMMON_UX=0.0 DEFORMABLE=1 STEPS=127 SEED=4931610 \
SUMMARY_EVERY=1 CLEAN_RUN_ROOT=1 \
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}" \
FILTERED_RECORDING_ENABLE=0 RECORD_ENABLE=false \
bash scripts/run_0493x16j_chi_kinetic_specular_case.sh
grep -R -q 'overlapTol=x16q-chi-1e-10h' "$BASE" || { echo '[0493x16q-smoke] ERROR runtime marker absent' >&2; exit 2; }
python3 scripts/analyze_0493x16q_overlap_deadzone_smoke.py "$BASE"
