# Patch 0168 — deep profiling of `resampling_population_guard`

This patch is diagnostic only.  It is intended to be applied after the validated
OpenMP optimization branch including the 0166 population-guard candidate-list
patch.

## Scope

The patch instruments the two remaining hot sub-loops inside
`apply_resampling_population_support_guard`:

- overfull candidate-cell processing;
- underfull candidate-cell processing.

It does not change the resampling algorithm, particle role transitions, Q6/CG,
closed-capacity/virial response, deposits, remap, thermal renormalization, or
mass-guard logic.

## Added timing phases

The original population-guard phases are kept as the high-level group:

- `init_thresholds`
- `count_copy`
- `stats_before`
- `ensure_cell_particle_index`
- `overfull_extraction_loop`
- `underfull_split_loop`
- `stats_after_finalize`

Additional deep phases are reported in a separate `population_guard_deep` group:

- `overfull_candidate_setup`
- `overfull_particle_scan`
- `overfull_apply_mutation`
- `overfull_diagnostics`
- `underfull_candidate_setup`
- `underfull_particle_scan`
- `underfull_apply_mutation`
- `underfull_diagnostics`

The deep phases are nested inside the high-level loop phases.  They should be
used to understand the internal decomposition of the overfull/underfull loops,
not added to the high-level total.

## Added counters

The guard profile CSV also reports metadata counters:

- `population_guard_overfull_candidate_particle_refs_total`
- `population_guard_underfull_candidate_particle_refs_total`
- `population_guard_overfull_scan_passes_total`
- `population_guard_underfull_scan_passes_total`
- `population_guard_overfull_particle_refs_scanned_total`
- `population_guard_underfull_particle_refs_scanned_total`
- `population_guard_overfull_eligible_particle_refs_total`
- `population_guard_underfull_eligible_particle_refs_total`
- `population_guard_overfull_candidate_population_max`
- `population_guard_underfull_candidate_population_max`

These counters indicate whether the candidate-cell operations are dominated by
repeated scans of local particles, mutation/role updates, pool operations, or
simple bookkeeping.

## Build

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
```

## Recommended run

```bash
RUN_ROOT=runs/performance_profile_0168_population_guard \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0168.sh
```

The key files are:

- `perf_summary_0168.csv`
- `phase_profile_0168.csv`
- `phase_profile_top_0168.csv`
- `q6_cg_profile_0168.csv`
- `q6_cg_profile_top_0168.csv`
- `resampling_guard_profile_0168.csv`
- `resampling_guard_profile_top_0168.csv`

## Validation expectation

This is a profiling patch; timings may include a small overhead, especially in
the candidate-cell loops.  Functional counters should remain unchanged relative
to the validated 0166 baseline:

- `q6Iterations`
- `resampMRelRms`
- `resampTransferPairs`
- `resampSelectedDonorParticles`
- population-guard extracted/split counts.
