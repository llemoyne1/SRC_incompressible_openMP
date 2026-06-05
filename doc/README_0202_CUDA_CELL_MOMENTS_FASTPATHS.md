# 0202 — CUDA particle-to-cell deposit: persistent buffers and fast paths

This patch follows the 0201 active CUDA cell-moments deposit. 0201 was
numerically valid, but the timing showed that the active path was dominated by
allocation/copy overhead rather than by the atomic deposit kernel itself.

## Scope

The patch keeps the same limited physical scope as 0201:

- CPU/OpenMP remains the default path.
- `MPCD_CUDA_CELL_MOMENTS_USE=1` activates the CUDA particle-to-cell deposit.
- The CUDA path is still used only for the first pre-virtual-particle deposit:
  `cellId`, `cellCount`, `cellMass`, `cellPx`, `cellPy`.
- The rest of the collision step remains on CPU: virtual particles, wallVP,
  immersed-solid contributions, SRC rotation, thermostat, resampling and Q6.

## Changes

0202 adds three low-risk optimizations to the CUDA deposit routine:

1. Persistent thread-local device buffers, enabled by default in the active
   path through `MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS=1`.
2. All-fluid fast path. If all particles are fluid, the role array is not
   copied and the kernel skips the role branch.
3. Uniform-mass fast path. If all particle masses are exactly identical, the
   mass array is not copied and the kernel uses a scalar mass value.
4. Active mode no longer computes/downloads `cellUx/cellUy`, because the CPU
   step recomputes final cell velocities after virtual-particle augmentation.

The fast paths are guarded by exact host-side checks, so they should not change
results. They can be disabled independently:

```bash
MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS=0
MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH=0
MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH=0
```

## Validation

Recommended run:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_BACKEND=cpu \
bash scripts/run_cuda_cell_moments_fastpath_0202.sh
```

The main summary is written to:

```text
dev_history/artifacts/gpu_cuda_deposit_0202/cuda_cell_moments_fastpath_0202.csv
```

Each run writes a per-case active diagnostic:

```text
runs/.../tg_periodic_full/cuda_cell_moments_active_0202.csv
```

Expected criteria:

- `failed_metrics = 0` in baseline vs active comparisons.
- `reuseBufferFraction = 1` in the default active run.
- `allFluidFastPathFraction = 1` for TG full-fluid states.
- `uniformMassFastPathFraction = 1` for uniform-mass TG states.
- `downloadedCellVelocitiesFraction = 0` in active mode.

## Interpretation

This patch is not expected to make the whole simulation GPU-fast yet. It removes
avoidable overhead in the active deposit path and prepares the next step: keeping
particle arrays resident on GPU, or moving the next CPU stage that consumes
cell moments onto GPU.
