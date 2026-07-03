# 0441 — CUDA shadow validator for resampling transfer planner

## Scope

This step validates the first exact CUDA shadow of the weighted-resampling transfer planner.
It does **not** modify the production solver and introduces no new public simulation parameter.

The validator extends the 0439/0440 standalone chain:

1. synthetic periodic particle state generation;
2. CPU `deposit_weighted_real_fluid(..., buildMutationPlan=true)` reference;
3. CUDA persistent-state deposit/classification;
4. CUDA poor/rich compaction;
5. CUDA serial exact transfer planner shadow;
6. entry-by-entry comparison against the CPU transfer plan.

The planner kernel is intentionally serial (`<<<1,1>>>`) for this first shadow. The aim is exactness of semantics and ordering, not performance. A later step can replace it with a scalable planner once the device representation and diagnostics are locked.

## Tested cases

The runner covers four periodic, wall-free, no-solid synthetic cases:

- shear, uniform mass, no shift;
- shear, uniform mass, shifted grid;
- Taylor--Green, variable mass, no shift;
- Taylor--Green, variable mass, shifted grid.

The shifted cases produce non-empty poor/rich lists and non-empty transfer plans, so they exercise the actual greedy nearest-donor planner.

## PASS criteria

A case passes when:

- CPU/GPU cell-id classification matches;
- CPU/GPU cell counts match;
- CPU/GPU poor/rich counts and compacted lists match after sorting;
- CPU/GPU transfer plan length matches;
- each transfer entry has the same donor cell and receiver cell;
- planned mass, cell distance, donor remaining mass, and receiver remaining mass match within tolerance;
- planned mass totals, remaining receiver deficit, remaining donor excess, and adjacent-pair counts match.

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
OUT=build/validate_cuda_resampling_planner_shadow_0441 \
bash scripts/build_validate_cuda_resampling_planner_shadow_0441.sh
```

## Run

```bash
BIN=build/validate_cuda_resampling_planner_shadow_0441 \
RUN_ROOT=runs/0441_cuda_resampling_planner_shadow_smoke \
NX=64 NY=32 GAMMA=20 INACTIVE_SLOTS=1024 SEED=1628638 \
bash scripts/run_validate_cuda_resampling_planner_shadow_0441.sh
```

Expected verdict:

```text
CUDA_RESAMPLING_PLANNER_SHADOW_0441 PASS cases=4/4
```
