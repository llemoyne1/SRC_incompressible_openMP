#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
TG=scripts/run_0493o0_src_baseline_tg.sh
GEN=scripts/run_0493o0_src_baseline_segmented_darcy.sh
for f in "$TG" "$GEN"; do
  [[ -f "$f" ]] || { echo "[0493o0-check] ERROR missing $f" >&2; exit 2; }
  bash -n "$f"
  grep -Fq 'MODE="src"' "$f"
  grep -Fq 'LIVE_PROGRESS="${LIVE_PROGRESS:-1}"' "$f"
  grep -Fq 'LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"' "$f"
  grep -Fq 'LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"' "$f"
  grep -Fq 'MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=1' "$f"
  grep -Fq 'MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304=1' "$f"
  grep -Fq 'MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0' "$f"
  grep -Fq 'MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=0' "$f"
done
grep -Fq 'TOPOLOGY="periodic"' "$TG"
grep -Fq 'openBoundarySegmentsEnable = false' "$TG"
grep -Fq 'TOPOLOGY="segmented"' "$GEN"
grep -Fq 'openBoundarySegmentsEnable = true' "$GEN"
grep -Fq 'wallVpEnable = true' "$GEN"
grep -Fq 'suite_write_darcy_params_0434' "$GEN"
echo '[0493o0-check] PASS additive SRC-only dual-bench runners'
