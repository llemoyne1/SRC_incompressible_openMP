# 0203 — Combined CUDA TG validation: Q6 + particle-to-cell deposit

## Scope

This patch does **not** add a new numerical algorithm. It adds a combined
validation/benchmark harness for the two currently validated CUDA bricks on the
`SRC_GPU` branch:

1. CUDA Q6 projection on the periodic, unmasked Taylor--Green subset;
2. CUDA particle-to-cell moment deposit inside the collision step.

CPU/OpenMP remains the default runtime path. The script explicitly compares four
configurations on the same initial condition and random seed:

| mode | projection | particle-to-cell deposit |
|---|---|---|
| `cpu_baseline` | CPU | CPU |
| `q6_cuda` | CUDA | CPU |
| `cell_cuda` | CPU | CUDA |
| `combined_cuda` | CUDA | CUDA |

The intended first target remains `tg_periodic_full`. This patch does not expand
CUDA support to Poiseuille, open boundaries, immersed solid, piston, or Von
Karman.

## Why this patch follows 0202

Patch 0202 showed that active CUDA cell-moment deposit is numerically correct and
near neutral in the current mixed CPU/GPU step:

- the kernel itself is cheap;
- the remaining cost is dominated by host/device transfer;
- the path becomes nearly neutral on the 128x128 short TG run.

Before moving collision, thermostat, or resampling to CUDA, it is useful to
measure whether the two existing GPU bricks compose cleanly and whether the
combined path improves the total TG runtime.

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
  bash scripts/build_src_mpcd_cuda_0203.sh
```

The build enables both optional CUDA components:

```text
-DMPCD_ENABLE_CUDA_Q6
-DMPCD_ENABLE_CUDA_CELL_MOMENTS
```

## Run

Short combined validation:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
BATCH_SIZE=20 \
bash scripts/run_cuda_tg_combined_gpu_0203.sh
```

Longer 128x128-only run:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='128:500' \
BATCH_SIZE=20 \
bash scripts/run_cuda_tg_combined_gpu_0203.sh
```

The script writes:

```text
dev_history/artifacts/gpu_cuda_combined_0203/cuda_tg_combined_gpu_0203.csv
```

and comparison files under:

```text
dev_history/artifacts/gpu_cuda_combined_0203/
```

## Runtime switches used by the script

For CUDA Q6:

```text
PROJECTION_BACKEND=cuda
MPCD_CUDA_Q6_TIMING=1
MPCD_CUDA_Q6_DEVICE_SCALAR_CG=1
MPCD_CUDA_Q6_DEVICE_SCALAR_BATCH=<BATCH_SIZE>
```

For CUDA deposit:

```text
MPCD_CUDA_CELL_MOMENTS_USE=1
MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS=1
MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH=1
MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH=1
```

## Acceptance criteria

For each non-baseline mode:

```text
failed_metrics = 0
q6DivAfterProjectedFluxRms <= 1e-8 for Q6 CUDA modes
```

The key performance columns are:

```text
wallTime
speedupWallBaselineOverMode
cellTotalSeconds
cellUploadSeconds
cellKernelSeconds
cudaTimingTotalSeconds
cudaTimingHostReductionSeconds
```

## Expected interpretation

If `combined_cuda` is faster than both `q6_cuda` and `cell_cuda`, the two GPU
bricks compose productively. If it remains close to `q6_cuda`, then the active
CUDA deposit is not yet the limiting factor. If `combined_cuda` is slower, the
step is still dominated by host/device traffic and the next GPU migration should
move the first consumer of the cell moments, most likely thermostat/collision,
rather than further optimizing deposit alone.

