# GPU patch 0252 — persistent CUDA SRC collision on shared 0251 particle state

## Purpose

Patch 0252 starts the CUDA migration of the SRC/MPCD collision stage.  It is deliberately limited to the periodic Taylor--Green subset and keeps Q6/Q9 on CPU.

The key goal is to consume the CUDA particle state already made current by the validated boundary stack, instead of uploading the particles again before the collision/deposit substep.

## What is enabled

For the validation mode `0252_persistent_src_collision_shared`:

- CUDA periodic streaming 0245 is enabled.
- The shared particle state introduced in 0251 must be fresh.
- Persistent CUDA deposit + SRC collision is enabled via `MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1`.
- The collision path consumes `cuda_shared_particle_state_0251()` when `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1`.
- A persistent `CudaCellWorkspace` is used for the cell scratch arrays.
- Final `vx/vy` and the CPU collision workspace arrays are still downloaded so downstream CPU Q6, thermostat and diagnostics remain unchanged.

## What remains CPU

- Q6/Q9 projection.
- Thermostat.
- Virial / capacity response.
- Resampling diagnostics and injection/reservoir logic.
- Non-periodic collision subsets: walls, immersed solids, piston, inlet/outlet.

## Why the external `mpcd_vkkh(1).cu` code was not copied directly

The external CUDA code confirms the useful algorithmic structure:

1. compute cell ids,
2. reduce mass and momentum by cell,
3. compute cell barycentric velocities and rotation signs,
4. rotate relative velocities,
5. write particle velocities.

The production branch already contains an equivalent double-precision persistent implementation aligned with the current CPU conventions, random rotation signs, particle roles and workspace layout.  Patch 0252 therefore reuses the existing production backend instead of importing a separate single-file implementation.

## Run

```bash
bash scripts/run_cuda_persistent_src_collision_0252.sh
```

Default validation:

- `tg_periodic_full`
- `64x64_s300`
- `128x128_s300`

Modes compared:

- `cpu_baseline`
- `0251_persistent_cell_moments`
- `0252_persistent_src_collision_shared`

Expected result:

- `verdict=PASS`
- `failed_metrics=0`

Output CSV:

```text
dev_history/artifacts/gpu_cuda_src_collision_0252/cuda_persistent_src_collision_0252.csv
```

## Main diagnostics

The runner extracts timing and usage from `cuda_persistent_src_collision_thermostat_0215.csv`:

- `collisionActiveCalls`
- `collisionUploadSeconds`
- `collisionKernelSeconds`
- `collisionDownloadSeconds`
- `collisionSharedParticleStateFraction`
- `collisionSharedCellWorkspaceFraction`
- `collisionParticleStateUploadSeconds`
- `collisionCellWorkspaceAllocateSeconds`

A successful 0252 should show `collisionSharedParticleStateFraction≈1` and `collisionParticleStateUploadSeconds≈0` in the CUDA collision mode.

## Safety guards

`MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1` is enabled by default in the runner. If the shared 0251 state is stale, the run fails instead of silently falling back to a hidden upload path.
