# 0215 — persistent CUDA SRC collision + thermostat substep

This patch extends the validated 0214 persistent CUDA SRC collision path to an
experimental `deposit -> SRC collision -> cell-relative thermostat` GPU substep.

The intent is to avoid the separated sequence of CUDA calls that repeatedly
uploads/downloads the same particle arrays. The new path uploads particle state
once, performs deposition, cell-mean finalization, SRC rotation and thermostat on
the GPU, then downloads final velocities and CPU workspace cell moments.

## Runtime switch

The default remains CPU. The new path is enabled with:

```bash
MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
```

The older 0214 collision-only path remains available with:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
```

If both are disabled, the existing CPU/OpenMP path is used.

## Supported subset

The 0215 path is deliberately strict. It is intended for the periodic TG subset
without any CPU velocity operator between collision and thermostat:

- periodic x/y;
- full fluid domain;
- no wall virtual particles;
- no immersed solid;
- `projectionEnable=false` for this first integration;
- closed-capacity/virial velocity kicks disabled;
- `thermostatEnable=true` and `thermostatMode=cell_relative_rescale`.

The `projectionEnable=false` restriction is important. In the current global step
order, Q6 projection and capacity response sit between collision and thermostat.
Applying the thermostat inside the persistent collision substep would otherwise
move it before those CPU velocity operators and change the numerical method.

## Validation harness

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_persistent_src_thermostat_active_0215.sh
```

The harness compares a CPU baseline against the persistent CUDA SRC+thermostat
path and writes:

```text
dev_history/artifacts/gpu_cuda_persistent_0215/cuda_persistent_src_collision_thermostat_0215.csv
```

Expected criteria:

- `verdict=PASS`;
- `failed_metrics=0`;
- `invalidCellParticles=0`;
- `thermostatAppliedCalls` equals the number of active steps for the tested
  configuration;
- `thermostatKBTAfterLast` is close to the thermostat target.

## Rationale

This patch is not yet the final GPU-resident step. It is a controlled bridge from
validated individual kernels to a persistent device-resident particle state. The
next necessary step is to keep particle arrays resident across the full step and
teach Q6/projection or other velocity operators to either consume device arrays
or explicitly synchronize only the fields they modify.
