#!/usr/bin/env bash
set -euo pipefail

# 0493w0 -- Kinetic-regime qualification of the segmented Darcy-cylinder case.
#
# Purpose:
#   Determine whether the observed inlet lip and depleted cylinder wake are
#   primarily consequences of an extreme SRC/MPCD regime (high Mach proxy,
#   very short streaming displacement, low effective Reynolds number), before
#   introducing a dedicated wall-support repair.
#
# This sweep is deliberately classic SRC only:
#   - Q6 off through the underlying 0493o0 runner;
#   - support repair off;
#   - no mutating resampling;
#   - no live visualization or field recorder;
#   - one final fluid-only particle dump per case for spatial diagnostics.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BASE_RUNNER="${BASE_RUNNER:-$ROOT/scripts/run_0493o0_src_baseline_segmented_darcy.sh}"
ANALYZER="${ANALYZER:-$ROOT/scripts/analyze_0493w0_darcy_kinetic_regime_sweep.py}"
BIN="${BIN:-$ROOT/build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
SWEEP_ROOT="${SWEEP_ROOT:-$ROOT/runs/0493w0_darcy_kinetic_regime_sweep}"
SWEEP_PROFILE="${SWEEP_PROFILE:-screen}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

# Same physical observation time for every case.  T_END=0.8 corresponds to
# half a cylinder transit time D/U0 for D=0.24 and U0=0.15.  It is long enough
# to pass the inlet ramp and reproduce the early wake depletion seen near
# t~0.58, while keeping the complete screen near the requested 20-minute cap.
T_END="${T_END:-0.8}"
MAX_STEPS="${MAX_STEPS:-1800}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-1200}"
STOP_BEFORE_BUDGET_SECONDS="${STOP_BEFORE_BUDGET_SECONDS:-45}"

Lx="${Lx:-1.0}"
Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-20}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
U0="${U0:-0.15}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
CYLINDER_CX="${CYLINDER_CX:-0.50}"
CYLINDER_CY="${CYLINDER_CY:-0.50}"
CYLINDER_R="${CYLINDER_R:-0.12}"
BASE_ALPHA="${BASE_ALPHA:-8000.0}"
SEED="${SEED:-493002}"
SUPPORT_TRIGGER_NMIN="${SUPPORT_TRIGGER_NMIN:-12}"
INACTIVE_SLOTS_PER_CELL="${INACTIVE_SLOTS_PER_CELL:-8}"
DIAG_PHYSICAL_EVERY="${DIAG_PHYSICAL_EVERY:-0.04}"
EXPECTED_SECONDS_PER_STEP_128="${EXPECTED_SECONDS_PER_STEP_128:-0.0435}"

[[ -x "$BASE_RUNNER" ]] || {
  echo "[0493w0] ERROR missing executable base runner: $BASE_RUNNER" >&2
  exit 2
}
[[ -f "$ANALYZER" ]] || {
  echo "[0493w0] ERROR missing analyzer: $ANALYZER" >&2
  exit 2
}
[[ -x "$BIN" ]] || {
  echo "[0493w0] ERROR missing executable binary: $BIN" >&2
  exit 2
}
command -v python3 >/dev/null || { echo "[0493w0] ERROR python3 unavailable" >&2; exit 2; }

mkdir -p "$SWEEP_ROOT/analysis" "$SWEEP_ROOT/cases" "$SWEEP_ROOT/logs"
MANIFEST="$SWEEP_ROOT/sweep_manifest.csv"
STATUS="$SWEEP_ROOT/run_status.csv"

# case_id | Nx | Ny | dt | kBT | alpha | note
#
# The screen spans approximately:
#   Re_D estimate: 3.7 -> 56
#   ideal-2D Mach proxy: 3.35 -> 0.34
#   thermal rms displacement/cell: 0.003 -> 0.23 (depending on combination)
#
# Two alpha*dt controls separate physical-dt effects from a possible
# under-resolved Brinkman/Darcy relaxation.  They keep alpha*dt=8 while changing
# the physical alpha; they are controls, not members of the physical-alpha axis.
read -r -d '' SCREEN_CASES <<'CASES' || true
ref|128|128|0.001|0.001|8000|reference_current_regime
kbt_003|128|128|0.001|0.003|8000|temperature_axis
kbt_010|128|128|0.001|0.010|8000|temperature_axis
kbt_030|128|128|0.001|0.030|8000|temperature_axis
kbt_100|128|128|0.001|0.100|8000|low_Mach_temperature_axis
grid_192|192|192|0.001|0.001|8000|grid_axis
dt_0020|128|128|0.002|0.001|8000|physical_dt_axis
mix_192_hot|192|192|0.001|0.030|8000|moderate_Mach_higher_Re
mix_256_hot_dt2|256|256|0.002|0.100|8000|low_Mach_Re_near_wake_transition
grid_256|256|256|0.001|0.001|8000|grid_axis
dt_0005|128|128|0.0005|0.001|8000|physical_dt_axis
grid_096|96|96|0.001|0.001|8000|grid_axis
mix_256_mid_dt2|256|256|0.002|0.030|8000|higher_Re_moderate_Mach
dt_0005_ast8|128|128|0.0005|0.001|16000|alpha_dt_control
dt_0020_ast8|128|128|0.002|0.001|4000|alpha_dt_control
CASES

# The quick profile retains the minimum discriminating set and is useful for a
# first smoke or on a slower GPU.
read -r -d '' QUICK_CASES <<'CASES' || true
ref|128|128|0.001|0.001|8000|reference_current_regime
kbt_010|128|128|0.001|0.010|8000|temperature_axis
kbt_100|128|128|0.001|0.100|8000|low_Mach_temperature_axis
grid_192|192|192|0.001|0.001|8000|grid_axis
dt_0020|128|128|0.002|0.001|8000|physical_dt_axis
mix_192_hot|192|192|0.001|0.030|8000|moderate_Mach_higher_Re
mix_256_hot_dt2|256|256|0.002|0.100|8000|low_Mach_Re_near_wake_transition
CASES

case "$SWEEP_PROFILE" in
  screen) CASE_TEXT="$SCREEN_CASES" ;;
  quick) CASE_TEXT="$QUICK_CASES" ;;
  *)
    echo "[0493w0] ERROR SWEEP_PROFILE must be screen or quick; got $SWEEP_PROFILE" >&2
    exit 2
    ;;
esac

python3 - "$MANIFEST" "$SWEEP_ROOT" "$T_END" "$MAX_STEPS" "$CASE_TEXT" <<'PY_MANIFEST'
import csv
import math
import sys
from pathlib import Path

manifest = Path(sys.argv[1])
sweep_root = Path(sys.argv[2])
t_end = float(sys.argv[3])
max_steps = int(sys.argv[4])
case_text = sys.argv[5]
rows = []
seen = set()
for raw in case_text.splitlines():
    raw = raw.strip()
    if not raw or raw.startswith("#"):
        continue
    case_id, nx, ny, dt, kbt, alpha, note = raw.split("|", 6)
    if case_id in seen:
        raise SystemExit(f"duplicate case_id: {case_id}")
    seen.add(case_id)
    dt_value = float(dt)
    steps = int(round(t_end / dt_value))
    if steps < 1 or steps > max_steps:
        raise SystemExit(
            f"{case_id}: steps={steps} outside 1..{max_steps}; "
            f"T_END={t_end} dt={dt_value}"
        )
    rows.append({
        "case_id": case_id,
        "nx": int(nx),
        "ny": int(ny),
        "dt": format(dt_value, ".17g"),
        "kbt": format(float(kbt), ".17g"),
        "alpha": format(float(alpha), ".17g"),
        "steps": steps,
        "t_end": format(steps * dt_value, ".17g"),
        "run_root": str(sweep_root / "cases" / case_id),
        "note": note,
    })
manifest.parent.mkdir(parents=True, exist_ok=True)
with manifest.open("w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
print(f"[0493w0] manifest={manifest} cases={len(rows)}")
PY_MANIFEST

python3 "$ANALYZER" \
  --sweep-root "$SWEEP_ROOT" \
  --manifest "$MANIFEST" \
  --lx "$Lx" --ly "$Ly" \
  --gamma "$GAMMA" --particle-mass "$PARTICLE_MASS" \
  --u0 "$U0" --rotation-angle "$ROTATION_ANGLE" \
  --cylinder-cx "$CYLINDER_CX" --cylinder-cy "$CYLINDER_CY" \
  --cylinder-r "$CYLINDER_R" \
  --support-nmin "$SUPPORT_TRIGGER_NMIN" \
  --preflight-only

ESTIMATE_SECONDS="$(python3 - "$MANIFEST" "$EXPECTED_SECONDS_PER_STEP_128" <<'PY_EST'
import csv
import sys
with open(sys.argv[1], newline="") as stream:
    rows = list(csv.DictReader(stream))
base = float(sys.argv[2])
seconds = 0.0
for row in rows:
    scale = int(row["nx"]) * int(row["ny"]) / (128.0 * 128.0)
    seconds += int(row["steps"]) * scale * base
print(f"{seconds:.1f}")
PY_EST
)"
python3 - "$ESTIMATE_SECONDS" "$MAX_WALL_SECONDS" <<'PY_BUDGET'
import sys
estimate = float(sys.argv[1])
budget = float(sys.argv[2])
print(f"[0493w0] estimatedWall={estimate:.1f}s ({estimate/60:.1f}min) budget={budget:.0f}s ({budget/60:.1f}min)")
if estimate > budget:
    print("[0493w0] WARNING estimate exceeds budget; use SWEEP_PROFILE=quick or lower T_END")
PY_BUDGET

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  echo "[0493w0] PREFLIGHT_ONLY=1; no simulation launched"
  exit 0
fi

printf 'case_id,status,exit_code,elapsed_seconds,run_root\n' > "$STATUS"
START_SECONDS=$SECONDS
COMPLETED=0
STOPPED_FOR_BUDGET=0

while IFS=, read -r case_id nx ny dt kbt alpha steps t_end run_root note; do
  [[ "$case_id" == case_id ]] && continue
  elapsed=$((SECONDS - START_SECONDS))
  if (( elapsed >= MAX_WALL_SECONDS - STOP_BEFORE_BUDGET_SECONDS )); then
    echo "[0493w0] BUDGET stop before case=$case_id elapsed=${elapsed}s" >&2
    STOPPED_FOR_BUDGET=1
    break
  fi

  diag_every="$(python3 - "$DIAG_PHYSICAL_EVERY" "$dt" "$steps" <<'PY_DIAG'
import sys
physical = float(sys.argv[1])
dt = float(sys.argv[2])
steps = int(sys.argv[3])
value = max(1, int(round(physical / dt)))
print(min(value, steps))
PY_DIAG
)"

  echo
  echo "======================================================================"
  echo "[0493w0] case=$case_id grid=${nx}x${ny} dt=$dt kBT=$kbt alpha=$alpha steps=$steps tEnd=$t_end"
  echo "[0493w0] runRoot=$run_root diagEvery=$diag_every"
  echo "======================================================================"

  case_start=$SECONDS
  set +e
  ROOT="$ROOT" \
  BIN="$BIN" \
  RUN_ROOT="$run_root" \
  NX="$nx" NY="$ny" \
  Lx="$Lx" Ly="$Ly" \
  GAMMA="$GAMMA" PARTICLE_MASS="$PARTICLE_MASS" \
  DT="$dt" STEPS="$steps" KBT="$kbt" \
  THERMOSTAT_TARGET_KBT="$kbt" \
  U0="$U0" VELOCITY_MODE=uniform_x \
  ROTATION_ANGLE="$ROTATION_ANGLE" \
  CYLINDER_CX="$CYLINDER_CX" CYLINDER_CY="$CYLINDER_CY" CYLINDER_R="$CYLINDER_R" \
  ALPHA="$alpha" \
  SEED="$SEED" \
  SUPPORT_REPAIR_ENABLE=false \
  INACTIVE_SLOTS_PER_CELL="$INACTIVE_SLOTS_PER_CELL" \
  LIVE_PROGRESS=1 \
  LIVE_VIS_ENABLE=0 \
  LIVE_VIS_HOLD_ON_EXIT=0 \
  FILTERED_RECORDING_ENABLE=0 \
  RECORD_ENABLE=false \
  MPCD_INTERNAL_PROFILES=0 \
  MPCD_CUDA_RESIDENT_PROFILE_0266=0 \
  SUMMARY_EVERY="$diag_every" \
  DUMP_STATE_EVERY="$steps" \
  RESAMPLING_SURVEY_EVERY="$diag_every" \
  FLAG_EVERY="$diag_every" \
  DARCY_COST_EVERY="$diag_every" \
  TOPO_BENCHMARK_EVERY="$diag_every" \
  SUPPORT_TRIGGER_NMIN="$SUPPORT_TRIGGER_NMIN" \
  DUMP_ROLE_FILTER=fluid \
  SUMMARY_ROLE_FILTER=fluid \
  CLEAN_RUN_ROOT=1 \
  bash "$BASE_RUNNER"
  rc=$?
  set -e
  case_elapsed=$((SECONDS - case_start))

  if (( rc != 0 )); then
    printf '%s,FAIL,%s,%s,%s\n' "$case_id" "$rc" "$case_elapsed" "$run_root" >> "$STATUS"
    echo "[0493w0] ERROR case=$case_id rc=$rc elapsed=${case_elapsed}s" >&2
    exit "$rc"
  fi

  final_dump="$run_root/output/state_step_$(printf '%08d' "$steps").smpcd"
  if [[ ! -f "$final_dump" ]]; then
    printf '%s,FAIL_MISSING_DUMP,3,%s,%s\n' "$case_id" "$case_elapsed" "$run_root" >> "$STATUS"
    echo "[0493w0] ERROR missing final dump: $final_dump" >&2
    exit 3
  fi

  printf '%s,PASS,0,%s,%s\n' "$case_id" "$case_elapsed" "$run_root" >> "$STATUS"
  COMPLETED=$((COMPLETED + 1))
  echo "[0493w0] PASS case=$case_id elapsed=${case_elapsed}s"
done < "$MANIFEST"

TOTAL_ELAPSED=$((SECONDS - START_SECONDS))
echo "[0493w0] runsComplete=$COMPLETED elapsed=${TOTAL_ELAPSED}s budgetStop=$STOPPED_FOR_BUDGET"

ANALYSIS_MANIFEST="$MANIFEST"
if (( STOPPED_FOR_BUDGET != 0 )); then
  echo "[0493w0] PARTIAL sweep; analysis will include completed runs only" >&2
  ANALYSIS_MANIFEST="$SWEEP_ROOT/sweep_manifest_completed.csv"
  python3 - "$MANIFEST" "$STATUS" "$ANALYSIS_MANIFEST" <<'PY_COMPLETED'
import csv
import sys
passed = set()
with open(sys.argv[2], newline="") as stream:
    for row in csv.DictReader(stream):
        if row["status"] == "PASS":
            passed.add(row["case_id"])
with open(sys.argv[1], newline="") as stream:
    rows = [row for row in csv.DictReader(stream) if row["case_id"] in passed]
if not rows:
    raise SystemExit("no completed case available for partial analysis")
with open(sys.argv[3], "w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
PY_COMPLETED
fi

python3 "$ANALYZER" \
  --sweep-root "$SWEEP_ROOT" \
  --manifest "$ANALYSIS_MANIFEST" \
  --lx "$Lx" --ly "$Ly" \
  --gamma "$GAMMA" --particle-mass "$PARTICLE_MASS" \
  --u0 "$U0" --rotation-angle "$ROTATION_ANGLE" \
  --cylinder-cx "$CYLINDER_CX" --cylinder-cy "$CYLINDER_CY" \
  --cylinder-r "$CYLINDER_R" \
  --support-nmin "$SUPPORT_TRIGGER_NMIN"

if (( STOPPED_FOR_BUDGET != 0 )); then
  exit 4
fi

echo "[0493w0] PASS sweepRoot=$SWEEP_ROOT"
