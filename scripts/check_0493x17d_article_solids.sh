#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; cd "$ROOT"
grep -q 'chiSolidMembraneAnchorMode = "none"' include/simulation_params.h
grep -q 'closed-loop-parity+nearest-edge-depth' src/cuda_q6_resident_0400.cu
grep -q 'supportConstraintImpulseX' include/cuda_q6_resident_0400.h
grep -q 'chiMembraneNodePinned0493x17d' src/cuda_q6_resident_0400.cu
grep -q 'md.supportConstraintImpulseX' src/chi_solid_dynamics_0493x16a.cpp
grep -q 'chiSolidMembraneAnchorMode supports none' src/params_io_base.cpp
grep -q 'chiKineticBoundaryMode = specular' scripts/run_0493x17d_fixed_membrane_case.sh
grep -q 'chiSolidModel = rigid_slab_1d' scripts/run_0493x17d_pressure_piston_case.sh
# Historical behavior remains the default: no anchor unless explicitly selected.
grep -q 'std::string chiSolidMembraneAnchorMode = "none"' include/simulation_params.h
for f in scripts/run_0493x17d_fixed_membrane_case.sh scripts/run_0493x17d_pressure_piston_case.sh scripts/run_0493x17d_article_solids.sh scripts/run_0493x17d_article_solids_smoke.sh; do bash -n "$f"; done
python3 -m py_compile scripts/generate_0493x17d_piston_state.py scripts/analyze_0493x17d_article_solids.py scripts/plot_0493x17d_article_solids.py scripts/check_0493x17d_article_solids.py
python3 scripts/check_0493x17d_article_solids.py
echo '[0493x17d] ALL CHECKS PASS'
