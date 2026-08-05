#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0493x4b: compare the validated 0493x4a one-solve path using a separate
# force-kick kernel with the resident CUDA path that fuses tentative-force
# deposition and force+Q6 application into the Q6 particle passes.
CASE_LABEL="q6_force_fusion_tg_0493x4b"
GEN_CASE="tg"
TOPOLOGY="periodic"
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-64}"; NY="${NY:-64}"
GAMMA="${GAMMA:-40}"; STEPS="${STEPS:-500}"; DT="${DT:-0.001}"; KBT="${KBT:-0.001}"
SEED="${SEED:-493400}"; U0="${U0:-0.04}"; VELOCITY_MODE="${VELOCITY_MODE:-taylor_green}"
TG_FORCING_AMPLITUDE="${TG_FORCING_AMPLITUDE:-0.02}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x4b_q6_force_fusion_tg_${NX}x${NY}_g${GAMMA}_s${STEPS}}"
SUMMARY_EVERY="${SUMMARY_EVERY:-20}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-20}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.25}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
NULL_NUMERICAL_TOLERANCE="${NULL_NUMERICAL_TOLERANCE:-1.0e-12}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-false}"
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-10}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE="${PROJECTION_MOMENTUM_CORRECTION_ENABLE:-true}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"
RUN_MODE="src-q6"

suite_defaults_common_0434
suite_compute_derived_0434

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then
  rm -rf "$BASE_RUN_ROOT"
fi
mkdir -p "$BASE_RUN_ROOT/init_shared"
SHARED_STATE="$BASE_RUN_ROOT/init_shared/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
suite_generate_case_0434 "$SHARED_STATE" ""

write_params_0493x4b() {
  local out=$1 params=$2 force_mode=$3 forcing_enable=$4
  local forcing_amplitude=0.0
  if suite_truthy_0434 "$forcing_enable"; then
    forcing_amplitude="$TG_FORCING_AMPLITUDE"
  fi
  cat > "$params" <<PARAMS
inputState = $SHARED_STATE
outputDir = $out
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = $forcing_enable
taylorGreenForcingAmplitude = $forcing_amplitude
taylorGreenForcingModeX = 1
taylorGreenForcingModeY = 1
q6ForceProjectionMode = $force_mode
PARAMS
  suite_write_common_params_0434 "$RUN_MODE" >> "$params"
}

run_case_0493x4b() {
  local case_name=$1 force_mode=$2 forcing_enable=$3
  local run_root="$BASE_RUN_ROOT/$case_name"
  suite_prepare_dirs_0434 "$run_root"
  local params="$run_root/params/${CASE_LABEL}.kv"
  local out="$run_root/output"
  local log="$run_root/logs/${CASE_LABEL}.log"
  local time_file="$run_root/logs/${CASE_LABEL}.time"
  mkdir -p "$out"
  write_params_0493x4b "$out" "$params" "$force_mode" "$forcing_enable"
  suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
  suite_prepare_livevis_control_0434 "$run_root" "$RUN_MODE"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0434.env" "$RUN_MODE"
  cat >> "$run_root/logs/environment_0434.env" <<META
Q6_FORCE_PROJECTION_MODE=$force_mode
TG_FORCING_ENABLE=$forcing_enable
TG_FORCING_AMPLITUDE=$TG_FORCING_AMPLITUDE
META
  local case_amplitude=0.0
  if suite_truthy_0434 "$forcing_enable"; then
    case_amplitude="$TG_FORCING_AMPLITUDE"
  fi
  echo "[0493x4b] case=$case_name mode=$force_mode forcing=$forcing_enable amplitude=$case_amplitude"
  suite_run_binary_0434 "$params" "$log" "$time_file" "$out"
}

STATUS="$BASE_RUN_ROOT/launch_status.csv"
echo "case,exit_code" > "$STATUS"
failures=0
for spec in \
  "null_single prestream_single false" \
  "null_fused prestream_single_fused false" \
  "forced_single prestream_single true" \
  "forced_fused prestream_single_fused true"; do
  read -r case_name force_mode forcing_enable <<< "$spec"
  set +e
  run_case_0493x4b "$case_name" "$force_mode" "$forcing_enable"
  rc=$?
  set -e
  echo "$case_name,$rc" >> "$STATUS"
  if [[ "$rc" != 0 ]]; then failures=$((failures + 1)); fi
done

if [[ "$failures" != 0 ]]; then
  echo "[0493x4b] FAIL: run failures=$failures" >&2
  exit 1
fi
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo "[0493x4b] preflight PASS root=$BASE_RUN_ROOT"
  exit 0
fi

python3 scripts/analyze_0493x4b_q6_force_fusion_tg.py \
  --root "$BASE_RUN_ROOT" --Lx "$Lx" --Ly "$Ly" \
  --null-tolerance "$NULL_NUMERICAL_TOLERANCE" \
  --csv "$BASE_RUN_ROOT/q6_force_fusion_tg_0493x4b.csv" \
  --report "$BASE_RUN_ROOT/q6_force_fusion_tg_0493x4b.md"

echo "[0493x4b] root=$BASE_RUN_ROOT"
echo "[0493x4b] csv=$BASE_RUN_ROOT/q6_force_fusion_tg_0493x4b.csv"
echo "[0493x4b] report=$BASE_RUN_ROOT/q6_force_fusion_tg_0493x4b.md"
