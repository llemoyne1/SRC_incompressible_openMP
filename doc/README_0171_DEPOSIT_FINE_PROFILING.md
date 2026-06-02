# 0171 — Fine profiling of weighted particle-to-cell deposits

This diagnostic patch instruments `deposit_weighted_real_fluid` without changing
its numerical logic.  It is intended to prepare the next CPU/GPU optimization
stage by decomposing the repeated particle-to-cell deposits used by the
incompressible resampling branch.

## Scope

Modified files:

- `include/weighted_resampling.h`
- `src/weighted_resampling.cpp`
- `src/src_mpcd_base.cpp`
- `scripts/run_performance_profile_0171.sh`

No Q6/CG, virial/capacity, population-guard, mass-guard, remap, thermal, or
collision algorithm is changed.

## New output

Each run directory receives:

- `deposit_profile_0171.csv`

The launcher aggregates:

- `RUN_ROOT/deposit_profile_0171.csv`
- `RUN_ROOT/deposit_profile_top_0171.csv`

Columns:

```text
context,phase,total_s,ms_per_call,percent_context_total,calls,particles_visited,fluid_particles,cells
```

Contexts currently labelled by the caller:

- `initial`
- `post_guard`
- `post_edit`
- `post_remap`
- `post_thermal`
- `generic` for direct calls not yet labelled, including the main initial diagnostic deposit

Deposit sub-phases:

- `validate_resize`
- `clear_arrays`
- `role_counts`
- `particle_loop_cell_accum`
- `reduce_cells_finalize`
- `active_wet_classification`
- `poor_rich_classification`
- `candidate_lists`
- `mutation_plan_cell_index`
- `transfer_plan_build`
- `donor_particle_selection`
- `passive_extraction_plan`

The profile is aggregated inside the deposit function and written at process
exit.  This avoids changing the step result structure while still preserving
per-context labels for the main resampling deposits.

## Build

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
```

## Recommended run

```bash
RUN_ROOT=runs/performance_profile_0171_deposit \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0171.sh
```

Files to inspect:

```text
perf_summary_0171.csv
phase_profile_0171.csv
phase_profile_top_0171.csv
q6_cg_profile_0171.csv
q6_cg_profile_top_0171.csv
resampling_guard_profile_0171.csv
resampling_guard_profile_top_0171.csv
deposit_profile_0171.csv
deposit_profile_top_0171.csv
```

## Interpretation

The most important comparisons are by context:

- `initial` identifies the full resampling deposit that can build mutation plans;
- `post_guard` identifies refresh after population changes;
- `post_remap` identifies refresh after mass/momentum remap;
- `post_thermal` identifies refresh after thermal renormalization.

The goal is to decide whether the next optimization should introduce specialized
deposit modes, for example thermal/velocity refresh instead of full deposit.
