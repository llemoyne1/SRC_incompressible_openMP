#!/usr/bin/env bash
set -euo pipefail

MAIN_ROOT="${MAIN_ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-INTEG}"
BASELINE_WT="${BASELINE_WT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-INTEG_0482_BASELINE_B4D0A77}"
BASELINE_BIN="${BASELINE_BIN:-$BASELINE_WT/build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0482_baseline}"
CANDIDATE_BIN="${CANDIDATE_BIN:-$MAIN_ROOT/build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0483b}"
GAIN_ROOT="${GAIN_ROOT:-$MAIN_ROOT/runs/0483b_remap_fusion_gain_ab_128_long}"
LOG_DIR="${LOG_DIR:-$MAIN_ROOT/logs/0483b_ab_128_long}"
CUDA_ARCH_FLAGS_VALUE="${CUDA_ARCH_FLAGS_VALUE:--arch=sm_89}"
STEPS_VALUE="${STEPS_VALUE:-2000}"
SUMMARY_EVERY_VALUE="${SUMMARY_EVERY_VALUE:-200}"
DEVICE_GATE_EVERY_VALUE="${DEVICE_GATE_EVERY_VALUE:-200}"
LIVE_PROGRESS_VALUE="${LIVE_PROGRESS_VALUE:-1}"

mkdir -p "$LOG_DIR"
cd "$MAIN_ROOT"

{
  echo "=== 0483b current tree state ==="
  git status --short
  git log --oneline -8
  echo
  echo "=== 0483b code diff ==="
  git diff -- src/cuda_resampling_pipeline_shadow_0445.cu
} | tee "$LOG_DIR/00_state_and_diff.log"

git diff -- src/cuda_resampling_pipeline_shadow_0445.cu > "$LOG_DIR/0483b_code_diff_current_tree.diff"

{
  echo "=== rebuild clean 0482 baseline in detached worktree ==="
  git worktree remove --force "$BASELINE_WT" 2>/dev/null || true
  rm -rf "$BASELINE_WT"
  git worktree add --detach "$BASELINE_WT" b4d0a77
} | tee "$LOG_DIR/01_prepare_baseline_worktree.log"

cd "$BASELINE_WT"
OUT="$BASELINE_BIN" \
CUDA_ARCH_FLAGS="$CUDA_ARCH_FLAGS_VALUE" \
bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh \
  2>&1 | tee "$LOG_DIR/02_build_0482_baseline.log"

cd "$MAIN_ROOT"
OUT="$CANDIDATE_BIN" \
CUDA_ARCH_FLAGS="$CUDA_ARCH_FLAGS_VALUE" \
bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh \
  2>&1 | tee "$LOG_DIR/03_build_0483b_candidate.log"

BASELINE_BIN="$BASELINE_BIN" \
CANDIDATE_BIN="$CANDIDATE_BIN" \
GAIN_ROOT="$GAIN_ROOT" \
SCALE_CASES='128x128x40' \
SEEDS='1628638' \
STEPS="$STEPS_VALUE" \
SUMMARY_EVERY="$SUMMARY_EVERY_VALUE" \
DEVICE_GATE_EVERY="$DEVICE_GATE_EVERY_VALUE" \
LIVE_PROGRESS="$LIVE_PROGRESS_VALUE" \
bash scripts/run_0483_vs_baseline_remap_gain.sh \
  2>&1 | tee "$LOG_DIR/04_gain_ab_0482_vs_0483b_128_long.log"

cd "$MAIN_ROOT"
git status --short > "$LOG_DIR/git_status_short_after_0483b_ab.txt"
git log --oneline -8 > "$LOG_DIR/git_log_oneline_after_0483b_ab.txt"

RETURN_BUNDLE="$MAIN_ROOT/SRC_GPU_0483b_ab_128_long_return_$(date +%Y%m%d_%H%M%S).tar.gz"
tar -czf "$RETURN_BUNDLE" \
  "logs/0483b_ab_128_long" \
  "runs/0483_remap_fusion_cpu_cuda_matrix_stress/remap_fusion_cpu_cuda_report_0483.md" \
  "runs/0483_remap_fusion_cpu_cuda_matrix_stress/remap_fusion_cpu_cuda_summary_0483.csv" \
  "runs/0483b_remap_fusion_gain_ab_128_long/remap_fusion_gain_compare_0483.md" \
  "runs/0483b_remap_fusion_gain_ab_128_long/remap_fusion_gain_compare_0483.csv" \
  "runs/0483b_remap_fusion_gain_ab_128_long/baseline/remap_fusion_cpu_cuda_report_0483.md" \
  "runs/0483b_remap_fusion_gain_ab_128_long/baseline/remap_fusion_cpu_cuda_summary_0483.csv" \
  "runs/0483b_remap_fusion_gain_ab_128_long/candidate/remap_fusion_cpu_cuda_report_0483.md" \
  "runs/0483b_remap_fusion_gain_ab_128_long/candidate/remap_fusion_cpu_cuda_summary_0483.csv"

echo
echo "RETURN_BUNDLE=$RETURN_BUNDLE"
echo
echo "=== 0483b reduced long A/B summary ==="
cat "$GAIN_ROOT/remap_fusion_gain_compare_0483.md"
