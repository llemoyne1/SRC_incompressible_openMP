# 0466A — CUDA resampling transaction timing

This patch instruments the CPU-authoritative transaction wrapper around the CUDA resampling device-carrier path.

It does not change solver behavior. The purpose is to split the complete wrapper cost into:

- `tmpCopySeconds`: `ParticleState tmp = state`
- `deviceCarrierSeconds`: `apply_gpu_particle_edits_device_carrier_0455(tmp, ...)`
- `stateCommitSeconds`: `state = std::move(tmp)`
- `wrapperTotalSeconds`: full wrapper time around the accepted/rejected CUDA transaction

The device-carrier internal timings are copied into the same CSV for comparison:

- `deviceUploadSeconds`
- `deviceGateDownloadSeconds`
- `deviceStateDownloadSeconds`
- `deviceMaterializeSeconds`
- `deviceApplySeconds`

The resulting per-run CSV is:

```text
cuda_resampling_transaction_0466.csv
```

The validation runner summarizes these files into:

```text
transaction_timing_report_0466.md
transaction_timing_summary_0466.csv
```

Expected interpretation:

- If `tmpCopySeconds` is significant, the CPU transactional copy is part of the scaling bottleneck.
- If `deviceUploadSeconds + deviceStateDownloadSeconds` dominates, the next target is persistent `CudaParticleState` residency.
- If `deviceApplySeconds` remains small, particle-edit kernels are not the limiting step.
