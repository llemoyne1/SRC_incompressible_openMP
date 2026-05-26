#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CASE_STEPS="${CASE_STEPS:-3000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
NUM_THREADS="${NUM_THREADS:-4}"
CLEAN_OUTPUTS="${CLEAN_OUTPUTS:-1}"

RUN_Q9="${RUN_Q9:-1}"
RUN_Q9_VIRIAL="${RUN_Q9_VIRIAL:-1}"
MAKE_VISUAL_REPORT="${MAKE_VISUAL_REPORT:-1}"
VISUAL_MAX_FRAMES="${VISUAL_MAX_FRAMES:-10}"
VISUAL_FRAME_STRIDE="${VISUAL_FRAME_STRIDE:-1}"
VISUAL_SAMPLE_MODE="${VISUAL_SAMPLE_MODE:-uniform}"
VISUAL_ZOOM_HALF_WIDTH="${VISUAL_ZOOM_HALF_WIDTH:-0.32}"
VISUAL_ZOOM_HALF_HEIGHT="${VISUAL_ZOOM_HALF_HEIGHT:-0.24}"

STATE="initial_state_periodic_cylinder_96x48_g20_0102.smpcd"
TMP_DIR="runs/_tmp_periodic_cylinder_dynamic_visual_0105"
mkdir -p "$TMP_DIR"

if [[ ! -x build/src_mpcd_base ]]; then
  ./scripts/build_src_mpcd_base.sh
fi

if [[ ! -f "$STATE" ]]; then
  if command -v matlab >/dev/null 2>&1; then
    matlab -batch "cd('matlab'); generate_smpcd_state_uniform('output','../${STATE}', 'Lx',2.0, 'Ly',1.0, 'Nx',96, 'Ny',48, 'gamma',20, 'kBT',0.01, 'mass',1.0, 'type',0, 'seed',12345, 'mode','uniform_per_cell', 'velocityMode','maxwell', 'removeMeanMomentum',true, 'excludeCircle',true, 'circleCx',0.5, 'circleCy',0.5, 'circleR',0.12);"
  else
    cat >&2 <<MSG
Missing ${STATE} and matlab is not on PATH.
Generate it once from the repository root with:

  cd matlab
  generate_smpcd_state_uniform('output','../${STATE}', ...
      'Lx',2.0,'Ly',1.0,'Nx',96,'Ny',48,'gamma',20,'kBT',0.01, ...
      'mass',1.0,'type',0,'seed',12345,'mode','uniform_per_cell', ...
      'velocityMode','maxwell','removeMeanMomentum',true, ...
      'excludeCircle',true,'circleCx',0.5,'circleCy',0.5,'circleR',0.12);
  cd ..
MSG
    exit 1
  fi
fi

summarize_run() {
  local label="$1"
  local outdir="$2"
  python3 - "$label" "$outdir" <<'PY'
import csv
import math
import pathlib
import sys

label = sys.argv[1]
outdir = pathlib.Path(sys.argv[2])
summary = outdir / "summary_runtime.csv"
print(f"[{label}] outputDir={outdir}")
if not summary.exists():
    print(f"[{label}] ERROR: missing {summary}")
    sys.exit(2)
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
if not rows:
    print(f"[{label}] ERROR: empty summary_runtime.csv")
    sys.exit(2)
for ir, row in enumerate(rows):
    for key, value in row.items():
        try:
            x = float(value)
        except (TypeError, ValueError):
            continue
        if not math.isfinite(x):
            print(f"[{label}] ERROR: non-finite value at row={ir}, key={key}, value={value}")
            sys.exit(2)
last = rows[-1]
print(f"[{label}] rows={len(rows)} finalStep={last.get('step','?')} finalTime={last.get('time','?')}")
keys = [
    'totalMass','kBTEstimate','meanUx','meanUy','hitsImmersed','maxParticlesInsideCircle',
    'q6ImmersedSolidLeakProjectedFluxRms','q6ImmersedSolidAppliedLeakBeforeClosureRms',
    'q9ImmersedHaloExcludedCells','q9ImmersedSolidActiveCutCells','q9ImmersedSolidActiveAdjacentCells',
    'q9ImmersedSolidLeakMassFluxRms','q9ImmersedSolidAppliedLeakBeforeClosureRms',
    'q9ImmersedSolidClosedFaceFluxEnforcedFaces','q9LowMassSuppressedCells','q9LimiterActiveCells',
    'q9VelocityLimitedCells','q9CorrectionVelocityRawMaxAbs','q9CorrectionVelocityMaxAbs',
    'q9MassFluxDivAfterRms','q9MassFluxDivAfterMaxAbs',
    'virialImmersedSolidActiveAdjacentCells','virialImmersedSolidNormalKickClippedCells',
    'virialImmersedSolidNormalKickClippedRms','virialImmersedSolidNormalKickClippedMaxAbs']
for key in keys:
    if key in last:
        print(f"[{label}] {key}={last[key]}")
q9bins = sorted(outdir.glob('*.q9bin'))
states = sorted(outdir.glob('state_step_*.smpcd'))
print(f"[{label}] state_count={len(states)} q9bin_count={len(q9bins)}")

def f(key):
    try:
        return float(last[key])
    except Exception:
        return None
if label.startswith('q9'):
    leak = f('q9ImmersedSolidLeakMassFluxRms')
    halo = f('q9ImmersedHaloExcludedCells')
    adj = f('q9ImmersedSolidActiveAdjacentCells')
    low = f('q9LowMassSuppressedCells')
    limited = f('q9VelocityLimitedCells')
    if halo is not None and halo != 0.0:
        print(f"[{label}] WARNING: q9ImmersedHaloExcludedCells is non-zero")
    if leak is not None and abs(leak) > 1.0e-12:
        print(f"[{label}] WARNING: q9 immersed-solid leak is not near zero")
    if adj is not None and adj <= 0.0:
        print(f"[{label}] WARNING: no active adjacent cells detected")
    if low is not None and low > 0.0:
        print(f"[{label}] NOTE: q9LowMassSuppressedCells is non-zero")
    if limited is not None and limited > 0.0:
        print(f"[{label}] NOTE: q9VelocityLimitedCells is non-zero")
PY
}

run_case() {
  local label="$1"
  local base_params="$2"
  local outdir="$3"
  local effective="$TMP_DIR/params_${label}_effective.kv"
  if [[ "$CLEAN_OUTPUTS" == "1" ]]; then
    rm -rf "$outdir"
  fi
  cp "$base_params" "$effective"
  cat >> "$effective" <<EOF2

# Runtime overrides appended by scripts/run_periodic_cylinder_dynamic_visual_0105.sh
outputDir = ${outdir}
nSteps = ${CASE_STEPS}
summaryEvery = ${SUMMARY_EVERY}
dumpStateEvery = ${DUMP_STATE_EVERY}
numThreads = ${NUM_THREADS}
EOF2
  echo "[0105] running ${label}: steps=${CASE_STEPS}, summaryEvery=${SUMMARY_EVERY}, dumpStateEvery=${DUMP_STATE_EVERY}, threads=${NUM_THREADS}"
  ./build/src_mpcd_base "$effective"
  summarize_run "$label" "$outdir"
}

run_dirs=()
if [[ "$RUN_Q9" == "1" ]]; then
  run_case "q9" \
    "examples/params_periodic_cylinder_q9_dynamic_visual_96x48_0105.kv" \
    "runs/periodic_cylinder_q9_dynamic_visual_96x48_0105"
  run_dirs+=("../runs/periodic_cylinder_q9_dynamic_visual_96x48_0105")
fi
if [[ "$RUN_Q9_VIRIAL" == "1" ]]; then
  run_case "q9_virial" \
    "examples/params_periodic_cylinder_q9_virial_dynamic_visual_96x48_0105.kv" \
    "runs/periodic_cylinder_q9_virial_dynamic_visual_96x48_0105"
  run_dirs+=("../runs/periodic_cylinder_q9_virial_dynamic_visual_96x48_0105")
fi

if [[ "$MAKE_VISUAL_REPORT" == "1" ]]; then
  if command -v matlab >/dev/null 2>&1; then
    matlab_dirs="{"
    for d in "${run_dirs[@]}"; do
      matlab_dirs+="'${d}',"
    done
    matlab_dirs="${matlab_dirs%,}}"
    echo "[0105] generating MATLAB dynamic visual report for ${matlab_dirs}"
    matlab -batch "cd('matlab'); make_periodic_cylinder_dynamic_visual_report_0105(${matlab_dirs}, 'maxFrames', ${VISUAL_MAX_FRAMES}, 'frameStride', ${VISUAL_FRAME_STRIDE}, 'sampleMode', '${VISUAL_SAMPLE_MODE}', 'zoomHalfWidth', ${VISUAL_ZOOM_HALF_WIDTH}, 'zoomHalfHeight', ${VISUAL_ZOOM_HALF_HEIGHT}, 'visible', true);"
  else
    cat <<MSG
[0105] matlab not found; runs are complete but visual PNGs were not generated.
Generate them later with:

  cd matlab
  make_periodic_cylinder_dynamic_visual_report_0105({}, 'maxFrames', ${VISUAL_MAX_FRAMES}, ...
      'sampleMode', '${VISUAL_SAMPLE_MODE}', 'zoomHalfWidth', ${VISUAL_ZOOM_HALF_WIDTH}, ...
      'zoomHalfHeight', ${VISUAL_ZOOM_HALF_HEIGHT}, 'visible', true);
MSG
  fi
fi

echo "[0105] periodic-cylinder dynamic visual suite completed"
