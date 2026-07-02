#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0400_livevis_0435d}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0435e_algorithmic_matrix}"
STEPS="${STEPS:-300}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
GAMMA="${GAMMA:-6}"
read -r -a MODES <<< "${MODES_LIST:-src src-resampling src-q6 src-q6-resampling}"
read -r -a CASES <<< "${CASES_LIST:-tg poiseuille step io_box_same_face injection_type1_into_type2 bend_pipe naca vk}"

mkdir -p "$CAMPAIGN_ROOT/launcher_logs"
STATUS="$CAMPAIGN_ROOT/launch_status.csv"
printf 'case,mode,exit_code,log\n' > "$STATUS"

case_grid_0435e() {
  case "$1" in
    tg) printf '48 48' ;;
    poiseuille) printf '64 32' ;;
    step) printf '64 32' ;;
    io_box_same_face) printf '48 48' ;;
    injection_type1_into_type2) printf '64 16' ;;
    bend_pipe) printf '48 48' ;;
    naca) printf '64 32' ;;
    vk) printf '72 24' ;;
    *) return 2 ;;
  esac
}

case_inactive_fraction_0435e() {
  case "$1" in
    step|injection_type1_into_type2) printf '8.0' ;;
    *) printf '' ;;
  esac
}

failures=0
for case_name in "${CASES[@]}"; do
  read -r nx ny <<< "$(case_grid_0435e "$case_name")"
  inactive_fraction="$(case_inactive_fraction_0435e "$case_name")"
  extra_env=()
  if [[ -n "$inactive_fraction" ]]; then
    extra_env+=("INACTIVE_SLOTS_CELL_FRACTION=$inactive_fraction")
  fi
  for mode in "${MODES[@]}"; do
    case_root="$CAMPAIGN_ROOT/$case_name"
    log="$CAMPAIGN_ROOT/launcher_logs/${case_name}__${mode}.log"
    echo "[0435e] case=$case_name mode=$mode grid=${nx}x${ny} steps=$STEPS"
    rc=0
    env \
      BIN="$BIN" AUTO_BUILD=0 BUILD_IF_STALE=0 FORCE_BUILD=0 \
      BASE_RUN_ROOT="$case_root" RUN_MODES="$mode" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$STEPS" \
      SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY=1000000 \
      LIVE_VIS_ENABLE=0 FILTERED_RECORDING_ENABLE=0 \
      DARCY_BRINKMAN_FORCING_MODE=mean_outward_bath \
      DARCY_CHI_COLLISION_VP_ENABLE=true \
      DARCY_CHI_COLLISION_VP_MODE=interface_band \
      DARCY_CHI_COLLISION_VP_GAMMA="$GAMMA" \
      DARCY_CHI_COLLISION_VP_STRENGTH=0.25 \
      "${extra_env[@]}" \
      bash "scripts/run_0434_${case_name}.sh" >"$log" 2>&1 || rc=$?
    printf '%s,%s,%s,%s\n' "$case_name" "$mode" "$rc" "$log" >> "$STATUS"
    if [[ "$rc" != 0 ]]; then
      failures=$((failures + 1))
      echo "[0435e] FAIL case=$case_name mode=$mode rc=$rc"
      tail -20 "$log"
    fi
  done
done

python3 scripts/summarize_0435e_algorithmic_matrix.py \
  --root "$CAMPAIGN_ROOT" --status "$STATUS" \
  --csv "$CAMPAIGN_ROOT/algorithmic_audit.csv" \
  --markdown "$CAMPAIGN_ROOT/algorithmic_report.md"

echo "[0435e] launch_failures=$failures"
echo "[0435e] audit=$CAMPAIGN_ROOT/algorithmic_audit.csv"
echo "[0435e] report=$CAMPAIGN_ROOT/algorithmic_report.md"
exit "$failures"
