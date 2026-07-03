#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/validate_cuda_resampling_pipeline_shadow_0444}
RUN_ROOT=${RUN_ROOT:-runs/0444_cuda_resampling_pipeline_shadow}
mkdir -p "$RUN_ROOT"

if [[ ! -x "$BIN" ]]; then
  echo "[0444-run] ERROR: binary not executable: $BIN" >&2
  exit 2
fi

NX=${NX:-64}
NY=${NY:-32}
GAMMA=${GAMMA:-20}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-1024}
SEED=${SEED:-1628638}
TOL_ABS=${TOL_ABS:-2e-10}
TOL_REL=${TOL_REL:-2e-12}

CSV="$RUN_ROOT/pipeline_shadow_0444.csv"
LOG="$RUN_ROOT/pipeline_shadow_0444.log"
REPORT="$RUN_ROOT/pipeline_shadow_report_0444.md"

set +e
NX="$NX" NY="$NY" GAMMA="$GAMMA" INACTIVE_SLOTS="$INACTIVE_SLOTS" \
SEED="$SEED" TOL_ABS="$TOL_ABS" TOL_REL="$TOL_REL" \
"$BIN" > "$CSV" 2> "$LOG"
status=$?
set -e

{
  echo "# 0444 CUDA resampling clean pipeline shadow"
  echo
  echo "Binary: \`$BIN\`"
  echo "NX=$NX NY=$NY GAMMA=$GAMMA INACTIVE_SLOTS=$INACTIVE_SLOTS SEED=$SEED"
  echo
  echo "Exit code: **$status**"
  echo
  echo '```text'
  cat "$LOG"
  echo '```'
  echo
  if [[ -s "$CSV" ]]; then
    python3 - "$CSV" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline='')))
print("| case | massMode | shiftX | shiftY | pass | planEntries | passiveOps | CPU ext/ins | GPU ext/ins | invalid GPU | role/type mism | remap cells CPU/GPU | thermal cells CPU/GPU | max x/y/vx/vy/m | fluid CPU/GPU | badPrefix CPU/GPU | mass CPU/GPU | px CPU/GPU | py CPU/GPU | KE CPU/GPU | apply_s | remapThermal_s |")
print("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
for r in rows:
    maxs = "/".join(r[k] for k in ["maxAbsX","maxAbsY","maxAbsVx","maxAbsVy","maxAbsMass"])
    apply_s = str(float(r.get("extractionKernelSeconds", 0) or 0) + float(r.get("insertionKernelSeconds", 0) or 0))
    print("| {case} | {massMode} | {shiftX} | {shiftY} | {pass} | {planEntries} | {passiveOps} | {cpuExtractionApplied}/{cpuInsertionApplied} | {gpuExtractionApplied}/{gpuInsertionApplied} | {gpuExtractionInvalid}/{gpuInsertionInvalid} | {roleMismatch}/{typeMismatch} | {cpuRemapCells}/{gpuRemapCells} | {cpuThermalCells}/{gpuThermalCells} | ".format(**r) + maxs + " | {cpuFluidRoles}/{gpuFluidRoles} | {cpuBadActivePrefix}/{gpuBadActivePrefix} | {cpuMass}/{gpuMass} | {cpuPx}/{gpuPx} | {cpuPy}/{gpuPy} | {cpuKe}/{gpuKe} | ".format(**r) + apply_s + " | {remapThermalTotalSeconds} |".format(**r))
PY
  fi
  echo
  echo "CSV: \`$CSV\`"
} > "$REPORT"

cat "$REPORT"
exit "$status"
