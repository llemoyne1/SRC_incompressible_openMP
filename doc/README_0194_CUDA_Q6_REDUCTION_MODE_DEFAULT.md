# 0194 — CUDA Q6 reduction-mode default after 0193 regression

## Context

Patch 0193 tested a device-side final reduction for the CUDA Q6 CG block sums:

```text
blockSums[0:nBlocks] on GPU
  -> q6_reduce_block_sums_to_scalar_kernel
  -> copy one double to host
```

The 0193 validation remained numerically correct, but performance worsened on the
validated Taylor--Green sizes.  The additional reduction kernel is not amortized
for the current number of blocks and the CG still requires host-visible scalars.

## Change in 0194

The default CUDA Q6 reduction path is restored to the previous host-block mode:

```text
blockSums[0:nBlocks] on GPU
  -> copy blockSums to host
  -> final sum on host
```

The 0193 device-scalar path is retained only as an explicit ablation mode:

```bash
MPCD_CUDA_Q6_DEVICE_SCALAR_REDUCTION=1
```

The legacy force-host switch remains accepted:

```bash
MPCD_CUDA_Q6_HOST_BLOCK_SUM=1
```

This is intentionally a conservative correction rather than a new physics scope.
The supported CUDA projection subset remains the same:

```text
projectionBackend=cuda
fully periodic Q6 plan
unmasked / all-active cell set
Taylor--Green validation first
```

## Why not keep device scalar reduction as default?

The 0193 data show that the device-scalar reduction adds an extra kernel launch
per reduction while still requiring a host synchronization for the scalar.  For
64^2 and 128^2 TG, this is slower than downloading the modest block-sum array.

This means the next real optimization is not simply a smaller copy.  It must
reduce the number of host-visible scalar synchronization points in CG, e.g. by
fusing/encapsulating more of the CG iteration logic on device or by switching to
a device-resident reduction/iteration strategy.

## Validation

Build:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' bash scripts/build_src_mpcd_cuda_0194.sh
```

Default host-block reduction plus device-scalar ablation:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000 128:500' \
bash scripts/run_cuda_q6_tg_reduction_modes_0194.sh
```

Default-only run:

```bash
RUN_DEVICE_SCALAR_ABLATION=0 \
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:1000 128:500' \
bash scripts/run_cuda_q6_tg_reduction_modes_0194.sh
```

Output:

```text
dev_history/artifacts/gpu_cuda_integration_0194/cuda_q6_tg_reduction_modes_0194.csv
```

Expected numerical criteria:

```text
failed_metrics = 0
q6Iterations CPU = CUDA
q6DivAfterProjectedFluxRms <= 1e-8
Poiseuille + projectionBackend=cuda remains explicitly rejected
```

## Next direction

If 0194 restores 0192-level timing, the next patch should not revisit block-sum
copy size.  It should instead target CG scalar synchronization count:

```text
pAp scalar synchronization
rrNew scalar synchronization
mean-removal scalar synchronization
beta/alpha host control of the iteration
```

A likely next patch is a deeper CG refactor that either fuses scalar operations
more aggressively or adds a dedicated CUDA CG loop with device-side scalar state.
