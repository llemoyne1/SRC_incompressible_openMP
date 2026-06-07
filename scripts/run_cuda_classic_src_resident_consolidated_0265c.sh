#!/usr/bin/env bash
set -euo pipefail

echo "[0265c-consolidated] runner version=0265c_csv_verdict_filter"

# 0265 — short consolidated validation suite for the CUDA resident classic SRC stack.
# This runner does not introduce new physics. It builds one 0265 binary, reuses the
# dedicated validators from 0260-0264, and writes a global manifest with pass/fail
# counts and paths to the per-family CSV diagnostics.
#
# Default scope is deliberately short but representative:
#   periodic resident, wall-simple resident, solid rectangle resident,
#   piston/mobile-wall legacy resident collision, full-face inlet/outlet resident,
#   segmented inlet/outlet resident.
#
# Q6 and resampling remain disabled inside the classic-only 0260-0264 validators.
# This is a validation choice only: the runner must not be interpreted as an
# architectural lock against later CPU Q6 and resampling reactivation.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0265}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_classic_src_resident_0265c}
OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_classic_src_resident_consolidated_0265c.csv}
SHORT_GRID_CASES=${SHORT_GRID_CASES:-"64:64:180"}
PERIODIC_GRID_CASES=${PERIODIC_GRID_CASES:-$SHORT_GRID_CASES}
WALL_GRID_CASES=${WALL_GRID_CASES:-$SHORT_GRID_CASES}
SOLID_GRID_CASES=${SOLID_GRID_CASES:-$SHORT_GRID_CASES}
IO_FULLFACE_GRID_CASES=${IO_FULLFACE_GRID_CASES:-$SHORT_GRID_CASES}
IO_SEGMENTED_GRID_CASES=${IO_SEGMENTED_GRID_CASES:-$SHORT_GRID_CASES}
PISTON_GRID_CASES=${PISTON_GRID_CASES:-"64:64:120"}
INCLUDE_PISTON=${INCLUDE_PISTON:-1}
THREADS=${THREADS:-8}
GAMMA=${GAMMA:-20}
FORCE_REBUILD=${FORCE_REBUILD:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
SUMMARY_EVERY_MODE=${SUMMARY_EVERY_MODE:-final}

mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0265c-consolidated] rebuilding $BIN (FORCE_REBUILD=$FORCE_REBUILD)"
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0265.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0265.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0265c-consolidated] ERROR: missing binary $BIN" >&2
  exit 127
fi

printf 'suite,script,gridCases,outputCsv,exitCode,rows,passRows,failRows,verdict\n' > "$OUT_CSV"

summarize_suite_csv() {
  local csv_path=$1
  python3 - "$csv_path" <<'PY'
import csv
import os
import sys

p = sys.argv[1]
try:
    with open(p, newline='') as fh:
        raw_rows = list(csv.DictReader(fh))
except FileNotFoundError:
    print('0,0,0,FAIL')
    raise SystemExit(0)

# Child validator CSVs in this branch are not guaranteed to be RFC-complete:
# some write the final compareSummary path on a continuation line. For the
# consolidated verdict, use the verdict column as the single source of truth:
# count only explicit PASS/FAIL validation rows. Empty-verdict rows are ignored,
# because genuine child failures are represented either by verdict=FAIL, by a
# non-zero child rc, or by the absence of any explicit validation row.
valid_rows = []
ignored_rows = 0
for r in raw_rows:
    verdict = (r.get('verdict') or '').strip().upper()
    if verdict in {'PASS', 'FAIL'}:
        valid_rows.append(r)
    else:
        ignored_rows += 1

pass_rows = sum(1 for r in valid_rows if (r.get('verdict') or '').strip().upper() == 'PASS')
fail_rows = sum(1 for r in valid_rows if (r.get('verdict') or '').strip().upper() == 'FAIL')
verdict = 'PASS' if valid_rows and fail_rows == 0 else 'FAIL'
print(f'{len(valid_rows)},{pass_rows},{fail_rows},{verdict},{ignored_rows}')
PY
}

append_manifest_row() {
  local suite=$1 script=$2 grid_cases=$3 csv_path=$4 rc=$5 rows=$6 pass_rows=$7 fail_rows=$8 verdict=$9
  python3 - "$OUT_CSV" "$suite" "$script" "$grid_cases" "$csv_path" "$rc" "$rows" "$pass_rows" "$fail_rows" "$verdict" <<'PY'
import csv, sys
out, suite, script, grid_cases, csv_path, rc, rows, pass_rows, fail_rows, verdict = sys.argv[1:]
with open(out, 'a', newline='') as fh:
    csv.writer(fh).writerow([suite, script, grid_cases, csv_path, rc, rows, pass_rows, fail_rows, verdict])
PY
}

run_suite() {
  local suite=$1 script=$2 grid_cases=$3 suite_art=$4 suite_csv=$5
  echo "[0265c-consolidated] running suite=$suite gridCases=[$grid_cases]"
  mkdir -p "$suite_art"
  local rc=0
  set +e
  env BIN="$BIN" FORCE_REBUILD=0 ART_DIR="$suite_art" OUT_CSV="$suite_csv" \
      GRID_CASES="$grid_cases" GAMMA="$GAMMA" THREADS="$THREADS" \
      STOP_ON_FAIL=0 SUMMARY_EVERY_MODE="$SUMMARY_EVERY_MODE" \
      bash "$script"
  rc=$?
  set -e
  local rows pass_rows fail_rows verdict ignored_rows
  IFS=, read -r rows pass_rows fail_rows verdict ignored_rows <<<"$(summarize_suite_csv "$suite_csv")"
  if [[ "$rc" != "0" ]]; then
    verdict="FAIL"
  fi
  append_manifest_row "$suite" "$script" "$grid_cases" "$suite_csv" "$rc" "$rows" "$pass_rows" "$fail_rows" "$verdict"
  echo "[0265c-consolidated] $verdict suite=$suite rc=$rc rows=$rows pass=$pass_rows fail=$fail_rows ignored=${ignored_rows:-0} csv=$suite_csv"
  if [[ "$STOP_ON_FAIL" == "1" && "$verdict" != "PASS" ]]; then
    echo "[0265c-consolidated] stopping after failure in suite=$suite; see $suite_csv" >&2
    exit 1
  fi
}

run_piston_suite() {
  local suite="piston_mobile_wall_0255_legacy"
  local script="scripts/run_cuda_persistent_src_collision_piston_0255.sh"
  local suite_art="$ART_DIR/piston_0255"
  local suite_csv="$suite_art/cuda_persistent_src_collision_0255.csv"
  echo "[0265c-consolidated] running suite=$suite gridCases=[$PISTON_GRID_CASES]"
  mkdir -p "$suite_art"
  local rc=0
  set +e
  env BIN="$BIN" ART_DIR="$suite_art" OUT_CSV="$suite_csv" \
      GRID_CASES="$PISTON_GRID_CASES" CASE_LIST="piston_virial_full" \
      GAMMA="$GAMMA" THREADS="$THREADS" STOP_ON_FAIL=0 \
      SUMMARY_EVERY=120 PROJECTION_BACKEND=cpu PROJECTION_ENABLE=true \
      bash "$script"
  rc=$?
  set -e
  local rows pass_rows fail_rows verdict ignored_rows
  IFS=, read -r rows pass_rows fail_rows verdict ignored_rows <<<"$(summarize_suite_csv "$suite_csv")"
  if [[ "$rc" != "0" ]]; then
    verdict="FAIL"
  fi
  append_manifest_row "$suite" "$script" "$PISTON_GRID_CASES" "$suite_csv" "$rc" "$rows" "$pass_rows" "$fail_rows" "$verdict"
  echo "[0265c-consolidated] $verdict suite=$suite rc=$rc rows=$rows pass=$pass_rows fail=$fail_rows ignored=${ignored_rows:-0} csv=$suite_csv"
  if [[ "$STOP_ON_FAIL" == "1" && "$verdict" != "PASS" ]]; then
    echo "[0265c-consolidated] stopping after failure in suite=$suite; see $suite_csv" >&2
    exit 1
  fi
}

run_suite "periodic_0260" \
  "scripts/run_cuda_classic_src_periodic_resident_0260.sh" \
  "$PERIODIC_GRID_CASES" \
  "$ART_DIR/periodic_0260" \
  "$ART_DIR/periodic_0260/cuda_classic_src_periodic_resident_0260.csv"

run_suite "wall_simple_0261" \
  "scripts/run_cuda_classic_src_wall_resident_0261.sh" \
  "$WALL_GRID_CASES" \
  "$ART_DIR/wall_0261" \
  "$ART_DIR/wall_0261/cuda_classic_src_wall_resident_0261.csv"

run_suite "solid_rectangle_0262" \
  "scripts/run_cuda_classic_src_solid_resident_0262.sh" \
  "$SOLID_GRID_CASES" \
  "$ART_DIR/solid_0262" \
  "$ART_DIR/solid_0262/cuda_classic_src_solid_resident_0262.csv"

if [[ "$INCLUDE_PISTON" != "0" && "$INCLUDE_PISTON" != "false" && "$INCLUDE_PISTON" != "FALSE" ]]; then
  run_piston_suite
else
  append_manifest_row "piston_mobile_wall_0255_legacy" "scripts/run_cuda_persistent_src_collision_piston_0255.sh" "$PISTON_GRID_CASES" "skipped" "0" "0" "0" "0" "SKIPPED"
fi

run_suite "io_fullface_0263d" \
  "scripts/run_cuda_classic_src_io_fullface_resident_0263.sh" \
  "$IO_FULLFACE_GRID_CASES" \
  "$ART_DIR/io_fullface_0263" \
  "$ART_DIR/io_fullface_0263/cuda_classic_src_io_fullface_resident_0263.csv"

run_suite "io_segmented_0264" \
  "scripts/run_cuda_classic_src_io_segmented_resident_0264.sh" \
  "$IO_SEGMENTED_GRID_CASES" \
  "$ART_DIR/io_segmented_0264" \
  "$ART_DIR/io_segmented_0264/cuda_classic_src_io_segmented_resident_0264.csv"

python3 - "$OUT_CSV" <<'PY'
import csv, sys
p=sys.argv[1]
with open(p, newline='') as fh:
    rows=list(csv.DictReader(fh))
active=[r for r in rows if r.get('verdict') != 'SKIPPED']
failed=[r for r in active if r.get('verdict') != 'PASS']
print(f"[0265c-consolidated] manifest={p}")
print(f"[0265c-consolidated] suites={len(active)} failed={len(failed)} verdict={'PASS' if active and not failed else 'FAIL'}")
if failed:
    for r in failed:
        print(f"[0265c-consolidated] failed-suite={r.get('suite')} csv={r.get('outputCsv')} rc={r.get('exitCode')} rows={r.get('rows')} failRows={r.get('failRows')}")
    raise SystemExit(1)
PY

echo "[0265c-consolidated] wrote $OUT_CSV"
echo "[0265c-consolidated] classic-only validators keep Q6/resampling/virial/thermostat disabled only for this validation pass."
echo "[0265c-consolidated] future CPU Q6 + resampling and wall/solid/piston/IO-aware CUDA thermostat reactivation remain separate, preserved chantiers."
