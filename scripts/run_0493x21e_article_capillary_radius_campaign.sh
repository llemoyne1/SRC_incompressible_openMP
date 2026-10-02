#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0493x21e — Section 3.4 article production campaign.
# Purpose: directly produce the requested capillary tables and 3-panel figure.
# No solver modification, no build, no long sigma=0 baseline.
# Each realization = relaxed active drop + one same-checkpoint active/sigma0 shadow pair.

CASE_LABEL=article_capillary_radius_0493x21e
RUN_MODE=src-q6-g-f
TOPOLOGY=closed_box
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
EXPECTED_BIN_SHA256="${EXPECTED_BIN_SHA256:-422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc}"
GENERATOR="$ROOT/scripts/generate_0493x9s_splash_state.py"
ANALYZER="$ROOT/scripts/analyze_0493x21e_article_capillary_radius_campaign.py"
RECON_HELPER="$ROOT/scripts/analyze_0493x13n_rim_traction_v2.py"

for f in "$BIN" "$GENERATOR" "$ANALYZER" "$RECON_HELPER" "$ROOT/scripts/src_mpcd_run_common_0434.sh"; do
  [[ -f "$f" ]] || { echo "[0493x21e] ERROR missing $f" >&2; exit 2; }
done
[[ -x "$BIN" ]] || { echo "[0493x21e] ERROR binary not executable: $BIN" >&2; exit 2; }
ACTUAL_BIN_SHA256="$(sha256sum "$BIN" | awk '{print $1}')"
[[ "$ACTUAL_BIN_SHA256" == "$EXPECTED_BIN_SHA256" ]] || {
  echo "[0493x21e] ERROR binary hash mismatch" >&2
  echo " expected=$EXPECTED_BIN_SHA256" >&2
  echo " actual  =$ACTUAL_BIN_SHA256" >&2
  echo " Override EXPECTED_BIN_SHA256 only if intentionally continuing with another traced binary." >&2
  exit 2
}

# HARD no-build policy.
export FORCE_BUILD=0 AUTO_BUILD=0 BUILD_IF_STALE=0

# Nominal article fluid, exact current free-surface chain.
NX="${NX:-256}"; NY="${NY:-256}"; Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-8}"; DT="${DT:-0.0063471328149122585}"; KBT="${KBT:-0.125}"
LIQUID_TYPE=1; LIQUID_MASS=1.0
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3

# Resolved radius map around the validated R/h=64 pilot.  R=40 remains safely
# above the x12a radius and the x9r cutoff scale; R=80 retains 48 cells clearance.
RADII="${RADII:-40 48 56 64 72 80}"
SEEDS="${SEEDS:-4932401 4933401 4934401}"
SIGMA_TARGET="${SIGMA_TARGET:-10000}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
ACTIVE_STEPS="${ACTIVE_STEPS:-1500}"
ACTIVE_SUMMARY_EVERY="${ACTIVE_SUMMARY_EVERY:-5}"
ACTIVE_DUMP_EVERY="${ACTIVE_DUMP_EVERY:-100}"
SHADOW_STEPS="${SHADOW_STEPS:-2}"
THREADS="${THREADS:-8}"
RESTART="${RESTART:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE_ACTIVE="${LIVE_VIS_ENABLE_ACTIVE:-0}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x21e_article_capillary_radius_s${SIGMA_TARGET}}"
MANIFEST="$CAMPAIGN_ROOT/manifest_0493x21e.csv"
mkdir -p "$CAMPAIGN_ROOT" "$CAMPAIGN_ROOT/audit"
export OMP_NUM_THREADS="$THREADS"

# Q6-g-f controls.
PROJECTION_BACKEND=cuda; PROJECTION_OPERATOR=auto_fv_cg; PROJECTION_MAX_ITERATIONS=2000; PROJECTION_TOLERANCE=1.0e-5; PROJECTION_MOMENTUM_CORRECTION_ENABLE=false
Q6_PROJECTION_STRENGTH=1.0; Q6_STRICT=1; Q6_FORCE_PROJECTION_MODE=prestream_single_fused
Q6_GF_EXTERNAL_SPECIES=1; Q6_GF_HAS_GAS_PHASE=0; Q6_GF_DENSITY_RELAXATION_TIME=0.25; Q6_GF_MIN_FILL_FRACTION=0.10
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1; Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3.0; Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6.0; Q6_GF_DENSITY_TRACTION_GAIN=1.0
SPECIES_RESAMPLING_ENABLE=false; LIQUID_RESAMPLING_ENABLE=false; GAS_RESAMPLING_ENABLE=false; VIRIAL_DENSITY_KICK_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero; PARTICLE_MASS="$LIQUID_MASS"; BACKGROUND_TYPE="$LIQUID_TYPE"; INACTIVE_TYPE="$LIQUID_TYPE"; TG_HOLE_ENABLE=false

export NX NY Lx Ly GAMMA DT KBT LIQUID_TYPE LIQUID_MASS PARTICLE_MASS BACKGROUND_TYPE INACTIVE_TYPE
export ROTATION_ANGLE RANDOM_ROTATION_SIGN GRID_SHIFT_ENABLE THERMOSTAT_ENABLE THERMOSTAT_MODE THERMOSTAT_EVERY THERMOSTAT_TARGET_KBT THERMOSTAT_MIN_PARTICLES
export PROJECTION_BACKEND PROJECTION_OPERATOR PROJECTION_MAX_ITERATIONS PROJECTION_TOLERANCE PROJECTION_MOMENTUM_CORRECTION_ENABLE
export Q6_PROJECTION_STRENGTH Q6_STRICT Q6_FORCE_PROJECTION_MODE Q6_GF_EXTERNAL_SPECIES Q6_GF_HAS_GAS_PHASE Q6_GF_DENSITY_RELAXATION_TIME Q6_GF_MIN_FILL_FRACTION
export Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES Q6_GF_DENSITY_TRACTION_GAIN
export SPECIES_RESAMPLING_ENABLE LIQUID_RESAMPLING_ENABLE GAS_RESAMPLING_ENABLE VIRIAL_DENSITY_KICK_ENABLE WEIGHTED_RESAMPLING_ENABLE_OVERRIDE CUDA_EMPTY_REFILL_ENABLE_OVERRIDE
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS LIVE_PROGRESS

suite_defaults_common_0434
suite_compute_derived_0434
suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"

# Production free-surface/capillary chain + existing scalar audits.
export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
export MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0
export MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1
export MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=0
export MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1
export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=1
export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0 MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0 MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=0
export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0 MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0 MPCD_X10M_MOVING_INTERFACE_WALL=0 MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1 MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS" MPCD_X10O_THERMAL_SIGMAS=3.0 MPCD_X10O_THERMAL_MAX_CELLS=0.75
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1 MPCD_X10_KINETIC_INTERFACE_CIC=1 MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1 MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0 MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0 MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0 MPCD_X12A_LOCAL_THERMAL_COOLING=1

H="$(awk -v lx="$Lx" -v nx="$NX" 'BEGIN{printf "%.17g",lx/nx}')"
LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"

python3 - "$H" "$SIGMA_TARGET" "$GAMMA" "$KBT" "$MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS" "$SURFACE_TENSION_MIN_RADIUS_CELLS" $RADII <<'PY'
import sys
h,sig,g,kbt,rcool,rmin=map(float,sys.argv[1:7]); radii=list(map(float,sys.argv[7:])); pth=g*kbt/h**2
print('===== 0493x21e SECTION 3.4 RADIUS CAMPAIGN =====')
print('radii=',','.join(f'{r:g}' for r in radii),' sigma=',sig,' seeds=3')
for r in radii:
    if r<=rcool+8: raise SystemExit(f'R/h={r:g} too close to x12a radius {rcool:g}')
    if r<=4*rmin: raise SystemExit(f'R/h={r:g} too close to x9r minimum radius')
    if 128-r<40: raise SystemExit(f'R/h={r:g} leaves <40 cells wall clearance')
    dp=sig/(r*h)
    print(f'R/h={r:5g} wallClearance/h={128-r:5g} dp/pThermal={dp/pth:8.3%}')
print('protocol=relaxed active drop -> plateau dump -> 2-step same-state sigma/sigma0 shadows')
print('curvature=offline exact x6c->p3->alpha0.5 face interpolation->x9r cutoff, validated against runtime x9r counters')
print('buildPolicy=HARD_NO_BUILD')
PY

write_params() {
  local state="$1" out="$2" params="$3" sigma="$4" steps="$5" dump="$6" summary="$7" seed="$8"
  SEED="$seed"; SUMMARY_EVERY="$summary"; DUMP_STATE_EVERY="$dump"; SUMMARY_ROLE_FILTER=fluid; DUMP_ROLE_FILTER=fluid
  export SEED SUMMARY_EVERY DUMP_STATE_EVERY SUMMARY_ROLE_FILTER DUMP_ROLE_FILTER
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $steps
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
wallVpEnable = false
wallAccommodation = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
surfaceTensionSigma = $sigma
surfaceTensionMinRadiusCells = $SURFACE_TENSION_MIN_RADIUS_CELLS
phaseInterfaceKineticReflectionFraction = 1.0
phaseInterfaceEvaporationTargetType = -1
phaseInterfaceASelector = type:$LIQUID_TYPE
phaseInterfaceBSelector = vacuum
phaseInterfaceContactAngleDegrees = -1
speciesRegistryEnable = true
speciesCount = 1
species0 = $LIQUID_TYPE q6_g_f_liquid liquid 1.0 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $Q6_GF_MIN_FILL_FRACTION
PARAMS
  suite_write_common_params_0434 "$RUN_MODE" >> "$params"
}

set_livevis() {
  local root="$1" enabled="$2"
  LIVE_VIS_ENABLE="$enabled"; LIVE_VIS_EVERY=1000; LIVE_VIS_FIELD=mass; LIVE_VIS_HOLD_ON_EXIT=0; LIVE_VIS_RECORD_ENABLE=0; FILTERED_RECORDING_ENABLE=0
  PARTICLE_TYPE_FILTER="$LIQUID_TYPE"; OVERWRITE_LIVEVIS_CONTROL=1; LIVE_VIS_CONTROL_FILE="$root/livevis_control_0493x21e.kv"
  export LIVE_VIS_ENABLE LIVE_VIS_EVERY LIVE_VIS_FIELD LIVE_VIS_HOLD_ON_EXIT LIVE_VIS_RECORD_ENABLE FILTERED_RECORDING_ENABLE PARTICLE_TYPE_FILTER OVERWRITE_LIVEVIS_CONTROL LIVE_VIS_CONTROL_FILE
  suite_prepare_livevis_control_0434 "$root" "$RUN_MODE"; suite_export_livevis_0434
}

run_binary_case() {
  local params="$1" log="$2" tf="$3" out="$4"
  suite_run_binary_0434 "$params" "$log" "$tf" "$out"
}

is_complete_active() {
  local f="$1"
  [[ -s "$f" ]] || return 1
  local last
  last="$(tail -n 1 "$f" | cut -d, -f1 | awk '{printf "%d",$1}')"
  (( last >= ACTIVE_STEPS ))
}

is_complete_shadow() {
  local f="$1"
  [[ -s "$f" ]] || return 1
  awk -F, 'NR>1 && ($1+0)>0 {ok=1} END{exit(ok?0:1)}' "$f"
}

# Fresh manifest describing all 18 independent active realizations and their paired shadows.
echo 'radiusCells,seed,activeRoot,selectionCsv,shadowActiveRoot,shadowZeroRoot' > "$MANIFEST"

for RC in $RADII; do
  RPHYS="$(awk -v r="$RC" -v h="$H" 'BEGIN{printf "%.17g",r*h}')"
  for SEED0 in $SEEDS; do
    TAG="R${RC}_seed${SEED0}"
    ACTIVE="$CAMPAIGN_ROOT/active/$TAG"
    SEL="$ACTIVE/analysis/selected_checkpoint_0493x21e.csv"
    STATE="$ACTIVE/init/${CASE_LABEL}_${TAG}.smpcd"
    PARAMS="$ACTIVE/params/${CASE_LABEL}_${TAG}.kv"
    OUT="$ACTIVE/output"; LOG="$ACTIVE/logs/${CASE_LABEL}_${TAG}.log"; TF="$ACTIVE/logs/${CASE_LABEL}_${TAG}.time"
    mkdir -p "$ACTIVE"/{init,output,params,logs,analysis}

    if [[ "$RESTART" == 1 ]] && is_complete_active "$OUT/cuda_static_drop_pressure_0493x9e.csv"; then
      echo "[0493x21e] REUSE active $TAG"
    else
      echo "[0493x21e] ACTIVE $TAG R/h=$RC sigma=$SIGMA_TARGET"
      rm -rf "$ACTIVE"; mkdir -p "$ACTIVE"/{init,output,params,logs,analysis}
      python3 "$GENERATOR" --output "$STATE" --target wall --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
        --gamma "$GAMMA" --drop-center-x 0.5 --drop-center-y 0.5 --drop-radius "$RPHYS" --drop-vx 0 --drop-vy 0 --puddle-depth 0 \
        --liquid-type "$LIQUID_TYPE" --liquid-mass "$LIQUID_MASS" --kBT "$KBT" --seed "$SEED0"
      write_params "$STATE" "$OUT" "$PARAMS" "$SIGMA_TARGET" "$ACTIVE_STEPS" "$ACTIVE_DUMP_EVERY" "$ACTIVE_SUMMARY_EVERY" "$SEED0"
      export MPCD_X11C_FORCE_X9E_SIGMA0=0
      set_livevis "$ACTIVE" "$LIVE_VIS_ENABLE_ACTIVE"
      suite_write_env_file_0434 "$ACTIVE/logs/environment_0493x21e.env" "$RUN_MODE"
      run_binary_case "$PARAMS" "$LOG" "$TF" "$OUT"
    fi

    python3 "$ANALYZER" select-checkpoint --run-root "$ACTIVE" --radius-cells "$RC" --seed "$SEED0" --out "$SEL"
    # Read the selector output with Python's CSV parser.  The file is written
    # with RFC-compatible CRLF records, so parsing it as raw comma-delimited
    # shell text can leave the record terminator attached to checkpointState.
    IFS=$'\t' read -r CPSTEP CPSTATE < <(
      python3 - "$SEL" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    row = next(csv.DictReader(f))
print(f"{row['checkpointStep']}\t{row['checkpointState']}")
PY
    )
    [[ -s "$CPSTATE" ]] || { echo "[0493x21e] ERROR selected state missing: $CPSTATE" >&2; exit 2; }
    PROBE_SEED=$(( 4932500 + 1000*RC + SEED0 % 997 ))

    SHA="$CAMPAIGN_ROOT/shadows/$TAG/active"
    SHZ="$CAMPAIGN_ROOT/shadows/$TAG/sigma0"
    for ROLE in active sigma0; do
      if [[ "$ROLE" == active ]]; then SR="$SHA"; SS="$SIGMA_TARGET"; export MPCD_X11C_FORCE_X9E_SIGMA0=0; else SR="$SHZ"; SS=0; export MPCD_X11C_FORCE_X9E_SIGMA0=1; fi
      mkdir -p "$SR"/{output,params,logs}
      SP="$SR/params/${CASE_LABEL}_${TAG}_${ROLE}.kv"; SL="$SR/logs/${CASE_LABEL}_${TAG}_${ROLE}.log"; STF="$SR/logs/${CASE_LABEL}_${TAG}_${ROLE}.time"
      if [[ "$RESTART" == 1 ]] && is_complete_shadow "$SR/output/cuda_static_drop_pressure_0493x9e.csv"; then
        echo "[0493x21e] REUSE shadow $TAG $ROLE"
      else
        rm -rf "$SR"; mkdir -p "$SR"/{output,params,logs}
        write_params "$CPSTATE" "$SR/output" "$SP" "$SS" "$SHADOW_STEPS" 0 1 "$PROBE_SEED"
        set_livevis "$SR" 0
        echo "[0493x21e] SHADOW $TAG cp=$CPSTEP role=$ROLE sigma=$SS"
        run_binary_case "$SP" "$SL" "$STF" "$SR/output"
      fi
    done
    echo "$RC,$SEED0,$ACTIVE,$SEL,$SHA,$SHZ" >> "$MANIFEST"
  done
done

{
  echo campaign=0493x21e_article_capillary_radius
  echo date="$(date -Iseconds 2>/dev/null || true)"
  echo gitHead="$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
  echo binary="$BIN"
  echo binarySha256="$ACTUAL_BIN_SHA256"
  echo sigmaTarget="$SIGMA_TARGET"
  echo radii="$RADII"
  echo seeds="$SEEDS"
  echo activeSteps="$ACTIVE_STEPS"
  echo activeSummaryEvery="$ACTIVE_SUMMARY_EVERY"
  echo activeDumpEvery="$ACTIVE_DUMP_EVERY"
  echo shadowSteps="$SHADOW_STEPS"
  echo protocol='relaxed active states + one-step paired shadows; no long sigma0 baseline'
  echo buildPolicy=FORCE_BUILD0_AUTO_BUILD0_BUILD_IF_STALE0
  sha256sum "$ANALYZER" "$RECON_HELPER" "$GENERATOR" "$ROOT/scripts/src_mpcd_run_common_0434.sh" "$BIN"
} > "$CAMPAIGN_ROOT/audit/traceability_0493x21e.txt"

python3 "$ANALYZER" final --repo "$ROOT" --campaign-root "$CAMPAIGN_ROOT" --manifest "$MANIFEST" --sigma "$SIGMA_TARGET" --binary-sha256 "$ACTUAL_BIN_SHA256"

echo "[0493x21e] DONE"
echo "[0493x21e] article package: $CAMPAIGN_ROOT/article_capillary_outputs.zip"
