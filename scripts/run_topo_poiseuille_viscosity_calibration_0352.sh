#!/usr/bin/env bash
set -euo pipefail

# 0352/topo: Poiseuille viscosity calibration launcher for the NACA/topology
# parameter family.  This script is deliberately a launcher only; the viscosity
# fit is expected to be done with the existing MATLAB analyze_poiseuille_profile
# scripts or equivalent.
#
# Default geometry preserves the cell size of a prospective NACA grid
# Lx=1.5, Ly=0.4, Nx=600, Ny=160, but uses a shorter periodic streamwise domain
# for the Poiseuille calibration:
#   dy = Ly / NACA_NY
#   POISE_LX = POISE_NX * dy
#   POISE_NY = NACA_NY
#
# This keeps the transverse resolution and wall/cell size relevant to the NACA
# sweep while avoiding an unnecessary 600-cell streamwise domain.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source scripts/src_gpu_demo_common_0283.sh

NACA_LX="${NACA_LX:-1.5}"
NACA_LY="${NACA_LY:-0.4}"
NACA_NX="${NACA_NX:-600}"
NACA_NY="${NACA_NY:-160}"

NX="${NX:-128}"
NY="${NY:-$NACA_NY}"
Ly="${Ly:-$NACA_LY}"
if [[ -z "${Lx:-}" ]]; then
  Lx="$(python3 - <<PY
Ly=float("${Ly}")
Nx=int("${NX}")
Ny=int("${NY}")
print("{:.17g}".format(Nx*Ly/Ny))
PY
)"
fi

GAMMA="${GAMMA:-10}"
STEPS="${STEPS:-30000}"
DT="${DT:-0.0005}"
KBT="${KBT:-0.1}"
SEED="${SEED:-1628520}"
SUMMARY_EVERY="${SUMMARY_EVERY:-200}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
BODY_AX="${BODY_AX:-0.002}"
U0_INIT="${U0_INIT:-0.0}"
THREADS="${THREADS:-12}"

BIN="${BIN:-build/src_mpcd_base_cuda_topo_0348a}"
CASE_NAME="topo_poiseuille_viscosity_calibration_0352"
RUN_ROOT="${RUN_ROOT:-runs/${CASE_NAME}_nx${NX}_ny${NY}_g${GAMMA}}"

# Keep dumps compact for MATLAB profile fitting.
export DUMP_ROLE_FILTER="${DUMP_ROLE_FILTER:-fluid}"
export SUMMARY_ROLE_FILTER="${SUMMARY_ROLE_FILTER:-fluid}"
export SRC_GPU_DEMO_REQUIRE_DUMPS="${SRC_GPU_DEMO_REQUIRE_DUMPS:-1}"
export INACTIVE_SLOTS="${INACTIVE_SLOTS:-0}"
export CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

prepare_demo_dirs_0283 "$RUN_ROOT"

STATE_FILE="$RUN_ROOT/init/${CASE_NAME}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS_FILE="$RUN_ROOT/params/${CASE_NAME}.kv"
OUT_DIR="$RUN_ROOT/output"
LOG_FILE="$RUN_ROOT/logs/${CASE_NAME}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_NAME}.time"
META_FILE="$RUN_ROOT/logs/poiseuille_calibration_0352.env"
HINT_FILE="$RUN_ROOT/logs/poiseuille_viscosity_fit_hint_0352.txt"

generate_demo_state_0283 "$STATE_FILE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" \
  poiseuille_x "$U0_INIT" 0.0 0.0 0.0 -1.0 0.0 -1.0 "$INACTIVE_SLOTS" none

mkdir -p "$OUT_DIR"
cat > "$PARAMS_FILE" <<PARAMS
inputState = ${STATE_FILE}
outputDir = ${OUT_DIR}

Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}

bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = solid

bodyAccelerationX = ${BODY_AX}
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false

wallAccommodation = 1.0
wallVpGamma = ${GAMMA}
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
wallUxBottom = 0.0
wallUyBottom = 0.0
wallUxTop = 0.0
wallUyTop = 0.0

$(write_src_classic_common_params_0283 "$STEPS" "$DT" "$KBT" "$SEED" "$SUMMARY_EVERY" "$DUMP_STATE_EVERY" "$THREADS")
PARAMS

cat > "$META_FILE" <<META
CASE_NAME=${CASE_NAME}
RUN_ROOT=${RUN_ROOT}
BIN=${BIN}
NACA_LX=${NACA_LX}
NACA_LY=${NACA_LY}
NACA_NX=${NACA_NX}
NACA_NY=${NACA_NY}
POISE_Lx=${Lx}
POISE_Ly=${Ly}
POISE_NX=${NX}
POISE_NY=${NY}
GAMMA=${GAMMA}
STEPS=${STEPS}
DT=${DT}
KBT=${KBT}
SEED=${SEED}
BODY_AX=${BODY_AX}
U0_INIT=${U0_INIT}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY}
SUMMARY_EVERY=${SUMMARY_EVERY}
DUMP_ROLE_FILTER=${DUMP_ROLE_FILTER}
SUMMARY_ROLE_FILTER=${SUMMARY_ROLE_FILTER}
META

cat > "$HINT_FILE" <<HINT
Poiseuille viscosity fit hint (0352)
------------------------------------
For acceleration forcing a_x = BODY_AX and channel height H = Ly:

  u(y) = A y (H-y) + B
  nu_eff = a_x / (2 A)

Equivalent using Umax after a reliable steady fit:

  nu_eff = a_x H^2 / (8 Umax)

Recommended fitting practice:
  - average profiles over the final steady window;
  - exclude 2 to 4 cells near each wall;
  - check symmetry and R^2;
  - use the same dt, kBT, gamma and Ny/cell size as the future NACA sweep.

This run:
  BODY_AX=${BODY_AX}
  H=${Ly}
  params=${PARAMS_FILE}
  output=${OUT_DIR}
HINT

src_gpu_cuda_env_wall_resident_thermostat_0283

echo "[0352-poiseuille-calib] run_root=$RUN_ROOT"
echo "[0352-poiseuille-calib] binary=$BIN"
echo "[0352-poiseuille-calib] params=$PARAMS_FILE"
echo "[0352-poiseuille-calib] meta=$META_FILE"
echo "[0352-poiseuille-calib] hint=$HINT_FILE"
echo "[0352-poiseuille-calib] adopted-naca-grid=${NACA_NX}x${NACA_NY} domain=${NACA_LX}x${NACA_LY}"
echo "[0352-poiseuille-calib] poiseuille-grid=${NX}x${NY} domain=${Lx}x${Ly} gamma=${GAMMA} particles=$((NX*NY*GAMMA))"

run_demo_case_0283 "$PARAMS_FILE" "$LOG_FILE" "$TIME_FILE" "$OUT_DIR"

echo "[0352-poiseuille-calib] dumps:"
find "$OUT_DIR" -maxdepth 1 -name 'state_step_*.smpcd' -type f | sort | tail -10
echo "[0352-poiseuille-calib] done"
