#!/usr/bin/env bash
set -euo pipefail

# 0218 — smoke test for persistent CUDA particle-state manager.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_persistent_0218}
BIN=${BIN:-build/validate_cuda_particle_state_0218}
GRID_CASES=${GRID_CASES:-"64:64:20 128:128:20"}
CYCLES=${CYCLES:-25}
THREADS=${THREADS:-256}
TOLERANCE=${TOLERANCE:-1e-12}
DVX=${DVX:-1e-5}
DVY=${DVY:--2e-5}
MIXED_ROLES=${MIXED_ROLES:-1}
VARIABLE_MASS=${VARIABLE_MASS:-1}

mkdir -p "$ART_DIR"
CSV="$ART_DIR/cuda_particle_state_smoke_0218.csv"
LOG="$ART_DIR/cuda_particle_state_smoke_0218.log"
rm -f "$CSV" "$LOG"

echo "[0218-smoke] root       : $ROOT" | tee -a "$LOG"
echo "[0218-smoke] grid cases : $GRID_CASES" | tee -a "$LOG"
echo "[0218-smoke] cycles     : $CYCLES" | tee -a "$LOG"

bash scripts/build_cuda_particle_state_0218.sh 2>&1 | tee -a "$LOG"

first=1
for spec in $GRID_CASES; do
  IFS=: read -r NX NY GAMMA <<< "$spec"
  echo "[0218-smoke] case ${NX}x${NY}_g${GAMMA}_c${CYCLES} mixedRoles=${MIXED_ROLES} variableMass=${VARIABLE_MASS}" | tee -a "$LOG"
  args=(--nx "$NX" --ny "$NY" --gamma "$GAMMA" --cycles "$CYCLES" --threads "$THREADS" \
        --dvx "$DVX" --dvy "$DVY" --tolerance "$TOLERANCE" \
        --mixed-roles "$MIXED_ROLES" --variable-mass "$VARIABLE_MASS" \
        --out-csv "$CSV")
  if [[ "$first" -eq 0 ]]; then
    args+=(--append)
  fi
  "$BIN" "${args[@]}" 2>&1 | tee -a "$LOG"
  first=0
done

echo "[0218-smoke] wrote $CSV" | tee -a "$LOG"
