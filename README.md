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

### Patch 0114 — wet/dry and poor/rich cell classification

Patch 0114 adds passive cell masks for the future resampling core:

```text
activeCell, wetCell, dryCell, poorCell, richCell, targetBandCell
```

The default wet-mask mode is `active_domain`, so a void pocket inside the
active fluid domain is classified as a poor wet cell rather than ignored as dry.
The optional `occupied` mode is reserved for later injection/free-surface tests.

Smoke test:

```bash
./scripts/run_resampling_cell_classification_smoke_0114.sh
```

Expected diagnostic core:

```text
wet=32 dry=0 poor=2 rich=1 emptyWet=1 targetBand=29
```

See `doc/README_0114_RESAMPLING_CELL_CLASSIFICATION.md`.

### Patch 0115 — passive donor/receiver candidate lists

Patch 0115 turns the 0114 masks into deterministic passive lists for the future
resampling operator:

```text
receiverPoorCells      = wet cells below the poor threshold
donorRichCells         = wet cells above the rich threshold
emptyWetReceiverCells  = poor wet cells with N_c = 0
```

The patch also reports deficit/excess diagnostics relative to
`resamplingTargetCellMass`, plus a lower-bound pool sufficiency flag
`resampPoolCanSeedReceivers`.  No particle is moved and the free-list is not
consumed.

Smoke test:

```bash
./scripts/run_resampling_candidate_lists_smoke_0115.sh
```

Expected diagnostic core:

```text
receivers=2 donors=1 emptyReceivers=1 deficit=7 excess=4 potential=4 poolCanSeed=1
```

See `doc/README_0115_RESAMPLING_CANDIDATE_LISTS.md`.

### Patch 0116 — passive local donor/receiver transfer plan

Patch 0116 keeps the candidate lists passive but converts them into a
non-mutating local transfer plan.  All donor/receiver cell pairs are sorted by
periodic-aware grid distance; the planner greedily assigns the minimum of donor
excess and receiver deficit.

The plan records only cell-level intentions:

```text
resampTransferPairs
resampPlannedTransferMass
resampRemainingReceiverDeficitAfterPlan
resampRemainingDonorExcessAfterPlan
resampTransferMeanCellDistance
resampTransferMaxCellDistance
```

No particle is moved, no mass is changed, no role is changed and the inactive
pool is not consumed.

Smoke test:

```bash
./scripts/run_resampling_transfer_plan_smoke_0116.sh
```

Expected diagnostic core:

```text
transferPairs=2 planned=4 remainingReceiver=3 remainingDonor=0 coverage=0.5714285714285714
```

See `doc/README_0116_RESAMPLING_TRANSFER_PLAN.md`.

### Patch 0117 — passive donor particle selection

Patch 0117 keeps the 0116 transfer plan passive but selects deterministic
candidate particle indices from rich donor cells.  The selection follows the
ordered donor→receiver transfer entries and scans true `Fluid` particle indices
in increasing order, skipping particles already selected by earlier plan
entries.

The selected set is diagnostic only:

```text
no particle is moved
no mass is changed
no role is changed
no inactive pool slot is consumed
no remap is applied
```

The diagnostic block records the selected donor mass and any overshoot produced
by particle indivisibility:

```text
resampDonorParticleSelectionBuilt
resampSelectedDonorParticles
resampDonorCellsWithSelectedParticles
resampSelectedDonorParticleMass
resampSelectedDonorMassOvershoot
resampSelectedDonorMassCoverageFraction
```

Smoke test:

```bash
./scripts/run_resampling_donor_particle_selection_smoke_0117.sh
```

Expected diagnostic core:

```text
selected=4 selectedMass=4 overshoot=0 coverage=1 firstParticle=1 lastParticle=4
```

See `doc/README_0117_RESAMPLING_DONOR_PARTICLE_SELECTION.md`.

### Patch 0118 — passive extraction operation plan

Patch 0118 converts the passive donor-particle selection from 0117 into an
explicit extraction-operation list.  Each operation records which true `Fluid`
particle would later be extracted from a donor cell, the receiver cell attached
to that transfer entry, and the carried mass, momentum and kinetic energy.

This is still diagnostic only:

```text
no particle role is changed
no particle is moved
no particle mass is changed
no inactive pool slot is consumed
no remap is applied
```

The new diagnostic block records:

```text
resampExtractionPlanBuilt
resampExtractionOps
resampExtractionParticles
resampExtractionMass
resampExtractionMomentumX
resampExtractionMomentumY
resampExtractionKineticEnergy
resampHypotheticalPoolFreeSlotsAfterExtraction
resampExtractionAllSelectedAreFluid
resampExtractionNoDuplicateParticles
```

Smoke test:

```bash
./scripts/run_resampling_passive_extraction_smoke_0118.sh
```

Expected diagnostic core:

```text
ops=4 particles=4 mass=4 coverage=1 poolAfter=11 allFluid=1 noDup=1
```

See `doc/README_0118_RESAMPLING_PASSIVE_EXTRACTION.md`.

### Patch 0119 — mutating extraction Fluid -> Inactive

Patch 0119 is the first deliberately mutating resampling step.  It adds the
parameter:

```text
resamplingExtractionEnable = false
```

The default is `false`, so all classic SRC/Q6 runs and all passive resampling
smokes remain unchanged.  When enabled, the code applies the passive extraction
operations prepared in 0118 by converting selected donor particles:

```text
Fluid -> Inactive
```

No insertion, mass remap, momentum remap, or renormalisation is performed yet.
After the role mutation, the inactive pool is rebuilt and the real-fluid deposit
is recomputed, so the runtime summary reports the post-extraction transported
fluid plus a separate `resampExtractionApply*` diagnostic block.

Smoke test:

```bash
./scripts/run_resampling_mutating_extraction_smoke_0119.sh
```

Expected diagnostic core:

```text
applied=4 mass=4 fluid=121 inactive=11 poolFree=11 richAfter=0
```

See `doc/README_0119_RESAMPLING_MUTATING_EXTRACTION.md`.

### Patch 0120 — controlled insertion Inactive -> Fluid

Patch 0120 adds the first controlled mutating insertion step.  It introduces:

```text
resamplingInsertionEnable = false
```

The option is disabled by default and currently requires
`resamplingExtractionEnable = true`.  When both switches are enabled, the code
first applies the 0119 extraction plan (`Fluid -> Inactive`), then immediately
reactivates the extracted free-list slots into receiver cells:

```text
Inactive -> Fluid
```

The inserted particles preserve the mass, momentum and `type` carried by the
corresponding extraction operation.  Positions are assigned deterministically in
the receiver cell using a small interior stencil.  This is intentionally still a
minimal recycling step: no local mass/momentum remap, no thermal correction and
no renormalisation are applied yet.

Smoke test:

```bash
./scripts/run_resampling_mutating_insertion_smoke_0120.sh
```

Expected diagnostic core:

```text
inserted=4 mass=4 fluid=125 inactive=7 poolFree=7 poorAfter=1
```

See `doc/README_0120_RESAMPLING_MUTATING_INSERTION.md`.

### Patch 0121 — local mass/momentum remap after insertion

Patch 0121 adds the first local remap stage after controlled extraction and
insertion.  It introduces:

```text
resamplingRemapEnable = false
```

The option is disabled by default and currently requires both
`resamplingExtractionEnable = true` and `resamplingInsertionEnable = true`.
When enabled, the code applies the 0119/0120 extraction-insertion cycle, builds
the post-edit real-fluid deposit, then remaps each non-empty wet cell by a
uniform mass scale:

```text
m_p <- s_c m_p,      s_c = M_target / M_c
```

Particle velocities are not changed in this first remap patch.  Therefore each
remapped cell satisfies `M_c -> M_target` while preserving its cell velocity
`U_c`; the target cell momentum is consequently `M_target U_c`.  Full thermal
renormalisation / preservation of `E_th,c` remains a later patch.

Smoke test:

```bash
./scripts/run_resampling_local_remap_smoke_0121.sh
```

Expected diagnostic core:

```text
remappedCells=2 particles=125 MRelRms~2e-17 scaleMin<1 scaleMax>1
```

See `doc/README_0121_RESAMPLING_LOCAL_REMAP.md`.

### Patch 0122 — local thermal renormalization

Patch 0122 adds the optional switch
`resamplingThermalRenormalizationEnable`.  When extraction, insertion and local
mass remap are enabled, this final local stage rescales velocities relative to
cell velocity so the pre-remap relative thermal energy `E_th,c` is restored while
preserving `M_c` and `U_c`.  Validate with:

```bash
./scripts/run_resampling_thermal_renormalization_smoke_0122.sh
```
