# 0214 — CUDA persistent SRC collision workspace moment fix

Patch 0213 activated a persistent CUDA substep for the periodic Taylor--Green collision phase:

```text
upload particles once -> CUDA deposit -> CUDA cell velocity finalization -> CUDA SRC rotation -> download vx/vy + cellId
```

The velocity path was physically correct, but the CPU `CollisionWorkspace` was returned with zeroed cell occupancy/moment arrays. As a result, summary diagnostics such as `meanN`, `stdN`, `minN`, and `maxN` failed even though momentum, kinetic energy, Q6, and resampling diagnostics were consistent.

Patch 0214 extends the persistent collision API so that the CUDA backend also downloads the cell arrays computed during the persistent deposit:

```text
cellId
cellCount
cellMass
cellUx
cellUy
```

`src_collision_step` now restores these arrays before returning from the persistent active path. The intended effect is diagnostic/workspace restoration only; the particle velocities produced by the CUDA SRC rotation are unchanged.

## Runtime flag

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
```

The subset remains deliberately restricted to periodic, full-fluid Taylor--Green-like cases without wall virtual particles, immersed solids, or open boundaries.

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_BACKEND=cpu \
bash scripts/run_cuda_persistent_src_collision_active_0214.sh
```

Expected:

```text
verdict = PASS
failed_metrics = 0
meanN/stdN/minN/maxN match CPU baseline
invalidCellParticles = 0
```
