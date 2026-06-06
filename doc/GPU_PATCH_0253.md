# GPU patch 0253 — persistent SRC collision, wall-simple subset

## Goal

Extend the 0252 persistent SRC collision bridge from the fully periodic
Taylor--Green subset to the deterministic Poiseuille wall-simple subset.

The patch remains intentionally narrow:

- validated case: `poiseuille_wall_full`;
- boundary family: periodic `x`, bounded/solid `y` walls;
- Q6/Q9 remain CPU;
- thermostat remains CPU;
- resampling, streaming wall-simple and shared particle state stay on the
  previously validated CUDA paths;
- stochastic virtual-wall thermal noise is **not** ported in this patch.

The validation runner therefore forces

```bash
WALL_THERMAL_NOISE=0
```

for both CPU baseline and CUDA mode. This validates the bounded cell indexing,
wall-simple streaming composition, deterministic virtual-wall mass/momentum
contribution and shared-state SRC collision without trying to reproduce the
CPU `std::mt19937_64` wall-noise stream on CUDA.

## Main code changes

- `include/cuda_persistent_mpcd_step.h`
  - extends `CudaPersistentMpcdStepConfig` with periodic flags, domain bounds
    and deterministic wall parameters.

- `src/cuda_persistent_mpcd_step.cu`
  - replaces always-periodic cell indexing by periodic/bounded indexing;
  - adds deterministic virtual-wall mass/momentum contribution before cell
    velocity finalization;
  - keeps the real-particle `cellCount` semantics unchanged.

- `src/src_collision.cpp`
  - allows the persistent collision active path on the wall-simple subset when
    `MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1`;
  - rejects wall-simple CUDA collision if `wallThermalNoise != 0`;
  - fills virtual-particle diagnostics when the CUDA collision path returns
    before the CPU collision loop.

- `scripts/run_validation_mono_config_0162.sh`
  - makes `wallThermalNoise` configurable through `WALL_THERMAL_NOISE`, keeping
    the historical default at `1.0`.

## Build

```bash
bash scripts/build_src_mpcd_cuda_0253.sh
```

## Validation

```bash
bash scripts/run_cuda_persistent_src_collision_wall_0253.sh
```

Default validation:

```text
case:  poiseuille_wall_full
grids: 64x64_s300, 128x128_s300
modes: cpu_baseline,
       0251_persistent_cell_moments_wall,
       0253_persistent_src_collision_wall_shared
```

Expected criterion:

```text
verdict=PASS
failed_metrics=0
collisionActiveCalls > 0 for the 0253 mode
collisionSharedParticleStateFraction = 1
collisionSharedCellWorkspaceFraction = 1
```

The output CSV is written to:

```text
dev_history/artifacts/gpu_cuda_src_collision_0253/cuda_persistent_src_collision_0253.csv
```
