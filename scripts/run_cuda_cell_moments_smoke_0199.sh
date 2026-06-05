#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR="dev_history/artifacts/gpu_cuda_deposit_0199"
mkdir -p "$ART_DIR"

bash scripts/build_cuda_cell_moments_0199.sh
BIN="build/validate_cuda_cell_moments_0199"

GRID_CASES="${GRID_CASES:-64:64:20 128:128:20}"
TOLERANCE="${TOLERANCE:-1e-10}"
REPEATS="${REPEATS:-1}"
MIXED_ROLES="${MIXED_ROLES:-1}"
OUT="$ART_DIR/cuda_cell_moments_smoke_0199.csv"
LOG="$ART_DIR/cuda_cell_moments_smoke_0199.log"
TMP="$ART_DIR/.cuda_cell_moments_one.csv"

: > "$LOG"
rm -f "$OUT" "$TMP"
first=1
status=0

for spec in $GRID_CASES; do
  IFS=: read -r NX NY GAMMA <<< "$spec"
  NY="${NY:-$NX}"
  GAMMA="${GAMMA:-20}"
  echo "[0199-smoke] case ${NX}x${NY} gamma=${GAMMA} mixedRoles=${MIXED_ROLES}" | tee -a "$LOG"
  if "$BIN" --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --mixedRoles "$MIXED_ROLES" \
          --repeats "$REPEATS" --tolerance "$TOLERANCE" --csv "$TMP" 2>&1 | tee -a "$LOG"; then
    if [[ $first -eq 1 ]]; then
      cat "$TMP" > "$OUT"
      first=0
    else
      tail -n +2 "$TMP" >> "$OUT"
    fi
  else
    status=1
    if [[ -f "$TMP" ]]; then
      if [[ $first -eq 1 ]]; then cat "$TMP" > "$OUT"; first=0; else tail -n +2 "$TMP" >> "$OUT"; fi
    fi
  fi
done

rm -f "$TMP"
echo "[0199-smoke] wrote $OUT" | tee -a "$LOG"
exit "$status"
