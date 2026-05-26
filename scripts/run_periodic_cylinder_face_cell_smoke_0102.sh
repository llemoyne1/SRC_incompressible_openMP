#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CASE_STEPS="${CASE_STEPS:-150}"
SUMMARY_EVERY="${SUMMARY_EVERY:-25}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-25}"
NUM_THREADS="${NUM_THREADS:-4}"
CLEAN_OUTPUTS="${CLEAN_OUTPUTS:-1}"

RUN_CLASSIC="${RUN_CLASSIC:-0}"
RUN_Q6="${RUN_Q6:-1}"
RUN_Q9="${RUN_Q9:-1}"
RUN_Q9_VIRIAL="${RUN_Q9_VIRIAL:-1}"

STATE="initial_state_periodic_cylinder_96x48_g20_0102.smpcd"
TMP_DIR="runs/_tmp_periodic_cylinder_face_cell_0102"
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

bad = []
for ir, row in enumerate(rows):
    for key, value in row.items():
        try:
            x = float(value)
        except (TypeError, ValueError):
            continue
        if not math.isfinite(x):
            bad.append((ir, key, value))
if bad:
    print(f"[{label}] ERROR: non-finite values found, first={bad[0]}")
    sys.exit(2)

last = rows[-1]
print(f"[{label}] rows={len(rows)} finalStep={last.get('step','?')} finalTime={last.get('time','?')}")

wanted = [
    "totalMass",
    "kBTEstimate",
    "meanUx",
    "meanUy",
    "hitsImmersed",
    "maxParticlesInsideCircle",
    "q6ImmersedSolidLeakProjectedFluxRms",
    "q6ImmersedSolidLeakProjectedFluxMaxAbs",
    "q6ImmersedSolidLeakFaceCount",
    "q6ImmersedSolidAppliedLeakBeforeClosureRms",
    "q6ImmersedSolidAppliedLeakBeforeClosureMaxAbs",
    "q6ImmersedSolidClosedFaceFluxEnforcedFaces",
    "q6ImmersedSolidClosedFaceFluxEnforcedRms",
    "q6ImmersedSolidClosedFaceFluxEnforcedMaxAbs",
    "q9ImmersedHaloExcludedCells",
    "q9ImmersedSolidFluidCells",
    "q9ImmersedSolidSolidCells",
    "q9ImmersedSolidCutCells",
    "q9ImmersedSolidActiveCutCells",
    "q9ImmersedSolidActiveAdjacentCells",
    "q9ImmersedSolidClosedXFaces",
    "q9ImmersedSolidClosedYFaces",
    "q9ImmersedSolidLeakMassFluxRms",
    "q9ImmersedSolidLeakMassFluxMaxAbs",
    "q9ImmersedSolidLeakFaceCount",
    "q9ImmersedSolidAppliedLeakBeforeClosureRms",
    "q9ImmersedSolidAppliedLeakBeforeClosureMaxAbs",
    "q9ImmersedSolidClosedFaceFluxEnforcedFaces",
    "q9ImmersedSolidClosedFaceFluxEnforcedRms",
    "q9ImmersedSolidClosedFaceFluxEnforcedMaxAbs",
    "q9MassFluxDivAfterRms",
    "q9MassFluxDivAfterMaxAbs",
    "q9SafetyActiveCells",
    "q9SafetyExcludedCells",
    "virialImmersedSolidActiveAdjacentCells",
    "virialImmersedSolidNormalKickClippedCells",
    "virialImmersedSolidNormalKickClippedComponents",
    "virialImmersedSolidNormalKickClippedRms",
    "virialImmersedSolidNormalKickClippedMaxAbs",
]
for key in wanted:
    if key in last:
        print(f"[{label}] {key}={last[key]}")

q9bins = sorted(outdir.glob("*.q9bin"))
if q9bins:
    print(f"[{label}] q9bin_count={len(q9bins)} first={q9bins[0].name}")
else:
    print(f"[{label}] q9bin_count=0")

# Non-fatal consistency warnings: this is a smoke runner, not a physics validator.
def f(key, default=None):
    try:
        return float(last[key])
    except Exception:
        return default

halo = f("q9ImmersedHaloExcludedCells")
if halo is not None and halo != 0.0:
    print(f"[{label}] WARNING: q9ImmersedHaloExcludedCells is non-zero")

leak = f("q9ImmersedSolidLeakMassFluxRms")
if label.startswith("q9") and leak is not None and abs(leak) > 1.0e-12:
    print(f"[{label}] WARNING: q9 immersed-solid mass-flux leak is not near machine zero")

adj = f("q9ImmersedSolidActiveAdjacentCells")
if label.startswith("q9") and adj is not None and adj <= 0.0:
    print(f"[{label}] WARNING: no active fluid cells adjacent to the immersed cylinder were detected")
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

# Runtime overrides appended by scripts/run_periodic_cylinder_face_cell_smoke_0102.sh
outputDir = ${outdir}
nSteps = ${CASE_STEPS}
summaryEvery = ${SUMMARY_EVERY}
dumpStateEvery = ${DUMP_STATE_EVERY}
numThreads = ${NUM_THREADS}
EOF2

  echo "[0102] running ${label}: steps=${CASE_STEPS}, summaryEvery=${SUMMARY_EVERY}, dumpStateEvery=${DUMP_STATE_EVERY}, threads=${NUM_THREADS}"
  ./build/src_mpcd_base "$effective"
  summarize_run "$label" "$outdir"
}

if [[ "$RUN_CLASSIC" == "1" ]]; then
  run_case "classic" \
    "examples/params_periodic_cylinder_classic_smoke_96x48_0102.kv" \
    "runs/periodic_cylinder_classic_smoke_96x48_0102"
fi

if [[ "$RUN_Q6" == "1" ]]; then
  run_case "q6" \
    "examples/params_periodic_cylinder_q6_smoke_96x48_0102.kv" \
    "runs/periodic_cylinder_q6_smoke_96x48_0102"
fi

if [[ "$RUN_Q9" == "1" ]]; then
  run_case "q9" \
    "examples/params_periodic_cylinder_q9_smoke_96x48_0102.kv" \
    "runs/periodic_cylinder_q9_smoke_96x48_0102"
fi

if [[ "$RUN_Q9_VIRIAL" == "1" ]]; then
  run_case "q9_virial" \
    "examples/params_periodic_cylinder_q9_virial_smoke_96x48_0102.kv" \
    "runs/periodic_cylinder_q9_virial_smoke_96x48_0102"
fi

echo "[0102] periodic-cylinder face/cell smoke suite completed"
