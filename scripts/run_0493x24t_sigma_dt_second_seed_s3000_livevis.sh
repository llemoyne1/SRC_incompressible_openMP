#!/usr/bin/env bash
# =============================================================================
# 0493x24t — second-seed confirmation of sigma(dt) smoke
#
# Purpose:
#   Repeat ONLY dt=4e-4 and dt=2e-4 from x24s with one independent seed,
#   keeping exactly the same short paired Young–Laplace protocol:
#
#       R/h = 40
#       sigma = 0 / 3000
#       physical duration = 0.4
#
# Total: 4 solver runs.
#
# This is a relative dt-sensitivity check, not a precision calibration.
# No C++/CUDA modification.
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

X12YL="scripts/run_0493x12yl_young_laplace_calibrator.sh"
ANALYZER="scripts/analyze_0493x12yl_young_laplace_calibrator.py"
PARENT="scripts/run_0493x10o_q6_thermal_interface_static_drop.sh"

for f in "$X12YL" "$ANALYZER" "$PARENT"; do
  if [[ ! -f "$f" ]]; then
    echo "[0493x24t] ERROR missing required file: $f" >&2
    exit 2
  fi
done

CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x24t_sigma_dt_second_seed_s3000}"
MODE="${MODE:-production}"
PHYSICAL_TIME="${PHYSICAL_TIME:-0.4}"

# Exact Sato-liquid signature used in x24s.
export NX="${NX:-256}"
export NY="${NY:-256}"
export Lx="${Lx:-1.0}"
export Ly="${Ly:-1.0}"

export GAMMA="${GAMMA:-20}"
export KBT="${KBT:-0.02}"
export LIQUID_MASS="${LIQUID_MASS:-1.0}"

export ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
export RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
export GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"

export THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
export THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
export THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
export THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
export THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

export SIGMA_DECLARED="${SIGMA_DECLARED:-3000}"
export SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
export ALLOW_LOCAL_COOLING="${ALLOW_LOCAL_COOLING:-0}"

RADII="${RADII:-40}"
REPLICATES=1

# Independent from x24s default seed=4932401.
export BASE_SEED="${BASE_SEED:-4933401}"
export SEED_STRIDE="${SEED_STRIDE:-1009}"
export TAIL_START="${TAIL_START:-0.50}"

export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export THREADS="${THREADS:-8}"

mkdir -p "$CAMPAIGN_ROOT" || exit 2

# Dedicated campaign-local LiveVis control.
if [[ "$CAMPAIGN_ROOT" = /* ]]; then
  CAMPAIGN_ROOT_ABS="$CAMPAIGN_ROOT"
else
  CAMPAIGN_ROOT_ABS="$ROOT/$CAMPAIGN_ROOT"
fi
LIVEVIS_CONTROL="$CAMPAIGN_ROOT_ABS/livevis_control_0493x24t.kv"

cat > "$LIVEVIS_CONTROL" <<'CONTROL'
# 0493x24t — dedicated second-seed static-drop visual check.
field = mass
colormap = hot
clip = -1
gain = 1.0
smoothPasses = 1
liveGridNx = 256
liveGridNy = 256
liveEvery = 20
particleTypeFilter = 1
recordEnable = false
CONTROL

export LIVE_VIS_ENABLE=1
export LIVE_VIS_FIELD=mass
export LIVE_VIS_EVERY=20
export LIVE_VIS_NX=256
export LIVE_VIS_NY=256
export LIVE_VIS_COLORMAP=hot
export LIVE_VIS_CLIP=-1
export LIVE_VIS_GAIN=1.0
export LIVE_VIS_SMOOTH_PASSES=1
export LIVE_VIS_WINDOW_SCALE=1
export LIVE_VIS_HOLD_ON_EXIT=0
export LIVE_VIS_RECORD_ENABLE=0
export FILTERED_RECORDING_ENABLE=0

export LIVE_VIS_CONTROL_FILE="$LIVEVIS_CONTROL"
export LIVE_VIS_CONTROL_FILE_EFFECTIVE="$LIVEVIS_CONTROL"
export SRC_LIVE_VIS_CONTROL_FILE="$LIVEVIS_CONTROL"
export MPCD_LIVE_VIS_CONTROL_FILE="$LIVEVIS_CONTROL"
export SRC_LIVE_VIS_CONTROL_EVERY=1
export MPCD_LIVE_VIS_CONTROL_EVERY=1
export SRC_LIVE_VIS_CONTROL_LOG=1
export MPCD_LIVE_VIS_CONTROL_LOG=1
export OVERWRITE_LIVEVIS_CONTROL=0

PLAN="$CAMPAIGN_ROOT/campaign_plan.tsv"
STATUS="$CAMPAIGN_ROOT/campaign_status.tsv"
SUMMARY="$CAMPAIGN_ROOT/sigma_dt_second_seed_summary.tsv"

printf "tag\tdt\tsteps\tphysical_time\tradius\tseed\tsigma_declared\tlivevis_control\n" > "$PLAN"
printf "tag\tstage\tstatus\troot\n" > "$STATUS"

CASES=(
  "dt4e4 0.0004"
  "dt2e4 0.0002"
)

calc_steps() {
  python3 - "$1" "$PHYSICAL_TIME" <<'PY'
import sys
dt=float(sys.argv[1]); T=float(sys.argv[2])
n=round(T/dt)
if abs(n*dt-T)>1e-12:
    raise SystemExit("PHYSICAL_TIME is not an integer number of steps")
summary=max(1,round(0.02/dt))
print(int(n), int(summary))
PY
}

for spec in "${CASES[@]}"; do
  read -r TAG DT_LOCAL <<<"$spec"
  read -r STEPS_LOCAL SUMMARY_LOCAL <<<"$(calc_steps "$DT_LOCAL")" || exit 2
  RUN_ROOT="$CAMPAIGN_ROOT/$TAG"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$TAG" "$DT_LOCAL" "$STEPS_LOCAL" "$PHYSICAL_TIME" "$RADII" \
    "$BASE_SEED" "$SIGMA_DECLARED" "$LIVEVIS_CONTROL" >> "$PLAN"

  echo
  echo "================================================================"
  echo "[0493x24t] CASE=$TAG dt=$DT_LOCAL"
  echo "[0493x24t] secondSeed=$BASE_SEED R/h=$RADII"
  echo "[0493x24t] paired sigma=0 / sigma=$SIGMA_DECLARED"
  echo "[0493x24t] T=$PHYSICAL_TIME steps=$STEPS_LOCAL"
  echo "[0493x24t] livevis=$LIVEVIS_CONTROL"
  echo "================================================================"

  export DT="$DT_LOCAL"
  export STEPS="$STEPS_LOCAL"
  export SUMMARY_EVERY="$SUMMARY_LOCAL"

  if [[ "$MODE" == "preflight" ]]; then
    PROFILE=quick RADII="$RADII" REPLICATES=1 RUN_ROOT="$RUN_ROOT" \
    PREFLIGHT_ONLY=1 ANALYZE_ONLY=0 CLEAN_RUN_ROOT=0 \
    bash "$X12YL"
    rc=$?
    [[ "$rc" == "0" ]] || exit "$rc"
    printf "%s\tpreflight\tPASS\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
    continue
  fi

  if [[ "$MODE" == "analyze" ]]; then
    PROFILE=quick RADII="$RADII" REPLICATES=1 RUN_ROOT="$RUN_ROOT" \
    PREFLIGHT_ONLY=0 ANALYZE_ONLY=1 CLEAN_RUN_ROOT=0 \
    bash "$X12YL"
    rc=$?
    [[ "$rc" == "0" ]] || exit "$rc"
    printf "%s\tanalyze\tPASS\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
    continue
  fi

  PROFILE=quick RADII="$RADII" REPLICATES=1 RUN_ROOT="$RUN_ROOT" \
  PREFLIGHT_ONLY=1 ANALYZE_ONLY=0 CLEAN_RUN_ROOT=0 \
  bash "$X12YL"

  rc=$?
  if [[ "$rc" != "0" ]]; then
    printf "%s\tpreflight\tFAIL\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
    exit "$rc"
  fi

  # Reassert dedicated control after preflight.
  export LIVE_VIS_CONTROL_FILE="$LIVEVIS_CONTROL"
  export LIVE_VIS_CONTROL_FILE_EFFECTIVE="$LIVEVIS_CONTROL"
  export SRC_LIVE_VIS_CONTROL_FILE="$LIVEVIS_CONTROL"
  export MPCD_LIVE_VIS_CONTROL_FILE="$LIVEVIS_CONTROL"
  export OVERWRITE_LIVEVIS_CONTROL=0

  PROFILE=quick RADII="$RADII" REPLICATES=1 RUN_ROOT="$RUN_ROOT" \
  PREFLIGHT_ONLY=0 ANALYZE_ONLY=0 CLEAN_RUN_ROOT=1 \
  bash "$X12YL"

  rc=$?
  if [[ "$rc" != "0" ]]; then
    printf "%s\tproduction\tFAIL\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
    exit "$rc"
  fi

  printf "%s\tproduction\tPASS\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
done

if [[ "$MODE" != "preflight" ]]; then
  python3 - "$CAMPAIGN_ROOT" "$SUMMARY" <<'PY'
import csv, math, sys
from pathlib import Path
root=Path(sys.argv[1]); out=Path(sys.argv[2])
rows=[]

for tag,dt in (("dt4e4",4e-4),("dt2e4",2e-4)):
    p=root/tag/"analysis"/"young_laplace_pairs_0493x12yl.csv"
    if not p.is_file():
        print(f"[0493x24t] WARNING missing {p}")
        continue
    with p.open(newline="") as f:
        rr=list(csv.DictReader(f))
    if not rr:
        continue
    r=rr[0]

    def fval(*names):
        for n in names:
            if n in r and r[n] not in ("",None):
                try: return float(r[n])
                except Exception: pass
        return math.nan

    rows.append({
        "tag":tag,
        "dt":dt,
        "dpCap":fval("pressure_capillary_increment","deltaPressureCapillary","dpCap","deltaP"),
        "kappaActive":fval("kappa_active","activeMeanKappa","meanKappaActive","kappaActive"),
        "gain":fval("gain_vs_kappa","gainVsKappa","gain"),
        "sigmaEffPair":fval("sigma_effective_pair","sigmaEffectivePair","sigmaEffective"),
        "curvatureRelError":fval("curvature_rel_error","curvatureRelError"),
    })

if rows:
    with out.open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]),delimiter="\t")
        w.writeheader(); w.writerows(rows)

    print("\n===== 0493x24t SECOND-SEED RELATIVE DT CHECK =====")
    for r in rows:
        print(
            f"{r['tag']} dt={r['dt']:.1e} "
            f"dpCap={r['dpCap']:.9g} kappa={r['kappaActive']:.9g} "
            f"gain={r['gain']:.9g} sigmaEffPair={r['sigmaEffPair']:.9g}"
        )
PY
fi

echo
echo "================================================================"
echo "[0493x24t] COMPLETE mode=$MODE"
echo "[0493x24t] root=$CAMPAIGN_ROOT"
echo "[0493x24t] livevis control=$LIVEVIS_CONTROL"
if [[ "$MODE" != "preflight" ]]; then
  echo "[0493x24t] summary=$SUMMARY"
fi
echo "================================================================"
