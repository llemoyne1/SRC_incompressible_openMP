# Patch 0114 — resampling wet/dry and poor/rich cell classification

This patch adds the first passive cell-level classification needed by the
weighted-resampling core.  It does **not** move, activate, deactivate, insert,
extract or remap particles.

## Purpose

Patch 0114 classifies the real-fluid weighted deposit introduced in patch 0112
into masks that later extraction/insertion patches will consume:

- `activeCell`: cell center lies in the active fluid domain and, when an
  immersed solid is enabled, the cell fluid fraction is above the resampling
  active threshold;
- `wetCell`: cell belongs to the resampling target set;
- `dryCell`: cell is outside the current resampling target set;
- `poorCell`: wet cell with real-fluid mass below the poor threshold;
- `richCell`: wet cell with real-fluid mass above the rich threshold;
- `targetBandCell`: wet cell between poor and rich thresholds.

The classification uses the real transported fluid deposit only.  It excludes
latent particles, inactive pool slots, wall virtual particles, and immersed-solid
virtual particles.

## Default wet-mask convention

The default mode is:

```text
resamplingWetMaskMode = active_domain
```

In this mode, every active fluid-domain cell is wet, even when it currently has
zero particles.  This is deliberate: in bulk/channel tests, a true void pocket
inside the fluid domain must be classified as `poorCell`, not silently ignored as
an exterior dry/free-surface cell.

A second passive mode is available for later injection/free-surface tests:

```text
resamplingWetMaskMode = occupied
```

In `occupied` mode, a cell is wet only if it is active and its real-fluid mass is
above `resamplingWetCellMassThreshold`.

## Parameters

```text
resamplingTargetCellMass = 0.0
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = 0.5
resamplingRichCellMassFraction = 1.5
resamplingActiveFluidFractionThreshold = 0.5
```

If `resamplingTargetCellMass <= 0`, the current mean real-fluid mass over wet
cells is used as the classification target.  Otherwise the supplied value is used.

For a target mass `M0`, the thresholds are:

```text
poorMassThreshold = resamplingPoorCellMassFraction * M0
richMassThreshold = resamplingRichCellMassFraction * M0
```

## Runtime columns

The patch adds these columns to `summary_runtime.csv`:

```text
resampCellClassificationComputed
resampActiveCells
resampWetCells
resampDryCells
resampPoorCells
resampRichCells
resampTargetBandCells
resampEmptyWetCells
resampOccupiedDryCells
resampWetMassThreshold
resampPoorMassThreshold
resampRichMassThreshold
resampWetCellFraction
resampDryCellFraction
resampPoorCellFraction
resampRichCellFraction
resampEmptyWetCellFraction
```

## Smoke test

Run:

```bash
./scripts/run_resampling_cell_classification_smoke_0114.sh
```

The test constructs a periodic 8x4 state with:

- one empty active-domain cell: `poorCell + emptyWetCell`;
- one underfilled cell: `poorCell`;
- one overfilled cell: `richCell`;
- all other active-domain cells inside the target band;
- separate `Latent` and `Inactive` dormant slots.

Expected summary:

```text
wet=32 dry=0 poor=2 rich=1 emptyWet=1 targetBand=29
```

## Non-goals

Patch 0114 deliberately does not implement:

- extraction from rich cells;
- insertion into poor cells;
- activation of latent slots;
- use of inactive slots;
- mass/momentum remap;
- mass safety or renormalization.

The next logical patch is 0115: passive candidate lists for rich donors and poor
receivers, still without modifying the state.
