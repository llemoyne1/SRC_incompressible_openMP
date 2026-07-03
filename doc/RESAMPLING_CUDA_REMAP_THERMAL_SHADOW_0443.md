# 0443 — CUDA shadow validator for resampling remap + thermal renormalization

## Purpose

Patch 0443 adds a standalone validator for the two clean-periodic resampling stages that remain active after the transfer/apply chain has been validated:

- local mass/momentum remap;
- local thermal-energy renormalization.

This patch does **not** modify the production solver and does **not** introduce any public runtime parameter. It is a shadow validator only.

## Relation to previous steps

The validated chain is now:

- 0439: CUDA deposit/classification shadow equals CPU;
- 0440: CUDA poor/rich compaction shadow equals CPU;
- 0441: CUDA transfer planner shadow equals CPU;
- 0442: CUDA particle extraction/insertion apply shadow equals CPU;
- 0443: CUDA remap + thermal renormalization shadow equals CPU.

## Scope

The validator uses synthetic periodic, wall-free, no-solid cases:

- shear wave, uniform mass, no grid shift;
- shear wave, uniform mass, shifted grid;
- Taylor--Green, variable mass, no grid shift;
- Taylor--Green, variable mass, shifted grid.

The CPU reference calls the production functions:

```cpp
apply_resampling_local_mass_momentum_remap(...)
apply_resampling_local_thermal_renormalization(...)
```

The CUDA shadow path uses dedicated validator kernels that consume the same `WeightedRealFluidDepositWorkspace` fields: `cellId`, `wetCell`, `count`, `mass`, `ux`, `uy`.

## Acceptance criteria

Expected smoke verdict:

```text
CUDA_RESAMPLING_REMAP_THERMAL_SHADOW_0443 PASS cases=4/4
```

Strict comparisons:

- remap cell count CPU/GPU equal;
- thermal cell count CPU/GPU equal;
- role mismatch zero;
- final mass, velocity and global invariants match to tolerance;
- total mass, momentum and kinetic energy CPU/GPU match to tolerance.

Floating-point differences are expected to remain at roundoff level, with tolerance controlled by `TOL_ABS` and `TOL_REL` in the runner.
