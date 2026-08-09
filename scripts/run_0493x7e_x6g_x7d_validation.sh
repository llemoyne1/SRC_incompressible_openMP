#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

DENSITY_RELAXATION_TIME="${DENSITY_RELAXATION_TIME:-0.25}"
SEED="${SEED:-493953}"
GAMMA="${GAMMA:-10}"
RUN_X6G_INVARIANTS="${RUN_X6G_INVARIANTS:-1}"
RUN_COMBINED_REFINEMENT="${RUN_COMBINED_REFINEMENT:-1}"
X6G_VALIDATION_STEPS="${X6G_VALIDATION_STEPS:-5}"
X6G_NULL_POSITION_TOL="${X6G_NULL_POSITION_TOL:-1e-10}"
X6G_NULL_VELOCITY_TOL="${X6G_NULL_VELOCITY_TOL:-3e-8}"
COARSE_STEPS="${COARSE_STEPS:-100}"
COARSE_NX="${COARSE_NX:-300}"; COARSE_NY="${COARSE_NY:-150}"; COARSE_DT="${COARSE_DT:-0.005}"
FINE_NX="${FINE_NX:-600}"; FINE_NY="${FINE_NY:-300}"; FINE_DT="${FINE_DT:-0.0025}"
ROOT_RUN="${ROOT_RUN:-runs/0493x7e_x6g_x7d_validation_c${COARSE_STEPS}}"

for required in \
  scripts/run_0493x6g_validation.sh \
  scripts/run_0493x6g_phase_gas_pressure.sh \
  scripts/analyze_0493x7d_density_rhs_grid_refinement.py \
  scripts/analyze_0493x7e_x6g_x7d_combination.py; do
  if [[ ! -f "$required" ]]; then
    echo "[0493x7e] ERROR: required file missing: $required" >&2
    exit 2
  fi
done

if ! awk -v t="$DENSITY_RELAXATION_TIME" 'BEGIN{exit !(t>0)}'; then
  echo "[0493x7e] ERROR: DENSITY_RELAXATION_TIME must be positive" >&2
  exit 2
fi

FINE_STEPS="$(python3 - "$COARSE_STEPS" "$COARSE_DT" "$FINE_DT" <<'PY'
import math, sys
steps, dt0, dt1 = int(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])
x = steps * dt0 / dt1
n = round(x)
if steps <= 0 or dt0 <= 0 or dt1 <= 0 or not math.isfinite(x) or abs(x-n) > 1e-12*max(1.0, abs(x)):
    raise SystemExit("[0493x7e] coarse physical time is not an integer number of fine steps")
print(n)
PY
)"
COARSE_SUMMARY="${COARSE_SUMMARY:-25}"
FINE_SUMMARY="$(python3 - "$COARSE_SUMMARY" "$COARSE_DT" "$FINE_DT" <<'PY'
import sys
n = round(int(sys.argv[1]) * float(sys.argv[2]) / float(sys.argv[3]))
print(max(1, n))
PY
)"

mkdir -p "$ROOT_RUN"

common_density_env=(
  RUN_MODE=src-q6
  WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
  SPECIES_RESAMPLING_ENABLE=false
  LIQUID_RESAMPLING_ENABLE=false
  GAS_RESAMPLING_ENABLE=false
  CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
  MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0
  MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1
  VIRIAL_DENSITY_KICK_ENABLE=false
  Q6_DENSITY_RELAXATION_BETA=0.0
  Q6_DENSITY_RELAXATION_TIME="$DENSITY_RELAXATION_TIME"
  LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
  LIVE_VIS_ENABLE=0
  LIVE_VIS_HOLD_ON_EXIT=0
  SEED="$SEED"
  PROJECTION_MAX_ITERATIONS=1600
  PROJECTION_TOLERANCE=1e-5
  SPECIES_Q6_MIN_FILL_FRACTION=0.10
)

if [[ "$RUN_X6G_INVARIANTS" == "1" ]]; then
  echo
  echo "============================================================"
  echo "[0493x7e] phase 1: x6g invariant suite with x7d active"
  echo "[0493x7e] tau=${DENSITY_RELAXATION_TIME} B1=on virial=off steps=${X6G_VALIDATION_STEPS}"
  echo "[0493x7e] x6g null-path tolerances: position=${X6G_NULL_POSITION_TOL} velocity=${X6G_NULL_VELOCITY_TOL}"
  echo "============================================================"
  env "${common_density_env[@]}" \
    NX=120 NY=60 GAMMA="$GAMMA" DT=0.005 Lx=2 Ly=1 KBT=0.05 \
    VALIDATION_STEPS="$X6G_VALIDATION_STEPS" \
    ZERO_POSITION_TOL="$X6G_NULL_POSITION_TOL" \
    ZERO_VELOCITY_TOL="$X6G_NULL_VELOCITY_TOL" \
    ROOT_RUN="$ROOT_RUN/x6g_invariants" \
    bash scripts/run_0493x6g_validation.sh
fi

run_combined_eos() {
  local label="$1" nx="$2" ny="$3" dt="$4" steps="$5" summary="$6" root="$7"
  local cell_area p0
  cell_area="$(awk -v nx="$nx" -v ny="$ny" 'BEGIN{printf "%.17g",(2.0/nx)*(1.0/ny)}')"
  p0="$(awk -v g="$GAMMA" -v a="$cell_area" 'BEGIN{printf "%.17g",g*0.05/a}')"

  echo
  echo "============================================================"
  echo "[0493x7e] ${label}: x6g EOS + x7d, grid=${nx}x${ny} dt=${dt} steps=${steps}"
  echo "[0493x7e] tau=${DENSITY_RELAXATION_TIME} pRef=${p0}"
  echo "============================================================"

  env "${common_density_env[@]}" \
    NX="$nx" NY="$ny" GAMMA="$GAMMA" Lx=2 Ly=1 KBT=0.05 DT="$dt" \
    GRAVITY_Y=-0.5 STEPS="$steps" SUMMARY_EVERY="$summary" DUMP_STATE_EVERY="$steps" \
    GAS_PRESSURE_MODE=eos GAS_PRESSURE_SCALE=1 GAS_PRESSURE_REFERENCE="$p0" \
    CLEAN_RUN_ROOT=1 BASE_RUN_ROOT="$root" \
    bash scripts/run_0493x6g_phase_gas_pressure.sh
}

COARSE_ROOT="$ROOT_RUN/combined_coarse_${COARSE_NX}x${COARSE_NY}_s${COARSE_STEPS}"
FINE_ROOT="$ROOT_RUN/combined_fine_${FINE_NX}x${FINE_NY}_s${FINE_STEPS}"

if [[ "$RUN_COMBINED_REFINEMENT" == "1" ]]; then
  run_combined_eos coarse "$COARSE_NX" "$COARSE_NY" "$COARSE_DT" "$COARSE_STEPS" "$COARSE_SUMMARY" "$COARSE_ROOT"
  run_combined_eos fine "$FINE_NX" "$FINE_NY" "$FINE_DT" "$FINE_STEPS" "$FINE_SUMMARY" "$FINE_ROOT"
fi

if [[ -f "$COARSE_ROOT/output/cuda_species_q6_independent_masked_0493w5.csv" && \
      -f "$FINE_ROOT/output/cuda_species_q6_independent_masked_0493w5.csv" ]]; then
  echo
  echo "============================================================"
  echo "[0493x7e] combined coarse/fine analysis"
  echo "============================================================"
  python3 scripts/analyze_0493x7d_density_rhs_grid_refinement.py \
    --coarse-root "$COARSE_ROOT" --fine-root "$FINE_ROOT"
  python3 scripts/analyze_0493x7e_x6g_x7d_combination.py \
    --coarse-root "$COARSE_ROOT" --fine-root "$FINE_ROOT"
else
  echo "[0493x7e] combined coarse/fine outputs not both present; analysis deferred"
fi

echo "[0493x7e] qualification sequence completed root=$ROOT_RUN"
