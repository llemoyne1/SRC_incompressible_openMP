#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
BASE="scripts/run_0493x12yl_young_laplace_calibrator.sh"
AN="scripts/analyze_0493x21b_capillary_static_weak.py"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x21b_capillary_static_weak_R64_s120}"
[[ -f "$BASE" ]] || { echo "[0493x21b] missing $BASE" >&2; exit 2; }
[[ -f "$AN" ]] || { echo "[0493x21b] missing $AN" >&2; exit 2; }
MODE="${1:---run}"
case "$MODE" in --preflight|--run|--analyze) ;; *) echo "usage: $0 [--preflight|--run|--analyze]" >&2; exit 2;; esac

export NX=256 NY=256 Lx=1.0 Ly=1.0
export GAMMA=8 KBT=0.125 LIQUID_MASS=1.0
export DT=0.0063471328149122585
export ROTATION_ANGLE=2.0943951023931953
export RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true
export THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT="$KBT"
export THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
export PROFILE=quick RADII="64" REPLICATES=1 BASE_SEED=4932101 SEED_STRIDE=1009
export SIGMA_DECLARED=120
export SURFACE_TENSION_MIN_RADIUS_CELLS=4
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS=25.298221281347036
export ALLOW_LOCAL_COOLING=0
# Historical x13j physical horizon/cadence for the x13h Young-Laplace smoke.
export STEPS="${STEPS:-316}" SUMMARY_EVERY="${SUMMARY_EVERY:-3}" DUMP_STATE_EVERY=0 TAIL_START=0.5
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}" LIVE_VIS_ENABLE=1 LIVE_VIS_RECORD_ENABLE=0 FILTERED_RECORDING_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0
export SPECIES_RESAMPLING_ENABLE=false LIQUID_RESAMPLING_ENABLE=false GAS_RESAMPLING_ENABLE=false
export WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false VIRIAL_DENSITY_KICK_ENABLE=false

preflight(){
python3 - <<'PY2'
import math
h=1/256; R=64*h; sig=120.; gamma=8.; kbt=.125; m=1.; rho=gamma*m/h**2; pth=gamma*kbt/h**2
print('===== 0493x21b WEAK STATIC CAPILLARY PILOT =====')
print(f'grid=256x256 h={h:.12g} R/h=64 R={R:.12g} wallClearance/h=64')
print(f'fluid gamma=8 alphaSRC=120deg dt=0.0063471328149122585 kBT=.125 mass=1')
print(f'x12a Rc/h=25.2982212813 R/Rc={64/25.298221281347036:.6g}')
print(f'curvature cutoff Rmin/h=4 R/Rmin=16')
print(f'sigma={sig:g} kappaTh={1/R:.9g} dpTh={sig/R:.9g} pThermal={pth:.9g} dp/pThermal={sig/R/pth:.6%}')
print(f'rho={rho:.9g} U_sigma={math.sqrt(sig/(rho*R)):.9g}')
print('purpose=weak Young-Laplace mechanism test; not strong-sigma dynamic benchmark')
PY2
PREFLIGHT_ONLY=1 RUN_ROOT="$CAMPAIGN_ROOT" bash "$BASE"
python3 "$AN" --self-test
}
trace(){ mkdir -p "$CAMPAIGN_ROOT/audit"; {
 echo campaign=0493x21b_capillary_static_weak_R64_s120; date=$(date -Iseconds 2>/dev/null || true); echo gitHead=$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)
 echo gamma=$GAMMA; echo dt=$DT; echo kBT=$KBT; echo rotationAngleRad=$ROTATION_ANGLE; echo radiusCells=64; echo sigmaTarget=$SIGMA_DECLARED; echo seed=$BASE_SEED
 for f in "$BASE" "$AN" scripts/run_0493x10o_q6_thermal_interface_static_drop.sh scripts/src_mpcd_run_common_0434.sh build/src_mpcd_base_cuda_q6_resident_livevis_0486; do [[ -f "$f" ]] && sha256sum "$f"; done
 } > "$CAMPAIGN_ROOT/audit/traceability_0493x21b.txt"; }
analyze(){ python3 "$AN" --campaign-root "$CAMPAIGN_ROOT"; trace; }
case "$MODE" in
 --preflight) preflight;;
 --analyze) analyze;;
 --run) preflight; RUN_ROOT="$CAMPAIGN_ROOT" CLEAN_RUN_ROOT=1 PREFLIGHT_ONLY=0 ANALYZE_ONLY=0 bash "$BASE"; analyze;;
esac
