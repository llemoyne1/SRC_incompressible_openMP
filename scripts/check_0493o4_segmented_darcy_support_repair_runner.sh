#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RUNNER="$ROOT/scripts/run_0493o0_src_baseline_segmented_darcy.sh"

fail() {
  echo "[0493o4-check] ERROR: $*" >&2
  exit 1
}

[[ -f "$RUNNER" ]] || fail "missing runner: $RUNNER"
bash -n "$RUNNER" || fail "bash syntax"

grep -q 'SUPPORT_REPAIR_ENABLE="${SUPPORT_REPAIR_ENABLE:-false}"' "$RUNNER" ||
  fail "missing support repair switch"
grep -q 'WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=true' "$RUNNER" ||
  fail "missing resampling activation"
grep -q 'RESAMPLING_INSERTION_ENABLE=true' "$RUNNER" ||
  fail "missing split insertion activation"
grep -q 'RESAMPLING_EXTRACTION_ENABLE=false' "$RUNNER" ||
  fail "extraction is not forced off"
grep -q 'RESAMPLING_REMAP_ENABLE=false' "$RUNNER" ||
  fail "remap is not forced off"
grep -q 'CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false' "$RUNNER" ||
  fail "empty refill is not forced off"
grep -q 'RESAMPLING_MASS_GUARD_ENABLE=false' "$RUNNER" ||
  fail "mass guard is not forced off"
grep -q 'RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false' "$RUNNER" ||
  fail "thermal renormalization is not forced off"
grep -q 'CUDA_RESAMPLING_CHI_FILTER_ENABLE=true' "$RUNNER" ||
  fail "chi filter is not enabled on repair path"
grep -q 'DARCY_INITIAL_DEACTIVATE_BELOW_CHI' "$RUNNER" ||
  fail "chi filter does not reuse Darcy threshold"
grep -q 'speciesRegistryEnable = true' "$RUNNER" ||
  fail "missing species registry"
grep -q 'species0ResamplingEnable = ${SPECIES0_RESAMPLING_ENABLE}' "$RUNNER" ||
  fail "species repair switch not connected"
grep -q 'openBoundarySegment0 = .*${BACKGROUND_TYPE} ${PARTICLE_MASS}' "$RUNNER" ||
  fail "inlet type is not registry-driven"
grep -q 'openBoundarySegment1 = .*${BACKGROUND_TYPE} ${PARTICLE_MASS}' "$RUNNER" ||
  fail "outlet type is not registry-driven"
grep -q 'export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0' "$RUNNER" ||
  fail "0296 must remain off"
grep -q 'export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=0' "$RUNNER" ||
  fail "0319 must remain off"
grep -q 'export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0' "$RUNNER" ||
  fail "legacy env-driven 0297 path must remain off"
grep -q 'export MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0' "$RUNNER" ||
  fail "0448 pipeline must remain off"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/root/scripts"

cat > "$TMP/root/scripts/src_mpcd_run_common_0434.sh" <<'STUB'
suite_truthy_0434() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}
suite_root_cd_0434() { cd "$ROOT"; }
suite_defaults_common_0434() {
  PARTICLE_MASS="${PARTICLE_MASS:-2.0}"
  BACKGROUND_TYPE="${BACKGROUND_TYPE:-7}"
  CUDA_RESAMPLING_CHI_FILTER_ENABLE="${CUDA_RESAMPLING_CHI_FILTER_ENABLE:-false}"
  CUDA_RESAMPLING_CHI_MIN="${CUDA_RESAMPLING_CHI_MIN:-0.05}"
}
suite_compute_derived_0434() {
  GUARD_NMIN="${GUARD_NMIN:-12}"
  GUARD_NTARGET="${GUARD_NTARGET:-20}"
  GUARD_NMAX="${GUARD_NMAX:-32}"
}
suite_prepare_dirs_0434() {
  local r=$1
  rm -rf "$r"
  mkdir -p "$r/init" "$r/chi" "$r/params" "$r/output" "$r/logs"
}
suite_generate_case_0434() {
  : > "$1"
  [[ $# -lt 2 ]] || : > "$2"
}
suite_write_common_params_0434() {
  cat <<PARAMS
resamplingEnable = ${WEIGHTED_RESAMPLING_ENABLE_OVERRIDE:-false}
cudaResamplingChiFilterEnable = ${CUDA_RESAMPLING_CHI_FILTER_ENABLE}
cudaResamplingChiMin = ${CUDA_RESAMPLING_CHI_MIN}
cudaResamplingEmptyRefillEnable = ${CUDA_EMPTY_REFILL_ENABLE_OVERRIDE:-false}
resamplingPopulationNMin = ${GUARD_NMIN}
resamplingPopulationNTarget = ${GUARD_NTARGET}
resamplingPopulationNMax = ${GUARD_NMAX}
resamplingExtractionEnable = ${RESAMPLING_EXTRACTION_ENABLE:-true}
resamplingInsertionEnable = ${RESAMPLING_INSERTION_ENABLE:-true}
resamplingRemapEnable = ${RESAMPLING_REMAP_ENABLE:-true}
resamplingThermalRenormalizationEnable = ${RESAMPLING_THERMAL_RENORMALIZATION_ENABLE:-true}
resamplingMassGuardEnable = ${RESAMPLING_MASS_GUARD_ENABLE:-true}
PARAMS
}
suite_write_darcy_params_0434() {
  cat <<PARAMS
darcyBrinkmanEnable = true
darcyChiFile = $1
PARAMS
}
suite_export_cuda_flags_0434() { :; }
suite_prepare_livevis_control_0434() { : > "$ROOT/livevis_control.kv"; }
suite_export_livevis_0434() { :; }
suite_write_env_file_0434() { mkdir -p "$(dirname "$1")"; : > "$1"; }
suite_run_binary_0434() { :; }
STUB

run_case() {
  local mode=$1
  local run="$TMP/$mode"
  ROOT="$TMP/root" \
  RUN_ROOT="$run" \
  SUPPORT_REPAIR_ENABLE="$mode" \
  LIVE_VIS_ENABLE=0 \
  FILTERED_RECORDING_ENABLE=0 \
  RECORD_ENABLE=false \
  CLEAN_RUN_ROOT=1 \
  bash "$RUNNER" >/dev/null
}

run_case false
run_case true

BASE_PARAMS="$TMP/false/params/0493o0_src_baseline_segmented_darcy.kv"
REPAIR_PARAMS="$TMP/true/params/0493o0_src_baseline_segmented_darcy.kv"

[[ -f "$BASE_PARAMS" && -f "$REPAIR_PARAMS" ]] ||
  fail "stub execution did not produce params"

grep -q '^resamplingEnable = false$' "$BASE_PARAMS" ||
  fail "baseline resampling is not off"
grep -q '^species0ResamplingEnable = false$' "$BASE_PARAMS" ||
  fail "baseline species repair is not off"

grep -q '^resamplingEnable = true$' "$REPAIR_PARAMS" ||
  fail "repair resampling is not on"
grep -q '^resamplingInsertionEnable = true$' "$REPAIR_PARAMS" ||
  fail "repair insertion is not on"
grep -q '^resamplingExtractionEnable = false$' "$REPAIR_PARAMS" ||
  fail "repair extraction is not off"
grep -q '^resamplingRemapEnable = false$' "$REPAIR_PARAMS" ||
  fail "repair remap is not off"
grep -q '^cudaResamplingEmptyRefillEnable = false$' "$REPAIR_PARAMS" ||
  fail "repair empty refill is not off"
grep -q '^resamplingThermalRenormalizationEnable = false$' "$REPAIR_PARAMS" ||
  fail "repair thermal renormalization is not off"
grep -q '^resamplingMassGuardEnable = false$' "$REPAIR_PARAMS" ||
  fail "repair mass guard is not off"
grep -q '^cudaResamplingChiFilterEnable = true$' "$REPAIR_PARAMS" ||
  fail "repair chi filter is not on"
grep -q '^cudaResamplingChiMin = 0.05$' "$REPAIR_PARAMS" ||
  fail "repair chi threshold mismatch"
grep -q '^resamplingPopulationNMin = 10$' "$REPAIR_PARAMS" ||
  fail "repair Nmin mismatch"
grep -q '^resamplingPopulationNTarget = 12$' "$REPAIR_PARAMS" ||
  fail "repair Ntarget mismatch"
grep -q '^resamplingPopulationNMax = 32$' "$REPAIR_PARAMS" ||
  fail "repair Nmax mismatch"
grep -q '^species0 = 7 segmented_darcy_mono unspecified 1.0 1.0 40.0$' "$REPAIR_PARAMS" ||
  fail "registry target mass/type mismatch"
grep -q '^species0ResamplingEnable = true$' "$REPAIR_PARAMS" ||
  fail "repair species is not enabled"
grep -q '^openBoundarySegment0 = left inlet .* 7 2.0$' "$REPAIR_PARAMS" ||
  fail "inlet type/mass mismatch"
grep -q '^openBoundarySegment1 = right outlet .* 7 2.0$' "$REPAIR_PARAMS" ||
  fail "outlet type/mass mismatch"

echo "[0493o4-check] syntax and static constraints: PASS"
echo "[0493o4-check] paired baseline/repair params: PASS"
echo "[0493o4-check] segmented Darcy support-repair runner: PASS"
