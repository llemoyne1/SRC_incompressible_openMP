# 0174b equivalence diagnostic output fix

This corrective patch keeps the 0174b diagnostic path unchanged and only fixes
profile emission for the post-guard diagnostic CSVs.

## Problem

The first 0174b run produced empty aggregate files:

- `post_guard_profile_0174b.csv`
- `post_guard_equivalence_profile_0174b.csv`

The computation path itself still used the full post-guard deposit, but the
accumulators were not reliably visible to the aggregation script.

## Fix

`src/src_mpcd_base.cpp` now writes the post-guard diagnostic snapshots
immediately when the corresponding accumulator is updated, and again at normal
static-destruction time. The filenames are also normalized to the 0174b tag:

- `post_guard_profile_0174b.csv`
- `post_guard_equivalence_profile_0174b.csv`

This is still diagnostic-only. It does not change the simulation path, the
post-guard deposit, resampling choices, Q6, virial/capacity, mass guard, or
particle roles.

## Suggested run

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh

RUN_ROOT=runs/performance_profile_0174b_post_guard_equiv_fixed \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0174b.sh
```

The two previously empty files should now contain data rows.
