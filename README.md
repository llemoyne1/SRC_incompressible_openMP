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

### Patch 0123 — bounded particle-mass guard and local renormalization

Patch 0123 adds an optional mass-safety stage after extraction, insertion,
local mass remap and optional thermal renormalization:

```text
resamplingMassGuardEnable = false
resamplingParticleMassMin = 0.25
resamplingParticleMassMax = 4.0
```

When enabled, each non-empty wet cell solves a bounded local mass projection:

```text
m_min <= m_p <= m_max,
Σ_p m_p = M_target
```

when the constraint is feasible.  The projected masses are the closest bounded
masses to the current values under an additive Lagrange multiplier.  The stage
then recenters and rescales velocities so the local cell velocity `U_c` and the
relative thermal energy `E_th,c` measured before mass projection are restored.
Thus the guard is not a simple clamp: it is a bounded local `M,U,E_th`
renormalization stage.

Smoke test:

```bash
./scripts/run_resampling_mass_guard_smoke_0123.sh
```

Expected diagnostic core:

```text
belowBefore>0 aboveBefore>0 belowAfter=0 aboveAfter=0 MRelRms~1e-16
```

See `doc/README_0123_RESAMPLING_MASS_GUARD.md`.

### Patch 0124 — controlled wet/latent activation

Patch 0124 adds an optional latent-particle activation stage:

```text
resamplingLatentActivationEnable = false
resamplingLatentActivationMaxPerCell = 1
resamplingLatentActivationParticleMass = 0.0   # <=0: M_target / maxPerCell
```

When enabled, the stage converts preallocated `Latent` slots into `Fluid`
particles inside poor wet receiver cells, with empty wet cells treated first.
It does not consume `Inactive` free-list slots, so conservative donor/receiver
recycling remains separate from explicit wet/dry filling.  Newly activated
particles inherit their `type`/species from the latent slot, are positioned by a
deterministic in-cell stencil, and use the receiver cell velocity if available
or zero velocity in empty wet cells.  The stage is disabled by default.

Smoke test:

```bash
./scripts/run_resampling_latent_activation_smoke_0124.sh
```

Expected diagnostic core:

```text
activated=4 cells=1 fluid=128 latent=1 inactive=3 MRelRms=0
```

See `doc/README_0124_RESAMPLING_LATENT_ACTIVATION.md`.


## 0125 integrated resampling validator

- `scripts/run_resampling_integrated_void_rich_latent_smoke_0125.sh`: integrated void/rich/latent validator for activation, recycle, remap, thermal renormalisation and mass guard. See `doc/README_0125_RESAMPLING_INTEGRATED_VOID_RICH_LATENT.md`.

## 0126 periodic Taylor--Green resampling validation

Patch 0126 adds the first dynamic, fully periodic validation for the OpenMP
resampling branch.  It provides a MATLAB V2 `.smpcd` Taylor--Green initial-state
generator, MATLAB V1/V2 state readers/writers, fluid-only field binning for
role-aware dumps, a bash runner for `classic`, `q6` and `q6_resampling`, and a
MATLAB analyzer with visible figures and CSV summaries.

Main command:

```bash
./scripts/run_taylor_green_resampling_validation_0126.sh
```

Useful larger run:

```bash
TG_NX=64 TG_NY=64 TG_GAMMA=20 TG_STEPS=3000 TG_DUMP_EVERY=100 TG_THREADS=8 \
./scripts/run_taylor_green_resampling_validation_0126.sh
```

The main post-processing output is:

```text
runs/taylor_green_resampling_0126/analysis/tg_summary.csv
```

See `doc/README_0126_TAYLOR_GREEN_RESAMPLING_VALIDATION.md`.

## 0129 resampling cadence and global switch

Patch 0129 separates the three operational levels explicitly:

```text
resamplingEnable = true/false                 # gates role-changing resampling
resamplingMassRenormalizationPeriod = K        # K=1 old behaviour, K>1 periodic, K=0 disabled
resamplingThermalRenormalizationEnable = true  # thermal renormalisation is attempted every step
```

When `resamplingEnable=false`, the mutating resampling path is bypassed even if
individual sub-switches remain present in `params.kv`.  When enabled, extraction,
insertion and latent activation can operate every step, while mass remap and mass
guard are only applied on steps satisfying `step % K == 0`.  The thermal
renormalisation remains per-step so discrete role changes do not create an
uncontrolled thermal drift between mass-remap events.

Smoke test:

```bash
./scripts/run_resampling_cadence_smoke_0129.sh
```

See `doc/README_0129_RESAMPLING_CADENCE_AND_SWITCH.md`.

## Resampling branch milestone 0130: Taylor--Green forcing

The C++ runtime now supports an optional periodic Taylor--Green body acceleration:

```text
taylorGreenForcingEnable = true
taylorGreenForcingAmplitude = 0.02
taylorGreenForcingModeX = 1
taylorGreenForcingModeY = 1
```

The forcing is divergence-free and only available for fully periodic Taylor--Green
validation runs. MATLAB remains responsible for preparing initial `.smpcd` files;
bash launchers only write `params.kv` and run the OpenMP executable. See
`doc/README_0130_TAYLOR_GREEN_FORCING.md`.

### 0132 — Resampling performance triage

Patch 0132 removes the first major performance bottleneck in the weighted-resampling path. The full donor/receiver mutation plan is now built only once per step, before role-changing operations. Post-edit deposits are lightweight diagnostics. The planner also avoids the previous donor×receiver Cartesian sort and uses a cell→particle index for donor particle selection. See `doc/README_0132_RESAMPLING_PERFORMANCE_TRIAGE.md`.

### 0133 thermal renormalization performance fix

Patch 0133 removes an accidental `O(Ncells*Nparticles)` diagnostic loop from
resampling thermal renormalization.  The operation remains physically unchanged,
but the post-renormalization momentum residual is accumulated in the particle
loop and reduced over cells.  This is essential for Poiseuille/channel cases
where thermal renormalization runs every step.

### Patch 0140 — MATLAB-compatible population-support guard

Patch 0140 restores the MATLAB `Nmin/Ntarget/Nmax` support-control mechanism in the OpenMP resampling branch.  Since patch 0144, this stage is no longer controlled by a separate `resamplingPopulationGuardEnable` key: `resamplingEnable=true` activates the population-driven support guard, while `resamplingPopulationNMin/NTarget/NMax` set the support band.  Under-populated wet cells are locally split up to `Ntarget`, over-populated wet cells are merge-extracted down to `Ntarget`, and mass/momentum are preserved locally by construction.  This separates support control (`N_c`) from weighted-mass remap (`M_c`) and avoids the previous failure mode where `M_c` was correct but the active particle support became too sparse.


### Patch 0144 — explicit projection/resampling switches

Patch 0144 removes the historical `method=classic/q6` selector from the active
OpenMP resampling branch.  Q6 is now controlled only by:

```text
projectionEnable = true|false
```

and the population-driven weighted resampling chain is controlled only by:

```text
resamplingEnable = true|false
```

This gives the four intended ablation modes:

```text
projectionEnable=false, resamplingEnable=false  # classic SRC/MPCD
projectionEnable=false, resamplingEnable=true   # classic SRC + population support guard
projectionEnable=true,  resamplingEnable=false  # Q6 projection only
projectionEnable=true,  resamplingEnable=true   # Q6 + weighted resampling
```

The former `resamplingPopulationGuardEnable` key is also removed.  When
`resamplingEnable=true`, the population guard is active and is configured by
`resamplingPopulationNMin`, `resamplingPopulationNTarget`, and
`resamplingPopulationNMax`; set all three to positive increasing values for an
explicit band, or set all three to `0` to infer defaults from the target cell
mass.  See `doc/README_0144_EXPLICIT_PROJECTION_RESAMPLING_SWITCHES.md`.
