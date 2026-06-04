# 0173 — Post-guard deposit profiling

This diagnostic patch adds a narrow profiler around the `post_guard_deposit`
path after `apply_resampling_population_support_guard`.

It does not change the population guard, deposit, Q6 projection, virial/capacity,
thermal renormalization, or particle roles. It records how expensive the full
post-guard deposit is relative to the number of cells and particle references
affected by the population guard.

New per-run file:

```text
post_guard_profile_0173.csv
```

Aggregated by the launcher into:

```text
RUN_ROOT/post_guard_profile_0173.csv
RUN_ROOT/post_guard_profile_top_0173.csv
```

Useful metadata rows include:

```text
post_guard_calls
post_guard_build_mutation_plan_calls
post_guard_edited_cells_total
post_guard_candidate_cells_total
post_guard_candidate_particle_refs_total
post_guard_scanned_particle_refs_total
post_guard_eligible_particle_refs_total
post_guard_split_particles_total
post_guard_extracted_particles_total
post_guard_full_deposit_particles_visited_total
post_guard_full_deposit_fluid_particles_total
post_guard_full_deposit_cells_total
```

Recommended run:

```bash
RUN_ROOT=runs/performance_profile_0173_post_guard \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0173.sh
```
