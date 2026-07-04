# 0467A — Minimal resident-core refactor for CUDA resampling

This patch is the first architectural step after the 0465/0466 residency audits.

It does **not** claim full CUDA-resident resampling yet. Instead, it extracts the validated 0455/0460/0461 device-carrier implementation into a new core routine that operates on a caller-provided `CudaParticleState&`.

## What changes

Before 0467A, the device-carrier routine created a local CUDA particle state and performed its own state roundtrip:

```text
CudaParticleState local
upload_all(host ParticleState)
materialize/apply CUDA
optional gate/downloads
download_all(host ParticleState)
```

After 0467A, the carrier logic is split into:

```text
apply_gpu_particle_edits_device_carrier_resident_0467(CudaParticleState&, ParticleState&, ...)
```

and the legacy entry point remains as a compatibility wrapper:

```text
apply_gpu_particle_edits_device_carrier_0455(ParticleState&, ...)
```

The wrapper still uploads and downloads, so existing solver behavior is unchanged. The new resident core does not allocate a local `CudaParticleState` and does not call `upload_all` internally.

## Why this matters

0465 and 0466 showed that the current CUDA path is dominated by host/device roundtrips and the CPU-authoritative transaction wrapper, not by the particle-edit kernels.

0467A creates the architectural seam required for the next step:

```text
upload once / keep CudaParticleState resident / apply resampling edits / download only at chosen boundaries
```

## Validation target

The 0467A probe should show:

- CPU/CUDA numerical equivalence remains PASS-like.
- Device-carrier CSV rows have `residentCore0467=1`.
- Performance is expected to remain close to 0466 because the legacy wrapper still performs upload/download.

This patch is therefore a refactor validation, not a speedup patch.
