#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
BASE="$ROOT/scripts/run_0493x14ah_drop_gas_transient_poiseuille_drag.sh"
ANALYZER="$ROOT/scripts/analyze_0493x14ai_cost_ab.py"
SRC="$ROOT/src/cuda_q6_resident_0400.cu"
for f in "$BASE" "$ANALYZER" "$SRC"; do [[ -f "$f" ]] || { echo "[0493x14ai-cost] missing $f" >&2; exit 2; }; done
grep -q '0493x14ai — production-candidate device-side Q6 resultant closure' "$SRC" || { echo '[0493x14ai-cost] x14ai source marker missing' >&2; exit 2; }

# Cost qualification parameters.  3 paired repetitions (6 measured runs) are
# the default compromise; increase TIMING_REPS or TIMING_STEPS only if the
# paired MAD says the overhead is unresolved.
TIMING_STEPS="${TIMING_STEPS:-400}"
TIMING_REPS="${TIMING_REPS:-3}"
TIMING_WARMUP_STEPS="${TIMING_WARMUP_STEPS:-100}"
SEED="${SEED:-493191}"
ROOTOUT="${ROOTOUT:-runs/0493x14ai_cost_ab_seed${SEED}}"
CSV="$ROOTOUT/timing_0493x14ai.csv"
JSON="$ROOTOUT/timing_summary_0493x14ai.json"
GPUCSV="$ROOTOUT/gpu_state_0493x14ai.csv"
mkdir -p "$ROOTOUT"
echo 'mode,rep,order,steps,elapsed,user,sys,seconds_per_step,time_file' > "$CSV"

sample_gpu() {
  local stage=$1
  if command -v nvidia-smi >/dev/null 2>&1; then
    if [[ ! -s "$GPUCSV" ]]; then
      echo 'stage,timestamp,name,driver_version,pstate,temperature_gpu,power_draw_w,clocks_sm_mhz,utilization_gpu_pct,memory_used_mib' > "$GPUCSV"
    fi
    # nvidia-smi already returns a timestamp; stage is prepended for A/B ordering.
    local line
    line="$(nvidia-smi --query-gpu=timestamp,name,driver_version,pstate,temperature.gpu,power.draw,clocks.sm,utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)"
    [[ -n "$line" ]] && printf '%s,%s\n' "$stage" "$line" >> "$GPUCSV"
  fi
}

# One excluded warm-up keeps first-run CUDA allocation/clock ramp out of the
# paired timing.  It uses the ON path so every x14ai code path has executed.
if (( TIMING_WARMUP_STEPS > 0 )); then
  warmroot="$ROOTOUT/warmup_on"
  warmlabel="0493x14ai_cost_warmup_on"
  echo "[0493x14ai-cost] WARMUP ON steps=$TIMING_WARMUP_STEPS (excluded)"
  MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=1 \
  MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=0 \
  MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0 \
  CASE_LABEL="$warmlabel" CAMPAIGN_ROOT="$warmroot" SEED="$SEED" \
  STEPS="$TIMING_WARMUP_STEPS" SUMMARY_EVERY="$TIMING_WARMUP_STEPS" DUMP_STATE_EVERY=1000000 \
  LIVE_PROGRESS=0 LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 \
  FILTERED_RECORDING_ENABLE=0 RECORD_ENABLE=false \
  CLEAN_RUN_ROOT=1 SKIP_ANALYSIS=1 \
  bash "$BASE"
fi
sample_gpu warm

run_one() {
  local mode=$1 rep=$2 ord=$3 gate label runroot tf line elapsed user sys sps
  if [[ "$mode" == ON ]]; then gate=1; else gate=0; fi
  label="0493x14ai_cost_${mode,,}_r${rep}"
  runroot="$ROOTOUT/${mode,,}_r${rep}"
  echo
  echo "[0493x14ai-cost] START mode=$mode rep=$rep order=$ord steps=$TIMING_STEPS gate=$gate"
  sample_gpu "pre_${mode,,}_r${rep}"
  MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE="$gate" \
  MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=0 \
  MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0 \
  CASE_LABEL="$label" CAMPAIGN_ROOT="$runroot" SEED="$SEED" \
  STEPS="$TIMING_STEPS" SUMMARY_EVERY="$TIMING_STEPS" DUMP_STATE_EVERY=1000000 \
  LIVE_PROGRESS=0 LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 \
  FILTERED_RECORDING_ENABLE=0 RECORD_ENABLE=false \
  CLEAN_RUN_ROOT=1 SKIP_ANALYSIS=1 \
  bash "$BASE"
  tf="$runroot/logs/${label}.time"
  [[ -s "$tf" ]] || { echo "[0493x14ai-cost] missing $tf" >&2; exit 2; }
  line="$(cat "$tf")"
  elapsed="$(printf '%s\n' "$line" | sed -n 's/.*elapsed=\([^ ]*\).*/\1/p')"
  user="$(printf '%s\n' "$line" | sed -n 's/.*user=\([^ ]*\).*/\1/p')"
  sys="$(printf '%s\n' "$line" | sed -n 's/.*sys=\([^ ]*\).*/\1/p')"
  [[ -n "$elapsed" ]] || { echo "[0493x14ai-cost] cannot parse $tf: $line" >&2; exit 2; }
  sps="$(awk -v e="$elapsed" -v n="$TIMING_STEPS" 'BEGIN{printf "%.17g",e/n}')"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$mode" "$rep" "$ord" "$TIMING_STEPS" "$elapsed" "$user" "$sys" "$sps" "$tf" >> "$CSV"
  sample_gpu "post_${mode,,}_r${rep}"
  echo "[0493x14ai-cost] DONE mode=$mode rep=$rep elapsed=$elapsed s s/step=$sps"
}

# AB/BA alternation removes first-order thermal/clock drift from the paired
# comparison: OFF/ON, ON/OFF, OFF/ON, ...
for ((rep=1; rep<=TIMING_REPS; ++rep)); do
  if (( rep % 2 == 1 )); then
    run_one OFF "$rep" 1
    run_one ON  "$rep" 2
  else
    run_one ON  "$rep" 1
    run_one OFF "$rep" 2
  fi
done

python3 "$ANALYZER" "$CSV" "$JSON"
echo "[0493x14ai-cost] return: $CSV $JSON $GPUCSV"
