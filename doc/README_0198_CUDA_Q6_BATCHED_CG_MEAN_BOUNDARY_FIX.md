# 0198 — CUDA Q6 batched CG mean-removal boundary fix

Patch 0198 corrects the first 0197 batched-CG integration.

## Problem seen in 0197

The 0197 validation failed already for `batchSize=1`, which was expected to be
0196-equivalent.  Typical symptoms were:

- `q6Iterations` much larger than the CPU/0196 reference;
- degraded Q6 residuals;
- at 128x128, non-convergence within the configured iteration cap and subsequent
  divergence of resampling-sensitive trajectory metrics.

## Root cause

Inside the device-scalar CG loop, 0197 copied

```text
dRr <- dRrNew
```

immediately at the end of every iteration.  At an iteration that coincides with
`meanRemovalPeriod`, the residual is then gauge-fixed by subtracting its active-cell
mean.  The post-gauge-fix direction update must use

```text
beta = rr_new_after_mean_removal / rr_old_before_this_iteration
```

but 0197 had already overwritten `rr_old` with the pre-mean-removal `rrNew`.
This breaks CG conjugacy even for `batchSize=1`.

## Fix

At mean-removal boundaries, do not copy `dRr <- dRrNew` inside the per-iteration
loop. Keep `dRr` as the old residual norm until the gauge-fixed residual norm has
been computed. Then perform the direction update and copy the corrected `dRrNew`
to `dRr`.

## Validation target

Start with:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000' \
BATCH_CASES='1 5 10 20' \
bash scripts/run_cuda_q6_tg_batched_cg_0198.sh
```

Then, if `batchSize=1` is restored to 0196-like behavior and all batch modes pass:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='128:500' \
BATCH_CASES='1 5 10 20' \
bash scripts/run_cuda_q6_tg_batched_cg_0198.sh
```

Expected criteria:

- `failed_metrics = 0` for accepted batch modes;
- `q6Converged = 1`;
- `q6Iterations` consistent with CPU/0196 at `batchSize=1`;
- `q6DivAfterProjectedFluxRms <= 1e-8`;
- `deviceScalarCgConvergenceDownloads` decreases with larger batch sizes.
