#!/usr/bin/env bash
set -euo pipefail

cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF

SEEDS=(493150 593150 693150 793150 893150 993150)

for S in "${SEEDS[@]}"; do
  R="runs/0493x14s_multiseed6_sigma256_seed${S}"
  echo
  echo "===== x14s sigma=256 seed=$S ====="
  SEED="$S" \
  BASE_RUN_ROOT="$R" \
  CLEAN_RUN_ROOT=1 \
  SURFACE_TENSION_SIGMA=256 \
  STEPS=1000 \
  SUMMARY_EVERY=100 \
  DUMP_STATE_EVERY=500 \
  LIVE_VIS_ENABLE=0 \
  LIVE_VIS_HOLD_ON_EXIT=0 \
  RECORD_ENABLE=false \
  FILTERED_RECORDING_ENABLE=0 \
  bash scripts/run_ok_0493x14s_x6g_accessible_volume_drop.sh

  echo "[multiseed6] final radial row seed=$S"
  tail -n 1 "$R/analysis/radial_metrics_0493x14s.csv"
done

# Compact return package: analyses + small existing diagnostics only.
OUT="0493x14s_sigma256_multiseed6_compact.tar.gz"
TMP_LIST="$(mktemp)"
trap 'rm -f "$TMP_LIST"' EXIT

for S in "${SEEDS[@]}"; do
  R="runs/0493x14s_multiseed6_sigma256_seed${S}"
  printf '%s\n' \
    "$R/analysis" \
    "$R/output/cuda_phase_interface_pressure_0493x6g.csv" \
    "$R/output/cuda_phase_interface_stencil_0493x6f.csv" \
    "$R/output/cuda_surface_tension_0493x9d.csv" \
    "$R/output/species_runtime_0493x14s.csv" \
    "$R/logs/0493x14s_x6g_accessible_volume_drop.log" \
    >> "$TMP_LIST"
done

tar -czf "$OUT" -T "$TMP_LIST"
echo
echo "[multiseed6] DONE"
echo "[multiseed6] return: $PWD/$OUT"
