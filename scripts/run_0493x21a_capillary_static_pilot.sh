#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BASE="scripts/run_0493x12yl_young_laplace_calibrator.sh"
PILOT_ANALYZER="scripts/analyze_0493x21a_capillary_static_pilot.py"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x21a_capillary_static_pilot_R64_vLV}"

[[ -f "$BASE" ]] || { echo "[0493x21a] ERROR missing $BASE" >&2; exit 2; }
[[ -f "$PILOT_ANALYZER" ]] || { echo "[0493x21a] ERROR missing $PILOT_ANALYZER" >&2; exit 2; }

MODE="${1:---run}"
case "$MODE" in
  --preflight|--run|--analyze) ;;
  *) echo "usage: $0 [--preflight|--run|--analyze]" >&2; exit 2 ;;
esac

# -----------------------------------------------------------------------------
# Article nominal liquid point + deliberately well-resolved static drop.
# No C++/CUDA physics is changed by this wrapper.
# -----------------------------------------------------------------------------
export NX=256 NY=256 Lx=1.0 Ly=1.0
export GAMMA=8
export DT=0.0063471328149122585
export KBT=0.125
export LIQUID_MASS=1.0
export ROTATION_ANGLE=2.0943951023931953       # 120 deg
export RANDOM_ROTATION_SIGN=true
export GRID_SHIFT_ENABLE=true
export THERMOSTAT_ENABLE=true
export THERMOSTAT_MODE=cell_relative_rescale
export THERMOSTAT_EVERY=1
export THERMOSTAT_TARGET_KBT="$KBT"
export THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

# Capillary pilot: far from x12a small-structure law and x9r curvature cutoff.
export PROFILE=quick
export RADII="64"
export REPLICATES=1
export BASE_SEED=4932101
export SEED_STRIDE=1009
export SIGMA_DECLARED=10000
export SURFACE_TENSION_MIN_RADIUS_CELLS=4
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS=25.298221281347036
export ALLOW_LOCAL_COOLING=0

export STEPS="${STEPS:-1000}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
export TAIL_START=0.5   # historical x12yl output only; x21a detects its own plateau.

# Keep the pilot headless/minimal. x9e/x9r diagnostics are independent of LiveVis.
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE=1
export LIVE_VIS_RECORD_ENABLE=0
export FILTERED_RECORDING_ENABLE=0
export LIVE_VIS_HOLD_ON_EXIT=0

# Explicitly keep non-production closures out.
export SPECIES_RESAMPLING_ENABLE=false
export LIQUID_RESAMPLING_ENABLE=false
export GAS_RESAMPLING_ENABLE=false
export WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
export CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
export VIRIAL_DENSITY_KICK_ENABLE=false

preflight() {
  echo "===== 0493x21a STATIC CAPILLARY PILOT PREFLIGHT ====="
  python3 - <<'PY_PREF'
import math
h=1.0/256.0
Rcells=64.0
R=Rcells*h
rcool=25.298221281347036
rmin=4.0
sigma=10000.0
gamma=8.0
kbt=0.125
mass=1.0
dt=0.0063471328149122585
ell=dt*math.sqrt(kbt/mass)/h
rho=gamma*mass/h**2
ptherm=gamma*kbt/h**2
dp=sigma/R
usigma=math.sqrt(sigma/(rho*R))
print(f"grid=256x256 h={h:.17g}")
print(f"fluid gamma={gamma:g} alphaSRC=120deg dt={dt:.17g} kBT={kbt:g} mass={mass:g} ell={ell:.12g}")
print(f"drop R/h={Rcells:g} R={R:.9g} wallClearance/h={128-Rcells:g}")
print(f"x12a Rc/h={rcool:.12g} R/Rc={Rcells/rcool:.6g}")
print(f"curvature cutoff Rmin/h={rmin:g} R/Rmin={Rcells/rmin:.6g}")
print(f"sigmaTarget={sigma:.9g} kappaTh={1/R:.9g} deltaPTh={dp:.9g}")
print(f"rhoRef={rho:.9g} pThermal={ptherm:.9g} deltaP/pThermal={dp/ptherm:.6g} U_sigma={usigma:.9g}")
print("pair=one sigma0 baseline + one sigma10000 active run; identical seed=4932101")
print("physics=x13h qualified chain through existing x12yl/x10o; no solver patch")
PY_PREF
  PREFLIGHT_ONLY=1 RUN_ROOT="$CAMPAIGN_ROOT" bash "$BASE"
  python3 "$PILOT_ANALYZER" --self-test
}

write_traceability() {
  local audit="$CAMPAIGN_ROOT/audit"
  mkdir -p "$audit"
  {
    echo "campaign=0493x21a_capillary_static_pilot_R64"
    echo "date=$(date -Iseconds 2>/dev/null || true)"
    echo "pwd=$PWD"
    echo "gitHead=$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
    echo "gitBranch=$(git branch --show-current 2>/dev/null || echo UNKNOWN)"
    echo "baseRunner=$BASE"
    echo "pilotAnalyzer=$PILOT_ANALYZER"
    echo "parentRunner=scripts/run_0493x10o_q6_thermal_interface_static_drop.sh"
    echo "rotationAngleRad=$ROTATION_ANGLE"
    echo "gamma=$GAMMA"
    echo "dt=$DT"
    echo "kBT=$KBT"
    echo "liquidMass=$LIQUID_MASS"
    echo "radiusCells=64"
    echo "sigmaTarget=$SIGMA_DECLARED"
    echo "seed=$BASE_SEED"
    echo "surfaceTensionMinRadiusCells=$SURFACE_TENSION_MIN_RADIUS_CELLS"
    echo "x12aRadiusCells=$MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS"
    for f in "$BASE" "$PILOT_ANALYZER" scripts/run_0493x10o_q6_thermal_interface_static_drop.sh scripts/src_mpcd_run_common_0434.sh build/src_mpcd_base_cuda_q6_resident_livevis_0486; do
      if [[ -f "$f" ]]; then sha256sum "$f"; fi
    done
  } > "$audit/traceability_0493x21a.txt"
}

analyze() {
  python3 "$PILOT_ANALYZER" --campaign-root "$CAMPAIGN_ROOT"
  write_traceability
}

case "$MODE" in
  --preflight)
    preflight
    ;;
  --analyze)
    analyze
    ;;
  --run)
    preflight
    RUN_ROOT="$CAMPAIGN_ROOT" CLEAN_RUN_ROOT=1 PREFLIGHT_ONLY=0 ANALYZE_ONLY=0 bash "$BASE"
    analyze
    ;;
esac
