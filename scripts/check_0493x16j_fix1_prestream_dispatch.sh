#!/usr/bin/env bash
ROOT="${ROOT:-$(pwd)}"
cd "$ROOT" || exit $?
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
check header_api "grep -q 'cuda_q6_apply_chi_kinetic_boundary_prestream_0493x16j' include/cuda_q6_resident_0400.h"
check prestream_dispatch "grep -q '0493x16j-fix1: x10n interprets particle x/y as PRE-STREAM' src/src_mpcd_base.cpp"
check resident_marker "grep -q 'timing=prestream geometry=S=1-chi' src/cuda_q6_resident_0400.cu"
check local_cell_lookup "grep -q 'const int initialCell = chiKineticBoundary0493x16j' src/cuda_q6_resident_0400.cu"
check phase_guard "grep -q 'forbids simultaneous liquid/gas and chi kinetic crossings' src/params_io_base.cpp"
check runner_syntax "bash -n scripts/run_0493x16j_chi_kinetic_specular_case.sh"
check smoke_syntax "bash -n scripts/run_0493x16j_fix1_prestream_smoke.sh"
check recorder_no_chi "! grep -Eq 'RECORD_FIELDS=.*chi' scripts/run_0493x16j_chi_kinetic_specular_case.sh"
exit $fail
