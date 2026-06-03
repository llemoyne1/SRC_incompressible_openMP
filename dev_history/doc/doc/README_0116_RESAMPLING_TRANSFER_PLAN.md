# Patch 0116 — passive local donor/receiver transfer plan

This patch adds the first passive planning layer after the donor/receiver lists
introduced by patch 0115.

## Purpose

The weighted-resampling branch now builds a deterministic cell-level transfer
plan:

```text
rich donor wet cells  ->  poor receiver wet cells
```

The plan is still diagnostic only.  It does not:

- move particles;
- change particle masses;
- activate latent particles;
- consume inactive pool slots;
- remap mass or momentum;
- modify SRC collision, Q6, thermostat, boundaries or immersed solids.

## Algorithm

For every donor/receiver pair, the planner computes a grid-cell distance.  The
distance respects periodic boundary pairs through `is_x_periodic(params)` and
`is_y_periodic(params)`.

Candidate pairs are sorted by:

```text
1. increasing cell distance;
2. donor cell id;
3. receiver cell id.
```

The planner then greedily assigns

```text
plannedMass = min(donorRemainingExcess, receiverRemainingDeficit)
```

until either all receiver deficits or all donor excesses are exhausted.

This is deliberately a planning stage only.  It answers the question:

```text
Given the current poor/rich masks, how much mass could be transferred locally,
and across which cell pairs?
```

## Runtime diagnostics

Patch 0116 adds these `summary_runtime.csv` columns:

```text
resampTransferPlanBuilt
resampTransferPairs
resampAdjacentTransferPairs
resampFirstTransferDonorCell
resampFirstTransferReceiverCell
resampLastTransferDonorCell
resampLastTransferReceiverCell
resampPlannedTransferMass
resampRemainingReceiverDeficitAfterPlan
resampRemainingDonorExcessAfterPlan
resampTransferMassCoverageFraction
resampTransferMeanCellDistance
resampTransferMaxCellDistance
resampTransferPlanDonorLimited
resampTransferPlanReceiverLimited
```

## Smoke test

Run:

```bash
./scripts/run_resampling_transfer_plan_smoke_0116.sh
```

The deterministic test uses one rich donor cell and two poor receivers.  The
local planner assigns the nearest receiver first, then the remaining mass to the
next receiver.  Expected core result:

```text
transferPairs=2 planned=4 remainingReceiver=3 remainingDonor=0 coverage=0.5714285714285714
```

The smoke also verifies that the inactive pool is unchanged and still counted
only as future capacity.
