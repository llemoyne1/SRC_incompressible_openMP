# Patch 0193 — CUDA Q6 device-side scalar reduction

## Purpose

Patch 0193 keeps the `SRC_GPU` branch in the CUDA-only prototype strategy.  It does not expand the CUDA physics support: `projectionBackend=cuda` remains limited to the fully periodic, unmasked Taylor--Green/Q6 subset.

The 0192 timing/scaling runs showed that the stencil application itself is cheap, while most CUDA Q6 time is spent in CG scalar reductions and the associated host-device synchronization.  On the available measurements, the effect is present at both 64x64 and 128x128.  The 128x128 run nearly closes the total CPU/CUDA wall-time gap, but the CUDA timing still reports host-reduction dominated Q6 time.

## Change

Before 0193, every CG scalar reduction copied the whole `blockSums` array back to the host and summed it on the CPU.  Patch 0193 adds a second-stage CUDA reduction:

```text
blockSums[0:nBlocks]
  -> q6_reduce_block_sums_to_scalar_kernel<<<1,256>>>
  -> scalarSum[0]
  -> copy one double to host
```

This reduces device-to-host traffic and host summation work for every CG dot/norm/mean reduction.  It does not yet remove the mandatory scalar synchronization itself; `alpha`, `beta`, convergence checks and periodic mean removal still need host-side decisions in this prototype.

## Runtime switch

The new device-scalar path is enabled by default.  The previous host block-sum path can be restored for ablation with:

```bash
MPCD_CUDA_Q6_HOST_BLOCK_SUM=1
```

The existing timing switch remains:

```bash
MPCD_CUDA_Q6_TIMING=1
```

The timing line intentionally keeps the inherited tag:

```text
[cuda_q6_timing_0192] ...
```

so the existing parser remains compatible.

## Validation

Build and run:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000 128:500' \
bash scripts/run_cuda_q6_tg_reduction_0193.sh
```

For a quick ablation against the legacy path:

```bash
MPCD_CUDA_Q6_HOST_BLOCK_SUM=1 \
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000' \
bash scripts/run_cuda_q6_tg_reduction_0193.sh
```

Expected criteria:

- `failed_metrics = 0` in CPU/CUDA comparisons;
- CPU and CUDA `q6Iterations` match exactly;
- `q6DivAfterProjectedFluxRms <= 1e-8`;
- non-periodic Poiseuille remains explicitly rejected with `projectionBackend=cuda`.

## Interpretation

If `hostReductionSeconds` drops materially but total CUDA time remains too high, the next bottleneck is the scalar synchronization pattern itself.  The next architectural step would then be a more fused CG iteration, or a CUDA-side reduction/control strategy that reduces host round trips per CG iteration.
