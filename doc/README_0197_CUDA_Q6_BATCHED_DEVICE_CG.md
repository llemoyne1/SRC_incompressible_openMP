# Patch 0197 — CUDA Q6 batched device-side CG

This patch keeps the SRC/MPCD CPU/OpenMP path unchanged and keeps the CUDA
projection restricted to the already validated periodic, unmasked Taylor--Green
subset.

## Motivation

Patch 0196 was the first structural speedup: it kept `pAp`, `alpha` and `beta`
on device and reduced the main CG loop from two host scalar downloads per
iteration to one.  The 64x64 and 128x128 measurements still showed that the
remaining host-side convergence download dominates the CUDA Q6 time.

Patch 0197 therefore adds an experimental batched device-side CG loop:

```text
batchSize = 1   -> 0196-equivalent path
batchSize > 1   -> run several CG iterations on device before host convergence check
```

The batch is never allowed to cross a periodic mean-removal/gauge-fix boundary.
Within a batch, a device-side convergence flag records the exact iteration at
which `rrNew <= absTol^2`.  Subsequent kernels in the same batch return without
changing the state.  The host downloads the convergence state and final residual
only at the batch boundary.

## Runtime controls

The default remains conservative:

```bash
MPCD_CUDA_Q6_DEVICE_SCALAR_CG=1
MPCD_CUDA_Q6_DEVICE_SCALAR_BATCH=1
```

Useful experimental values:

```bash
MPCD_CUDA_Q6_DEVICE_SCALAR_BATCH=5
MPCD_CUDA_Q6_DEVICE_SCALAR_BATCH=10
MPCD_CUDA_Q6_DEVICE_SCALAR_BATCH=20
```

The batch size is capped internally at 64.

## Validation script

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000' \
BATCH_CASES='1 5 10 20' \
bash scripts/run_cuda_q6_tg_batched_cg_0197.sh
```

Then, if 64x64 passes:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='128:500' \
BATCH_CASES='1 5 10 20' \
bash scripts/run_cuda_q6_tg_batched_cg_0197.sh
```

The script writes:

```text
dev_history/artifacts/gpu_cuda_integration_0197/cuda_q6_tg_batched_cg_0197.csv
```

and one CPU/CUDA comparison file per grid/batch.

## Expected criteria

- `failed_metrics = 0` in the validation comparison.
- CPU and CUDA `q6Iterations` remain equal; device-side flags preserve exact
  early stop within a batch.
- `q6DivAfterProjectedFluxRms <= 1e-8`.
- `deviceScalarCgConvergenceDownloads` should be much smaller than
  `deviceScalarCgIterations` for batch sizes greater than one.
- Poiseuille/non-periodic CUDA Q6 remains explicitly rejected.

## Important caveat

This is deliberately more aggressive than the previous patches.  It should be
validated first on 64x64 before any 128x128 or longer run.  If a batch size
fails or slows down, keep `batchSize=1` as the safe 0196-equivalent path and use
that result to guide the next refactor.
