# Patch 0117 — passive donor particle selection

Patch 0117 adds the last passive step before an actual extraction operator: a
non-mutating selection of candidate donor particle indices.

The previous patch 0116 produced a continuous cell-level transfer plan:

```text
donor rich cell -> receiver poor cell, plannedMass
```

Patch 0117 now selects concrete `role=Fluid` particle slots from the donor
cells, following this plan.  The selection is deliberately passive: it never
changes positions, velocities, masses, roles, pool lists or cell moments.

## Deterministic selection rule

For each transfer-plan entry, in order:

1. take the donor cell and planned continuous mass;
2. scan particle indices in increasing order;
3. keep only true `Fluid` particles whose resampling deposit cell is the donor;
4. skip particles already selected by an earlier entry;
5. select until the accumulated selected mass for this entry reaches or exceeds
   the planned mass.

This deterministic rule gives stable smoke tests and reproducible diagnostics.
It is not yet the final extraction policy; later patches may replace the scan by
per-cell particle lists, randomised selection, or weighted sampling.

## Indivisibility and overshoot

The transfer plan is continuous in mass, but particles are still indivisible at
this stage.  Therefore the selected donor mass can be larger than the planned
mass.  Patch 0117 measures this explicitly:

```text
resampSelectedDonorParticleMass
resampSelectedDonorMassOvershoot
resampSelectedDonorMassCoverageFraction
resampDonorParticleSelectionExactOrOvershoot
resampDonorParticleSelectionUnderfilled
```

The future active extraction/remap patch will use this information to preserve
mass and momentum exactly after moving or recycling slots.

## New runtime columns

```text
resampDonorParticleSelectionBuilt
resampSelectedDonorParticles
resampDonorCellsWithSelectedParticles
resampMaxSelectedParticlesForTransferEntry
resampMaxSelectedParticlesPerDonorCell
resampFirstSelectedDonorParticle
resampLastSelectedDonorParticle
resampFirstSelectedDonorCell
resampLastSelectedDonorCell
resampFirstSelectedReceiverCell
resampLastSelectedReceiverCell
resampSelectedDonorParticleMass
resampSelectedDonorMassOvershoot
resampSelectedDonorMassCoverageFraction
resampSelectedDonorMeanParticleMass
resampSelectedDonorMaxParticleMass
resampDonorParticleSelectionExactOrOvershoot
resampDonorParticleSelectionUnderfilled
```

## Smoke test

```bash
./scripts/run_resampling_donor_particle_selection_smoke_0117.sh
```

Expected core output:

```text
donor selection: selected=4 selectedMass=4 overshoot=0 coverage=1 firstParticle=1 lastParticle=4

[0117 resampling donor particle selection smoke] OK: passive donor particle selection is deterministic and non-mutating.
```

The smoke uses the same 8x4 synthetic population as 0116:

```text
cell 0: empty wet receiver
cell 1: poor receiver, mass 1
cell 2: rich donor, mass 8
other cells: target-band mass 4
```

The passive transfer plan requests mass 3 from donor cell 2 to receiver cell 1,
then mass 1 from donor cell 2 to receiver cell 0.  Since donor particles all
have unit mass, the deterministic selected donor indices are 1, 2, 3, 4 and the
selected mass exactly equals the planned transfer mass.
