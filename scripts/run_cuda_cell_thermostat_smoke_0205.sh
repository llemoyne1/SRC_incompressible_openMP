#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR="${ART_DIR:-dev_history/artifacts/gpu_cuda_thermostat_0205}"
BIN="${BIN:-build/validate_cuda_cell_thermostat_0205}"
GRID_CASES="${GRID_CASES:-64:64:20 128:128:20}"
MIXED_ROLES="${MIXED_ROLES:-1}"
VARIABLE_MASS="${VARIABLE_MASS:-1}"
TARGET_KBT="${TARGET_KBT:-1e-3}"
TOL_VELOCITY="${TOL_VELOCITY:-1e-10}"
TOL_DIAG="${TOL_DIAG:-1e-10}"
SEED_BASE="${SEED_BASE:-20500}"

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:--arch=sm_89}" bash scripts/build_cuda_cell_thermostat_0205.sh
fi

OUT_CSV="${OUT_CSV:-$ART_DIR/cuda_cell_thermostat_smoke_0205.csv}"
LOG="${LOG:-$ART_DIR/cuda_cell_thermostat_smoke_0205.log}"
printf 'case,Nx,Ny,gamma,mixedRoles,variableMass,particles,fluidParticles,cellsRescaled,particlesRescaled,maxAbsVx,maxAbsVy,rmsV,velocityMismatches,maxDiagDiff,cpuKBTBefore,gpuKBTBefore,cpuKBTAfter,gpuKBTAfter,uploadSeconds,kineticKernelSeconds,scaleKernelSeconds,applyKernelSeconds,downloadSeconds,totalSeconds,verdict\n' > "$OUT_CSV"
: > "$LOG"

case_index=0
for spec in $GRID_CASES; do
  IFS=: read -r NX NY GAMMA <<< "$spec"
  case_index=$((case_index + 1))
  label="${NX}x${NY}_g${GAMMA}"
  seed=$((SEED_BASE + case_index + NX + NY + GAMMA))
  echo "[0205-smoke] case $label mixedRoles=$MIXED_ROLES variableMass=$VARIABLE_MASS" | tee -a "$LOG"
  line=$("$BIN" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
      --mixed-roles "$MIXED_ROLES" --variable-mass "$VARIABLE_MASS" \
      --target-kbt "$TARGET_KBT" --tol-velocity "$TOL_VELOCITY" --tol-diag "$TOL_DIAG" \
      --seed "$seed" | tee -a "$LOG")
  python3 - "$OUT_CSV" "$label" "$NX" "$NY" "$GAMMA" "$MIXED_ROLES" "$VARIABLE_MASS" "$line" <<'PY'
import csv, re, sys
out,label,nx,ny,gamma,mixed,vmass,line=sys.argv[1:]
status='PASS' if 'CUDA_CELL_THERMOSTAT_0205 PASS' in line else 'FAIL'
fields=dict(re.findall(r'([A-Za-z0-9_]+)=([^\s]+)', line))
row={
 'case':label,'Nx':nx,'Ny':ny,'gamma':gamma,'mixedRoles':mixed,'variableMass':vmass,
 'particles':fields.get('particles',''),'fluidParticles':fields.get('fluidParticles',''),
 'cellsRescaled':fields.get('cellsRescaled',''),'particlesRescaled':fields.get('particlesRescaled',''),
 'maxAbsVx':fields.get('maxAbsVx',''),'maxAbsVy':fields.get('maxAbsVy',''),'rmsV':fields.get('rmsV',''),
 'velocityMismatches':fields.get('velocityMismatches',''),'maxDiagDiff':fields.get('maxDiagDiff',''),
 'cpuKBTBefore':fields.get('cpuKBTBefore',''),'gpuKBTBefore':fields.get('gpuKBTBefore',''),
 'cpuKBTAfter':fields.get('cpuKBTAfter',''),'gpuKBTAfter':fields.get('gpuKBTAfter',''),
 'uploadSeconds':fields.get('uploadSeconds',''),'kineticKernelSeconds':fields.get('kineticKernelSeconds',''),
 'scaleKernelSeconds':fields.get('scaleKernelSeconds',''),'applyKernelSeconds':fields.get('applyKernelSeconds',''),
 'downloadSeconds':fields.get('downloadSeconds',''),'totalSeconds':fields.get('totalSeconds',''),
 'verdict':status}
with open(out,'a',newline='') as f:
    w=csv.DictWriter(f, fieldnames=list(row.keys()))
    w.writerow(row)
if status != 'PASS':
    raise SystemExit(1)
PY
  echo "[0205-smoke] PASS $label" | tee -a "$LOG"
done

echo "[0205-smoke] wrote $OUT_CSV" | tee -a "$LOG"
