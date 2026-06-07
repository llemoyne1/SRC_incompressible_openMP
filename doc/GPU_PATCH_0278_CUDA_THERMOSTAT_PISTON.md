# GPU patch 0278 — CUDA thermostat piston/mobile-wall validation

## Scope

Patch 0278 adds a piston/mobile-wall validator for the CUDA thermostat stage.
It does not modify CUDA kernels.

The important distinction is the physical ordering. For `piston_virial_full`, the
simulation may run CPU Q6/projection, resampling and closed-capacity virial/capacity
operations between SRC collision and thermostat. Therefore 0278 intentionally does
not use the fused persistent SRC collision + thermostat path:

```text
MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
```

Instead it validates the post-CPU-stage persistent thermostat path:

```text
CUDA piston/mobile-wall streaming 0247b
+ CUDA persistent SRC collision 0255
+ CPU Q6/resampling/capacity/virial stages when enabled
+ CUDA persistent cell-relative thermostat 0258
```

This preserves future reactivation of CPU/OpenMP Q6, CUDA/CPU resampling, virial,
and later Q6 CUDA. The fused classic-only fast paths remain separate and are not
used for the piston-capacity validation.

## Files

```text
scripts/build_src_mpcd_cuda_0278.sh
scripts/run_cuda_persistent_src_thermostat_piston_0278.sh
doc/GPU_PATCH_0278_CUDA_THERMOSTAT_PISTON.md
```

## Smoke test

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
unzip -o SRC_GPU_0278_cuda_thermostat_piston_files_only.zip

bash scripts/build_src_mpcd_cuda_0278.sh

GRID_CASES="64:64:120" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_piston_0278.sh
```

## Extended check

```bash
GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_piston_0278.sh
```

## Output

```text
dev_history/artifacts/gpu_cuda_persistent_src_thermostat_piston_0278/cuda_persistent_src_thermostat_piston_0278.csv
```

Expected discriminants:

```text
verdict=PASS
failed_metrics=0
postCpuThermostatPersistent0258=1
fusedSrcThermostatUse=0
thermostatActiveCalls > 0
thermostatKBTAfterMean close to target kBT
```

## Notes

The default validator keeps `PROJECTION_ENABLE=true` and `RESAMPLING_ENABLE=true`
so that the piston test remains representative of the physical piston/capacity
pipeline. It is not a Q6 CUDA development patch; Q6 CUDA remains a separate future
work package.
