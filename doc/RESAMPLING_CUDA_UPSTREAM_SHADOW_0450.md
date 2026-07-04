# 0450 — CUDA resampling upstream shadow in the real solver

## Purpose

0448/0449 made CUDA authoritative for the clean mutating phases of weighted
resampling:

- passive extraction / insertion;
- local mass-momentum remap;
- local thermal renormalization.

The upstream part still remained CPU-authoritative: deposit, cell
classification, poor/rich compaction and transfer-plan construction.  Patch
0450 adds an in-solver CUDA shadow for that upstream path.

## Scope

The 0450 hook is intentionally restricted to the clean periodic validation
regime:

- periodic in x and y;
- no analytic immersed solid;
- no Darcy/chi/inlet/outlet/walls;
- CPU remains authoritative;
- CUDA only recomputes and compares upstream quantities.

The hook is enabled by:

```bash
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_EVERY_0450=1
```

It writes:

```text
cuda_resampling_upstream_shadow_0450.csv
```

in the run output directory.

## What is compared

For each enabled step, after the CPU post-guard resampling deposit has built
the mutation plan and before extraction/insertion mutates the particle state,
CUDA recomputes:

1. real-fluid deposit through the existing CUDA cell-moment backend;
2. poor/rich list compaction from cell masses and CPU wet mask;
3. greedy nearest-donor transfer plan with the same periodic distance rule as
   the CPU reference.

The CSV compares:

- cell ids;
- per-cell counts, mass and momentum;
- total mass and momentum;
- receiver poor-cell and donor rich-cell lists;
- transfer-plan donor/receiver cells;
- transfer masses and distances;
- CPU passive operation count, for coverage.

## Relation to the 100% CUDA objective

0450 does not yet make upstream CUDA authoritative.  It is the validation gate
before replacing:

```text
CPU deposit / classification / compaction / planner
```

by:

```text
CUDA deposit / classification / compaction / planner
```

inside the production path.

After 0450 PASS, the next step can start turning the upstream shadow into an
apply backend, still under an explicit experimental flag.

## Smoke

Use:

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0450 \
BASE_UPSTREAM_ROOT=runs/0450_upstream_shadow_apply_smoke \
STEPS=20 \
SUMMARY_EVERY=1 \
RUN_MODES="src-resampling src-q6-resampling" \
LIVE_VIS_ENABLE=0 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0450_upstream_shadow_apply_smoke.sh
```

Expected report:

```text
runs/0450_upstream_shadow_apply_smoke/upstream_shadow_report_0450.md
```

PASS criteria:

- `PASS-like modes = 2/2`;
- handled rows equal passed rows;
- skipped rows = 0;
- nonzero transfer pairs and passive operations;
- cellIdMismatch = 0;
- receiver/donor list mismatches = 0;
- planMismatch = 0;
- mass/momentum/plan deltas at floating-point roundoff.


## 0450 type-compare correction

The 0450 first smoke exposed a false negative in the existing 0445/0446 pipeline comparator: `typeMismatch` was counted over all allocated particle slots.  In the periodic nonzero-plan runner the inactive/free reserve has 1024 slots; after CPU extraction/insertion and CUDA replay, the inactive tail can carry different non-physical type tags while role, active prefix, fluid payload, mass, momentum, and energy remain identical.

The comparator now follows the same semantic rule as the earlier 0442 particle-apply comparefix: inactive/free payload is ignored. `roleMismatch` is still counted over the full allocated range, but `typeMismatch` and payload deltas are counted only on matching physical fluid slots.
