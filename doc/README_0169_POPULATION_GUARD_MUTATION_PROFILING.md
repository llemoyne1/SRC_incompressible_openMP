# 0169a — Deep profiling of population-guard mutations

This differential patch is diagnostic only. It keeps the 0168 population-guard
logic unchanged and adds nested timers inside the two expensive mutation blocks:

- `overfull_apply_mutation`
- `underfull_apply_mutation`

New profile rows are emitted under group `population_guard_mutation_detail` in
`resampling_guard_profile_0169.csv`. These rows are nested inside the existing
mutation phases and must not be added to the high-level totals.

## New phases

Overfull extraction mutation:

- `overfull_mutation_momentum_merge`
- `overfull_mutation_state_write`
- `overfull_mutation_role_inactivate`
- `overfull_mutation_pool_push`
- `overfull_mutation_count_update`

Underfull split mutation:

- `underfull_mutation_pool_pop`
- `underfull_mutation_particle_clone`
- `underfull_mutation_role_activate`
- `underfull_mutation_pool_fluid_push`
- `underfull_mutation_counters_update`

## Run

```bash
RUN_ROOT=runs/performance_profile_0169_population_mutation THREAD_LIST="1 2 4 8" CASE_LIST="q6_resampling" STEPS=500 ./scripts/run_performance_profile_0169.sh
```

Key outputs:

- `perf_summary_0169.csv`
- `phase_profile_0169.csv`
- `q6_cg_profile_0169.csv`
- `resampling_guard_profile_0169.csv`
- `resampling_guard_profile_top_0169.csv`

Use this patch to decide whether the remaining population-guard cost is caused
by role changes, pool stack operations, state writes, or diagnostic/counter
updates. No physical or algorithmic operation is changed.
