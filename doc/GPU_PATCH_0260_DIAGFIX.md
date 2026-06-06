# GPU patch 0260 diagnostic fix — resident classic CUDA resampling diagnostics

This fix addresses the `0260_periodic_resident_classic_cuda` validation failure where
only the disabled-resampling diagnostic metrics differed:

- `resampStdN`
- `resampMRelRms`
- `resampMRelMaxAbs`

The 0260 resident path intentionally keeps `ParticleState` on the GPU between runtime
summaries.  The runtime summary still computes disabled-resampling diagnostics from the
host `ParticleState`; therefore those diagnostics were stale/zero in the optimized run.

The fix synchronizes the shared CUDA particle state back to the host only when disabled-
resampling diagnostics are requested, which in the production loop happens only on
summary/final steps.  It does not add a per-step download in the resident path.

Apply and rerun:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
unzip -o gpu_patch_0260_diagfix_files_only.zip
bash scripts/run_cuda_classic_src_periodic_resident_0260.sh
```

Expected result: `0260_periodic_resident_classic_cuda` should pass with
`failed_metrics=0` for TG periodic.
