# GPU patch 0280b — segmented inlet/outlet thermostat runner fix

## Scope

Patch 0280b fixes the segmented inlet/outlet thermostat validator introduced in
0280.  The 0280 smoke failed before producing a usable comparison because the
CUDA validation summary was empty.  The stderr artifact only exposed the final
comparison symptom, not the underlying case log.

No CUDA kernel is changed in 0280b.

## Runner correction

For the resident segmented case, the 0264 boundary path leaves the shared CUDA
particle state fresh after streaming and reservoir/boundary handling.  The fused
SRC+thermostat consumer should therefore be the same kind of shared-state
consumer as in the validated 0260 periodic resident runner:

```text
CUDA segmented stream/boundary/reservoir
→ shared-state fused persistent CUDA SRC+thermostat
```

The 0280 runner also requested the collision-only shared consumer.  That is not
needed when `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1`, because the thermostat
consumer already performs deposit + SRC collision + thermostat.  In 0280b the
CUDA mode therefore uses:

```bash
MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0
```

This keeps the segmented support route unambiguous and still exercises the
fused CUDA SRC+thermostat path.

## Diagnostics improvement

If the validation still fails, the runner appends a failure context block to the
stderr log, including:

- line count and tail of `validation_summary_0162.csv`;
- line count and tail of `segmented_u_turn_full/summary_runtime.csv`;
- tail of `segmented_u_turn_full.log`;
- contents of `segmented_u_turn_full.time`.

This avoids the opaque `failed=999999/0` report without the actual binary log.

## Validation commands

Smoke test:

```bash
GRID_CASES="64:64:120" FORCE_REBUILD=0 bash scripts/run_cuda_persistent_src_thermostat_io_segmented_0280b.sh
```

Discriminant validation:

```bash
GRID_CASES="64:64:300 128:128:300" FORCE_REBUILD=0 bash scripts/run_cuda_persistent_src_thermostat_io_segmented_0280b.sh
```

Expected summary:

```text
dev_history/artifacts/gpu_cuda_persistent_src_thermostat_io_segmented_0280b/cuda_persistent_src_thermostat_io_segmented_0280b.csv
```

Expected criteria:

```text
verdict=PASS
failed_metrics=0
fusedSrcThermostatUse=1
sharedThermostat0251_0260=1
postCpuThermostatPersistent0258=0
thermostatGpuAppliedFraction=1
thermostatKBTAfterMean ≈ target kBT
```

## Architecture constraints preserved

The runner disables Q6/resampling/virial only for this classic-only validation
subset.  It does not remove or bypass the future paths needed for Q6 CPU/OpenMP,
resampling CUDA/CPU, virial/capacity response, or future Q6 CUDA.
