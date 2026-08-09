#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

DENSITY_RELAXATION_TIME="${DENSITY_RELAXATION_TIME:-0.25}"
SEED="${SEED:-493953}"
GAMMA="${GAMMA:-10}"
COARSE_STEPS="${COARSE_STEPS:-100}"
COARSE_NX="${COARSE_NX:-300}"; COARSE_NY="${COARSE_NY:-150}"; COARSE_DT="${COARSE_DT:-0.005}"
FINE_NX="${FINE_NX:-600}"; FINE_NY="${FINE_NY:-300}"; FINE_DT="${FINE_DT:-0.0025}"
RUN_COARSE="${RUN_COARSE:-1}"; RUN_FINE="${RUN_FINE:-1}"
COARSE_ROOT="${COARSE_ROOT:-runs/0493x7d_density_rhs_coarse_${COARSE_NX}x${COARSE_NY}_s${COARSE_STEPS}}"

FINE_STEPS="$(python3 - "$COARSE_STEPS" "$COARSE_DT" "$FINE_DT" <<'PY'
import math, sys
steps, dt0, dt1 = int(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])
x = steps * dt0 / dt1
n = round(x)
if steps <= 0 or dt0 <= 0 or dt1 <= 0 or not math.isfinite(x) or abs(x-n) > 1e-12*max(1.0, abs(x)):
    raise SystemExit("[0493x7d] coarse physical time is not an integer number of fine steps")
print(n)
PY
)"
FINE_ROOT="${FINE_ROOT:-runs/0493x7d_density_rhs_fine_${FINE_NX}x${FINE_NY}_s${FINE_STEPS}}"

COARSE_SUMMARY="${COARSE_SUMMARY:-25}"
FINE_SUMMARY="$(python3 - "$COARSE_SUMMARY" "$COARSE_DT" "$FINE_DT" <<'PY'
import sys
n = round(int(sys.argv[1]) * float(sys.argv[2]) / float(sys.argv[3]))
print(max(1, n))
PY
)"

run_case() {
  local label="$1" nx="$2" ny="$3" dt="$4" steps="$5" summary="$6" root="$7"
  echo
  echo "============================================================"
  echo "[0493x7d] ${label}: grid=${nx}x${ny} dt=${dt} steps=${steps} tau=${DENSITY_RELAXATION_TIME}"
  echo "============================================================"

  env \
    RUN_MODE=src-q6 \
    WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false \
    SPECIES_RESAMPLING_ENABLE=false \
    LIQUID_RESAMPLING_ENABLE=false \
    GAS_RESAMPLING_ENABLE=false \
    CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false \
    MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0 \
    MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1 \
    VIRIAL_DENSITY_KICK_ENABLE=false \
    Q6_DENSITY_RELAXATION_BETA=0.0 \
    Q6_DENSITY_RELAXATION_TIME="$DENSITY_RELAXATION_TIME" \
    LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
    LIVE_VIS_ENABLE=0 \
    LIVE_VIS_HOLD_ON_EXIT=0 \
    SEED="$SEED" \
    NX="$nx" NY="$ny" \
    GAMMA="$GAMMA" \
    Lx=2 Ly=1 \
    KBT=0.05 \
    DT="$dt" \
    GRAVITY_Y=-0.5 \
    STEPS="$steps" \
    SUMMARY_EVERY="$summary" \
    DUMP_STATE_EVERY="$steps" \
    PROJECTION_MAX_ITERATIONS=1600 \
    PROJECTION_TOLERANCE=1e-5 \
    SPECIES_Q6_MIN_FILL_FRACTION=0.10 \
    CLEAN_RUN_ROOT=1 \
    BASE_RUN_ROOT="$root" \
    bash scripts/run_0493x6f_phase_interface_stencil.sh
}

if [[ "$RUN_COARSE" == "1" ]]; then
  run_case coarse "$COARSE_NX" "$COARSE_NY" "$COARSE_DT" "$COARSE_STEPS" "$COARSE_SUMMARY" "$COARSE_ROOT"
fi
if [[ "$RUN_FINE" == "1" ]]; then
  run_case fine "$FINE_NX" "$FINE_NY" "$FINE_DT" "$FINE_STEPS" "$FINE_SUMMARY" "$FINE_ROOT"
fi

if [[ -f "$COARSE_ROOT/output/cuda_species_q6_independent_masked_0493w5.csv" && \
      -f "$FINE_ROOT/output/cuda_species_q6_independent_masked_0493w5.csv" ]]; then
  echo
  python3 scripts/analyze_0493x7d_density_rhs_grid_refinement.py \
    --coarse-root "$COARSE_ROOT" \
    --fine-root "$FINE_ROOT"
else
  echo "[0493x7d] one side was not run/found; comparison deferred"
fi
