# 0112 — Weighted real-fluid deposit diagnostics

This milestone adds the first non-mutating weighted-resampling core module to
`openMP-resampling`.

## Scope

Patch 0112 introduces a real-fluid weighted deposit and diagnostics only.  It
must not perform extraction, insertion, recycling, mass clipping, thermal
renormalization, or particle-pool remapping yet.

The new module is deliberately separate from `CollisionWorkspace`:

- `CollisionWorkspace` remains the SRC/MPCD effective collision deposit.  It may
  include wall virtual particles and immersed-solid virtual particles when wall
  accommodation is active.
- `WeightedRealFluidDepositWorkspace` is the resampling deposit.  It includes
  only particles with `role=Fluid` and excludes latent/inactive slots, wallVP,
  and immersed-solid VP.

This distinction is essential because wallVP mass is a collision bath, not
transported fluid mass.

## New files

- `include/weighted_resampling.h`
- `src/weighted_resampling.cpp`
- `scripts/run_weighted_resampling_deposit_smoke_0112.sh`
- `doc/README_0112_WEIGHTED_REAL_FLUID_DEPOSIT.md`

## Runtime fields

`summary_runtime.csv` now contains a `resamp*` block:

- `resampComputed`
- `resampNFluid`, `resampNLatent`, `resampNInactive`
- `resampNonEmptyCells`, `resampEmptyCells`
- `resampMeanN`, `resampStdN`, `resampMinN`, `resampMaxN`
- `resampTotalMass`, `resampMeanMass`, `resampStdMass`, `resampMinMass`, `resampMaxMass`
- `resampTargetCellMass`, `resampMRelRms`, `resampMRelMaxAbs`
- `resampParticleMassMean`, `resampParticleMassStd`, `resampParticleMassRelStd`,
  `resampParticleMassMin`, `resampParticleMassMax`
- `resampMeanUx`, `resampMeanUy`, `resampCellUxRms`, `resampCellUyRms`

`resampTargetCellMass <= 0` means the diagnostic uses the current mean real-cell
mass as reference.  A positive value can be prescribed with:

```text
resamplingTargetCellMass = <mass>
```

or the alias:

```text
weightedResamplingTargetCellMass = <mass>
```

## Validation

Run:

```bash
./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection
./scripts/run_resampling_minimal_src_q6_smoke_0110.sh
./scripts/run_particle_roles_smoke_0111.sh
./scripts/run_weighted_resampling_deposit_smoke_0112.sh
```

The 0112 smoke creates 8x8 cells with four real fluid particles per cell and
masses `[0.5, 1.0, 1.5, 2.0]`, so each real-fluid cell has mass exactly 5.  It
also adds latent and inactive particles with huge masses outside the domain and
activates solid-wall virtual particles.

Expected outcome:

```text
resampTotalMass = 320
resampMeanN = 4
resampStdN = 0
resampMeanMass = 5
resampStdMass = 0
resampMRelRms = 0
virtualMass > 0
```

The key check is that `virtualMass` is positive while `resampTotalMass` remains
exactly 320.  This proves that the new deposit excludes wall virtual mass.

## Next milestone

Patch 0113 can add the inactive/free-pool infrastructure around the existing
`role` field, still without recycling.  Patch 0114 can then implement the first
local rich/sparse cell detector using the real-fluid deposit from this patch.
