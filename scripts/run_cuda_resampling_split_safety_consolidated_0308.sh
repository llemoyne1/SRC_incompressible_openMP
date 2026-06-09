#!/usr/bin/env bash
set -euo pipefail

# 0308 — consolidation validation for nominal CUDA resampling split safety.
#
# This runner reuses the 0306 velocity-outlier diagnostics, but enforces the
# 0307 safe-floor mode that is now the nominal resampling configuration:
#   - prefer the most massive local donor;
#   - do not split donors below a mass floor;
#   - do not create particles below a mass floor;
#   - keep solid-adjacent splitting enabled but protected by the same floor.
#
# The goal is to confirm that the large-|U| / tiny-mass outliers are removed on
# backward-step and Von Karman stress cases while preserving classic comparison
# runs.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0308}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_split_safety_consolidated_0308}
FORCE_REBUILD=${FORCE_REBUILD:-1}
CLEAN_ART_DIR=${CLEAN_ART_DIR:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}

# Nominal split-safety values selected from 0307 diagnostics.
SPLIT_SAFETY_ENABLE=${SPLIT_SAFETY_ENABLE:-1}
SPLIT_PREFER_MAX_MASS_DONOR=${SPLIT_PREFER_MAX_MASS_DONOR:-1}
SPLIT_DONOR_MIN_MASS=${SPLIT_DONOR_MIN_MASS:-0.5}
SPLIT_NEW_PARTICLE_MIN_MASS=${SPLIT_NEW_PARTICLE_MIN_MASS:-0.25}
SOLID_ADJACENT_SPLIT_MODE=${SOLID_ADJACENT_SPLIT_MODE:-0}
SOLID_ADJACENT_DONOR_MIN_MASS=${SOLID_ADJACENT_DONOR_MIN_MASS:-1.0}
SOLID_ADJACENT_HALO_CELLS_0307=${SOLID_ADJACENT_HALO_CELLS_0307:-1}
TINY_MASS_THRESHOLD_0307=${TINY_MASS_THRESHOLD_0307:-0.25}

# Keep the stress-test defaults aligned with 0306/0307.
RUN_STEP=${RUN_STEP:-1}
RUN_VK=${RUN_VK:-1}
RUN_TG_HOLE=${RUN_TG_HOLE:-0}
RUN_POISEUILLE=${RUN_POISEUILLE:-0}
RUN_CLASSIC=${RUN_CLASSIC:-1}
RUN_RESAMPLING=${RUN_RESAMPLING:-1}

STEP_NX=${STEP_NX:-128}; STEP_NY=${STEP_NY:-48}; STEP_STEPS=${STEP_STEPS:-6000}; STEP_UIN=${STEP_UIN:-0.60}
VK_NX=${VK_NX:-128}; VK_NY=${VK_NY:-48}; VK_STEPS=${VK_STEPS:-6000}; VK_UIN=${VK_UIN:-0.45}; VK_THERMOSTAT_ENABLE=${VK_THERMOSTAT_ENABLE:-1}
GUARD_EVERY=${GUARD_EVERY:-1}
FLAG_EVERY=${FLAG_EVERY:-10}
HIGH_U=${HIGH_U:-1.0}
OUTLIER_U=${OUTLIER_U:-$HIGH_U}

if [[ "$CLEAN_ART_DIR" != "0" ]]; then
  rm -rf "$ART_DIR"
fi
mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0308.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0308.sh
fi

if [[ ! -x scripts/run_cuda_resampling_outlier_diagnostics_0306.sh ]]; then
  echo "[0308-consolidated] ERROR: missing scripts/run_cuda_resampling_outlier_diagnostics_0306.sh" >&2
  echo "[0308-consolidated] Apply the 0306 diagnostic patch before 0308." >&2
  exit 2
fi

echo "[0308-consolidated] BIN=$BIN"
echo "[0308-consolidated] ART_DIR=$ART_DIR"
echo "[0308-consolidated] split safety: enable=$SPLIT_SAFETY_ENABLE preferMax=$SPLIT_PREFER_MAX_MASS_DONOR donorMin=$SPLIT_DONOR_MIN_MASS newMin=$SPLIT_NEW_PARTICLE_MIN_MASS solidMode=$SOLID_ADJACENT_SPLIT_MODE"

set +e
env \
  BIN="$BIN" \
  ART_DIR="$ART_DIR" \
  FORCE_REBUILD=0 \
  STOP_ON_FAIL="$STOP_ON_FAIL" \
  RUN_STEP="$RUN_STEP" RUN_VK="$RUN_VK" RUN_TG_HOLE="$RUN_TG_HOLE" RUN_POISEUILLE="$RUN_POISEUILLE" \
  RUN_CLASSIC="$RUN_CLASSIC" RUN_RESAMPLING="$RUN_RESAMPLING" \
  STEP_NX="$STEP_NX" STEP_NY="$STEP_NY" STEP_STEPS="$STEP_STEPS" STEP_UIN="$STEP_UIN" \
  VK_NX="$VK_NX" VK_NY="$VK_NY" VK_STEPS="$VK_STEPS" VK_UIN="$VK_UIN" VK_THERMOSTAT_ENABLE="$VK_THERMOSTAT_ENABLE" \
  GUARD_EVERY="$GUARD_EVERY" FLAG_EVERY="$FLAG_EVERY" HIGH_U="$HIGH_U" OUTLIER_U="$OUTLIER_U" \
  MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307="$SPLIT_SAFETY_ENABLE" \
  MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307="$SPLIT_PREFER_MAX_MASS_DONOR" \
  MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307="$SPLIT_DONOR_MIN_MASS" \
  MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307="$SPLIT_NEW_PARTICLE_MIN_MASS" \
  MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307="$SOLID_ADJACENT_SPLIT_MODE" \
  MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_DONOR_MIN_MASS_0307="$SOLID_ADJACENT_DONOR_MIN_MASS" \
  MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_HALO_CELLS_0307="$SOLID_ADJACENT_HALO_CELLS_0307" \
  MPCD_CUDA_RESAMPLING_TINY_MASS_THRESHOLD_0307="$TINY_MASS_THRESHOLD_0307" \
  bash scripts/run_cuda_resampling_outlier_diagnostics_0306.sh
rc=$?
set -e

# Provide 0308 aliases for the 0306 analyzer outputs, while preserving the
# original 0306 filenames expected by existing tooling.
for kind in run_manifest per_run timeseries worst_cells; do
  src="$ART_DIR/cuda_resampling_outlier_diagnostics_0306_${kind}.csv"
  dst="$ART_DIR/cuda_resampling_split_safety_consolidated_0308_${kind}.csv"
  if [[ -s "$src" ]]; then
    cp "$src" "$dst"
  fi
done

if [[ "$rc" != "0" ]]; then
  echo "[0308-consolidated] FAIL rc=$rc" >&2
  exit "$rc"
fi

echo "[0308-consolidated] PASS"
echo "[0308-consolidated] per-run=$ART_DIR/cuda_resampling_split_safety_consolidated_0308_per_run.csv"
echo "[0308-consolidated] worst=$ART_DIR/cuda_resampling_split_safety_consolidated_0308_worst_cells.csv"
