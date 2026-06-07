# GPU patch 0280 — CUDA thermostat for segmented inlet/outlet

## Scope

Patch 0280 validates the thermostat-aware persistent CUDA SRC path on the
segmented inlet/outlet case:

- validation case: `segmented_u_turn_full`;
- CUDA segmented inlet/outlet resident path: `MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1`;
- persistent CUDA SRC collision enabled;
- fused persistent CUDA thermostat enabled;
- Q6, resampling, and virial/capacity response disabled only for this classic-only validator.

No CUDA kernel is changed in 0280. The patch adds a targeted validator and build
alias. The physical thermostat correction introduced for wall/solid cases in
0276 is reused.

## Physical ordering

For this classic-only segmented inlet/outlet subset, there is no CPU Q6,
resampling, or virial stage between collision and thermostat. Therefore the
validated target order is:

```text
CUDA segmented stream/boundary/reservoir
→ CUDA persistent SRC collision
→ CUDA fused persistent cell-relative thermostat
```

This is deliberately distinct from piston/full-method cases, where the validated
ordering remains:

```text
CUDA SRC collision
→ CPU Q6/resampling/virial or capacity response
→ CUDA post-CPU thermostat
```

## Shared-state detail

The segmented resident boundary path keeps the CUDA shared particle state fresh.
The 0280 validator therefore enables the shared-state fused thermostat consumer:

```bash
MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
```

This avoids making the segmented validation depend on a stale host upload after
the GPU inlet/outlet boundary stage.

## Validation commands

Smoke test:

```bash
GRID_CASES="64:64:120" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_io_segmented_0280.sh
```

Discriminant short validation:

```bash
GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_io_segmented_0280.sh
```

Expected summary:

```text
dev_history/artifacts/gpu_cuda_persistent_src_thermostat_io_segmented_0280/cuda_persistent_src_thermostat_io_segmented_0280.csv
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

The validator disables Q6/resampling/virial only to exercise the classic-only
fusion point. It does not remove or bypass the future paths needed for:

- Q6 CPU/OpenMP after CUDA SRC;
- resampling CUDA/CPU;
- virial/capacity response;
- future Q6 CUDA.
