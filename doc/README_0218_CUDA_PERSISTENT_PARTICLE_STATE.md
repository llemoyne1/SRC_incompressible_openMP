# 0218 — Persistent CUDA particle-state manager

This patch starts the architectural transition from independent CUDA bricks to a shared resident particle state.

Until now, each CUDA component owned its own transfers:

```text
cell moments CUDA      : upload particles -> deposit -> download moments
SRC collision CUDA     : upload particles/moments -> rotate -> download velocities
thermostat CUDA        : upload particles/moments -> rescale -> download velocities
persistent 0215 path   : local persistent substep, but not a reusable state object
```

Patch 0218 introduces `CudaParticleState`, an owning CUDA cache for the particle SoA arrays:

```text
x, y, vx, vy, mass, type, role
```

The class provides explicit upload/download methods and exposes a raw `CudaParticleDeviceView` for later kernels. This patch does **not** yet modify `src_collision_step`; it creates the state-management layer that the next integration patches can consume.

## New files

```text
include/cuda_particle_state.h
src/cuda_particle_state.cu
src/main_validate_cuda_particle_state_0218.cpp
scripts/build_cuda_particle_state_0218.sh
scripts/run_cuda_particle_state_smoke_0218.sh
doc/README_0218_CUDA_PERSISTENT_PARTICLE_STATE.md
dev_history/artifacts/gpu_cuda_persistent_0218/*.csv
```

## Build and smoke test

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU

CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:64:20 128:128:20' \
CYCLES=25 \
bash scripts/run_cuda_particle_state_smoke_0218.sh
```

The validator uploads the particle arrays once, reuses the allocation, applies repeated device-side velocity increments only to fluid particles, then downloads velocities once. It checks that latent/inactive particles are untouched and that positions remain unchanged.

Expected output:

```text
CUDA_PARTICLE_STATE_0218 PASS
```

Main output:

```text
dev_history/artifacts/gpu_cuda_persistent_0218/cuda_particle_state_smoke_0218.csv
```

## Validation criteria

```text
pass = 1
velocityMismatches = 0
maxAbsVx, maxAbsVy <= tolerance
allocationCalls = 1
reusedAllocation = 1
```

## Scope

This is an infrastructure patch. It does not change the CPU reference path and does not yet replace the active 0215/0216/0217 CUDA paths.

The next patch should connect the existing deposit/collision/thermostat CUDA kernels to this shared state so that `vx/vy`, `cellId`, and cell moments are not transferred between every CUDA brick.
