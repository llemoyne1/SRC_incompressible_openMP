# 0165 — Fine profiling of resampling guards

This patch is a profiling-only patch for the OpenMP CPU optimization branch.
It does not change the resampling algorithm, particle state updates, projection,
or closed-capacity/virial response.

## Purpose

The 0161/0162 validated branch moved the dominant cost away from the Q6 elliptic
operator and toward the resampling path.  The coarse step profile identifies
three remaining expensive blocks:

- `resampling_population_guard`
- `resampling_mass_guard`
- repeated particle-to-cell deposits

Patch 0165 adds internal timers for the first two blocks so the next
optimization can target the actual hot subphase instead of changing the guard
logic blindly.

## New output

Each run directory now contains:

```text
resampling_guard_profile_0165.csv
```

The launcher aggregates these into:

```text
RUN_ROOT/resampling_guard_profile_0165.csv
RUN_ROOT/resampling_guard_profile_top_0165.csv
```

The profile groups are:

```text
population_guard
mass_guard
```

Population-guard phases:

```text
init_thresholds
count_copy
stats_before
ensure_cell_particle_index
overfull_extraction_loop
underfull_split_loop
stats_after_finalize
```

Mass-guard phases:

```text
init_validate
build_particles_by_cell
cell_loop
finalize
```

## Recommended run

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh

RUN_ROOT=runs/performance_profile_0165_resamp_guard \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0165.sh
```

The script also preserves the existing coarse phase profile and Q6/CG profile.
It detects older profile suffixes for those existing files, while the new
resampling guard profile is always written as `0165`.

## Acceptance checks

The patch should preserve the known functional counters:

```text
q6Iterations
resampMRelRms
resampTransferPairs
resampSelectedDonorParticles
resampPopulationGuardApplied
resampMassGuardApplied
```

It is expected to introduce a small profiling overhead inside the guard blocks;
this patch is intended for diagnosis, not as a performance optimization.
