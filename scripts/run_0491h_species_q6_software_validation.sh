#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
RUN_ROOT="${RUN_ROOT:-runs/0491h_species_q6_software_validation}"
VALIDATION_PROFILE="${VALIDATION_PROFILE:-software}" # software | full
NX="${NX:-8}"
NY="${NY:-4}"
GAMMA="${GAMMA:-4}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
KBT="${KBT:-0.005}"
LIQUID_TO_GAS_MASS_RATIO="${LIQUID_TO_GAS_MASS_RATIO:-10.0}"
GAS_PARTICLE_MASS="${GAS_PARTICLE_MASS:-1.0}"
LIQUID_PARTICLE_MASS="${LIQUID_PARTICLE_MASS:-$(awk -v mg="$GAS_PARTICLE_MASS" -v r="$LIQUID_TO_GAS_MASS_RATIO" 'BEGIN{printf "%.17g", mg*r}')}"
SPECIES_Q6_COMPARISON_TOLERANCE="${SPECIES_Q6_COMPARISON_TOLERANCE:-1.0e-11}"
MASS_RELATIVE_TOLERANCE="${MASS_RELATIVE_TOLERANCE:-1.0e-10}"

case "$VALIDATION_PROFILE" in
  software)
    PATH_STEPS="${PATH_STEPS:-2}"
    PATH_SEEDS="${PATH_SEEDS:-491101}"
    STRICT_STEPS="${STRICT_STEPS:-3}"
    ENERGY_STEPS="${ENERGY_STEPS:-3}"
    BOUNDARY_STEPS="${BOUNDARY_STEPS:-2}"
    CUSTOM_STEPS="${CUSTOM_STEPS:-3}"
    LONG_Q6_STEPS="${LONG_Q6_STEPS:-4}"
    LONG_RESAMPLING_Q6_STEPS="${LONG_RESAMPLING_Q6_STEPS:-4}"
    ;;
  full)
    PATH_STEPS="${PATH_STEPS:-1000}"
    PATH_SEEDS="${PATH_SEEDS:-491101 491102 491103}"
    STRICT_STEPS="${STRICT_STEPS:-1000}"
    ENERGY_STEPS="${ENERGY_STEPS:-1000}"
    BOUNDARY_STEPS="${BOUNDARY_STEPS:-1000}"
    CUSTOM_STEPS="${CUSTOM_STEPS:-1000}"
    LONG_Q6_STEPS="${LONG_Q6_STEPS:-10000}"
    LONG_RESAMPLING_Q6_STEPS="${LONG_RESAMPLING_Q6_STEPS:-10000}"
    ;;
  *)
    echo "[0491h] ERROR VALIDATION_PROFILE must be software or full, got '$VALIDATION_PROFILE'" >&2
    exit 2
    ;;
esac

if (( GAMMA < 2 )); then
  echo "[0491h] ERROR GAMMA must be >=2" >&2
  exit 2
fi

if [[ "${CLEAN_RUN_ROOT:-1}" == 1 ]]; then
  rm -rf "$RUN_ROOT"
fi
mkdir -p "$RUN_ROOT/logs"
STATUS="$RUN_ROOT/stage_status_0491h.csv"
printf 'stage,kind,exit_code,log,artifact_root\n' > "$STATUS"

suite_ensure_binary_0434

run_stage_0491h() {
  local stage=$1
  local kind=$2
  local artifact_root=$3
  shift 3
  local log="$RUN_ROOT/logs/${stage}.log"
  echo "[0491h] stage=$stage kind=$kind root=$artifact_root"
  set +e
  "$@" > "$log" 2>&1
  local rc=$?
  set -e
  printf '%s,%s,%s,%s,%s\n' "$stage" "$kind" "$rc" "$log" "$artifact_root" >> "$STATUS"
  if [[ "$rc" != 0 ]]; then
    echo "[0491h] FAIL stage=$stage rc=$rc"
    tail -40 "$log"
  fi
  return 0
}

write_custom_state_0491h() {
  local state=$1
  local profile=$2
  python3 - "$state" "$profile" "$NX" "$NY" "$GAMMA" "$GAS_PARTICLE_MASS" "$LIQUID_PARTICLE_MASS" <<'PY_STATE_0491H'
import math
import os
import struct
import sys

state_path, profile, nx, ny, gamma, gas_mass, liquid_mass = sys.argv[1:]
nx, ny, gamma = int(nx), int(ny), int(gamma)
gas_mass, liquid_mass = float(gas_mass), float(liquid_mass)

x = []
y = []
vx = []
vy = []
typ = []
mass = []
role = []

for j in range(ny):
    for i in range(nx):
        xc = (i + 0.5) / nx
        yc = (j + 0.5) / ny
        ux = 0.02 * math.sin(2.0 * math.pi * xc) * math.cos(2.0 * math.pi * yc)
        uy = 0.015 * math.cos(2.0 * math.pi * xc) * math.sin(2.0 * math.pi * yc)
        if profile == "interface":
            liquid_count = max(1, gamma - 1) if i < nx // 2 else 1
        else:
            liquid_count = 1
        for k in range(gamma):
            px = (i + (k + 0.5) / gamma) / nx
            py = (j + ((k * 3 + 1) % gamma + 0.5) / gamma) / ny
            x.append(px)
            y.append(py)
            vx.append(ux + 0.0005 * math.sin(2.0 * math.pi * (px + py + k)))
            vy.append(uy + 0.0005 * math.cos(2.0 * math.pi * (px - py + k)))
            if profile == "trace" and i == nx // 2 and j == ny // 2 and k == 0:
                typ.append(3)
                mass.append(gas_mass)
            elif k < liquid_count:
                typ.append(1)
                mass.append(liquid_mass)
            else:
                typ.append(2)
                mass.append(gas_mass)
            role.append(1)

os.makedirs(os.path.dirname(state_path) or ".", exist_ok=True)
magic = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
reserved = [0] * 8
reserved[0] = 1
reserved[1] = 1
n = len(x)
with open(state_path, "wb") as f:
    f.write(magic)
    f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
    f.write(struct.pack("<8Q", *reserved))
    for arr, fmt in [
        (x, "d"), (y, "d"), (vx, "d"), (vy, "d"),
        (typ, "I"), (mass, "d"), (role, "B"),
    ]:
        f.write(struct.pack("<%d%s" % (n, fmt), *arr))
print(f"[0491h-state] profile={profile} state={state_path} particles={n}")
PY_STATE_0491H
}

run_custom_periodic_0491h() {
  local case_name=$1
  local profile=$2
  local steps=$3
  local case_dir="$RUN_ROOT/custom_${case_name}"
  local state="$case_dir/init/${case_name}.smpcd"
  local params="$case_dir/params/${case_name}.kv"
  local log="$case_dir/logs/${case_name}.log"
  local env_log="$case_dir/logs/environment_0491h.env"
  mkdir -p "$case_dir/init" "$case_dir/params" "$case_dir/output" "$case_dir/logs"
  write_custom_state_0491h "$state" "$profile"

  cat > "$params" <<PARAMS_0491H_CUSTOM
inputState = $state
outputDir = $case_dir/output
Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY
dt = 0.01
nSteps = $steps
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
srcClassicCudaModeEnable = false
projectionEnable = true
projectionBackend = cuda
projectionOperator = auto_fv_cg
projectionMaxIterations = 250
projectionTolerance = 1.0e-12
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false
keepMeanFlowEnable = false
rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = 49108
thermostatEnable = false
kBT = $KBT
summaryEvery = $SUMMARY_EVERY
dumpStateEvery = 0
summaryRoleFilter = fluid
dumpRoleFilter = fluid
initialInactiveSlots = 0
numThreads = 4
speciesRegistryEnable = true
speciesCount = $(if [[ "$profile" == "trace" ]]; then echo 3; else echo 2; fi)
species0 = 1 liquid_incompressible liquid 1.0 1.0 $(awk -v g="$GAMMA" -v m="$LIQUID_PARTICLE_MASS" 'BEGIN{printf "%.17g", g*m}')
species1 = 2 gas_compressible gas 0.0 0.0 $(awk -v g="$GAMMA" -v m="$GAS_PARTICLE_MASS" 'BEGIN{printf "%.17g", g*m}')
PARAMS_0491H_CUSTOM
  if [[ "$profile" == "trace" ]]; then
    cat >> "$params" <<PARAMS_0491H_TRACE
species2 = 3 trace_compressible gas 0.0 0.0 $GAS_PARTICLE_MASS
PARAMS_0491H_TRACE
  fi
  cat >> "$params" <<PARAMS_0491H_CUSTOM_TAIL
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0491h_${case_name}.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = weighted
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = $SPECIES_Q6_COMPARISON_TOLERANCE
PARAMS_0491H_CUSTOM_TAIL

  suite_clear_cuda_flags_0434
  export MPCD_CUDA_INACTIVE_TAIL_POOL_0313=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
  export MPCD_CUDA_STREAMING_PERIODIC_0245=1
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
  export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1
  export MPCD_CUDA_Q6_RESIDENT_0400=1
  export MPCD_CUDA_Q6_RESIDENT_STRICT_0400=1
  export MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=0
  export MPCD_DISABLED_RESAMPLING_SUMMARY_DIAGNOSTICS_0315G=0
  export SRC_LIVE_VIS_ENABLE=0
  export MPCD_LIVE_VIS_ENABLE=0
  env | sort | grep -E '^(MPCD_CUDA|MPCD_DISABLED_RESAMPLING|SRC_LIVE_VIS|MPCD_LIVE_VIS)' > "$env_log"

  echo "[0491h] custom=$case_name profile=$profile steps=$steps"
  set +e
  /usr/bin/time -p "$BIN" "$params" > "$log" 2>&1
  local rc=$?
  set -e
  printf '%s,%s,%s,%s,%s\n' "$case_name" "custom_${profile}" "$rc" "$log" "$case_dir" >> "$STATUS"
  if [[ "$rc" != 0 ]]; then
    echo "[0491h] FAIL custom=$case_name rc=$rc"
    tail -40 "$log"
  fi
}

run_stage_0491h 0491a_cpu_reference analytic "$RUN_ROOT/0491a_cpu_reference" \
  bash scripts/run_0491a_species_q6_cpu_reference.sh

run_stage_0491h 0491e_strict_resident strict "$RUN_ROOT/0491e_strict_resident" \
  env RUN_ROOT="$RUN_ROOT/0491e_strict_resident" BIN="$BIN" NX="$NX" NY="$NY" GAMMA="$GAMMA" \
      STEPS="$STRICT_STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" CLEAN_RUN_ROOT=1 \
      SPECIES_Q6_COMPARISON_TOLERANCE="$SPECIES_Q6_COMPARISON_TOLERANCE" \
      bash scripts/run_0491e_species_q6_strict_resident_audit.sh

run_stage_0491h 0491f_energy energy "$RUN_ROOT/0491f_energy" \
  env RUN_ROOT="$RUN_ROOT/0491f_energy" BIN="$BIN" NX="$NX" NY="$NY" GAMMA="$GAMMA" \
      STEPS="$ENERGY_STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" CLEAN_RUN_ROOT=1 \
      SPECIES_Q6_COMPARISON_TOLERANCE="$SPECIES_Q6_COMPARISON_TOLERANCE" \
      bash scripts/run_0491f_species_q6_energy_validation.sh

run_stage_0491h 0491g_boundary_darcy boundary_darcy "$RUN_ROOT/0491g_boundary_darcy" \
  env RUN_ROOT="$RUN_ROOT/0491g_boundary_darcy" BIN="$BIN" NX="$NX" NY="$NY" GAMMA="$GAMMA" \
      STEPS="$BOUNDARY_STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" CLEAN_RUN_ROOT=1 \
      SPECIES_Q6_COMPARISON_TOLERANCE="$SPECIES_Q6_COMPARISON_TOLERANCE" \
      bash scripts/run_0491g_species_q6_boundary_darcy_matrix.sh

for seed in $PATH_SEEDS; do
  run_stage_0491h "0491d_path_seed_${seed}" path_matrix "$RUN_ROOT/path_matrix_seed_${seed}" \
    env MATRIX_ROOT="$RUN_ROOT/path_matrix_seed_${seed}" BIN="$BIN" NX="$NX" NY="$NY" GAMMA="$GAMMA" \
        SEED="$seed" STEPS="$PATH_STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" CLEAN_RUN_ROOT=1 \
        SPECIES_Q6_COMPARISON_TOLERANCE="$SPECIES_Q6_COMPARISON_TOLERANCE" \
        bash scripts/run_0491d_species_q6_path_matrix.sh
done

run_custom_periodic_0491h persistent_interface interface "$CUSTOM_STEPS"
run_custom_periodic_0491h trace_species trace "$CUSTOM_STEPS"

run_stage_0491h long_src_q6_weighted long_q6 "$RUN_ROOT/long_src_q6_weighted" \
  env RUN_ROOT="$RUN_ROOT/long_src_q6_weighted" BIN="$BIN" NX="$NX" NY="$NY" GAMMA="$GAMMA" \
      STEPS="$LONG_Q6_STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" CLEAN_RUN_ROOT=1 \
      SPECIES_Q6_COMPARISON_TOLERANCE="$SPECIES_Q6_COMPARISON_TOLERANCE" \
      bash scripts/run_0491e_species_q6_strict_resident_audit.sh

run_stage_0491h long_src_resampling_q6_weighted long_resampling_q6 "$RUN_ROOT/long_src_resampling_q6_weighted" \
  env BIN="$BIN" AUTO_BUILD=0 BUILD_IF_STALE=0 FORCE_BUILD=0 \
      BASE_RUN_ROOT="$RUN_ROOT/long_src_resampling_q6_weighted" RUN_MODES="src-q6-resampling" \
      NX="$NX" NY="$NY" GAMMA="$GAMMA" SEED=491109 STEPS="$LONG_RESAMPLING_Q6_STEPS" \
      SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY=0 CLEAN_RUN_ROOT=1 \
      LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 FILTERED_RECORDING_ENABLE=0 \
      Q6_STRICT=1 SPECIES_Q6_ENABLE=true SPECIES_Q6_MODE=weighted \
      SPECIES_Q6_SENSITIVITY=1.0 SPECIES_Q6_FALLBACK_MODE=common \
      SPECIES_Q6_COMPARISON_TOLERANCE="$SPECIES_Q6_COMPARISON_TOLERANCE" \
      LIQUID_TO_GAS_MASS_RATIO="$LIQUID_TO_GAS_MASS_RATIO" \
      bash scripts/run_ok_injection_type1_into_type2_empty.sh

python3 scripts/summarize_0491h_species_q6_software_validation.py \
  --root "$RUN_ROOT" \
  --status "$STATUS" \
  --profile "$VALIDATION_PROFILE" \
  --mass-relative-tolerance "$MASS_RELATIVE_TOLERANCE" \
  --csv "$RUN_ROOT/species_q6_software_validation_0491h.csv" \
  --markdown "$RUN_ROOT/species_q6_software_validation_0491h.md"
summary_rc=$?

echo "[0491h] audit=$RUN_ROOT/species_q6_software_validation_0491h.csv"
echo "[0491h] report=$RUN_ROOT/species_q6_software_validation_0491h.md"
exit "$summary_rc"
