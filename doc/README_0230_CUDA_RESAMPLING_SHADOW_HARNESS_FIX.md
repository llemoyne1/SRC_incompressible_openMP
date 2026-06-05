# 0230 — Robust CUDA resampling shadow harness

Patch 0229 added CUDA classification/compaction/plan checks on real weighted
resampling deposits. The first run could leave the consolidated CSV with only a
`cpu_baseline` row when the shadow execution aborted before the post-processing
append step. That made the result ambiguous: the baseline passed, but the CUDA
shadow was not actually validated.

This patch changes only the validation harness.

## Changes

- Adds `scripts/run_cuda_resampling_shadow_0230.sh`.
- Adds `scripts/build_src_mpcd_cuda_0230.sh` with the same CUDA feature set as
  0229.
- Captures stdout/stderr for baseline and shadow runs.
- Runs shadow in non-strict mode by default (`STRICT_SHADOW=0`) so mismatches are
  written to the detail CSV and summarized instead of aborting before analysis.
- Writes one consolidated row per requested mode.
- Treats `shadowRows == 0` as a hard FAIL for the shadow mode.

No numerical kernel or CPU resampling logic is modified.

## Recommended command

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_resampling_shadow_0230.sh
```

Primary output:

```text
dev_history/artifacts/gpu_cuda_resampling_0230/cuda_resampling_shadow_0230.csv
```

Expected for validation:

```text
cpu_baseline             PASS
cuda_resampling_shadow   PASS
shadowRows > 0
shadowPoorMismatch = 0
shadowRichMismatch = 0
failed_metrics = 0
```
