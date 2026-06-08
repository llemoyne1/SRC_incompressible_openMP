# 0297 — CUDA post-SRC local population guard

## Scope

Patch 0297 adds the first support-changing CUDA resampling brick after the
validated SRC classic CUDA resident step.  The physical ordering is unchanged:

```text
streaming / boundary conditions / immersed solids / inlet-outlet
-> SRC collision + shift machinery
-> thermostat when enabled
-> optional post-SRC support survey 0295
-> optional mass reconditioning 0296
-> local population guard 0297
-> existing CPU diagnostics/resampling path when enabled
```

The module does not introduce Q6 CUDA and does not replace the existing CPU/Q6
or CPU resampling path.  It only acts when the resident CUDA particle state is
explicitly fresh.  If the CUDA state is stale, 0297 writes a diagnostic row and
skips the mutation instead of uploading an authoritative state from the host.

## Physical interpretation

The guard is a local remeshing of the particle representation produced by SRC.
It is not a source term and it does not impose a new velocity field.  Each local
operation is designed to conserve the cell mass and momentum up to roundoff.

The initial implementation is deliberately limited:

- one local merge at most per rich cell and per application;
- one local split at most per poor cell and per application;
- no long-distance transfer plan;
- no activation in solid cells or outside the active domain;
- no Q6 CUDA coupling.

## Operations

### Rich-cell merge

For a cell with `N_c > Nmax`, the kernel deterministically selects the two
lowest-index fluid particles in that cell.  The second particle is merged into
the first:

```text
m_keep' = m_keep + m_drop
v_keep' = (m_keep v_keep + m_drop v_drop) / m_keep'
role_drop' = Inactive
m_drop' = 0
```

This decreases support by one while preserving the local mass and momentum.

### Poor-cell split

For a wet cell with `0 < N_c < Nmin`, the kernel deterministically selects the
lowest-index fluid donor and the next available inactive slot.  A bounded mass
fraction is moved from the donor to the slot:

```text
dm = min(splitFraction * m_donor, m_donor - minDonorMassAfterSplit)
m_donor' = m_donor - dm
m_slot' = dm
v_slot' = v_donor
role_slot' = Fluid
```

The inserted slot is placed inside the same physical cell, near the donor, with
a fallback to the donor position if the offset would enter a solid.

## Environment controls

The module is disabled by default.

```bash
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY=10
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN=0
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET=20
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX=0
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION=0.5
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_MIN_DONOR_MASS_AFTER_SPLIT=1e-12
```

`NMIN=0` disables poor-cell split.  `NMAX=0` disables rich-cell merge.  The
default validation therefore calls the module in non-triggering mode: diagnostic
rows are written, but no mutation occurs.  Active mutation experiments must set
explicit thresholds.

## Diagnostics

Each guarded run writes:

```text
<outputDir>/cuda_resampling_population_guard_0297.csv
```

Important fields:

```text
poorCells, richCells
mergeApplied, splitApplied
splitSkippedNoInactive, splitSkippedNoDonor, mergeSkippedNoPair
fluidParticlesBefore, fluidParticlesAfter
totalMassBefore, totalMassAfter
totalPxBefore, totalPxAfter
totalPyBefore, totalPyAfter
maxAbsCellMassError, maxAbsCellMomentumError
```

For a conservative local mutation, mass and momentum errors should remain at
roundoff level.  In non-triggering validation, `mergeApplied=0` and
`splitApplied=0` are expected.

## Validation policy

The strict default runner uses the four bit-reproducible witnesses already used
for 0295/0296:

```text
TG periodic
Poiseuille wall
backward step / rectangle
segmented U-box inlet-outlet
```

Von Karman circle + inlet/outlet remains available with `RUN_VK=1`, but it is
not part of the default strict verdict because the thermostat-enabled case was
shown not to be OFF/OFF bit-reproducible.  Use `VK_THERMOSTAT_ENABLE=0` for a
strict optional VK check, or `VK_THERMOSTAT_ENABLE=1` as a non-verdict stress
case.

## Known limitations before 0298

- No local thermal restoration is applied after split/merge.
- Only one split/merge per eligible cell is attempted per application.
- Empty cells are not filled in 0297; there is no long-distance donor search.
- Population targets are approached gradually through repeated applications, not
  enforced in one pass.
- The richer 0298 stage must add explicit mass/momentum/thermal restoration and
  stronger diagnostics for active mutation runs.
