# GPU patch 0279 — CUDA thermostat full-face inlet/outlet aware

## Scope

Patch 0279 adds a validation runner for the CUDA persistent SRC + thermostat path on the `open_rect_obstacle_full` full-face inlet/outlet case.

No CUDA kernel is modified by this patch. It depends on the 0276 thermostat fix, where the fused CUDA thermostat reconstructs its moments from real post-collision particles instead of reusing collision moments contaminated by virtual wall/solid particles.

## Physical order validated

For this classic-only inlet/outlet case, the intended order is:

```text
CUDA full-face inlet/outlet resident boundary path
+ CUDA rectangle/wall handling where applicable
+ CUDA persistent SRC collision
+ CUDA persistent fused cell-relative thermostat
```

Q6, resampling and virial are disabled only for this discriminant validation. This does not remove or lock out the future mixed path:

```text
CUDA boundary/SRC
-> CPU Q6/resampling/virial continuation when requested
-> CUDA persistent post-CPU thermostat 0258 when physically appropriate
```

## Files

```text
scripts/build_src_mpcd_cuda_0279.sh
scripts/run_cuda_persistent_src_thermostat_io_fullface_0279.sh
doc/GPU_PATCH_0279_CUDA_THERMOSTAT_IO_FULLFACE.md
```

## Smoke test

```bash
bash scripts/build_src_mpcd_cuda_0279.sh

GRID_CASES="64:64:120" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_io_fullface_0279.sh
```

## Extended short validation

```bash
GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_io_fullface_0279.sh
```

## Output

```text
dev_history/artifacts/gpu_cuda_persistent_src_thermostat_io_fullface_0279/cuda_persistent_src_thermostat_io_fullface_0279.csv
```

Expected discriminants:

```text
verdict=PASS
failed_metrics=0
fusedSrcThermostatUse=1
postCpuThermostatPersistent0258=0
thermostatGpuAppliedFraction=1
thermostatKBTAfterMean close to target
```
