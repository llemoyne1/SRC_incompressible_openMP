#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/validate_cuda_resampling_planner_shadow_0441}
RUN_ROOT=${RUN_ROOT:-runs/0441_cuda_resampling_planner_shadow}
mkdir -p "$RUN_ROOT"

if [[ ! -x "$BIN" ]]; then
  echo "[0441-run] ERROR: binary not executable: $BIN" >&2
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
"$BIN" > "$RUN_ROOT/planner_shadow_0441.csv" 2> "$RUN_ROOT/planner_shadow_0441.log"
status=$?
set -e

{
  echo "# 0441 CUDA resampling transfer planner shadow"
  echo
  echo "Binary: \`$BIN\`"
  echo "NX=$NX NY=$NY GAMMA=$GAMMA INACTIVE_SLOTS=$INACTIVE_SLOTS SEED=$SEED"
  echo
  echo "Exit code: **$status**"
  echo
  echo '```text'
  cat "$RUN_ROOT/planner_shadow_0441.log"
  echo '```'
  echo
  if [[ -s "$RUN_ROOT/planner_shadow_0441.csv" ]]; then
    python3 - "$RUN_ROOT/planner_shadow_0441.csv" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline='')))
print("| case | massMode | shiftX | shiftY | pass | poor CPU/GPU | rich CPU/GPU | plan CPU/GPU | planMismatch | maxPlanMassAbs | plannedMass CPU/GPU | adjacent CPU/GPU | plannerKernel_s | plannerTotal_s |")
print("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
for r in rows:
    print("| {case} | {massMode} | {shiftX} | {shiftY} | {pass} | {poorCpu}/{poorGpu} | {richCpu}/{richGpu} | {cpuPlanEntries}/{gpuPlanEntries} | {planEntryMismatch} | {maxPlanMassAbs} | {cpuPlannedMass}/{gpuPlannedMass} | {cpuAdjacentPairs}/{gpuAdjacentPairs} | {plannerKernelSeconds} | {plannerTotalSeconds} |".format(**r))
PY
  fi
  echo
  echo "CSV: \`$RUN_ROOT/planner_shadow_0441.csv\`"
} > "$RUN_ROOT/planner_shadow_report_0441.md"

cat "$RUN_ROOT/planner_shadow_report_0441.md"
exit "$status"
