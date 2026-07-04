# 0470 — Resident upstream-coupled CUDA resampling probe

This patch adds a diagnostic shadow probe that couples the CUDA upstream deposit with the 0467 resident carrier core using the same caller-owned `CudaParticleState`.

It is intentionally not yet a full upstream replacement. The normal 0468 transaction path remains responsible for the actual solver mutation and host commit.

The probe performs:

1. Upload a shadow `CudaParticleState` once.
2. Run `cuda_deposit_cell_moments_atomic_from_persistent_state` on that same resident state.
3. Compare the downloaded CUDA cell moments against the CPU `WeightedRealFluidDepositWorkspace` cell moments.
4. Run `apply_gpu_particle_edits_device_carrier_resident_0467(..., downloadState=false)` on the same resident state.
5. Write `cuda_resampling_resident_upstream_0470.csv`.

Success means the same resident device particle state can drive both the upstream CUDA deposit and the resident carrier core without a final particle-state download. It does not yet remove the CPU transfer-plan authority.

Main flag:

```bash
MPCD_CUDA_RESAMPLING_RESIDENT_UPSTREAM_COUPLED_PROBE_0470=1
```

The probe is designed to be run together with:

```bash
MPCD_CUDA_RESAMPLING_RESIDENT_EXTERNAL_CARRIER_0467B=1
MPCD_CUDA_RESAMPLING_DEFER_RESIDENT_DOWNLOAD_0468=1
```
