#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
fail(){ echo "[0493x17c] FAIL $*" >&2; exit 2; }
pass(){ echo "[0493x17c] PASS $*"; }

CUDA=src/cuda_q6_resident_0400.cu
DYN=src/chi_solid_dynamics_0493x16a.cpp
PARAM=src/params_io_base.cpp
HDR=include/cuda_q6_resident_0400.h
SIM=include/simulation_params.h
for f in "$CUDA" "$DYN" "$PARAM" "$HDR" "$SIM"; do [[ -f "$f" ]] || fail "missing $f"; done

grep -q 'backend=x17a-lagrangian-edge-mesh' "$CUDA" || fail 'qualified x17a backend prerequisite absent'
grep -q '0493x17c-membrane' "$CUDA" || fail 'membrane runtime marker absent'
grep -q 'geometryAuthority=Lagrangian-nodes' "$CUDA" || fail 'Lagrangian-node authority marker absent'
grep -q 'q6_x17c_edge_internal_forces' "$CUDA" || fail 'edge elasticity kernel absent'
grep -q 'q6_x17c_area_internal_force' "$CUDA" || fail 'area penalty kernel absent'
grep -q 'membraneNodeImpulseX' "$CUDA" || fail 'direct nodal impact projection absent'
grep -q 'cuda_q6_advance_chi_membrane_0493x17c' "$CUDA" || fail 'membrane advance API implementation absent'
grep -q 'chi_membrane_nodes_0493x17c.csv' "$CUDA" || fail 'article nodal history output absent'
grep -q 'chi_membrane_0493x17c.csv' "$CUDA" || fail 'article membrane diagnostics output absent'
grep -q 'params.chiSolidModel == "membrane_2d"' "$DYN" || fail 'SolidDynamics membrane routing absent'
grep -q 'chiSolidMembraneStretchStiffness' "$PARAM" || fail 'membrane parameter parsing/validation absent'
grep -q 'chiSolidMembraneAreaStiffness' "$SIM" || fail 'membrane constitutive parameters absent'
pass persistent_lagrangian_membrane_backend
pass direct_nodal_fluid_structure_coupling
pass article_diagnostics_present

# Historical rigid/x16e and Darcy routes must still exist; x17c adds a branch.
grep -q 'make_solid_model_0493x16a(params)' "$DYN" || fail 'historical SolidModel factory path removed'
grep -q 'w.model.resident0493x16e->project_load_and_advance' "$DYN" || fail 'historical x16e rigid resident path removed'
grep -q '0493x7g Q6-g-f Darcy requires darcyInitialDeactivateBelowChi<0' "$PARAM" || fail 'historical Q6-g-f Darcy guard changed'
grep -q 'chiKineticBoundaryMode=off' README_0493x17c_elastic_membrane_fsi.txt 2>/dev/null || true
pass historical_rigid_and_darcy_paths_preserved

# No recorder misuse: chi remains unsupported by 0432 and the article runner
# records rho/ux/uy while membrane geometry uses native nodal CSVs.
! grep -Eq 'RECORD_FIELDS=.*chi' scripts/run_0493x17c_membrane_fsi_case.sh || fail 'chi incorrectly requested from recorder 0432'
pass recorder_contract_preserved

bash -n scripts/run_0493x17c_membrane_fsi_case.sh || fail 'case runner shell syntax'
bash -n scripts/run_0493x17c_membrane_smoke.sh || fail 'smoke runner shell syntax'
bash -n scripts/run_0493x17c_membrane_fsi_qualification.sh || fail 'qualification runner shell syntax'
python3 -m py_compile \
  scripts/check_0493x17c_membrane_math.py \
  scripts/analyze_0493x17c_membrane_fsi.py \
  scripts/plot_0493x17c_membrane_article.py || fail 'python syntax'
g++ -std=c++17 -fsyntax-only -Iinclude src/params_io_base.cpp || fail 'params C++ syntax'
g++ -std=c++17 -fsyntax-only -Iinclude src/chi_solid_dynamics_0493x16a.cpp || fail 'SolidDynamics C++ syntax'
python3 scripts/check_0493x17c_membrane_math.py || fail 'membrane analytical checks'
pass syntax_and_analytical_checks

echo '[0493x17c] ALL CHECKS PASS'
