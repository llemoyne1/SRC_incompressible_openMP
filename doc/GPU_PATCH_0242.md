# GPU patch 0242 — active-path transfer isolation

## Purpose

Patch 0241 proved that the active resampling path can delegate the extraction
and insertion edit lists to the 0239 persistent `CudaParticleState` kernels while
preserving the CPU validation summaries.

The 0241 timings still include a full particle-state upload and full particle-
state download around the local edit.  Patch 0242 isolates that transfer cost.
It adds an optional host-shadow-authoritative mode:

```text
CPU builds the exact extraction/insertion edit plan
CPU applies the same edit to its shadow state for deterministic continuation
GPU applies the validated 0239 kernels to CudaParticleState
full device-to-host particle download can be skipped
```

This is not yet the final GPU-owner architecture.  It is a controlled bridge
mode to measure and remove one avoidable synchronization while the rest of the
SRC/MPCD step remains CPU-owned.

## New environment switches

```bash
MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_UPLOAD_MODE=all|cached
MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_DOWNLOAD_ALL=0|1
MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_HOST_SHADOW_AUTHORITATIVE=0|1
```

Defaults preserve the 0241 behavior:

```bash
UPLOAD_MODE=all
DOWNLOAD_ALL=1
HOST_SHADOW_AUTHORITATIVE=0
```

The 0242 performance/isolation mode used by the runner is:

```bash
UPLOAD_MODE=cached
DOWNLOAD_ALL=0
HOST_SHADOW_AUTHORITATIVE=1
```

`cached` uses `CudaParticleState::upload_kinematics_with_cached_metadata()`.  It
keeps x/y/vx/vy refreshed from the CPU-owned step and uploads mass/type/role only
when the exact host-side metadata signature changes.

## Files changed

```text
include/cuda_resampling_persistent_active_path_0240.h
src/cuda_resampling_persistent_active_path_0240.cpp
scripts/build_src_mpcd_cuda_0242.sh
scripts/run_cuda_resampling_persistent_active_path_0242.sh
doc/GPU_PATCH_0242.md
```

## Validation

```bash
bash scripts/run_cuda_resampling_persistent_active_path_0242.sh
```

The runner compares, for each grid:

1. `cpu_baseline`
2. `persistent_active_path_0241_roundtrip` — GPU edit + full `download_all`
3. `persistent_active_path_0242_shadow` — GPU edit + no full `download_all`

The output table is written to:

```text
dev_history/artifacts/gpu_cuda_resampling_0242/cuda_resampling_persistent_active_path_0242.csv
```

Expected result:

```text
PASS on 64x64 and 128x128
failed_metrics = 0
compared_metrics > 0 for both CUDA modes
```

## Interpretation

If 0242 shadow mode is faster than 0241 roundtrip mode while preserving the
validation summaries, then the full D2H copy was a measurable overhead.  The next
migration step should then move upstream ownership rather than continuing to add
local wrappers:

```text
0243: explicit transfer/profile counters in summaries and logs
0244: CUDA streaming for periodic TG
0245: GPU cell populations / moments as the common owner of resampling inputs
```
