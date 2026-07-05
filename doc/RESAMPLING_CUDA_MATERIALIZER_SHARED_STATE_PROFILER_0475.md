# 0475 — CUDA operation materializer shared-state path + phase profiler

## Objective

Patch 0475 follows 0474. The 0474 result showed that the CPU transfer-plan timing is small and that the next suspect is not the final 0473 commit, but the intermediate CUDA operation materializer / orchestration path.

0475 therefore keeps:

- 0471 direct-state commit,
- 0472 shared CUDA state fast sync,
- 0473 host patchback fast commit,
- 0474 shared-state upstream gate,

and changes the 0453 operation materializer so it can consume the process-local shared `CudaParticleState` instead of allocating and uploading a private full particle state for the materializer pass.

## New flag

```bash
MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475=1
```

When this flag is enabled, `try_apply_cuda_resampling_operation_materializer_0453(...)` uses `cuda_shared_particle_state_0251()` as the materializer input.

If the shared state is fresh and matches the current host particle count, the materializer skips the full particle H2D upload. If it is not fresh, it performs a guarded upload into the shared state and marks it fresh.

## Compact materializer download

The legacy 0453 materializer downloaded the full `maxOps = nActive` output arrays and then kept only the first `nOps` operations.

0475 adds a shared-state materializer variant that downloads only:

- the 1-element operation count and invalid counter,
- the first `nOps` entries of the materialized operation payload.

This is reported by:

```text
materializerCompactDownload0475
```

## New CSV columns

0475 extends `cuda_resampling_operation_materialize_0453.csv` with:

```text
materializerSharedState0475
materializerUploadSkipped0475
materializerCompactDownload0475
stateUploadSeconds0475
planUploadSeconds0475
```

`uploadSeconds` remains the total upload-like time seen by the materializer path. With the shared path, it is mostly the compact transfer-plan upload plus any guarded fallback state upload.

## Runner

```bash
scripts/run_0475_materializer_shared_state_profiler.sh
```

The runner enables:

```bash
MPCD_INTERNAL_PROFILES=1
MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1
MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1
MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=1
MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474=1
MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475=1
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=1
```

Default case is intentionally reduced to:

```bash
SCALE_CASES="128x128x40"
```

because the current development objective is fast iteration on the largest currently informative case.

## Expected output

```text
runs/0475_materializer_shared_state_profiler/materializer_shared_state_profiler_report_0475.md
runs/0475_materializer_shared_state_profiler/materializer_shared_state_profiler_summary_0475.csv
```

A successful run should show:

```text
PASS-like rows: 2/2
mat_shared > 0
mat_upload_skipped > 0 if the shared state is fresh
mat_compact_dl > 0
mat_max_state_upload_s = 0 when fresh
carrier max upload/download = 0/0
```

## Interpretation

0475 is not expected to finish the full-resident migration by itself. Its purpose is to remove another hidden private upload/download in the 0453 materializer gate and to expose the remaining phase-level wall-time using `phase_profile_0163.csv`.

If wall-time remains close to 0473/0474 while materializer state upload is removed, the next patch should target broader step orchestration or GPU-authoritative operation application rather than transfer-plan construction alone.
