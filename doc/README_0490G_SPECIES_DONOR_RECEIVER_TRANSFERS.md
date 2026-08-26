# 0490g — Species-constrained donor/receiver transfers

## Scope

This patch makes the active weighted-resampling extraction/insertion transfer
plan species-aware behind the explicit opt-in switch:

```text
speciesResamplingTransferEnable = true
```

The legacy path is unchanged when the option is false.

## Policy

For each non-empty poor receiver cell, the total mass deficit is apportioned
between the species already present in that receiver according to their current
mass fractions. For each rich donor cell, the removable excess is apportioned
between its species using the same rule. The nearest donor search is then run
separately for each registered particle type.

Each transfer-plan entry stores its required particle type. Donor-particle
selection rejects every particle with a different type. The explicit extraction
operation preserves that type, and insertion reactivates the same slot with the
same type, mass and momentum.

Consequences:

- a pure liquid receiver cannot be supplied by a gas donor;
- mixed receivers may receive several same-type transfer entries;
- total and per-species mass are conserved by extraction/insertion;
- empty-cell composition is not guessed here; it remains handled by the 0490f
  composition-memory refill;
- Q6 is unchanged.

## CUDA boundary

The 0490g planner is CPU-authoritative. Existing CUDA 0240/0448 particle-edit
backends may apply the explicit host-built operations because those operations
already contain the selected particle type. CUDA upstream planners and the 0453
operation rematerializer are bypassed while 0490g is enabled because they do not
yet carry the species constraint in their compact plan format.

## Smoke test

`run_0490g_species_transfer_smoke.sh` creates three periodic cells:

1. a poor liquid receiver;
2. a nearest rich gas donor that must remain untouched;
3. a rich liquid donor that must supply the receiver.

The test verifies final cell composition and exact global mass conservation for
both species.
