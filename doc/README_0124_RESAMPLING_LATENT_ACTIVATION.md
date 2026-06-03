# 0124 — Controlled wet/latent activation for resampling

This patch adds the first explicit wet/dry filling hook for the OpenMP weighted
resampling branch.  It is still controlled and off by default.

## New parameters

```text
resamplingLatentActivationEnable = false
resamplingLatentActivationMaxPerCell = 1
resamplingLatentActivationParticleMass = 0.0
```

`resamplingLatentActivationParticleMass <= 0` means that the activated mass is
inferred as:

```text
M_target / resamplingLatentActivationMaxPerCell
```

## Semantics

The stage consumes only particles with:

```text
role = Latent
```

and converts them to:

```text
role = Fluid
```

inside poor wet receiver cells.  Empty wet receiver cells are processed first.
The `Inactive` free-list is not consumed by this stage, so donor/receiver
recycling and latent wet-front filling remain distinct mechanisms.

The activated particle:

- preserves its `type`/species identifier;
- receives a deterministic in-cell position;
- receives the receiver-cell velocity if the cell is non-empty;
- receives zero velocity in an empty wet cell;
- receives the configured/inferred activation mass.

This is intentionally a minimal activation stage.  It does not yet implement a
front-propagation law for free surfaces, capillary criteria, or stochastic
thermal sampling of the activated velocity.

## Runtime diagnostics

The runtime summary now includes:

```text
resampLatentActivationAttempted
resampLatentActivationApplied
resampLatentActivationReceiverCellsConsidered
resampLatentActivationCellsActivated
resampLatentActivationParticlesActivated
resampLatentActivationRoleChanges
resampLatentActivationSkippedNoLatentSlots
resampLatentActivationSkippedInvalidReceiverCells
resampLatentActivationSkippedReceiverNotWet
resampLatentActivationSkippedReceiverNotPoor
resampLatentActivationSkippedMaxPerCell
resampLatentActivationLatentSlotsBefore
resampLatentActivationLatentSlotsAfter
resampLatentActivationFluidSlotsBefore
resampLatentActivationFluidSlotsAfter
resampLatentActivationTargetCellMass
resampLatentActivationParticleMass
resampLatentActivationMass
resampLatentActivationMomentumX
resampLatentActivationMomentumY
resampLatentActivationKineticEnergy
resampFirstLatentActivatedParticle
resampLastLatentActivatedParticle
resampFirstLatentActivatedCell
resampLastLatentActivatedCell
resampLatentActivationAllSourcesWereLatent
resampLatentActivationNoDryCellsActivated
```

## Validation

Run:

```bash
./scripts/run_resampling_latent_activation_smoke_0124.sh
```

Expected core output:

```text
latent activation: activated=4 cells=1 fluid=128 latent=1 inactive=3 MRelRms=0

[0124 resampling latent activation smoke] OK: Latent->Fluid activation seeds empty wet cells without consuming Inactive pool slots.
```

The smoke builds a 8x4 periodic state with one empty wet cell, five latent
particles and three inactive slots.  Four latent particles are activated in the
empty wet cell.  The final V2 `.smpcd` dump is checked for role persistence:

```text
Fluid    = 128
Latent   = 1
Inactive = 3
```
