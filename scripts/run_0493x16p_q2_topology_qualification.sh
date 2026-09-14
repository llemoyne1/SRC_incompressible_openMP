#!/usr/bin/env bash
# 0493x16p — full Q2 boundary-root topology for chi material walls.
# Sequential qualification: static curved rest/boost, then rigid/deformable rest/boost.
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
BASE="${BASE_RUN_ROOT:-runs/0493x16p_q2_topology_qualification}"
STATIC_STEPS="${STATIC_STEPS:-800}"
FULL_STEPS="${FULL_STEPS:-600}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"

for marker in 'q2Topology=x16p-boundary-root-trace' 'q2Edges=x16o-q2-edge-roots' 'q2Owner=x16n-dual-square-clipped' 'q2Root=x16m-bisection-1e-8cell'; do
  grep -q "$marker" src/cuda_q6_resident_0400.cu || { echo "[0493x16p] ERROR source marker absent: $marker" >&2; exit 2; }
done
rm -rf "$BASE"; mkdir -p "$BASE"

echo "[0493x16p] phase=static-curved steps=$STATIC_STEPS"
BASE_RUN_ROOT="$BASE/static_curved" \
STEPS="$STATIC_STEPS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
bash scripts/run_0493x16m_static_curved_characterization.sh

grep -R -q 'q2Topology=x16p-boundary-root-trace' "$BASE/static_curved" || {
  echo '[0493x16p] ERROR runtime x16p marker absent in static-curved logs' >&2; exit 2; }

echo "[0493x16p] phase=full-mobile steps=$FULL_STEPS"
set +e
BASE_RUN_ROOT="$BASE/full_mobile" \
STEPS="$FULL_STEPS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
bash scripts/run_0493x16m_q2_root_refinement_qualification.sh
full_rc=$?
set -e
if (( full_rc != 0 && full_rc != 3 )); then
  echo "[0493x16p] ERROR full-mobile execution failed rc=$full_rc" >&2; exit "$full_rc"
fi
grep -R -q 'q2Topology=x16p-boundary-root-trace' "$BASE/full_mobile" || {
  echo '[0493x16p] ERROR runtime x16p marker absent in full-mobile logs' >&2; exit 2; }

python3 scripts/analyze_0493x16p_q2_topology_qualification.py "$BASE"
