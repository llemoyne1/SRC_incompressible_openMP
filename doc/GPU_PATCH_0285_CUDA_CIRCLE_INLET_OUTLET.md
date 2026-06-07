# GPU patch 0285 — circular immersed solid on the full-face inlet/outlet CUDA SRC classic path

## Scope

Patch 0285 extends the 0284 static circular immersed-solid CUDA path to the
full-face inlet/outlet resident CUDA path used for Von Karman-type channel runs.
The scope remains SRC classic only:

```text
advection / streaming
+ random grid shift
+ SRC rotation / collision
+ thermostat
```

The liquid closure remains separate and is not migrated here:

```text
SRC classic + Q6 + resampling + virial
```

Q6, resampling and virial/capacity are explicitly disabled by the validation and
demonstration runners.  The patch must not be interpreted as a Q6 CUDA or liquid
closure CUDA migration.

## Main implementation changes

`src/cuda_classic_src_io_resident_0263.cu` now carries the circular immersed
solid in the inlet/outlet resident configuration.  The hard reservoir exclusion
logic, previously rectangle-aware only, now rejects reservoir cells whose centers
fall inside the circular obstacle:

```text
(x_c - C_x)^2 + (y_c - C_y)^2 <= R^2
```

This prevents the CUDA inlet reservoir from inserting particles directly into
the cylinder.  The same geometry predicate is used by the host-side segmented
pool pre-pass and the device-side reservoir kernels.

The rest of the path reuses the 0284 components:

```text
full-face inlet/outlet resident CUDA
+ CUDA circular immersed-solid reflection
+ persistent CUDA SRC collision with circular virtual-wall contribution
+ fused persistent CUDA thermostat
```

## New validation case

`scripts/run_validation_mono_config_0162.sh` gains:

```text
open_circle_obstacle_classic
```

This is a left-inlet/right-outlet channel with a static circular immersed solid.
It is intended for classic SRC validation only when the runner sets:

```text
PROJECTION_ENABLE=false
RESAMPLING_ENABLE=false
THERMOSTAT_ENABLE=true
```

## Build

```bash
bash scripts/build_src_mpcd_cuda_0285.sh
```

The default binary is:

```text
build/src_mpcd_base_cuda_0285
```

## Validation

Smoke:

```bash
GRID_CASES="64:64:120" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_circle_io_0285.sh
```

Heavier discriminant validation:

```bash
GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_circle_io_0285.sh
```

Expected summary:

```text
dev_history/artifacts/gpu_cuda_persistent_src_thermostat_circle_io_0285/cuda_persistent_src_thermostat_circle_io_0285.csv
```

Expected discriminants:

```text
verdict=PASS
failed_metrics=0
ioFullfaceResidentFlag=1
immersedCircleFlag=1
fusedSrcThermostatUse=1
thermostatGpuAppliedFraction=1
thermostatKBTAfterMean ≈ target kBT
```

## Demonstration run

```bash
bash scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh
```

Default output:

```text
runs/demo_src_classic_cuda_von_karman_cylinder_0285/output
```

The script writes dumps every 100 steps by default for animation:

```text
DUMP_STATE_EVERY=100
SUMMARY_EVERY=100
```

## Limitations

0285 validates a fixed circular obstacle with full-face x inlet/outlet. It does
not yet add:

```text
moving/rotating circles
segmented inlet/outlet + circle
Q6 CUDA
resampling CUDA in the liquid closure
virial/capacity CUDA closure
```

Those remain separate future work items.
