#!/usr/bin/env bash
set -euo pipefail

cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF

SEEDS=(493150 593150 693150 793150 893150 993150)
ARGS=()
for S in "${SEEDS[@]}"; do
  R="runs/0493x14s_multiseed6_sigma256_seed${S}"
  STATE="$R/output/state_step_00001000.smpcd"
  if [[ ! -f "$STATE" ]]; then
    echo "ERROR: missing $STATE" >&2
    exit 2
  fi
  ARGS+=(--run "$R")
done

OUT="runs/0493x14s_multiseed6_sigma256_shape_step1000"
rm -rf "$OUT"

python3 scripts/analyze_0493x14s_drop_shape_fourier.py \
  "${ARGS[@]}" \
  --step 1000 \
  --angles 720 \
  --samples-per-h 8 \
  --max-mode 8 \
  --fit-modes-to 8 \
  --recenter-iterations 4 \
  --outdir "$OUT"

tar -czf 0493x14s_sigma256_multiseed6_shape_step1000.tar.gz "$OUT"

echo
echo "[x14s-shape] DONE"
echo "[x14s-shape] return: $PWD/0493x14s_sigma256_multiseed6_shape_step1000.tar.gz"
