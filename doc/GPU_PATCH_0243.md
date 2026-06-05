# GPU patch 0243 — active resampling role-only upload benchmark

## Purpose

Patch 0242 proved that the persistent active resampling path is numerically
identical to the CPU baseline when the CPU shadow is kept authoritative and the
full post-edit `download_all()` is skipped.  The remaining overhead is still
largely a host-to-device upload before the CUDA edit.

Patch 0243 adds a deliberately narrow diagnostic mode:

```text
MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_UPLOAD_MODE=roles_only
MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_HOST_SHADOW_AUTHORITATIVE=1
MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_DOWNLOAD_ALL=0
```

In this mode the active-path bridge uploads only `role[]` into the persistent
`CudaParticleState`.  This is sufficient for the current prevalidated
extraction/insertion kernels because:

- extraction checks and mutates only particle role,
- insertion writes all touched particle fields explicitly,
- the CPU shadow remains the authoritative state for the surrounding pipeline,
- no full device-to-host particle download is allowed.

This is **not** the final GPU-owner architecture.  It is a lower-bound benchmark
for the CUDA edit once the full particle-array transfers have been removed.

## Files changed

```text
include/cuda_particle_state.h
src/cuda_particle_state.cu
src/cuda_resampling_persistent_active_path_0240.cpp
scripts/build_src_mpcd_cuda_0243.sh
scripts/run_cuda_resampling_persistent_active_path_0243.sh
doc/GPU_PATCH_0243.md
```

## New API

`CudaParticleState::upload_roles()` allocates the persistent particle buffers if
needed, then refreshes only the device `role[]` array.  It intentionally does not
mark the metadata cache as valid, because mass/type are not refreshed by this
fast path.

## Validation

Run:

```bash
bash scripts/run_cuda_resampling_persistent_active_path_0243.sh
```

The script compares:

```text
cpu_baseline
persistent_active_path_0241_roundtrip
persistent_active_path_0242_shadow
persistent_active_path_0243_roles_only
```

Expected result:

```text
failed_metrics=0
verdict=PASS
```

for 64x64 and 128x128 default cases.

## Interpretation

If `persistent_active_path_0243_roles_only` passes and becomes faster than the
0242 shadow mode, the bottleneck confirmed by 0242 is specifically the full
kinematic upload.  The next production-oriented step is then not another shadow
resampling optimization, but keeping the particle state GPU-owned across at
least streaming/cell moments/resampling so that full host refreshes disappear.
