# GPU patch 0280c — resident inlet/outlet + fused CUDA SRC thermostat

## Purpose

Patch 0280c fixes the inlet/outlet resident validators with `THERMOSTAT_ENABLE=true`.

The previous resident inlet/outlet support gates `0263/0264` were still strictly
classic-only and rejected `params.thermostatEnable`. Consequently, enabling the
fused persistent SRC+thermostat validator could prevent the resident inlet/outlet
stream/boundary path from running. In the segmented case this left no fresh shared
CUDA particle state for the fused thermostat consumer, producing an empty
`validation_summary_0162.csv` and the opaque `failed=999999/0` runner verdict.

## Code change

File changed:

- `src/cuda_classic_src_io_resident_0263.cu`

The resident full-face and segmented support predicates now accept
`thermostatEnable=true` only when all of the following are true:

- `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1` is explicitly requested;
- `projectionEnable=false`;
- `resamplingEnable=false`;
- `closedCapacityResponseEnable=false`;
- the thermostat mode is `cell_relative_rescale`;
- `thermostatEvery > 0`.

This preserves the future CPU continuation architecture: Q6, resampling and
virial/capacity remain excluded from the fused classic-only path. Those cases
must continue to use the order validated for piston in 0278:

```text
CUDA SRC -> CPU Q6/resampling/virial -> CUDA post-CPU thermostat
```

## Validators

Added:

- `scripts/build_src_mpcd_cuda_0280c.sh`
- `scripts/run_cuda_persistent_src_thermostat_io_segmented_0280c.sh`
- `scripts/run_cuda_persistent_src_thermostat_io_fullface_0279b.sh`

The segmented validator uses:

```text
CUDA segmented resident stream/boundary 0264
-> fresh shared CUDA particle state 0251
-> fused persistent CUDA SRC+thermostat consumer
```

The full-face 0279b validator is included because 0279 may have passed while the
resident full-face path was still gated off by `thermostatEnable=true`. After the
0280c source fix, 0279b should be used to revalidate the full-face resident path
with the same shared-state fused thermostat discipline.

## Suggested commands

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
unzip -o SRC_GPU_0280c_cuda_thermostat_io_resident_support_files_only.zip

bash scripts/build_src_mpcd_cuda_0280c.sh

GRID_CASES="64:64:120" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_io_segmented_0280c.sh
```

If the smoke passes:

```bash
GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_io_segmented_0280c.sh
```

Then rerun full-face as a regression of the now-true resident path:

```bash
GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_io_fullface_0279b.sh
```

Expected discriminants:

```text
verdict=PASS
failed_metrics=0
fusedSrcThermostatUse=1
sharedThermostat0251_0260=1   # segmented CSV
postCpuThermostatPersistent0258=0
thermostatGpuAppliedFraction=1
thermostatKBTAfterMean ~= 1e-3
```
