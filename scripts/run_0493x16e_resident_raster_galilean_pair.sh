#!/usr/bin/env bash

# 0493x16e — paired CUDA-resident sub-cell rasterization / Galilean qualification.
# Two runs use the same grid, thermodynamic parameters and RNG seed.
#   rest : fluid mean Ux = solid Ux = 0
#   boost: fluid mean Ux = solid Ux = GALILEAN_UX
# Requires the x16e binary: device-resident solid state, load projection and sub-cell rasterization.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PAIR_ROOT="${PAIR_ROOT:-runs/0493x16e_resident_raster_galilean_pair}"
GALILEAN_UX="${GALILEAN_UX:-0.08}"
STEPS="${STEPS:-3000}"
SEED="${SEED:-4931601}"

printf '\n===== 0493x16e GALILEAN PAIR =====\n'
printf 'root=%s\n' "$PAIR_ROOT"
printf 'rest common Ux=0\n'
printf 'boost common Ux=%s\n' "$GALILEAN_UX"
printf 'steps/case=%s seed=%s\n' "$STEPS" "$SEED"
printf '==================================\n\n'

(
  export CASE_LABEL=0493x16e_resident_rest
  export BASE_RUN_ROOT="$PAIR_ROOT/rest"
  export COMMON_UX=0.0
  export STEPS="$STEPS"
  export SEED="$SEED"
  export CLEAN_RUN_ROOT=1
  bash "$ROOT/scripts/run_0493x16e_resident_raster_galilean_case.sh"
) || exit $?

(
  export CASE_LABEL=0493x16e_resident_boost
  export BASE_RUN_ROOT="$PAIR_ROOT/boost"
  export COMMON_UX="$GALILEAN_UX"
  export STEPS="$STEPS"
  export SEED="$SEED"
  export CLEAN_RUN_ROOT=1
  bash "$ROOT/scripts/run_0493x16e_resident_raster_galilean_case.sh"
) || exit $?

cat > "$PAIR_ROOT/pair_meta_0493x16e.txt" <<META
milestone=0493x16e
restCommonUx=0.0
boostCommonUx=$GALILEAN_UX
steps=$STEPS
seed=$SEED
restRun=$PAIR_ROOT/rest/fresh
boostRun=$PAIR_ROOT/boost/fresh
META

echo "[0493x16e] PAIR COMPLETE root=$PAIR_ROOT"
echo "[0493x16e] next: MATLAB analyze_0493x16e_resident_raster_galilean('../runs/0493x16e_resident_raster_galilean_pair')"
