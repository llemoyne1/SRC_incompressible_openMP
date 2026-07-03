#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/validate_cuda_resampling_particle_apply_shadow_0442}
RUN_ROOT=${RUN_ROOT:-runs/0442_cuda_resampling_particle_apply_shadow}
mkdir -p "$RUN_ROOT"

if [[ ! -x "$BIN" ]]; then
  echo "[0442-run] ERROR: binary not executable: $BIN" >&2
  exit 2
fi

NX=${NX:-64}
NY=${NY:-32}
GAMMA=${GAMMA:-20}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-1024}
SEED=${SEED:-1628638}
TOL_ABS=${TOL_ABS:-2e-10}
TOL_REL=${TOL_REL:-2e-12}

set +e
NX="$NX" NY="$NY" GAMMA="$GAMMA" INACTIVE_SLOTS="$INACTIVE_SLOTS" \
SEED="$SEED" TOL_ABS="$TOL_ABS" TOL_REL="$TOL_REL" \
"$BIN" > "$RUN_ROOT/particle_apply_shadow_0442.csv" 2> "$RUN_ROOT/particle_apply_shadow_0442.log"
status=$?
set -e

{
  echo "# 0442 CUDA resampling particle-state apply shadow"
  echo
  echo "Binary: \`$BIN\`"
  echo "NX=$NX NY=$NY GAMMA=$GAMMA INACTIVE_SLOTS=$INACTIVE_SLOTS SEED=$SEED"
  echo
  echo "Exit code: **$status**"
  echo
  echo '```text'
  cat "$RUN_ROOT/particle_apply_shadow_0442.log"
  echo '```'
  echo
  if [[ -s "$RUN_ROOT/particle_apply_shadow_0442.csv" ]]; then
    python3 - "$RUN_ROOT/particle_apply_shadow_0442.csv" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline='')))
print("| case | massMode | shiftX | shiftY | pass | planEntries | passiveOps | CPU ext/ins | GPU ext/ins | invalid GPU | role/type mism | max x/y/vx/vy/m | fluid CPU/GPU | badPrefix CPU/GPU | mass CPU/GPU | px CPU/GPU | py CPU/GPU | applyKernel_s | totalApply_s |")
print("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
for r in rows:
    maxs = "/".join(r[k] for k in ["maxAbsX","maxAbsY","maxAbsVx","maxAbsVy","maxAbsMass"])
    kernel = str(float(r.get("extractionKernelSeconds", 0) or 0) + float(r.get("insertionKernelSeconds", 0) or 0))
    print("| {case} | {massMode} | {shiftX} | {shiftY} | {pass} | {planEntries} | {passiveOps} | {cpuExtractionApplied}/{cpuInsertionApplied} | {gpuExtractionApplied}/{gpuInsertionApplied} | {gpuExtractionInvalid}/{gpuInsertionInvalid} | {roleMismatch}/{typeMismatch} | ".format(**r) + maxs + " | {cpuFluidRoles}/{gpuFluidRoles} | {cpuBadActivePrefix}/{gpuBadActivePrefix} | {cpuMass}/{gpuMass} | {cpuPx}/{gpuPx} | {cpuPy}/{gpuPy} | ".format(**r) + kernel + " | " + r.get("gpuApplyTotalSeconds", "") + " |")
PY
  fi
  echo
  echo "CSV: \`$RUN_ROOT/particle_apply_shadow_0442.csv\`"
} > "$RUN_ROOT/particle_apply_shadow_report_0442.md"

cat "$RUN_ROOT/particle_apply_shadow_report_0442.md"
exit "$status"
