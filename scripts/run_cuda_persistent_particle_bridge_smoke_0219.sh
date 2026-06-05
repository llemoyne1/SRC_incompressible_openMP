#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR="dev_history/artifacts/gpu_cuda_persistent_0219"
mkdir -p "$ART_DIR"

bash scripts/build_cuda_persistent_particle_bridge_0219.sh
BIN="build/validate_cuda_persistent_particle_bridge_0219"

GRID_CASES="${GRID_CASES:-64:64:20 128:128:20}"
CYCLES="${CYCLES:-5}"
MIXED_ROLES="${MIXED_ROLES:-1}"
VARIABLE_MASS="${VARIABLE_MASS:-1}"
RANDOM_SIGN="${RANDOM_SIGN:-1}"
TOLERANCE="${TOLERANCE:-1e-10}"
SEED_BASE="${SEED_BASE:-21900}"

CSV="$ART_DIR/cuda_persistent_particle_bridge_smoke_0219.csv"
LOG="$ART_DIR/cuda_persistent_particle_bridge_smoke_0219.log"

echo "case,Nx,Ny,gamma,cycles,pass,particles,allocationCalls,reusedAllocation,particleUploadSeconds,sharedStepUploadSeconds,sharedKernelSeconds,sharedDownloadSeconds,sharedTotalSeconds,legacyTotalSeconds,invalidCellParticles,cpuVelocityMismatches,legacyVelocityMismatches,cellIdMismatches,countMismatches,maxAbsVxCpu,maxAbsVyCpu,maxAbsVxLegacy,maxAbsVyLegacy,rmsCpu,thermostatKBTAfter" > "$CSV"
: > "$LOG"

idx=0
for spec in $GRID_CASES; do
  IFS=: read -r NX NY GAMMA <<<"$spec"
  CASE="${NX}x${NY}_g${GAMMA}_c${CYCLES}"
  SEED=$((SEED_BASE + idx))
  echo "[0219-smoke] case $CASE mixedRoles=$MIXED_ROLES variableMass=$VARIABLE_MASS randomSign=$RANDOM_SIGN" | tee -a "$LOG"
  OUT="$($BIN --nx "$NX" --ny "$NY" --gamma "$GAMMA" --cycles "$CYCLES" \
              --mixed-roles "$MIXED_ROLES" --variable-mass "$VARIABLE_MASS" \
              --random-sign "$RANDOM_SIGN" --tol-velocity "$TOLERANCE" --seed "$SEED" 2>&1)" || {
      echo "$OUT" | tee -a "$LOG"
      echo "[0219-smoke] FAIL $CASE" | tee -a "$LOG"
      exit 1
  }
  echo "$OUT" | tee -a "$LOG"
  python3 - "$CSV" "$CASE" "$NX" "$NY" "$GAMMA" "$CYCLES" "$OUT" <<'PY'
import csv, re, sys
csv_path, case, nx, ny, gamma, cycles, line = sys.argv[1:]
fields = dict(re.findall(r'([A-Za-z0-9_]+)=([^\s]+)', line))
pass_flag = 1 if ' PASS ' in f' {line} ' else 0
keys = ['particles','allocationCalls','reusedAllocation','particleUploadSeconds','sharedStepUploadSeconds','sharedKernelSeconds','sharedDownloadSeconds','sharedTotalSeconds','legacyTotalSeconds','invalidCellParticles','cpuVelocityMismatches','legacyVelocityMismatches','cellIdMismatches','countMismatches','maxAbsVxCpu','maxAbsVyCpu','maxAbsVxLegacy','maxAbsVyLegacy','rmsCpu','thermostatKBTAfter']
row = {'case':case,'Nx':nx,'Ny':ny,'gamma':gamma,'cycles':cycles,'pass':pass_flag}
for k in keys:
    row[k] = fields.get(k, '')
with open(csv_path, 'a', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['case','Nx','Ny','gamma','cycles','pass']+keys)
    writer.writerow(row)
PY
  echo "[0219-smoke] PASS $CASE" | tee -a "$LOG"
  idx=$((idx+1))
done

echo "[0219-smoke] wrote $CSV" | tee -a "$LOG"
