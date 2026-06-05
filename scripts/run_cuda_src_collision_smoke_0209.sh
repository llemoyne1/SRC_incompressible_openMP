#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR="${ART_DIR:-dev_history/artifacts/gpu_cuda_collision_0209}"
BIN="${BIN:-build/validate_cuda_src_collision_0209}"
GRID_CASES="${GRID_CASES:-64:64:20 128:128:20}"
MIXED_ROLES="${MIXED_ROLES:-1}"
VARIABLE_MASS="${VARIABLE_MASS:-1}"
RANDOM_SIGN="${RANDOM_SIGN:-1}"
ANGLE="${ANGLE:-2.0943951023931953}"
TOL_VELOCITY="${TOL_VELOCITY:-1e-12}"
TOL_MOMENTUM="${TOL_MOMENTUM:-1e-10}"
TOL_ENERGY="${TOL_ENERGY:-1e-10}"
SEED_BASE="${SEED_BASE:-20900}"

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:--arch=sm_89}" bash scripts/build_cuda_src_collision_0209.sh
fi

OUT_CSV="${OUT_CSV:-$ART_DIR/cuda_src_collision_smoke_0209.csv}"
LOG="${LOG:-$ART_DIR/cuda_src_collision_smoke_0209.log}"
printf 'case,Nx,Ny,gamma,mixedRoles,variableMass,randomSign,particles,fluidParticles,particlesRotated,invalidCellParticles,maxAbsVx,maxAbsVy,rmsV,velocityMismatches,maxCpuMomentumDrift,maxGpuMomentumDrift,maxCpuGpuMomentumDiff,maxCpuEnergyDrift,maxGpuEnergyDrift,maxCpuGpuEnergyDiff,uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds,verdict\n' > "$OUT_CSV"
: > "$LOG"

case_index=0
for spec in $GRID_CASES; do
  IFS=: read -r NX NY GAMMA <<< "$spec"
  case_index=$((case_index + 1))
  label="${NX}x${NY}_g${GAMMA}"
  seed=$((SEED_BASE + case_index + NX + NY + GAMMA))
  echo "[0209-smoke] case $label mixedRoles=$MIXED_ROLES variableMass=$VARIABLE_MASS randomSign=$RANDOM_SIGN" | tee -a "$LOG"
  line=$("$BIN" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
      --mixed-roles "$MIXED_ROLES" --variable-mass "$VARIABLE_MASS" --random-sign "$RANDOM_SIGN" \
      --angle "$ANGLE" --tol-velocity "$TOL_VELOCITY" --tol-momentum "$TOL_MOMENTUM" --tol-energy "$TOL_ENERGY" \
      --seed "$seed" | tee -a "$LOG")
  python3 - "$OUT_CSV" "$label" "$NX" "$NY" "$GAMMA" "$MIXED_ROLES" "$VARIABLE_MASS" "$RANDOM_SIGN" "$line" <<'PY'
import csv, re, sys
out,label,nx,ny,gamma,mixed,vmass,rsign,line=sys.argv[1:]
status='PASS' if 'CUDA_SRC_COLLISION_0209 PASS' in line else 'FAIL'
fields=dict(re.findall(r'([A-Za-z0-9_]+)=([^\s]+)', line))
row={
 'case':label,'Nx':nx,'Ny':ny,'gamma':gamma,'mixedRoles':mixed,'variableMass':vmass,'randomSign':rsign,
 'particles':fields.get('particles',''),'fluidParticles':fields.get('fluidParticles',''),
 'particlesRotated':fields.get('particlesRotated',''),'invalidCellParticles':fields.get('invalidCellParticles',''),
 'maxAbsVx':fields.get('maxAbsVx',''),'maxAbsVy':fields.get('maxAbsVy',''),'rmsV':fields.get('rmsV',''),
 'velocityMismatches':fields.get('velocityMismatches',''),
 'maxCpuMomentumDrift':fields.get('maxCpuMomentumDrift',''),'maxGpuMomentumDrift':fields.get('maxGpuMomentumDrift',''),
 'maxCpuGpuMomentumDiff':fields.get('maxCpuGpuMomentumDiff',''),
 'maxCpuEnergyDrift':fields.get('maxCpuEnergyDrift',''),'maxGpuEnergyDrift':fields.get('maxGpuEnergyDrift',''),
 'maxCpuGpuEnergyDiff':fields.get('maxCpuGpuEnergyDiff',''),
 'uploadSeconds':fields.get('uploadSeconds',''),'kernelSeconds':fields.get('kernelSeconds',''),
 'downloadSeconds':fields.get('downloadSeconds',''),'totalSeconds':fields.get('totalSeconds',''),
 'verdict':status}
with open(out,'a',newline='') as f:
    w=csv.DictWriter(f, fieldnames=list(row.keys()))
    w.writerow(row)
if status != 'PASS':
    raise SystemExit(1)
PY
  echo "[0209-smoke] PASS $label" | tee -a "$LOG"
done

echo "[0209-smoke] wrote $OUT_CSV" | tee -a "$LOG"
