#!/usr/bin/env bash
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
fail(){ echo "[0493x17b] FAIL $*" >&2; exit 2; }
pass(){ echo "[0493x17b] PASS $*"; }
SRC=src/cuda_q6_resident_0400.cu
[[ -f "$SRC" ]] || fail "missing x17a CUDA source"
grep -q 'backend=x17a-lagrangian-edge-mesh' "$SRC" || fail 'x17a backend prerequisite absent'
grep -q '0493x17b: with a persistent Lagrangian material boundary' src/params_io_base.cpp || fail 'x17b validation marker absent'
grep -q 'INITIAL_DEACTIVATE_BELOW_CHI="${INITIAL_DEACTIVATE_BELOW_CHI:-0.5}"' scripts/run_0493x16j_chi_kinetic_specular_case.sh || fail 'kinetic runner does not default t=0 exclusion to chi=0.5'
grep -q 'initialStatePolicy=x17b-chi0-fluid-exclusion' scripts/run_0493x16j_chi_kinetic_specular_case.sh || fail 'initialization policy marker absent'
[[ -x scripts/prepare_0493x17b_initial_state_curved_slab.py ]] || fail 'curved qualification initializer missing'
# Historical Q6-g-f fictitious-domain safety remains unchanged.
grep -q '0493x7g Q6-g-f Darcy requires darcyInitialDeactivateBelowChi<0' src/params_io_base.cpp || fail 'historical Q6-g-f Darcy guard changed'
# x17b must not alter the validated x17a material collision backend.
grep -q 'collision=space-time-moving-segment-quadratic' "$SRC" || fail 'x17a space-time collision marker absent'
pass x17a_backend_unchanged
pass initial_chi_fluid_exclusion_enabled
pass historical_q6gf_darcy_guard_preserved
bash -n scripts/run_0493x16j_chi_kinetic_specular_case.sh || fail 'x16j/x17 runner shell syntax'
bash -n scripts/run_0493x17b_mobile_solids_final_qualification.sh || fail 'x17b qualification shell syntax'
python3 -m py_compile scripts/prepare_0493x17b_initial_state_curved_slab.py scripts/analyze_0493x17b_mobile_solids_final_qualification.py || fail 'python syntax'
pass script_syntax
printf '[0493x17b] ALL CHECKS PASS\n'
