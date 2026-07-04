# 0465 — CUDA resampling residency audit

This audit documents the main architectural bottleneck after the validated 0460/0461/0462 CUDA sparse-gate resampling path.

The 0463/0464 scaling probes show that numerical equivalence is preserved as grid size and particle count increase, but the CUDA path does not yet outperform the CPU baseline. The audit therefore focuses on whether the device-carrier path is actually resident or whether it still performs a host/device roundtrip inside every resampling call.

The script `scripts/run_0465_residency_audit.sh` does not modify the solver. It:

- extracts source-level host/device copy sites from `src/cuda_resampling_pipeline_shadow_0445.cu`;
- collects call-site excerpts for the CUDA device-carrier path;
- parses existing `cuda_resampling_device_carrier_0455.csv` files;
- reports the timing fraction due to upload, gate download, state download, materialization, and apply kernels.

Expected conclusion on the current 0461/0464 code path: CUDA kernels are correct and comparatively cheap, but the path is not resident. The dominant costs are state upload, operation/state downloads, and repeated temporary buffer construction around each call.
