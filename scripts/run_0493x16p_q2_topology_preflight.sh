#!/usr/bin/env bash
# 0493x16p preflight only — NO source modification, NO simulation.
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
BASE="${BASE_RUN_ROOT:-runs/0493x16o_q2_edge_endpoint_qualification}"
for marker in 'q2Edges=x16o-q2-edge-roots' 'q2Owner=x16n-dual-square-clipped' 'q2Root=x16m-bisection-1e-8cell'; do
  grep -q "$marker" src/cuda_q6_resident_0400.cu || { echo "[x16p-preflight] ERROR source marker absent: $marker" >&2; exit 2; }
done
files=(
 "$BASE/static_curved/rest/fresh/output/chi_solid_dynamics_0493x16a.csv"
 "$BASE/static_curved/boost/fresh/output/chi_solid_dynamics_0493x16a.csv"
 "$BASE/full_mobile/rigid/rest/fresh/output/chi_solid_dynamics_0493x16a.csv"
 "$BASE/full_mobile/rigid/boost/fresh/output/chi_solid_dynamics_0493x16a.csv"
 "$BASE/full_mobile/deformable/rest/fresh/output/chi_solid_dynamics_0493x16a.csv"
 "$BASE/full_mobile/deformable/boost/fresh/output/chi_solid_dynamics_0493x16a.csv"
)
for f in "${files[@]}"; do
  [[ -s "$f" ]] || { echo "[x16p-preflight] ERROR missing $f" >&2; exit 2; }
done
python3 scripts/analyze_0493x16p_q2_topology_preflight.py "$BASE"
