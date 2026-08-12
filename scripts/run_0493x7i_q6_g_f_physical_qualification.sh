#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# 0493x7i is a dumps-only physical comparison layer on top of the 0493x7h
# run_ok routing.  It changes no C++/CUDA physics and does not post-process
# during the simulation.  MATLAB analysis is intentionally offline.
#
# 0493x7q qualification refresh:
#   - lock the production Q6-g-f signed1 parameter set used by the validated
#     Poiseuille/dam-break runs;
#   - use projection tolerance 1e-5 consistently for Q6 and Q6-g-f;
#   - force the x7j cooperative resident CG path;
#   - make Poiseuille the validated low-Mach zero-start case instead of the
#     historical high-force/initialized profile, so raw signed/ungated density
#     restoration cannot be selected accidentally by inherited defaults.
RUN_ROOT="${RUN_ROOT:-runs/0493x7q_q6_g_f_physical_qualification}"
CASES="${CASES:-tg poiseuille bend_pipe io_box}"
QUAL_MODES="${QUAL_MODES:-src src-q6 src-q6-g-f}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

# Qualification-wide production projection/Q6-g-f profile.  Use the X7I_*
# variables to make an intentional qualification override; generic inherited
# Q6_GF_* values are not allowed to silently change this campaign.
X7I_PROJECTION_TOLERANCE="${X7I_PROJECTION_TOLERANCE:-1.0e-5}"
X7I_PROJECTION_MAX_ITERATIONS="${X7I_PROJECTION_MAX_ITERATIONS:-800}"
X7I_Q6_GF_DENSITY_RELAXATION_TIME="${X7I_Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
X7I_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${X7I_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
X7I_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${X7I_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3}"
X7I_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${X7I_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6}"
X7I_Q6_GF_DENSITY_TRACTION_GAIN="${X7I_Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
X7I_Q6_GF_MIN_FILL_FRACTION="${X7I_Q6_GF_MIN_FILL_FRACTION:-0.10}"
X7I_Q6_STRICT="${X7I_Q6_STRICT:-1}"

# Resident CG production path.  x7q itself is selected inside CUDA only for
# B1 + full-domain + periodic direction(s); bend/IO and free-surface paths keep
# their historical non-periodic/partial-domain behavior.
X7I_Q6_G_F_RESIDENT_CG_0493X7J="${X7I_Q6_G_F_RESIDENT_CG_0493X7J:-1}"
# CG selection must be mode-specific.  Q6-g-f uses x7j cooperative multi-block
# (0407=0); historical src-q6 has no x7j equivalent, so keep its fastest
# validated 0407 path on the <=65536-cell cases.  The 300x300 IO case exceeds
# the 0407 heuristic threshold and keeps the historical multi-kernel resident
# Q6 step (with scalar host reductions inside CG).
X7I_Q6_GF_SINGLE_BLOCK_CG_0407="${X7I_Q6_GF_SINGLE_BLOCK_CG_0407:-0}"
X7I_Q6_LEGACY_SINGLE_BLOCK_CG_SMALL="${X7I_Q6_LEGACY_SINGLE_BLOCK_CG_SMALL:-1}"
X7I_Q6_LEGACY_SINGLE_BLOCK_CG_LARGE="${X7I_Q6_LEGACY_SINGLE_BLOCK_CG_LARGE:-0}"

# Full-set qualification is intended to run unattended.  Keep LIVE_PROGRESS,
# but do not block between modes on a LiveVis hold unless explicitly requested.
X7I_LIVE_VIS_ENABLE="${X7I_LIVE_VIS_ENABLE:-0}"
X7I_LIVE_VIS_HOLD_ON_EXIT="${X7I_LIVE_VIS_HOLD_ON_EXIT:-0}"

# Dump plans.  They are deliberately case-specific because particle-state
# dumps are much larger for the 300x300 same-face box than for TG/Poiseuille.
X7I_TG_STEPS="${X7I_TG_STEPS:-10000}"
X7I_TG_DUMP_EVERY="${X7I_TG_DUMP_EVERY:-500}"
X7I_TG_SUMMARY_EVERY="${X7I_TG_SUMMARY_EVERY:-100}"

# 0493x7q Poiseuille reference: low-Mach, zero-start, ax=4e-4.  30000 steps are
# required because the previous signed1 momentum-leak pathology was a long-run
# effect and the validated late profile uses the 25000..30000 window.
X7I_POISEUILLE_STEPS="${X7I_POISEUILLE_STEPS:-30000}"
X7I_POISEUILLE_DUMP_EVERY="${X7I_POISEUILLE_DUMP_EVERY:-500}"
X7I_POISEUILLE_SUMMARY_EVERY="${X7I_POISEUILLE_SUMMARY_EVERY:-100}"
X7I_POISEUILLE_BODY_AX="${X7I_POISEUILLE_BODY_AX:-0.0004}"
X7I_POISEUILLE_U0="${X7I_POISEUILLE_U0:-0.0}"
X7I_POISEUILLE_VELOCITY_MODE="${X7I_POISEUILLE_VELOCITY_MODE:-zero}"

# Bend-pipe and same-face IO are startup qualifications.  The bend defaults to
# rest so the pressure/projection-mediated response is measurable, while U0
# remains the inlet target.  All Darcy modes use the same filled fictitious
# domain so the comparison isolates the flow operator rather than initialization.
X7I_BEND_STEPS="${X7I_BEND_STEPS:-1000}"
X7I_BEND_DUMP_EVERY="${X7I_BEND_DUMP_EVERY:-25}"
X7I_BEND_SUMMARY_EVERY="${X7I_BEND_SUMMARY_EVERY:-25}"
X7I_BEND_START_FROM_REST="${X7I_BEND_START_FROM_REST:-1}"
X7I_BEND_COMMON_FILLED_STATE="${X7I_BEND_COMMON_FILLED_STATE:-1}"

X7I_IO_BOX_STEPS="${X7I_IO_BOX_STEPS:-500}"
X7I_IO_BOX_DUMP_EVERY="${X7I_IO_BOX_DUMP_EVERY:-50}"
X7I_IO_BOX_SUMMARY_EVERY="${X7I_IO_BOX_SUMMARY_EVERY:-25}"

truthy_0493x7i() {
  case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac
}

# Pass the qualification profile explicitly on every child run.  This is
# intentionally duplicated at the process boundary rather than relying on
# ambient exports: the generated params and CUDA path are reproducible for
# every case/mode in the campaign.
q6_single_block_for_mode_0493x7i() {
  local mode=$1 legacy_setting=$2
  case "$mode" in
    src-q6|q6) printf '%s\n' "$legacy_setting" ;;
    src-q6-g-f|q6-g-f|src+q6-g-f) printf '%s\n' "$X7I_Q6_GF_SINGLE_BLOCK_CG_0407" ;;
    *) printf '0\n' ;;
  esac
}

run_with_x7q_profile_0493x7i() {
  local mode=$1 legacy_single_block=$2
  shift 2
  local single_block
  single_block="$(q6_single_block_for_mode_0493x7i "$mode" "$legacy_single_block")"
  PROJECTION_TOLERANCE="$X7I_PROJECTION_TOLERANCE" \
  PROJECTION_MAX_ITERATIONS="$X7I_PROJECTION_MAX_ITERATIONS" \
  Q6_STRICT="$X7I_Q6_STRICT" \
  Q6_GF_DENSITY_RELAXATION_TIME="$X7I_Q6_GF_DENSITY_RELAXATION_TIME" \
  Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="$X7I_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE" \
  Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="$X7I_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES" \
  Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="$X7I_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES" \
  Q6_GF_DENSITY_TRACTION_GAIN="$X7I_Q6_GF_DENSITY_TRACTION_GAIN" \
  Q6_GF_MIN_FILL_FRACTION="$X7I_Q6_GF_MIN_FILL_FRACTION" \
  MPCD_Q6_G_F_RESIDENT_CG_0493X7J="$X7I_Q6_G_F_RESIDENT_CG_0493X7J" \
  MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407="$single_block" \
  "$@"
}

run_tg_0493x7i() {
  echo "[0493x7i] TG forced: vortex-core population qualification"
  local mode
  for mode in $QUAL_MODES; do
    echo "[0493x7i] TG mode=$mode legacy0407=$X7I_Q6_LEGACY_SINGLE_BLOCK_CG_SMALL q6gf0407=$X7I_Q6_GF_SINGLE_BLOCK_CG_0407"
    run_with_x7q_profile_0493x7i "$mode" "$X7I_Q6_LEGACY_SINGLE_BLOCK_CG_SMALL" env \
  RUN_MODES="$mode" \
  BASE_RUN_ROOT="$RUN_ROOT/tg" \
  STEPS="$X7I_TG_STEPS" \
  DUMP_STATE_EVERY="$X7I_TG_DUMP_EVERY" \
  SUMMARY_EVERY="$X7I_TG_SUMMARY_EVERY" \
  TG_HOLE_ENABLE=false \
  LIVE_VIS_ENABLE="$X7I_LIVE_VIS_ENABLE" LIVE_VIS_HOLD_ON_EXIT="$X7I_LIVE_VIS_HOLD_ON_EXIT" FILTERED_RECORDING_ENABLE=0 \
  DUMP_ROLE_FILTER=fluid LIVE_PROGRESS="$LIVE_PROGRESS" \
  CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
  bash scripts/run_ok_tg.sh
  done
}

run_poiseuille_0493x7i() {
  echo "[0493x7i] Poiseuille: low-Mach zero-start normalized-profile qualification"
  local mode
  for mode in $QUAL_MODES; do
    echo "[0493x7i] Poiseuille mode=$mode legacy0407=$X7I_Q6_LEGACY_SINGLE_BLOCK_CG_SMALL q6gf0407=$X7I_Q6_GF_SINGLE_BLOCK_CG_0407"
    run_with_x7q_profile_0493x7i "$mode" "$X7I_Q6_LEGACY_SINGLE_BLOCK_CG_SMALL" env \
  RUN_MODES="$mode" \
  BASE_RUN_ROOT="$RUN_ROOT/poiseuille" \
  STEPS="$X7I_POISEUILLE_STEPS" \
  DUMP_STATE_EVERY="$X7I_POISEUILLE_DUMP_EVERY" \
  SUMMARY_EVERY="$X7I_POISEUILLE_SUMMARY_EVERY" \
  BODY_AX="$X7I_POISEUILLE_BODY_AX" \
  U0="$X7I_POISEUILLE_U0" \
  VELOCITY_MODE="$X7I_POISEUILLE_VELOCITY_MODE" \
  LIVE_VIS_ENABLE="$X7I_LIVE_VIS_ENABLE" LIVE_VIS_HOLD_ON_EXIT="$X7I_LIVE_VIS_HOLD_ON_EXIT" FILTERED_RECORDING_ENABLE=0 \
  DUMP_ROLE_FILTER=fluid LIVE_PROGRESS="$LIVE_PROGRESS" \
  CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
  bash scripts/run_ok_poiseuille.sh
  done
}

run_bend_pipe_0493x7i() {
  local velocity_mode="uniform_x"
  if truthy_0493x7i "$X7I_BEND_START_FROM_REST"; then velocity_mode="zero"; fi
  echo "[0493x7i] bend pipe: startup qualification velocityMode=$velocity_mode commonFilledDarcy=$X7I_BEND_COMMON_FILLED_STATE"
  local mode
  for mode in $QUAL_MODES; do
    echo "[0493x7i] bend pipe mode=$mode legacy0407=$X7I_Q6_LEGACY_SINGLE_BLOCK_CG_SMALL q6gf0407=$X7I_Q6_GF_SINGLE_BLOCK_CG_0407"
    run_with_x7q_profile_0493x7i "$mode" "$X7I_Q6_LEGACY_SINGLE_BLOCK_CG_SMALL" env \
  RUN_MODES="$mode" \
  BASE_RUN_ROOT="$RUN_ROOT/bend_pipe" \
  STEPS="$X7I_BEND_STEPS" \
  DUMP_STATE_EVERY="$X7I_BEND_DUMP_EVERY" \
  SUMMARY_EVERY="$X7I_BEND_SUMMARY_EVERY" \
  VELOCITY_MODE="$velocity_mode" \
  RUN_OK_DARCY_COMMON_FILLED_STATE="$X7I_BEND_COMMON_FILLED_STATE" \
  LIVE_VIS_ENABLE="$X7I_LIVE_VIS_ENABLE" LIVE_VIS_HOLD_ON_EXIT="$X7I_LIVE_VIS_HOLD_ON_EXIT" FILTERED_RECORDING_ENABLE=0 \
  DUMP_ROLE_FILTER=fluid LIVE_PROGRESS="$LIVE_PROGRESS" \
  CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
  bash scripts/run_ok_bend_pipe.sh
  done
}

run_io_box_0493x7i() {
  echo "[0493x7i] same-face IO box: startup qualification"
  local mode
  for mode in $QUAL_MODES; do
    echo "[0493x7i] same-face IO mode=$mode legacy0407=$X7I_Q6_LEGACY_SINGLE_BLOCK_CG_LARGE q6gf0407=$X7I_Q6_GF_SINGLE_BLOCK_CG_0407"
    run_with_x7q_profile_0493x7i "$mode" "$X7I_Q6_LEGACY_SINGLE_BLOCK_CG_LARGE" env \
  RUN_MODES="$mode" \
  BASE_RUN_ROOT="$RUN_ROOT/io_box" \
  STEPS="$X7I_IO_BOX_STEPS" \
  DUMP_STATE_EVERY="$X7I_IO_BOX_DUMP_EVERY" \
  SUMMARY_EVERY="$X7I_IO_BOX_SUMMARY_EVERY" \
  LIVE_VIS_ENABLE="$X7I_LIVE_VIS_ENABLE" LIVE_VIS_HOLD_ON_EXIT="$X7I_LIVE_VIS_HOLD_ON_EXIT" FILTERED_RECORDING_ENABLE=0 \
  DUMP_ROLE_FILTER=fluid LIVE_PROGRESS="$LIVE_PROGRESS" \
  CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
  bash scripts/run_ok_io_box_same_face.sh
  done
}

echo "[0493x7i] Q6-g-f physical qualification -- x7q production profile"
echo "[0493x7i] root=$RUN_ROOT modes=$QUAL_MODES cases=$CASES preflight=$PREFLIGHT_ONLY"
echo "[0493x7i] projection: tol=$X7I_PROJECTION_TOLERANCE maxIt=$X7I_PROJECTION_MAX_ITERATIONS q6Strict=$X7I_Q6_STRICT"
echo "[0493x7i] Q6-g-f: tau=$X7I_Q6_GF_DENSITY_RELAXATION_TIME gate=$X7I_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE +thresholdParticles=$X7I_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES -thresholdParticles=$X7I_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES tractionGain=$X7I_Q6_GF_DENSITY_TRACTION_GAIN minFill=$X7I_Q6_GF_MIN_FILL_FRACTION"
echo "[0493x7i] resident CG: q6-g-f x7j=$X7I_Q6_G_F_RESIDENT_CG_0493X7J q6gf0407=$X7I_Q6_GF_SINGLE_BLOCK_CG_0407; legacyQ6 small0407=$X7I_Q6_LEGACY_SINGLE_BLOCK_CG_SMALL large0407=$X7I_Q6_LEGACY_SINGLE_BLOCK_CG_LARGE"
echo "[0493x7i] Poiseuille: steps=$X7I_POISEUILLE_STEPS ax=$X7I_POISEUILLE_BODY_AX velocityMode=$X7I_POISEUILLE_VELOCITY_MODE U0=$X7I_POISEUILLE_U0"
echo "[0493x7i] LiveVis: enable=$X7I_LIVE_VIS_ENABLE holdOnExit=$X7I_LIVE_VIS_HOLD_ON_EXIT; LIVE_PROGRESS=$LIVE_PROGRESS"
echo "[0493x7i] post-processing=offline MATLAB; no analysis runs during simulation"

for case_name in $CASES; do
  echo
  echo "============================================================"
  echo "[0493x7i] case=$case_name"
  echo "============================================================"
  case "$case_name" in
    tg) run_tg_0493x7i ;;
    poiseuille) run_poiseuille_0493x7i ;;
    bend_pipe|bend) run_bend_pipe_0493x7i ;;
    io_box|io_box_same_face|sameface) run_io_box_0493x7i ;;
    *) echo "[0493x7i] ERROR unknown case=$case_name" >&2; exit 2 ;;
  esac
done

if ! truthy_0493x7i "$PREFLIGHT_ONLY"; then
  echo
  echo "[0493x7i] simulations complete"
  echo "[0493x7i] MATLAB post-process from repository root:"
  echo "  addpath('matlab'); out = analyze_0493x7i_q6_g_f_qualification('$RUN_ROOT');"
fi
