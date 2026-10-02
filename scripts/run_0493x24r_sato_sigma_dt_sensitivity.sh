#!/usr/bin/env bash
# =============================================================================
# 0493x24r — dt sensitivity of effective mechanical surface tension
#
# Scientific question
#   Does the exact liquid/free-surface model used by the Sato benchmark retain
#   the same mechanical/static sigma_eff when dt is changed by a factor four?
#
# Method
#   Reuse the RETAINED mechanical/static surface-tension calibrator:
#
#       0493x12yl paired Young–Laplace
#
#   For each (R/h, seed), x12yl compares an otherwise identical sigma=0 case
#   with sigma=SIGMA_DECLARED and measures
#
#       dp_cap = p(sigma) - p(0)
#       dp_cap = sigma_eff * <kappa>_active
#
#   This is intentionally NOT the x12cal capillary-wave/dynamic calibrator.
#
# Exact Sato-liquid signature held fixed:
#   grid cell h       = 1/256
#   gamma             = 20
#   liquid mass       = 1
#   liquid kBT        = 0.02
#   SRC rotation      = pi/2 (90 deg)
#   random sign       = true
#   grid shift        = true
#   sigma declared    = 294.461365748622
#   min radius        = 4 cells
#   current production free-surface chain inherited from x12yl
#
# Only dt changes:
#   dt = 4e-4, 2e-4, 1e-4
#
# Default campaign:
#   radii       = 32 40 48
#   replicates  = 3
#   physical horizon per solver run = 1.0
#   paired sigma=0 / sigma>0 cases
#
# This is a runner-only qualification.  No C++/CUDA source is modified.
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

X12YL="scripts/run_0493x12yl_young_laplace_calibrator.sh"
ANALYZER="scripts/analyze_0493x12yl_young_laplace_calibrator.py"
PARENT="scripts/run_0493x10o_q6_thermal_interface_static_drop.sh"

for f in "$X12YL" "$ANALYZER" "$PARENT"; do
  if [[ ! -f "$f" ]]; then
    echo "[0493x24r] ERROR missing required existing file: $f" >&2
    exit 2
  fi
done

MODE="${MODE:-production}"       # preflight | production | analyze
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x24r_sato_sigma_dt_sensitivity}"

# -----------------------------------------------------------------------------
# Exact liquid signature of the Sato campaign
# -----------------------------------------------------------------------------
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

# Mechanical surface-tension law used by the Sato benchmark.
export SIGMA_DECLARED="${SIGMA_DECLARED:-294.461365748622}"
export SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"

# Keep the selected production x12a chain identical to x12yl/Sato.
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
export ALLOW_LOCAL_COOLING="${ALLOW_LOCAL_COOLING:-0}"

# Qualification matrix.
RADII="${RADII:-32 40 48}"
REPLICATES="${REPLICATES:-3}"
BASE_SEED="${BASE_SEED:-4932401}"
SEED_STRIDE="${SEED_STRIDE:-1009}"
TAIL_START="${TAIL_START:-0.50}"

# Keep the same PHYSICAL settling horizon for every dt.
PHYSICAL_TIME="${PHYSICAL_TIME:-1.0}"
PHYSICAL_SAMPLE_DT="${PHYSICAL_SAMPLE_DT:-0.02}"

# No heavy visualization/recording: x12yl's pressure/curvature audits are the data.
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-0}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
export THREADS="${THREADS:-8}"

mkdir -p "$CAMPAIGN_ROOT" || exit 2

PLAN="$CAMPAIGN_ROOT/campaign_plan.tsv"
STATUS="$CAMPAIGN_ROOT/campaign_status.tsv"
SUMMARY="$CAMPAIGN_ROOT/sigma_dt_summary.tsv"

printf "tag\tdt\tsteps\tphysical_time\tsummary_every\tradii\treplicates\tsigma_declared\tgamma\tkBT\tmass\trotation\n" > "$PLAN"
printf "tag\tstage\tstatus\troot\n" > "$STATUS"

# dt values corresponding to the Mach campaign.
CASES=(
  "dt4e4 0.0004"
  "dt2e4 0.0002"
  "dt1e4 0.0001"
)

calc_case_numbers() {
  python3 - "$1" "$PHYSICAL_TIME" "$PHYSICAL_SAMPLE_DT" <<'PY'
import sys
dt=float(sys.argv[1])
T=float(sys.argv[2])
sample=float(sys.argv[3])
steps=round(T/dt)
summary=max(1,round(sample/dt))
if abs(steps*dt-T) > 1e-12:
    raise SystemExit("PHYSICAL_TIME is not an integer number of dt")
print(int(steps), int(summary))
PY
}

run_one() {
  TAG="$1"
  DT_LOCAL="$2"

  read -r STEPS_LOCAL SUMMARY_LOCAL <<<"$(calc_case_numbers "$DT_LOCAL")" || exit 2

  RUN_ROOT="$CAMPAIGN_ROOT/$TAG"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$TAG" "$DT_LOCAL" "$STEPS_LOCAL" "$PHYSICAL_TIME" "$SUMMARY_LOCAL" \
    "$RADII" "$REPLICATES" "$SIGMA_DECLARED" "$GAMMA" "$KBT" \
    "$LIQUID_MASS" "$ROTATION_ANGLE" >> "$PLAN"

  echo
  echo "================================================================"
  echo "[0493x24r] CASE=$TAG"
  echo "[0493x24r] dt=$DT_LOCAL steps=$STEPS_LOCAL T=$PHYSICAL_TIME"
  echo "[0493x24r] liquid gamma=$GAMMA kBT=$KBT mass=$LIQUID_MASS alpha=$ROTATION_ANGLE"
  echo "[0493x24r] sigmaDeclared=$SIGMA_DECLARED radii=[$RADII] replicates=$REPLICATES"
  echo "================================================================"

  export DT="$DT_LOCAL"
  export STEPS="$STEPS_LOCAL"
  export SUMMARY_EVERY="$SUMMARY_LOCAL"
  export BASE_SEED
  export SEED_STRIDE
  export TAIL_START

  if [[ "$MODE" == "preflight" ]]; then
    PROFILE=production \
    RADII="$RADII" \
    REPLICATES="$REPLICATES" \
    RUN_ROOT="$RUN_ROOT" \
    PREFLIGHT_ONLY=1 \
    ANALYZE_ONLY=0 \
    CLEAN_RUN_ROOT=0 \
    bash "$X12YL"
    rc=$?
    if [[ "$rc" == "0" ]]; then
      printf "%s\tpreflight\tPASS\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
    else
      printf "%s\tpreflight\tFAIL\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
      exit "$rc"
    fi
    return 0
  fi

  if [[ "$MODE" == "analyze" ]]; then
    PROFILE=production \
    RADII="$RADII" \
    REPLICATES="$REPLICATES" \
    RUN_ROOT="$RUN_ROOT" \
    PREFLIGHT_ONLY=0 \
    ANALYZE_ONLY=1 \
    CLEAN_RUN_ROOT=0 \
    bash "$X12YL"
    rc=$?
    if [[ "$rc" == "0" ]]; then
      printf "%s\tanalyze\tPASS\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
    else
      printf "%s\tanalyze\tFAIL\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
      exit "$rc"
    fi
    return 0
  fi

  # Preflight each case immediately before execution.
  PROFILE=production \
  RADII="$RADII" \
  REPLICATES="$REPLICATES" \
  RUN_ROOT="$RUN_ROOT" \
  PREFLIGHT_ONLY=1 \
  ANALYZE_ONLY=0 \
  CLEAN_RUN_ROOT=0 \
  bash "$X12YL"

  rc=$?
  if [[ "$rc" != "0" ]]; then
    printf "%s\tpreflight\tFAIL\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
    exit "$rc"
  fi

  PROFILE=production \
  RADII="$RADII" \
  REPLICATES="$REPLICATES" \
  RUN_ROOT="$RUN_ROOT" \
  PREFLIGHT_ONLY=0 \
  ANALYZE_ONLY=0 \
  CLEAN_RUN_ROOT=1 \
  bash "$X12YL"

  rc=$?
  if [[ "$rc" != "0" ]]; then
    printf "%s\tproduction\tFAIL\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
    exit "$rc"
  fi

  printf "%s\tproduction\tPASS\t%s\n" "$TAG" "$RUN_ROOT" >> "$STATUS"
}

case "$MODE" in
  preflight|production|analyze) ;;
  *)
    echo "[0493x24r] ERROR MODE must be preflight, production, or analyze" >&2
    exit 2
    ;;
esac

for spec in "${CASES[@]}"; do
  read -r TAG DT_LOCAL <<<"$spec"
  run_one "$TAG" "$DT_LOCAL"
done

# -----------------------------------------------------------------------------
# Cross-dt compact summary from the authoritative x12yl output.
# -----------------------------------------------------------------------------
if [[ "$MODE" != "preflight" ]]; then
  python3 - "$CAMPAIGN_ROOT" "$SUMMARY" <<'PY'
import csv, json, math, sys
from pathlib import Path

root=Path(sys.argv[1])
out=Path(sys.argv[2])

rows=[]
for tag,dt in (("dt4e4",4e-4),("dt2e4",2e-4),("dt1e4",1e-4)):
    ad=root/tag/"analysis"
    js=ad/"young_laplace_calibration_0493x12yl.json"
    csvp=ad/"young_laplace_calibration_0493x12yl.csv"

    d=None
    if js.is_file():
        d=json.loads(js.read_text())
    elif csvp.is_file():
        with csvp.open(newline="") as f:
            rr=list(csv.DictReader(f))
        d=rr[0] if rr else None

    if d is None:
        print(f"[0493x24r] WARNING no x12yl calibration summary for {tag}")
        continue

    def val(*names):
        for n in names:
            if n in d and d[n] not in ("",None):
                try: return float(d[n])
                except Exception: return d[n]
        return math.nan

    rows.append({
        "tag":tag,
        "dt":dt,
        "status":d.get("status",""),
        "sigmaDeclared":val("sigmaDeclared"),
        "sigmaEff":val("surfaceTensionEffective","surfaceTensionEffectiveRaw"),
        "gain":val("surfaceTensionGainRaw"),
        "slopeStd":val("surfaceTensionGainSlopeStd"),
        "radiusSpread":val("surfaceTensionRadiusSpread"),
        "originR2":val("originFitR2"),
        "pairedRuns":val("pairedRuns"),
        "maxTailClipFraction":val("maxTailClipFraction"),
    })

if rows:
    with out.open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0].keys()),delimiter="\t")
        w.writeheader()
        w.writerows(rows)

    print("\n===== 0493x24r SIGMA_EFF vs DT =====")
    for r in rows:
        print(
            f"{r['tag']} dt={r['dt']:.1e} status={r['status']} "
            f"sigmaEff={r['sigmaEff']:.9g} gain={r['gain']:.9g} "
            f"R2={r['originR2']:.6g}"
        )

    good=[r for r in rows if isinstance(r["sigmaEff"],float) and math.isfinite(r["sigmaEff"])]
    if len(good)>=2:
        vals=[r["sigmaEff"] for r in good]
        mean=sum(vals)/len(vals)
        spread=(max(vals)-min(vals))/mean if mean else math.nan
        print(f"crossDtRelativeRange=(max-min)/mean = {spread:.6%}")
        print("Interpretation: use the individual x12yl statuses first; cross-dt spread is descriptive.")
PY
fi

echo
echo "================================================================"
echo "[0493x24r] CAMPAIGN COMPLETE mode=$MODE"
echo "[0493x24r] root=$CAMPAIGN_ROOT"
echo "[0493x24r] plan=$PLAN"
echo "[0493x24r] status=$STATUS"
if [[ "$MODE" != "preflight" ]]; then
  echo "[0493x24r] cross-dt summary=$SUMMARY"
fi
echo "================================================================"
