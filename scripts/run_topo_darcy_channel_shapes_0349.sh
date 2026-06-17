#!/usr/bin/env bash
set -euo pipefail

# 0349/topo: qualitative channel obstacle comparisons using external chi_file.
# Runs cylinder, ellipse, and NACA-like obstacles with the same CUDA-VIZ Darcy
# benchmark observable path.  Postprocessing uses 0348b final-window statistics.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

Lx="${Lx:-1.5}"; Ly="${Ly:-0.4}"; NX="${NX:-360}"; NY="${NY:-96}"
TAG_PREFIX="${TAG_PREFIX:-topo_darcy_channel_shapes_0349}"
RUN_ROOT="runs/${TAG_PREFIX}"
CHI_DIR="${RUN_ROOT}/chi"
mkdir -p "$CHI_DIR" "${RUN_ROOT}/logs"

STEPS="${STEPS:-1800}"
TAIL_FRACTION="${TAIL_FRACTION:-0.5}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-320}"
DARCY_Q="${DARCY_Q:-0.1}"
GAMMA="${GAMMA:-40}"
KBT="${KBT:-0.1}"
U0="${U0:-0.5}"
CX="${CX:-0.55}"
CY="${CY:-0.20}"
INTERFACE_WIDTH="${INTERFACE_WIDTH:-0.008}"

summary="${RUN_ROOT}/channel_shapes_0349_summary.csv"
echo "shape,chiFile,benchmarkCsv,windowStatsCsv" > "$summary"

run_shape_0349() {
  local shape="$1"; shift
  local tag="${TAG_PREFIX}_${shape}"
  local chi="${CHI_DIR}/${shape}_${NX}x${NY}.f32"
  echo "[0349-shapes] generating shape=$shape chi=$chi"
  python3 scripts/generate_topo_chi_field_0345.py "$@" \
    --out "$chi" --Nx "$NX" --Ny "$NY" --Lx "$Lx" --Ly "$Ly" \
    --interface-width "$INTERFACE_WIDTH" \
    | tee "${RUN_ROOT}/logs/generate_${shape}.log"

  echo "[0349-shapes] running shape=$shape tag=$tag"
  BIN="${BIN:-build/src_mpcd_base_cuda_topo_0348a}" \
  Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" \
  DARCY_CHI_MODE=file DARCY_CHI_FILE="$chi" DARCY_CHI_FILE_FORMAT=float32 \
  DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" DARCY_Q="$DARCY_Q" DARCY_COST_EVERY="${DARCY_COST_EVERY:-20}" \
  TOPO_BENCHMARK_ENABLE=1 TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-20}" \
  TOPO_BENCHMARK_FORCE_ENABLE=1 TOPO_BENCHMARK_DRAG_LIFT_ENABLE=1 \
  TOPO_BENCHMARK_FLOW_DIR_X=1 TOPO_BENCHMARK_FLOW_DIR_Y=0 \
  TOPO_BENCHMARK_LIFT_DIR_X=0 TOPO_BENCHMARK_LIFT_DIR_Y=1 \
  GAMMA="$GAMMA" KBT="$KBT" U0="$U0" STEPS="$STEPS" \
  LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}" LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}" LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}" \
  FORCE_REBUILD="${FORCE_REBUILD:-0}" CLEAN_RUN_ROOT=1 TAG="$tag" \
    bash scripts/run_topo_darcy_brinkman_viz_0343.sh

  local bench="runs/${tag}/output/topo_benchmark_0348.csv"
  local stats="runs/${tag}/topo_benchmark_window_stats_0348b.csv"
  python3 scripts/analyze_topo_benchmark_window_0348b.py \
    --csv "$bench" --out "$stats" --tail-fraction "$TAIL_FRACTION"
  printf '%s,%s,%s,%s\n' "$shape" "$chi" "$bench" "$stats" >> "$summary"
}

run_shape_0349 "cylinder_r0p04" \
  --mode channel_cylinder --cx "$CX" --cy "$CY" --radius "${CYLINDER_R_SMALL:-0.04}"

run_shape_0349 "cylinder_r0p07" \
  --mode channel_cylinder --cx "$CX" --cy "$CY" --radius "${CYLINDER_R_LARGE:-0.07}"

run_shape_0349 "ellipse_a0p10_b0p035" \
  --mode channel_ellipse --cx "$CX" --cy "$CY" --ellipse-a "${ELLIPSE_A:-0.10}" --ellipse-b "${ELLIPSE_B:-0.035}" --angle-deg "${ELLIPSE_ANGLE_DEG:-0}"

run_shape_0349 "naca0012_aoa0" \
  --mode naca4_airfoil --naca "${NACA_CODE:-0012}" --chord "${NACA_CHORD:-0.22}" --airfoil-cx "$CX" --airfoil-cy "$CY" --aoa-deg 0

echo "[0349-shapes] summary=$summary"
cat "$summary"
