#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN=${BIN:-build/validate_cuda_resampling_persistent_state_ops_0239}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_0239}
GRID_CASES=${GRID_CASES:-"64:64:20 128:128:20"}
OPS_PER_CASE=${OPS_PER_CASE:-0}
mkdir -p "$ART_DIR"
if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_cuda_resampling_persistent_state_ops_0239.sh
fi
LOG=${LOG:-$ART_DIR/cuda_resampling_persistent_state_ops_smoke_0239.log}
CSV=${CSV:-$ART_DIR/cuda_resampling_persistent_state_ops_smoke_0239.csv}
: > "$LOG"
printf 'case,pass,Nx,Ny,gamma,particles,operations,extractionApplied,insertionApplied,allocationCalls,maxAbsX,maxAbsY,maxAbsVx,maxAbsVy,maxAbsMass,roleMismatches,typeMismatches,opUploadSeconds,kernelSeconds\n' > "$CSV"
status=0
for spec in $GRID_CASES; do
  IFS=: read -r NX NY GAMMA <<< "$spec"
  label="${NX}x${NY}_g${GAMMA}"
  echo "[0239-resampling-state-ops] case $label" | tee -a "$LOG"
  tmp=$(mktemp)
  set +e
  "$BIN" "$NX" "$NY" "$GAMMA" "$OPS_PER_CASE" > "$tmp" 2>&1
  rc=$?
  set -e
  cat "$tmp" | tee -a "$LOG"
  python3 - "$tmp" "$CSV" "$label" <<'PY'
import re, sys, csv
text=open(sys.argv[1]).read()
csv_path=sys.argv[2]
label=sys.argv[3]
line=''
for l in text.splitlines():
    if l.startswith('CUDA_RESAMPLING_PERSISTENT_STATE_OPS_0239'):
        line=l
if not line:
    vals={'pass':'0'}
else:
    parts=line.split()
    vals={'pass':'1' if len(parts)>1 and parts[1]=='PASS' else '0'}
    for p in parts[2:]:
        if '=' in p:
            k,v=p.split('=',1); vals[k]=v
fields=['case','pass','Nx','Ny','gamma','particles','operations','extractionApplied','insertionApplied','allocationCalls','maxAbsX','maxAbsY','maxAbsVx','maxAbsVy','maxAbsMass','roleMismatches','typeMismatches','opUploadSeconds','kernelSeconds']
row={k:'' for k in fields}
row['case']=label
for k,v in vals.items():
    if k in row: row[k]=v
with open(csv_path,'a',newline='') as f:
    csv.DictWriter(f, fieldnames=fields).writerow(row)
PY
  if [[ $rc -ne 0 ]]; then
    echo "[0239-resampling-state-ops] FAIL $label" | tee -a "$LOG"
    status=1
  else
    echo "[0239-resampling-state-ops] PASS $label" | tee -a "$LOG"
  fi
  rm -f "$tmp"
done
echo "[0239-resampling-state-ops] wrote $CSV" | tee -a "$LOG"
exit $status
