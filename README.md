# SRC/MPCD C++ OpenMP — resampling baseline

This branch is a deliberately reduced OpenMP baseline for porting the weighted
resampling core validated in the MATLAB prototype.  The active solver keeps the
smallest useful hydrodynamic core:

- classical compressible SRC/MPCD: `method = classic`;
- Q6 velocity projection: `method = q6` or `projectionEnable = true`;
- periodic, solid-wall and inlet/outlet particle boundary conditions;
- wall virtual particles for no-slip/thermal wall coupling;
- analytic immersed solids, including circle and rectangle/backward-step masks;
- mass-aware cell thermostat;
- runtime summaries and `.smpcd` state dumps.

Q9 mass-flux projection and the optional virial/EOS pressure kick are not active
on this branch.  The executable now rejects `method = q9`, `method = q9_virial`
and Q9/virial parameter keys.  Their source files should be removed from the
branch with the cleanup commands documented in `doc/README_0110_OPENMP_RESAMPLING_MINIMAL_SRC_Q6_CORE.md`.

## Build

```bash
./scripts/build_src_mpcd_base.sh
```

The build creates:

```text
build/src_mpcd_base
build/validate_elliptic_projection
```

Run the elliptic-core validation with:

```bash
./build/validate_elliptic_projection
```

## Minimal smoke validation

A self-contained smoke script generates a small `.smpcd` state with Python,
runs a short periodic classical SRC case, then runs the same case with Q6:

```bash
./scripts/run_resampling_minimal_src_q6_smoke_0110.sh
```

Expected checks:

```text
classic run completes
q6 run completes
summary_runtime.csv contains no q9* or virial* columns
q6DivAfterProjectedFluxRms is finite and small in the q6 summary
```

## Supported method keys

```text
method = classic
method = q6
```

For Q6:

```text
projectionOperator = periodic_fv_cg | channel_fv_cg | auto_fv_cg | elliptic_fv_cg
projectionMaxIterations = 300
projectionTolerance = 1.0e-10
q6ProjectionStrength = 1.0
projectionMomentumCorrectionEnable = true
```

For immersed solids with Q6, keep the validated mask path:

```text
immersedSolidEnable = true
projectionImmersedSolidMaskEnable = true
projectionImmersedSolidCloseCutFaces = true
```

Moving immersed solids are intentionally rejected when the Q6 mask is active.

## Why this reduction exists

The weighted-resampling port should first target a clean core:

```text
streaming
particle boundary conditions
immersed-solid reflection
weighted SRC collision
Q6 projection
thermostat
diagnostics
```

This avoids mixing the new resampling logic with the older Q9/virial liquid
closure.  The next patches can add particle roles, real-fluid weighted deposit,
free-pool infrastructure, local extraction/insertion and mass/momentum remap on
top of this reduced baseline.

## Resampling branch milestone 0111: particle roles

The `openMP-resampling` branch now distinguishes particle `type` from particle
`role`. `type` remains the physical/material species identifier; `role` is the
algorithmic state used by the future weighted-resampling core:

```text
Inactive = 0, Fluid = 1, Latent = 2
```

Legacy `.smpcd` V1 states are still readable and are normalized as all `Fluid`.
New dumps are emitted as `.smpcd` V2 with an explicit role array. Current fluid
operators act only on `Fluid` particles; `Latent` and `Inactive` slots are stored
but dormant. See `doc/README_0111_PARTICLE_ROLES_MASKS.md`.

Validation:

```bash
./scripts/run_particle_roles_smoke_0111.sh
```

### 0112 — weighted real-fluid deposit diagnostics

The branch now includes a first non-mutating resampling deposit:

```text
WeightedRealFluidDepositWorkspace
```

It accumulates per cell, using only particles with `role=Fluid`:

```text
N_c, M_c, P_x,c, P_y,c, U_x,c, U_y,c
```

It deliberately excludes wall virtual particles and immersed-solid virtual
particles, unlike the SRC collision effective deposit.  The runtime summary now
contains `resamp*` diagnostics, including `resampMRelRms` and
`resampParticleMassRelStd`.  Validate with:

```bash
./scripts/run_weighted_resampling_deposit_smoke_0112.sh
```

See `doc/README_0112_WEIGHTED_REAL_FLUID_DEPOSIT.md`.

### Patch 0113 — resampling inactive pool/free-list

The resampling branch now rebuilds a passive particle pool from particle roles:
`Fluid`, `Latent`, and `Inactive`.  `Inactive` slots form the future free-list for
particle insertion, while `Latent` slots are tracked separately and are not treated
as free.  This patch remains diagnostic/passive: it does not activate, deactivate,
insert, extract, or remap particles.  See
`doc/README_0113_RESAMPLING_INACTIVE_POOL.md`.
