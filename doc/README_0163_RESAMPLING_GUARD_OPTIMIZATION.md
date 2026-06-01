# 0163 — Resampling guard/deposit hot-path optimization

This patch is the first CPU/OpenMP optimization pass after the validated 0161 elliptic-operator plan.
It targets the remaining dominant resampling costs observed in `phase_profile_0161.csv`:

- `resampling_population_guard`
- `resampling_mass_guard`
- repeated particle-pool rebuilds after operations that do not change particle roles

No physical model, resampling threshold, projection option, virial closure, or boundary-condition logic is changed.

## Changes

### 1. Population-support guard: candidate pre-scan

`apply_resampling_population_support_guard()` now builds compact ordered lists of cells that violate the population bounds before constructing the expensive cell-to-particle index.

If no wet cell is outside `[nMin,nMax]`, the function returns immediately with after-statistics equal to before-statistics and without rebuilding the per-cell particle index.

When edits are required, cells are processed in the same increasing cell-index order as before.

### 2. Cell-particle index reuse

A helper verifies whether the deposit workspace already contains a valid cell-to-particle index. If so, the population guard reuses it instead of rebuilding it.

This is important because `deposit_weighted_real_fluid(..., buildMutationPlan=true)` already builds this index in the resampling path.

### 3. Mass guard: reuse existing cell-to-particle index

`apply_resampling_particle_mass_guards()` now uses the existing cell-to-particle index when available, instead of constructing `std::vector<std::vector<std::size_t>> particlesByCell` on every call.

It falls back to the previous per-cell vector construction when the index is absent.

Reusable scratch arrays are also used for the old/new particle masses to avoid repeated per-cell vector allocations.

### 4. Skip pool rebuilds after mass/velocity-only operations

The following operations do not change particle roles or pool membership:

- local mass/momentum remap
- local thermal renormalization
- particle-mass guard

Therefore the post-remap and post-thermal pool rebuilds are skipped. Existing pool diagnostics are kept and attached to the final resampling diagnostics.

## Files changed

```text
src/weighted_resampling.cpp
src/src_mpcd_base.cpp
src/main_src_mpcd_base.cpp
scripts/run_performance_profile_0163.sh
doc/README_0163_RESAMPLING_GUARD_OPTIMIZATION.md
```

## Build

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
```

or:

```bash
BUILD_PROFILE=release ./scripts/build_src_mpcd_base_optimized_0156.sh
```

## Standard profiling run

```bash
RUN_ROOT=runs/performance_profile_0163 \
THREAD_LIST="1 2 4 8" \
CASE_LIST="classic q6 q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0163.sh
```

Expected outputs:

```text
runs/performance_profile_0163/perf_summary_0163.csv
runs/performance_profile_0163/phase_profile_0163.csv
runs/performance_profile_0163/phase_profile_top_0163.csv
runs/performance_profile_0163/q6_cg_profile_0163.csv
runs/performance_profile_0163/q6_cg_profile_top_0163.csv
```

## Target checks against 0161

The main expected gains are on:

```text
resampling_population_guard
resampling_mass_guard
resampling_post_remap_pool
resampling_post_thermal_pool
```

The last two should be nearly zero after this patch.

Functional counters to compare with 0161:

```text
q6Iterations
q6ResidualRel
resampMRelRms
resampTransferPairs
resampSelectedDonorParticles
resampPopulationGuardApplied
resampPopulationGuardCellsSplit
resampPopulationGuardCellsExtracted
resampMassGuardApplied
resampMassGuardCellsGuarded
```

## Validation recommendation

After the quick performance profile, rerun the mono-configuration validation suite from 0162 on the optimized branch and compare to the 0161/origin reference.
