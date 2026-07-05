# 0472 — Shared-state fast sync for CUDA resampling direct commit

This patch accelerates the validated 0471 direct-state commit path by using the process-local shared `CudaParticleState` (`cuda_shared_particle_state_0251`) when requested.

## Motivation

0471 removed the CPU rollback copy `ParticleState tmp = state`, but the CUDA resampling path still performed one host-to-device upload and one final device-to-host download per handled resampling step.

0472 attacks this remaining overhead in two conservative ways:

1. If `MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1`, the 0471 direct-commit path uses the shared CUDA particle state instead of a newly allocated local `CudaParticleState`.
2. If the shared state is already fresh at the resampling point, the upload is skipped.
3. If `MPCD_CUDA_RESAMPLING_ACTIVE_PREFIX_DOWNLOAD_0472=1`, the successful commit downloads only the active prefix rather than the full particle capacity.

The path remains transaction-safe: the host `ParticleState` is only overwritten after the resident carrier gate/apply status passes.

## Safety notes

The patch also adds conservative invalidations of the shared-state freshness marker for CPU-side resampling edits that can make the shared device mirror stale:

- population support guard edits;
- latent activation edits;
- CPU fallback extraction/insertion;
- remap/thermal/mass-guard edits not performed on the shared state.

This keeps the shared-state optimization opportunistic. If the device mirror is not fresh, 0472 uploads the current host state into the shared CUDA state before applying the resident core.

## Flags

```bash
MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1
MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1
MPCD_CUDA_RESAMPLING_ACTIVE_PREFIX_DOWNLOAD_0472=1
```

The 0472 runner sets these flags automatically.

## Expected validation

The scaling probe should preserve the strict CPU/CUDA equivalence of 0471:

- summary deltas at roundoff level;
- `residentDirectCommit0471=1` on handled rows;
- `residentSharedState0472=1` on handled rows;
- `residentActivePrefixDownload0472=1` on handled rows;
- `residentSharedUploadSkipped0472=1` when the shared state was already fresh.

Performance gain depends on whether the shared CUDA state is fresh at the resampling point. When it is fresh, upload cost should drop to nearly zero for those rows.
