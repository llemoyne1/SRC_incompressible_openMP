# GPU patch 0258 — persistent CUDA thermostat after CUDA SRC collision

## Purpose

Patch 0258 extends the validated CUDA collision stack by moving the cell-relative
rescale thermostat to CUDA, while preserving the physical order of the production
step:

```text
streaming / boundary CUDA
→ cell moments / SRC collision CUDA
→ Q6 / Q9 CPU
→ closed-capacity / virial CPU
→ thermostat CUDA 0258
→ keep-mean-flow / diagnostics CPU
```

This patch is deliberately not the older combined `collision+thermostat` path:
that path is only safe when no CPU velocity operator is inserted between collision
and thermostat. In the current physical cases, Q6/Q9 and virial kicks remain CPU,
so 0258 applies the thermostat at the normal thermostat phase, after those CPU
operators.

## New switch

```bash
MPCD_CUDA_THERMOSTAT_PERSISTENT_0258=1
```

The standard standalone CUDA thermostat switch remains available:

```bash
MPCD_CUDA_THERMOSTAT_USE=1
```

but the 0258 runner uses only the persistent 0258 mode.

## Implementation notes

The new primitive is:

```cpp
cuda_apply_cell_relative_rescale_thermostat_from_shared_state_0258(...)
```

It reuses:

- `CudaParticleState` for particle arrays,
- `CudaCellWorkspace` for `cellId`, `cellKinetic`, `cellScale`, and counters,
- the existing CUDA kernels for kinetic energy, scale computation and rescale.

Because Q6/Q9 and virial closure are still CPU, current velocities are uploaded
before the thermostat. However, mass/type/role metadata can be cached by
`CudaParticleState`, and the cell workspace allocation is persistent.

## Validation runner

```bash
bash scripts/run_cuda_persistent_src_collision_thermostat_0258.sh
```

Default cases:

```text
tg_periodic_full
poiseuille_wall_full
open_rect_obstacle_full
piston_virial_full
```

Default grids:

```text
64x64_s300
128x128_s300
```

Modes compared:

```text
cpu_baseline
0257_minimal_collision_download
0258_persistent_collision_thermostat
```

The output CSV is:

```text
dev_history/artifacts/gpu_cuda_src_collision_0258/cuda_persistent_src_collision_thermostat_0258.csv
```

## Expected result

The required correctness criterion is unchanged:

```text
verdict = PASS
failed_metrics = 0
```

The useful performance diagnostics are:

```text
thermostatTotalSeconds
thermostatUploadSeconds
thermostatKineticKernelSeconds
thermostatScaleKernelSeconds
thermostatApplyKernelSeconds
thermostatDownloadSeconds
```

## Limitations

This is still a hybrid CPU/GPU path. Since Q6/Q9 and virial closure remain CPU,
0258 cannot yet avoid an upload of current post-Q6 velocities before the
thermostat. The expected gain is therefore modest; the main goal is to validate
the next brick in the GPU chain and quantify whether the thermostat can be moved
without breaking equivalence.
