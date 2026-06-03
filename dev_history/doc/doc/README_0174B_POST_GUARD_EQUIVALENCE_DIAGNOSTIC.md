# 0174b — post-guard local-refresh equivalence diagnostic

This diagnostic patch does **not** replace the post-guard full deposit.  The production path remains:

1. `population_guard` mutates roles/masses locally;
2. `post_guard_deposit` performs the existing full `deposit_weighted_real_fluid(...)`;
3. downstream resampling logic consumes the full deposit exactly as before.

The patch only snapshots the cell-level deposit fields immediately before the full post-guard deposit, then compares this snapshot to the full post-guard result.  It writes:

```text
post_guard_equivalence_profile_0174b.csv
```

The key purpose is to estimate whether a future local post-guard refresh can be made strictly equivalent.

## Main metrics

- `post_guard_equiv_count_changed_cells_total`: cells whose population changed after population guard.
- `post_guard_equiv_any_field_changed_cells_total`: cells whose count/mass/momentum/classification changed.
- `post_guard_equiv_non_count_changed_mass_momentum_diff_cells_total`: dangerous cells for a count-only local refresh; should ideally be zero.
- `post_guard_equiv_non_count_changed_classification_diff_cells_total`: dangerous classification changes outside population-changed cells; should ideally be zero.
- `post_guard_equiv_candidate_list_size_changed_calls`: calls where poor/rich/empty receiver list sizes changed.
- `post_guard_equiv_affected_particle_refs_before_total` and `_after_total`: approximate particle references that a local affected-cell refresh would need.
- `post_guard_equiv_full_deposit_particles_visited_total`: full deposit work currently paid.
- `post_guard_equiv_full_to_affected_after_ref_ratio`: rough potential work-ratio between full deposit and affected-cell refresh.

## Run

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh

RUN_ROOT=runs/performance_profile_0174b_post_guard_equiv \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0174b.sh
```

Attach at least:

```text
perf_summary_0174b.csv
phase_profile_0174b.csv
post_guard_profile_0174b.csv
post_guard_equivalence_profile_0174b.csv
resampling_guard_profile_0174b.csv
```

## Interpretation

If the non-count-changed diff counters are zero or negligible, a future 0175 can try a local refresh that recomputes exactly the changed cells and then rebuilds global candidate lists in cell order.  If they are non-zero, the local-refresh candidate set must be expanded beyond count-changed cells before another optimization attempt.
