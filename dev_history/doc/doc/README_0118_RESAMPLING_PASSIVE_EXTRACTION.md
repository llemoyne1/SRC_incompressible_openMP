# Patch 0118 — passive extraction operation plan

Patch 0118 is the final passive staging layer before the first mutating
resampling operation.  It does not change the particle state.  It only converts
the donor-particle selection built in patch 0117 into explicit extraction
operations.

## Purpose

The resampling pipeline now has the following passive sequence:

```text
0112 real-fluid weighted deposit
0113 inactive pool/free-list diagnostics
0114 wet/dry + poor/rich cell classification
0115 donor/receiver candidate cell lists
0116 local donor->receiver transfer plan
0117 donor particle selection
0118 passive extraction operations
```

Patch 0118 records the exact operations that a future mutating patch will apply
by converting selected donor particles from `Fluid` to `Inactive` and returning
those slots to the inactive pool.

## What is recorded

Each passive extraction operation stores:

```text
particleIndex
donorCell
receiverCell
particleMass
momentumX
momentumY
kineticEnergy
currentRole
plannedRoleAfterExtraction = Inactive
```

These values are currently diagnostic only.  No state mutation is performed.

## Runtime diagnostics

The runtime summary gains:

```text
resampExtractionPlanBuilt
resampExtractionOps
resampExtractionParticles
resampExtractionDonorCells
resampExtractionReceiverCells
resampFirstExtractionParticle
resampLastExtractionParticle
resampFirstExtractionDonorCell
resampLastExtractionDonorCell
resampFirstExtractionReceiverCell
resampLastExtractionReceiverCell
resampExtractionMass
resampExtractionMomentumX
resampExtractionMomentumY
resampExtractionKineticEnergy
resampExtractionMeanParticleMass
resampExtractionMaxParticleMass
resampExtractionMassOvershoot
resampExtractionMassCoverageFraction
resampHypotheticalPoolFreeSlotsAfterExtraction
resampExtractionAllSelectedAreFluid
resampExtractionNoDuplicateParticles
```

`resampHypotheticalPoolFreeSlotsAfterExtraction` is not an actual pool update.
It predicts how many inactive slots would be available if the selected donor
particles were extracted.

## Invariants

Patch 0118 must preserve:

```text
state.Np
state.role
state.mass
state.x, state.y
state.vx, state.vy
inactive pool content
SRC collision path
Q6 projection path
wallVP / immersed VP handling
```

The future mutating extraction patch should be able to reuse the explicit
operation list and then validate the same mass/momentum totals before changing
roles.

## Smoke test

Run:

```bash
./scripts/run_resampling_passive_extraction_smoke_0118.sh
```

Expected core result:

```text
passive extraction: ops=4 particles=4 mass=4 coverage=1 firstParticle=1 lastParticle=4 poolAfter=11 allFluid=1 noDup=1

[0118 resampling passive extraction smoke] OK: extraction operations are explicit, passive, and pool-aware.
```
