# GPU patch 0284 — static immersed circle for SRC classic CUDA

Patch 0284 adds the first CUDA fast path for a fixed circular immersed solid.
It is intentionally scoped to the validated SRC classic subset and does not
change the Q6/resampling/virial architecture.

## Scope

Validated target:

```text
periodic box
+ static circular immersed solid
+ SRC classic = advection/streaming + shift + SRC rotation/collision + thermostat
+ CUDA particle state / cell workspace
+ fused persistent CUDA SRC+thermostat
```

Out of scope for 0284:

```text
moving or rotating circles
circle + inlet/outlet Von Karman
segmented inlet/outlet + circle
Q6 CUDA
resampling/virial CUDA integration
```

Those remain later patches. 0284 prepares the geometry and collision support
needed by the future Von Karman fast path, but the first validation is periodic
so that reflection, virtual solid fraction and thermostat can be isolated.

## Main implementation points

- New CUDA reflection path:
  - `include/cuda_immersed_circle_0284.h`
  - `src/cuda_immersed_circle_0284.cu`
- The kernel mirrors the CPU circle logic in `immersed_solid.cpp`: any fluid
  particle found inside the circle after streaming is radially mirrored outside
  the circle and its velocity is reflected relative to the local solid velocity.
  This is deliberately not a segment-circle intersection yet, in order to keep
  CPU/CUDA equivalence strict for the first validation.
- The persistent SRC collision config now carries circular-solid parameters.
- `cuda_persistent_mpcd_step.cu` now computes an immersed-circle cell solid
  fraction using the same sub-cell sampling strategy as the rectangle path and
  adds the corresponding virtual wall mass/momentum contribution on GPU.
- `src_collision.cpp` accepts a circular immersed solid when
  `MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=1`.
- `scripts/generate_validation_state_0162.py` and
  `scripts/run_validation_mono_config_0162.sh` gain a
  `periodic_circle_obstacle_classic` case for CPU/CUDA comparisons.

## Validation

Build:

```bash
bash scripts/build_src_mpcd_cuda_0284.sh
```

Smoke:

```bash
GRID_CASES="64:64:120" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_circle_0284.sh
```

Longer discriminant run:

```bash
GRID_CASES="64:64:300 128:128:300" \
FORCE_REBUILD=0 \
bash scripts/run_cuda_persistent_src_thermostat_circle_0284.sh
```

Output:

```text
dev_history/artifacts/gpu_cuda_persistent_src_thermostat_circle_0284/cuda_persistent_src_thermostat_circle_0284.csv
```

Expected criteria:

```text
verdict=PASS
failed_metrics=0
compared_metrics>0
thermostatGpuAppliedFraction=1
thermostatKBTAfterMean close to 1e-3
```

## Important architectural guard

This patch does not make the liquid closure a CUDA path.  The terminology stays:

```text
SRC classic = advection/streaming + shift + SRC rotation/collision + thermostat
liquid closure = SRC classic + Q6 + resampling + virial
```

0284 extends the SRC classic CUDA path. Q6/resampling/virial remain separated so
that CPU/OpenMP reactivation and later CUDA migration are preserved.
