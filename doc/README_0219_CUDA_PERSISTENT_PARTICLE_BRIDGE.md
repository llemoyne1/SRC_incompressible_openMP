# 0219 — CUDA persistent particle-state bridge

This patch is the first wiring step after `CudaParticleState` (0218).

It adds an overload of the persistent TG substep that consumes an already
resident `CudaParticleState` instead of allocating and uploading its own
particle buffers. The substep still allocates transient cell buffers and still
performs a final controlled download of `vx/vy` and CPU workspace moments so the
current host-side code can continue unchanged.

## Scope

Validated path:

```text
CudaParticleState upload_all once
  -> persistent deposit
  -> persistent SRC collision
  -> persistent cell-relative thermostat
  -> final velocity/workspace download
```

The patch is intentionally standalone. It does not yet modify the production
simulation step or keep the cell workspace persistent across timesteps.

## Why this step matters

Previous CUDA bricks were correct but each brick owned its own uploads and
downloads. This patch verifies that the persistent substep can operate directly
on shared particle buffers. That is the prerequisite for a real GPU-resident
step.

## Build and run

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:64:20 128:128:20' \
CYCLES=5 \
bash scripts/run_cuda_persistent_particle_bridge_smoke_0219.sh
```

Main output:

```text
dev_history/artifacts/gpu_cuda_persistent_0219/cuda_persistent_particle_bridge_smoke_0219.csv
```

Expected criteria:

```text
PASS
allocationCalls = 1
reusedAllocation = 0 for initial upload; no extra particle allocation in the substep
cpuVelocityMismatches = 0
legacyVelocityMismatches = 0
cellIdMismatches = 0
countMismatches = 0
invalidCellParticles = 0
```

`legacyVelocityMismatches = 0` checks equivalence against the previous
allocation-owning persistent CUDA path. `cpuVelocityMismatches = 0` checks
agreement with the scalar CPU reference used in earlier standalone validators.

## Next step

If 0219 passes, the next patch should move this shared-state path into a guarded
real-step mode, likely with one `CudaParticleState` kept alive across multiple
SRC/MPCD steps for the periodic TG subset.
