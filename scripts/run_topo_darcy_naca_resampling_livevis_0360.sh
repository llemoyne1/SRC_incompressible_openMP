#!/usr/bin/env bash
set -euo pipefail

# 0360: visible high-incidence NACA validation for Darcy alone versus
# Darcy + CUDA-resident chi-filtered resampling/refill.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NACA_CODE="${NACA_CODE:-0012}"
AOA_DEG="${AOA_DEG:-18}"
Lx="${Lx:-1.5}"
Ly="${Ly:-0.4}"
NX="${NX:-360}"
NY="${NY:-96}"
GAMMA="${GAMMA:-12}"
KBT="${KBT:-0.01}"
DT="${DT:-0.0005}"
U0="${U0:-1.0}"
STEPS="${STEPS:-2000}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-500000}"
CHORD="${CHORD:-0.22}"
AIRFOIL_CX="${AIRFOIL_CX:-0.55}"
AIRFOIL_CY="${AIRFOIL_CY:-0.20}"
DARCY_INTERFACE_WIDTH="${DARCY_INTERFACE_WIDTH:-0.004}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-320}"
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-20}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}"
LIVE_VIS_NX="${LIVE_VIS_NX:-720}"
LIVE_VIS_NY="${LIVE_VIS_NY:-192}"
LIVE_VIS_CONTROL_DIR="${LIVE_VIS_CONTROL_DIR:-${LIVE_VIS_DIR:-${LIVEVIS_DIR:-${livevis_dir:-.}}}}"
LIVE_VIS_CONTROL_BASENAME="${LIVE_VIS_CONTROL_BASENAME:-${LIVE_VIS_BASENAME:-livevis_control.kv}}"
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-${LIVE_VIS_CONTROL_DIR%/}/${LIVE_VIS_CONTROL_BASENAME}}"
LIVE_VIS_CONTROL_RESET="${LIVE_VIS_CONTROL_RESET:-0}"
RESAMPLING_CHI_MIN="${RESAMPLING_CHI_MIN:-0.5}"
EMPTY_REFILL_TARGET_FRACTION="${EMPTY_REFILL_TARGET_FRACTION:-1.}"
BIN="${BIN:-build/src_mpcd_base_cuda_darcy_resamp_0360}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
TAG_PREFIX="${TAG_PREFIX:-topo_darcy_naca_resampling_livevis_0360}"
RUN_ROOT="runs/${TAG_PREFIX}"
CHI_DIR="${RUN_ROOT}/chi"
mkdir -p "$CHI_DIR" "${RUN_ROOT}/logs"

if [[ "$AOA_DEG" == -* ]]; then
  aoa_tag="am${AOA_DEG#-}"
else
  aoa_tag="a${AOA_DEG}"
fi
aoa_tag="${aoa_tag//./p}"
chi_file="${CHI_DIR}/naca${NACA_CODE}_${aoa_tag}_${NX}x${NY}.f32"

python3 scripts/generate_topo_chi_field_0345.py \
  --mode naca4_airfoil \
  --out "$chi_file" \
  --Nx "$NX" --Ny "$NY" \
  --Lx "$Lx" --Ly "$Ly" \
  --naca "$NACA_CODE" \
  --chord "$CHORD" \
  --airfoil-cx "$AIRFOIL_CX" \
  --airfoil-cy "$AIRFOIL_CY" \
  --aoa-deg "$AOA_DEG" \
  --interface-width "$DARCY_INTERFACE_WIDTH" \
  | tee "${RUN_ROOT}/logs/generate_${aoa_tag}.log"

run_case() {
  local mode="$1"
  local resampling_enable="$2"
  local seed="$3"
  local tag="${TAG_PREFIX}_${mode}_naca${NACA_CODE}_${aoa_tag}"

  echo "[0360-naca-livevis] mode=${mode} resampling=${resampling_enable} tag=${tag}"
  BIN="$BIN" \
  FORCE_REBUILD="$FORCE_REBUILD" \
  Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" \
  GAMMA="$GAMMA" KBT="$KBT" DT="$DT" U0="$U0" \
  SEED="$seed" STEPS="$STEPS" INACTIVE_SLOTS="$INACTIVE_SLOTS" \
  DARCY_CHI_MODE=file \
  DARCY_CHI_FILE="$chi_file" \
  DARCY_CHI_FILE_FORMAT=float32 \
  DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
  DARCY_Q="$DARCY_Q" \
  DARCY_INTERFACE_WIDTH="$DARCY_INTERFACE_WIDTH" \
  DARCY_COST_EVERY="$DARCY_COST_EVERY" \
  TOPO_RESAMPLING_ENABLE="$resampling_enable" \
  RESAMPLING_CHI_FILTER_ENABLE=1 \
  RESAMPLING_CHI_MIN="$RESAMPLING_CHI_MIN" \
  EMPTY_REFILL_ENABLE="$resampling_enable" \
  EMPTY_REFILL_TARGET_FRACTION="$EMPTY_REFILL_TARGET_FRACTION" \
  EMPTY_REFILL_REFERENCE=nTarget \
  GUARD_NMIN="${GUARD_NMIN:-10}" \
  GUARD_NTARGET="${GUARD_NTARGET:-$GAMMA}" \
  GUARD_NMAX="${GUARD_NMAX:-14}" \
  MASS_RECONDITION_ENABLE="$resampling_enable" \
  MASS_RECONDITION_EVERY="${MASS_RECONDITION_EVERY:-5}" \
  GUARD_EVERY="${GUARD_EVERY:-1}" \
  LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
  LIVE_VIS_FIELD="$LIVE_VIS_FIELD" \
  LIVE_VIS_EVERY="$LIVE_VIS_EVERY" \
  LIVE_VIS_NX="$LIVE_VIS_NX" \
  LIVE_VIS_NY="$LIVE_VIS_NY" \
  LIVE_VIS_CONTROL_FILE="$LIVE_VIS_CONTROL_FILE" \
  LIVE_VIS_CONTROL_RESET="$LIVE_VIS_CONTROL_RESET" \
  CLEAN_RUN_ROOT=1 \
  TAG="$tag" \
    bash scripts/run_topo_darcy_brinkman_viz_0343.sh \
    2>&1 | tee "${RUN_ROOT}/logs/run_${mode}_${aoa_tag}.log"
}

run_case classic 0 1860001
run_case resampling_refill 1 1860001

echo "[0360-naca-livevis] chi=${chi_file}"
echo "[0360-naca-livevis] classic=runs/${TAG_PREFIX}_classic_naca${NACA_CODE}_${aoa_tag}"
echo "[0360-naca-livevis] resampling=runs/${TAG_PREFIX}_resampling_refill_naca${NACA_CODE}_${aoa_tag}"
