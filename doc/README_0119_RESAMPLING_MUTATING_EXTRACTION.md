# Patch 0119 — mutating extraction Fluid -> Inactive

Patch 0119 introduces the first controlled mutation of the weighted-resampling
pipeline.  Patches 0112--0118 only built deposits, masks, candidate lists,
transfer plans, donor-particle selections and passive extraction operations.
This patch applies those operations when explicitly enabled.

## Scope

The new parameter is:

```text
resamplingExtractionEnable = false
```

It is disabled by default.  This preserves the behaviour of existing classic
SRC, Q6, boundary-condition, wallVP and immersed-solid validations.

When enabled, the sequence is:

1. run the usual SRC/Q6/thermostat step;
2. rebuild the inactive pool;
3. compute the real-fluid weighted deposit and passive extraction plan;
4. apply each valid extraction operation by changing `role` from `Fluid` to
   `Inactive`;
5. push the extracted slots into the inactive free-list;
6. rebuild the pool from roles;
7. recompute the real-fluid deposit for post-extraction diagnostics.

No insertion into poor cells is performed yet.  Therefore this option is only a
controlled smoke-test mechanism at this stage, not a complete resampling method.

## Conservation interpretation

The extracted mass, momentum and kinetic energy are removed from the transported
fluid population because the selected particles become `Inactive`.  The particle
slots themselves are not deleted and are preserved in `.smpcd` V2 dumps with
`role=Inactive`.

The diagnostic block records the applied operation:

```text
resampExtractionApplyAttempted
resampExtractionApplied
resampExtractionApplyOpsConsidered
resampExtractionApplyOpsApplied
resampExtractionApplyRoleChanges
resampExtractionApplySkippedInvalidParticles
resampExtractionApplySkippedNonFluidParticles
resampExtractionApplySkippedDuplicateParticles
resampExtractionApplyPoolFreeSlotsBefore
resampExtractionApplyPoolFreeSlotsAfter
resampExtractionApplyPoolFreeSlotDelta
resampExtractionApplyMass
resampExtractionApplyMomentumX
resampExtractionApplyMomentumY
resampExtractionApplyKineticEnergy
resampExtractionApplyPlannedMass
resampExtractionApplyMassResidualVsPlan
resampFirstAppliedExtractionParticle
resampLastAppliedExtractionParticle
resampExtractionApplyNoDuplicateParticles
resampExtractionApplyAllAppliedWereFluid
```

## Smoke test

Run:

```bash
./scripts/run_resampling_mutating_extraction_smoke_0119.sh
```

Expected core output:

```text
mutating extraction: applied=4 mass=4 fluid=121 inactive=11 poolFree=11 richAfter=0

[0119 resampling mutating extraction smoke] OK: Fluid->Inactive extraction applies deterministically and persists roles.
```

The smoke also verifies that the final `.smpcd` V2 dump persists the changed
roles: four previously `Fluid` donor particles are now `Inactive`.

## Next step

Patch 0120 should introduce the first insertion/activation mechanism into poor
receiver cells, probably using existing inactive slots first and still avoiding
full local mass/momentum remap until the insertion bookkeeping is validated.
