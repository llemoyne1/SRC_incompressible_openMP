# Patch 0120 — controlled resampling insertion

Patch 0120 is the first mutating insertion milestone of the OpenMP weighted
resampling port.

It builds on the previous milestones:

- 0114: wet/dry and poor/rich cell classification;
- 0115: passive donor/receiver candidate lists;
- 0116: passive donor→receiver transfer plan;
- 0117: passive donor-particle selection;
- 0118: passive extraction operation plan;
- 0119: controlled `Fluid -> Inactive` donor extraction.

## New switch

```text
resamplingInsertionEnable = false
```

The default is `false`, so legacy SRC/Q6 runs remain unchanged.

For this first implementation, insertion requires extraction:

```text
resamplingExtractionEnable = true
resamplingInsertionEnable = true
```

The parser rejects `resamplingInsertionEnable=true` if extraction is disabled.

## Implemented operation

When both switches are enabled, one SRC/MPCD step performs the following
resampling-tail sequence after collision/Q6/thermostat:

```text
1. build passive extraction operations from the real-fluid deposit;
2. apply extraction: selected donor particles Fluid -> Inactive;
3. apply insertion: the same extracted slots are reactivated Inactive -> Fluid
   in the planned receiver cells;
4. rebuild the inactive pool;
5. recompute the real-fluid deposit and runtime diagnostics.
```

Insertion preserves the extracted particle payload:

```text
mass
momentum
kinetic energy through velocity reconstruction
particle type/species identifier
```

The inserted position is assigned deterministically in the receiver cell with a
small interior stencil.  This avoids exact overlap in the smoke tests and keeps
the operation reproducible.  It is not yet the final physical placement rule.

## Deliberately not implemented yet

Patch 0120 still does **not** implement:

```text
local mass/momentum remap
cell-wise thermal correction
M, U, E_th renormalisation
latent wetting/front activation
species-fraction control
solid-aware insertion point sampling in cut cells
```

The goal is only to validate the first complete role cycle:

```text
Fluid donor -> Inactive pool -> Fluid receiver
```

with exact global conservation of the moved particle payload.

## New runtime diagnostics

The runtime summary gains the block:

```text
resampInsertionApplyAttempted
resampInsertionApplied
resampInsertionApplyOpsConsidered
resampInsertionApplyOpsApplied
resampInsertionApplyRoleChanges
resampInsertionApplySkippedInvalidSourceParticles
resampInsertionApplySkippedSourceNotInactive
resampInsertionApplySkippedInvalidReceiverCells
resampInsertionApplySkippedNoFreeSlots
resampInsertionApplySkippedInvalidMass
resampInsertionApplyPoolFreeSlotsBefore
resampInsertionApplyPoolFreeSlotsAfter
resampInsertionApplyPoolFreeSlotDelta
resampInsertionApplyMass
resampInsertionApplyMomentumX
resampInsertionApplyMomentumY
resampInsertionApplyKineticEnergy
resampInsertionApplyPlannedMass
resampInsertionApplyMassResidualVsPlan
resampFirstAppliedInsertionParticle
resampLastAppliedInsertionParticle
resampFirstAppliedInsertionReceiverCell
resampLastAppliedInsertionReceiverCell
resampInsertionApplyNoInvalidReceiverCells
resampInsertionApplyAllSourcesWereInactive
```

## Smoke test

Run:

```bash
./scripts/run_resampling_mutating_insertion_smoke_0120.sh
```

The test constructs a deterministic V2 `.smpcd` state:

```text
cell 0: empty wet receiver
cell 1: poor receiver with mass 1
cell 2: rich donor with mass 8
other cells: target-band mass 4
latent slots: 5
inactive slots: 7
```

The expected transfer plan moves four unit-mass particles.  After extraction and
insertion, the total active-fluid mass and role counts are restored:

```text
fluid = 125
latent = 5
inactive = 7
poolFree = 7
```

The diagnostic printout should end with:

```text
mutating insertion: inserted=4 mass=4 fluid=125 inactive=7 poolFree=7 poorAfter=1

[0120 resampling mutating insertion smoke] OK: controlled Inactive->Fluid insertion recycles extracted particles into receiver cells.
```

`poorAfter=1` is expected: the donor had only four excess particles, so one of
the two receiver cells remains underfilled.  Later remap/renormalisation patches
will address smoother mass balancing.
