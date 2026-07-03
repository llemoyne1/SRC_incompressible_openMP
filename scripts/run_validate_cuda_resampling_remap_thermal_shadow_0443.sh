#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/validate_cuda_resampling_remap_thermal_shadow_0443}
RUN_ROOT=${RUN_ROOT:-runs/0443_cuda_resampling_remap_thermal_shadow}
mkdir -p "$RUN_ROOT"

if [[ ! -x "$BIN" ]]; then
  echo "[0443-run] ERROR: binary not executable: $BIN" >&2
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
"$BIN" > "$RUN_ROOT/remap_thermal_shadow_0443.csv" 2> "$RUN_ROOT/remap_thermal_shadow_0443.log"
status=$?
set -e

{
  echo "# 0443 CUDA resampling remap + thermal shadow"
  echo
  echo "Binary: \`$BIN\`"
  echo "NX=$NX NY=$NY GAMMA=$GAMMA INACTIVE_SLOTS=$INACTIVE_SLOTS SEED=$SEED"
  echo
  echo "Exit code: **$status**"
  echo
  echo '```text'
  cat "$RUN_ROOT/remap_thermal_shadow_0443.log"
  echo '```'
  echo
  if [[ -s "$RUN_ROOT/remap_thermal_shadow_0443.csv" ]]; then
    python3 - "$RUN_ROOT/remap_thermal_shadow_0443.csv" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline='')))
print("| case | massMode | shiftX | shiftY | pass | remap cells CPU/GPU | remap particles | thermal cells CPU/GPU | thermal particles | role mism | max x/y/vx/vy/m | mass CPU/GPU | px CPU/GPU | py CPU/GPU | ke CPU/GPU | remap_s | thermal_s | total_s |")
print("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
for r in rows:
    maxs = "/".join(r[k] for k in ["maxAbsX", "maxAbsY", "maxAbsVx", "maxAbsVy", "maxAbsMass"])
    print("| {case} | {massMode} | {shiftX} | {shiftY} | {pass} | {cpuRemapCells}/{gpuRemapCells} | {cpuRemapParticles} | {cpuThermalCells}/{gpuThermalCells} | {cpuThermalParticles} | {roleMismatch} | ".format(**r) + maxs + " | {cpuMass}/{gpuMass} | {cpuPx}/{gpuPx} | {cpuPy}/{gpuPy} | {cpuKe}/{gpuKe} | {remapKernelSeconds} | {thermalKernelSeconds} | {totalSeconds} |".format(**r))
PY
  fi
  echo
  echo "CSV: \`$RUN_ROOT/remap_thermal_shadow_0443.csv\`"
} > "$RUN_ROOT/remap_thermal_shadow_report_0443.md"

cat "$RUN_ROOT/remap_thermal_shadow_report_0443.md"
exit "$status"
