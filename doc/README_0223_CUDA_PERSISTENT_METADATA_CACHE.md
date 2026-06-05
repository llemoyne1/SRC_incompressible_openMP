# 0223 — CudaParticleState metadata-cache upload path

This patch optimizes the shared `CudaParticleState` path used by the persistent
CUDA deposit → SRC collision → thermostat substep.

## Motivation

After 0220--0222 the shared particle state is functionally correct and avoids
reallocating device particle buffers, but the real step still uploads all
particle arrays before each persistent CUDA substep. Since CPU transport still
updates `x/y/vx/vy`, those four arrays must still be refreshed every call.
However, `mass`, `type` and `role` often change less frequently.

This patch adds an exact host-side metadata signature and a new upload path:

```text
upload_kinematics_with_cached_metadata(state)
```

It always uploads:

```text
x, y, vx, vy
```

and uploads:

```text
mass, type, role
```

only when their signature has changed or the device allocation has been
rebuilt. If metadata changes, it is reuploaded immediately. Therefore this is a
conservative performance optimization, not a physics change.

## Runtime flag

The shared particle-state path now uses the metadata cache by default:

```bash
MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
```

For ablation / rollback:

```bash
MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=0
```

## Modified files

```text
include/cuda_particle_state.h
src/cuda_particle_state.cu
src/src_collision.cpp
```

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_persistent_particle_state_metadata_cache_0223.sh
```

The harness compares:

```text
cpu_baseline
legacy_internal_upload
shared_particle_state_cache_off
shared_particle_state
```

Expected criteria:

- `verdict=PASS`;
- `failed_metrics=0`;
- `sharedParticleStateFraction=1` for shared modes;
- `particleStateMetadataCacheHitFraction > 0` for `shared_particle_state` when
  metadata is stable across calls;
- no deterioration of physical metrics.

## Interpretation

This patch still keeps CPU transport authoritative between steps. It is not the
final GPU-resident design. It removes one avoidable part of the transfer cost
while preserving exact reupload whenever metadata changes.
