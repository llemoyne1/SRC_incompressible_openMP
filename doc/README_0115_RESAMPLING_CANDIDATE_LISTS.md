# Patch 0115 — passive resampling donor/receiver candidate lists

Patch 0115 prepares the last passive layer before an actual extraction/insertion
operator.  It does **not** mutate particles.  It only converts the 0114 wet/dry
and poor/rich masks into deterministic cell-index lists.

## Lists built

The lists are rebuilt at every step from the real-fluid weighted deposit:

```text
receiverPoorCells      = wet cells with M_c < poorMassThreshold
donorRichCells         = wet cells with M_c > richMassThreshold
emptyWetReceiverCells  = receiver cells with N_c = 0
```

The order is deterministic row-major cell order.  This is deliberate: later
patches can add prioritization, local-neighborhood pairing, or stochastic order
without changing the passive smoke validation.

## Diagnostics

`summary_runtime.csv` now includes:

```text
resampCandidateListsBuilt
resampReceiverCells
resampDonorCells
resampEmptyWetReceiverCells
resampFirstReceiverCell
resampLastReceiverCell
resampFirstDonorCell
resampLastDonorCell
resampReceiverMassDeficitToTarget
resampDonorMassExcessAboveTarget
resampDonorReceiverMassBalance
resampPotentialTransferMass
resampReceiverFractionOfWetCells
resampDonorFractionOfWetCells
resampPoolCanSeedReceivers
```

The deficit/excess are computed relative to `resamplingTargetCellMass`, not to
the poor/rich thresholds:

```text
receiver deficit = sum_{poor wet cells} max(0, M_target - M_c)
donor excess     = sum_{rich wet cells} max(0, M_c - M_target)
potential mass   = min(receiver deficit, donor excess)
```

`resampPoolCanSeedReceivers` is a conservative lower-bound check.  It is true if
the inactive pool contains at least one inactive slot per receiver cell.  It does
not guarantee that a future mass/momentum remap is possible; it only verifies
that the pool has enough immediately available slots to seed all poor cells.

## Non-goals

Patch 0115 intentionally does not perform:

```text
particle extraction
particle insertion
activation of latent particles
consumption of inactive slots
mass redistribution
momentum remap
energy renormalization
```

## Validation

Run:

```bash
./scripts/run_resampling_candidate_lists_smoke_0115.sh
```

The smoke case has 32 active-domain wet cells, with one empty receiver, one
single-particle receiver, and one rich donor.  With `M_target=4`, the expected
candidate diagnostics are:

```text
receivers = 2      # cells 0 and 1
donors    = 1      # cell 2
empty receivers = 1
receiver deficit to target = 4 + 3 = 7
donor excess above target  = 8 - 4 = 4
potential transfer mass    = 4
poolCanSeedReceivers       = true
```
