#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR="${ART_DIR:-dev_history/artifacts/gpu_cuda_persistent_0212}"
BIN="${BIN:-build/validate_cuda_persistent_mpcd_step_0212}"
GRID_CASES="${GRID_CASES:-64:64:20 128:128:20}"
CYCLES="${CYCLES:-5}"
MIXED_ROLES="${MIXED_ROLES:-1}"
VARIABLE_MASS="${VARIABLE_MASS:-1}"
RANDOM_SIGN="${RANDOM_SIGN:-1}"
TARGET_KBT="${TARGET_KBT:-1e-3}"
TOL_VELOCITY="${TOL_VELOCITY:-1e-10}"
SEED_BASE="${SEED_BASE:-21200}"

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:--arch=sm_89}" bash scripts/build_cuda_persistent_mpcd_step_0212.sh
fi

OUT_CSV="${OUT_CSV:-$ART_DIR/cuda_persistent_mpcd_step_smoke_0212.csv}"
LOG="${LOG:-$ART_DIR/cuda_persistent_mpcd_step_smoke_0212.log}"
printf 'case,Nx,Ny,gamma,cycles,mixedRoles,variableMass,randomSign,particles,fluidParticles,gpuFluidParticlesPerCycle,particlesRotatedTotal,invalidCellParticles,maxAbsVx,maxAbsVy,rmsV,velocityMismatches,uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds,verdict\n' > "$OUT_CSV"
: > "$LOG"

case_index=0
for spec in $GRID_CASES; do
  IFS=: read -r NX NY GAMMA <<< "$spec"
  case_index=$((case_index + 1))
  label="${NX}x${NY}_g${GAMMA}_c${CYCLES}"
  seed=$((SEED_BASE + case_index + NX + NY + GAMMA + CYCLES))
  echo "[0212-smoke] case $label mixedRoles=$MIXED_ROLES variableMass=$VARIABLE_MASS randomSign=$RANDOM_SIGN" | tee -a "$LOG"
  line=$("$BIN" --nx "$NX" --ny "$NY" --gamma "$GAMMA" --cycles "$CYCLES" \
      --mixed-roles "$MIXED_ROLES" --variable-mass "$VARIABLE_MASS" --random-sign "$RANDOM_SIGN" \
      --target-kbt "$TARGET_KBT" --tol-velocity "$TOL_VELOCITY" --seed "$seed" | tee -a "$LOG")
  python3 - "$OUT_CSV" "$label" "$NX" "$NY" "$GAMMA" "$CYCLES" "$MIXED_ROLES" "$VARIABLE_MASS" "$RANDOM_SIGN" "$line" <<'PY'
import csv, re, sys
out,label,nx,ny,gamma,cycles,mixed,vmass,rsign,line=sys.argv[1:]
status='PASS' if 'CUDA_PERSISTENT_MPCD_STEP_0212 PASS' in line else 'FAIL'
fields=dict(re.findall(r'([A-Za-z0-9_]+)=([^\s]+)', line))
row={
 'case':label,'Nx':nx,'Ny':ny,'gamma':gamma,'cycles':cycles,'mixedRoles':mixed,'variableMass':vmass,'randomSign':rsign,
 'particles':fields.get('particles',''),'fluidParticles':fields.get('fluidParticles',''),
 'gpuFluidParticlesPerCycle':fields.get('gpuFluidParticlesPerCycle',''),
 'particlesRotatedTotal':fields.get('particlesRotatedTotal',''),
 'invalidCellParticles':fields.get('invalidCellParticles',''),
 'maxAbsVx':fields.get('maxAbsVx',''),'maxAbsVy':fields.get('maxAbsVy',''),'rmsV':fields.get('rmsV',''),
 'velocityMismatches':fields.get('velocityMismatches',''),
 'uploadSeconds':fields.get('uploadSeconds',''),'kernelSeconds':fields.get('kernelSeconds',''),
 'downloadSeconds':fields.get('downloadSeconds',''),'totalSeconds':fields.get('totalSeconds',''),
 'verdict':status}
with open(out,'a',newline='') as f:
    w=csv.DictWriter(f, fieldnames=list(row.keys()))
    w.writerow(row)
if status != 'PASS':
    raise SystemExit(1)
PY
  echo "[0212-smoke] PASS $label" | tee -a "$LOG"
done

echo "[0212-smoke] wrote $OUT_CSV" | tee -a "$LOG"
