# 0204 — Robust combined CUDA TG harness

Patch 0204 fixes the combined CUDA validation harness introduced in 0203.
It does not change numerical kernels.

## Motivation

The 0203 output can contain only the CPU baseline row even when the Q6 comparison
files are produced. The likely cause is fragile capture of the compare-script
output through `mapfile`: if the compare script writes diagnostic text on stdout,
the captured array no longer contains only the two expected file paths.

0204 avoids that pattern. It derives comparison CSV paths directly and appends
rows from known paths. It also records FAIL rows and continues unless
`STOP_ON_FAIL=1` is set.

## Run

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
BATCH_SIZE=20 \
bash scripts/run_cuda_tg_combined_gpu_0204.sh
```

To run only the combined mode after the baseline:

```bash
RUN_Q6_ONLY=0 RUN_CELL_ONLY=0 RUN_COMBINED=1 \
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200' \
BATCH_SIZE=20 \
bash scripts/run_cuda_tg_combined_gpu_0204.sh
```

Main output:

```text
dev_history/artifacts/gpu_cuda_combined_0204/cuda_tg_combined_gpu_0204.csv
```

Expected rows per grid:

```text
cpu_baseline
q6_cuda
cell_cuda
combined_cuda
```

## Acceptance

For all non-baseline modes:

```text
failed_metrics = 0
verdict = PASS
```

For Q6 CUDA modes:

```text
q6DivAfterProjectedFluxRms <= 1e-8
```

This patch is a harness correction only. The next numerical migration should
still target a consumer of cell moments, most likely thermostat or collision.
