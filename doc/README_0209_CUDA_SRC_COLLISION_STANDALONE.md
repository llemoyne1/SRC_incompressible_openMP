# 0209 — CUDA SRC collision rotation standalone validator

## Purpose

This patch starts the CUDA port of the SRC/MPCD collision kernel.  It is deliberately limited to a standalone validator and does not modify the production time step.

The validated CUDA operation is the per-particle SRC rotation around already-computed cell moments:

```text
cellId[i], cellUx[c], cellUy[c], cosA[c], sinA[c]
        ↓
v_i <- u_c + R_c (v_i - u_c)
```

The CPU/OpenMP simulation path is unchanged.

## Why this order

The collision kernel is the next meaningful GPU target after:

- CUDA Q6 projection,
- CUDA particle-to-cell moments,
- CUDA cell-relative thermostat.

It is also a necessary step before a persistent GPU particle state becomes profitable: once deposit, collision and thermostat can operate on device, repeatedly copying the particle state to/from the GPU becomes avoidable.

## Scope

Included:

- CUDA per-particle SRC rotation kernel;
- CPU reference implementation in the standalone validator;
- support for mixed roles (`Fluid`, `Latent`, `Inactive`);
- support for variable mass;
- per-cell random rotation signs supplied from the host;
- checks of CPU/GPU velocity agreement;
- checks of cell momentum and relative kinetic-energy conservation.

Excluded for now:

- integration into `src_collision_step`;
- GPU generation of random rotation signs;
- virtual particles / wallVP / immersed-solid contributions;
- persistent GPU particle state;
- RNG parity with the full CPU step beyond externally supplied `cosA/sinA` arrays.

## Files

```text
include/cuda_src_collision.h
src/cuda_src_collision.cu
src/main_validate_cuda_src_collision_0209.cpp
scripts/build_cuda_src_collision_0209.sh
scripts/run_cuda_src_collision_smoke_0209.sh
dev_history/artifacts/gpu_cuda_collision_0209/cuda_src_collision_standalone_manifest_0209.csv
dev_history/artifacts/gpu_cuda_collision_0209/cuda_src_collision_standalone_scope_0209.csv
```

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
bash scripts/build_cuda_src_collision_0209.sh
```

## Smoke validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:64:20 128:128:20' \
bash scripts/run_cuda_src_collision_smoke_0209.sh
```

The output is written to:

```text
dev_history/artifacts/gpu_cuda_collision_0209/cuda_src_collision_smoke_0209.csv
dev_history/artifacts/gpu_cuda_collision_0209/cuda_src_collision_smoke_0209.log
```

Expected verdict:

```text
CUDA_SRC_COLLISION_0209 PASS
```

## Acceptance criteria

For the default smoke cases:

```text
velocityMismatches = 0
invalidCellParticles = 0
particlesRotated = fluidParticles
maxAbsVx, maxAbsVy <= 1e-12
maxCpuGpuMomentumDiff <= 1e-10
maxCpuGpuEnergyDiff <= 1e-10
```

The CPU and CUDA particle velocities should agree to roundoff because the kernel applies an independent per-particle formula with no reductions.

## Next step

If 0209 passes, the next patch should add a shadow mode inside `src_collision_step`:

```text
CPU collision remains active
CUDA collision applies the same rotation to a copied pre-collision state
CPU/CUDA post-collision velocities and cell diagnostics are compared
```

Only after that should we add an active runtime flag for CUDA collision.  Persistent GPU particle state should follow once deposit, collision and thermostat are all active and validated.
