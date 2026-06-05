# 0210 — CUDA SRC collision shadow validation in the real step

## Purpose

This patch integrates the validated CUDA SRC rotation kernel from 0209 as a **shadow validator** inside the real `src_collision_step`.

The CPU/OpenMP collision remains the only path that updates the simulation state.  When shadow mode is enabled, the code copies the pre-collision particle state, applies the same SRC rotation on the GPU, and compares the CUDA post-collision velocities to the CPU post-collision velocities.

## Runtime controls

Shadow mode is off by default.

```bash
MPCD_CUDA_SRC_COLLISION_SHADOW=1
```

Optional controls:

```bash
MPCD_CUDA_SRC_COLLISION_SHADOW_EVERY=1
MPCD_CUDA_SRC_COLLISION_SHADOW_TOL=1e-12
MPCD_CUDA_SRC_COLLISION_SHADOW_STRICT=1
MPCD_CUDA_SRC_COLLISION_THREADS_PER_BLOCK=256
```

## Scope

Included:

- CUDA SRC collision shadow mode in `src_collision_step`;
- exact reuse of CPU-computed `cellId`, `cellUx`, `cellUy`, `cosA`, `sinA`;
- comparison of CPU and CUDA post-collision velocities;
- timing and mismatch CSV written per run;
- TG validation harness for 64x64 and 128x128.

Excluded:

- active CUDA collision path;
- GPU generation of rotation signs;
- persistent GPU particle state;
- replacement of the CPU collision in production runs.

## Files

```text
src/src_collision.cpp
scripts/build_src_mpcd_cuda_0210.sh
scripts/run_cuda_src_collision_shadow_0210.sh
doc/README_0210_CUDA_SRC_COLLISION_SHADOW.md
dev_history/artifacts/gpu_cuda_collision_0210/cuda_src_collision_shadow_manifest_0210.csv
dev_history/artifacts/gpu_cuda_collision_0210/cuda_src_collision_shadow_scope_0210.csv
```

The patch assumes the 0209 standalone files are already present:

```text
include/cuda_src_collision.h
src/cuda_src_collision.cu
```

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
bash scripts/build_src_mpcd_cuda_0210.sh
```

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_BACKEND=cpu \
bash scripts/run_cuda_src_collision_shadow_0210.sh
```

The consolidated output is:

```text
dev_history/artifacts/gpu_cuda_collision_0210/cuda_src_collision_shadow_0210.csv
```

Each run also writes:

```text
runs/cuda_src_collision_shadow_0210_<grid>/tg_periodic_full/cuda_src_collision_shadow_0210.csv
```

## Acceptance criteria

For each case:

```text
verdict = PASS
failed_metrics = 0
velocityMismatches = 0
invalidCellParticles = 0
maxAbsVx, maxAbsVy ~ roundoff
```

## Next step

If 0210 passes, the next patch can add an active CUDA SRC collision path under an explicit runtime flag:

```bash
MPCD_CUDA_SRC_COLLISION_USE=1
```

This should still be tested separately before attempting a persistent GPU particle state shared by deposit, collision, and thermostat.
