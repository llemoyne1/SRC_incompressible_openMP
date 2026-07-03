#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/validate_cuda_resampling_compact_shadow_0440}
RUN_ROOT=${RUN_ROOT:-runs/0440_cuda_resampling_compact_shadow}
mkdir -p "$RUN_ROOT"

if [[ ! -x "$BIN" ]]; then
  echo "[0440-run] ERROR: binary not executable: $BIN" >&2
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
"$BIN" > "$RUN_ROOT/compact_shadow_0440.csv" 2> "$RUN_ROOT/compact_shadow_0440.log"
status=$?
set -e

{
  echo "# 0440 CUDA resampling poor/rich compaction shadow"
  echo
  echo "Binary: \`$BIN\`"
  echo "NX=$NX NY=$NY GAMMA=$GAMMA INACTIVE_SLOTS=$INACTIVE_SLOTS SEED=$SEED"
  echo
  echo "Exit code: **$status**"
  echo
  echo '```text'
  cat "$RUN_ROOT/compact_shadow_0440.log"
  echo '```'
  echo
  if [[ -s "$RUN_ROOT/compact_shadow_0440.csv" ]]; then
    python3 - "$RUN_ROOT/compact_shadow_0440.csv" <<'PY'
import csv, sys
path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline='')))
print("| case | massMode | shiftX | shiftY | pass | poor CPU/GPU | poorMismatch | rich CPU/GPU | richMismatch | maxMassAbs | compactKernel_s | compactTotal_s |")
print("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
for r in rows:
    print("| {case} | {massMode} | {shiftX} | {shiftY} | {pass} | {poorCpu}/{poorGpu} | {poorListMismatch} | {richCpu}/{richGpu} | {richListMismatch} | {maxMassAbs} | {compactKernelSeconds} | {compactTotalSeconds} |".format(**r))
PY
  fi
  echo
  echo "CSV: \`$RUN_ROOT/compact_shadow_0440.csv\`"
} > "$RUN_ROOT/compact_shadow_report_0440.md"

cat "$RUN_ROOT/compact_shadow_report_0440.md"
exit "$status"
