#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "[0493b-check] ERROR $*" >&2; exit 2; }

for f in \
  scripts/src_mpcd_run_common_0434.sh \
  scripts/run_ok_injection_type1_into_type2_empty.sh \
  scripts/run_0493b_universal_species_resampling_matrix.sh; do
  bash -n "$f" || fail "shell syntax: $f"
done

# Public configuration contract: separate key, default enabled, all-species deposits.
grep -q 'bool resamplingEnable = true' include/species_registry.h || fail "missing default-true species switch"
grep -q 'speciesKResamplingEnable = true|false' include/simulation_params.h || fail "missing documented speciesK switch"
grep -q 'parse_species_resampling_enable_key' src/params_io_base.cpp || fail "missing switch parser"
grep -q 'resamplingEnabled' include/cuda_species_cell_fields_0490h.h || fail "missing CUDA species metadata"
grep -q 'hResamplingEnabled' src/cuda_species_cell_fields_0490h.cu || fail "missing CUDA metadata upload"
grep -q 'SpeciesPhaseFamily::Dispersed' src/species_registry.cpp || fail "missing dispersed phase family"

# Production must not retain topology-only routing or runtime fatal guards.
for text in \
  '0490m direct fast path requires periodic wall-free no-solid geometry' \
  '0490n currently requires periodic wall-free no-solid geometry' \
  '0490m resident fast path is currently restricted to no immersed solid' \
  '0490m resident fast path is currently restricted to fully periodic boundaries' \
  'SPECIES_RESIDENT_MODE=fast requires topology=periodic'; do
  if grep -Rqs -- "$text" src include scripts/src_mpcd_run_common_0434.sh; then
    fail "residual topology restriction: $text"
  fi
done

grep -q 'SPECIES_RESIDENT_MODE="${SPECIES_RESIDENT_MODE:-production}"' scripts/src_mpcd_run_common_0434.sh || fail "production routing is not default"
grep -q 'MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458=0' scripts/src_mpcd_run_common_0434.sh || fail "CPU operation carrier not disabled"
grep -q 'RESAMPLING_HOST_PATCHBACK_ENABLE:-0' scripts/src_mpcd_run_common_0434.sh || fail "host patchback default is not zero"
grep -q 'RESAMPLING_SPARSE_DEVICE_GATE_ENABLE:-0' scripts/src_mpcd_run_common_0434.sh || fail "CPU/CUDA gate default is not zero"
grep -q 'compactPatchbackBytes = 0u' src/cuda_species_resampling_fast_path_0490m.cu || fail "0490m patchback is not zero"
grep -q 'downloadHostArrays = !residentZeroHostMirrors0493b' src/cuda_resampling_population_guard_0297.cu || fail "resident population guard still requires host cell mirrors"
grep -q 'build_physical_fluid_cell_mask_kernel_0493b' src/cuda_species_resident_maintenance_0490n.cu || fail "immersed-solid cell policy is not built on device"
if grep -q 'std::vector<unsigned char> physicalFluidCell' src/cuda_species_resident_maintenance_0490n.cu; then
  fail "0490n still builds a host cell-policy mirror"
fi

# Reject any device-to-host transfer of per-operation particle arrays from 0490m.
python3 - <<'PY'
import re
from pathlib import Path
p=Path('src/cuda_species_resampling_fast_path_0490m.cu')
s=p.read_text()
for m in re.finditer(r'cudaMemcpy\s*\((.*?)\)\s*;', s, re.S):
    call=m.group(1)
    if 'cudaMemcpyDeviceToHost' in call and re.search(r'impl->out(?:Particle|Donor|Receiver|Type|Mass|Px|Py)\s*,', call):
        raise SystemExit('[0493b-check] ERROR 0490m per-operation host patchback remains')
PY

# Double defense against disabled-species mutations.
grep -q 'resamplingEnabled\[s\] != 0u' src/cuda_species_transfer_plan_0490k.cu || fail "0490k does not filter disabled species"
grep -q 'outDisabledSpeciesMutation' src/cuda_species_resampling_fast_path_0490m.cu || fail "0490m lacks mutation counter"
grep -q 'disabledSpeciesMutationCount0493b' src/cuda_resampling_population_guard_0297.cu || fail "0297/0490j lacks mutation counter"
grep -q 'pv.type, pv.role, mutationSpeciesView0493b' src/cuda_resampling_population_guard_0297.cu || fail "0298 energy restoration can still mutate disabled species"
grep -q 'disabledSpeciesMutationCount' src/cuda_species_mass_closure_0490i.cu || fail "0490i lacks mutation counter"
grep -q 'resampDisabledSpeciesMutationCount' src/runtime_summary.cpp || fail "runtime scalar summary missing"
grep -q 'bool downloadHostArrays = true' include/cuda_cell_moments.h || fail "cell-moment zero-host option missing"

# LiveVis remains rooted and is not overwritten unless explicitly requested.
grep -q 'LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-\$ROOT/livevis_control.kv}"' scripts/run_ok_injection_type1_into_type2_empty.sh || fail "runner LiveVis control is not root-based"
grep -q 'OVERWRITE_LIVEVIS_CONTROL:-0' scripts/src_mpcd_run_common_0434.sh || fail "LiveVis overwrite default is not zero"
grep -q 'LIVE_PROGRESS="${LIVE_PROGRESS:-1}"' scripts/run_ok_injection_type1_into_type2_empty.sh || fail "LIVE_PROGRESS default missing"

# Host-side translation units touched by the patch must parse.
CXX="${CXX:-g++}"
for f in src/params_io_base.cpp src/species_registry.cpp src/runtime_summary.cpp src/src_mpcd_base.cpp; do
  "$CXX" -std=c++17 -Iinclude -fopenmp -fsyntax-only "$f" || fail "C++ syntax: $f"
done

git diff --check -- include src scripts README_0493B_UNIVERSAL_RESIDENT_PER_SPECIES.md || fail "git diff --check"

# Q6, Darcy and boundary physics implementation files are intentionally untouched.
if git diff --name-only -- \
    src/cuda_species_q6_0491b.cu src/cuda_q6_backend.cu src/cuda_q6_resident_0400.cu \
    src/cuda_darcy_brinkman_0343.cu src/boundary_base.cpp \
    src/cuda_inlet_outlet_fullface_0249a.cu src/cuda_inlet_outlet_segmented_0249b.cu \
    | grep -q .; then
  fail "Q6/Darcy/boundary physics source modified"
fi

# Validate all eight generated configurations without launching or rebuilding.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
PREFLIGHT_ONLY=1 CLEAN_RUN_ROOT=1 RUN_ROOT="$tmp/matrix" \
  bash scripts/run_0493b_universal_species_resampling_matrix.sh > "$tmp/matrix.log"
grep -q '^08_q6_segmented,PASS,preflight-only$' "$tmp/matrix/status_0493b.csv" || fail "matrix preflight incomplete"
[[ "$(grep -c ',PASS,preflight-only$' "$tmp/matrix/status_0493b.csv")" == 8 ]] || fail "matrix does not contain eight passing cases"

echo "[0493b-check] PASS"
echo "[0493b-check] base_commit=aa0a4a0a42f3"
echo "[0493b-check] universal_runtime=on"
echo "[0493b-check] per_species_switch=on_default_true"
echo "[0493b-check] cuda_authoritative=1"
echo "[0493b-check] cpu_plan_required=0"
echo "[0493b-check] host_patchback=0"
echo "[0493b-check] matrix_preflight=8/8"
echo "[0493b-check] q6_physics_untouched=1"
echo "[0493b-check] darcy_physics_untouched=1"
echo "[0493b-check] boundary_physics_untouched=1"
