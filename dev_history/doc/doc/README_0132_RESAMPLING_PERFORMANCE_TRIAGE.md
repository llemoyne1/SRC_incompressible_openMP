# 0132 — Resampling performance triage

This patch addresses the first severe performance regression observed in Poiseuille wallVP runs with `q6_resampling`.

The previous implementation used `deposit_weighted_real_fluid` as both a real-fluid deposit and a full resampling planner. That meant that every deposit rebuilt:

- poor/rich candidate lists;
- the full donor × receiver transfer candidate matrix;
- a sorted transfer plan;
- passive donor-particle selections;
- passive extraction operations.

This became especially expensive in channel runs because the resampling path performs several deposits per step: before role changes, after extraction/insertion, after mass remap/guard, and after thermal renormalisation. Only the first deposit needs a mutating extraction plan; later deposits only need updated diagnostics and cell moments.

## Changes

1. `deposit_weighted_real_fluid(...)` now accepts a `buildMutationPlan` flag.
2. `src_mpcd_base.cpp` requests the full mutation plan only once per step, before role-changing operations.
3. Post-edit/post-remap/post-thermal deposits run in lightweight mode: they still compute masses, velocities, wet/poor/rich masks and diagnostics, but do not build transfer plans or particle extraction lists.
4. The transfer planner no longer materialises and sorts the full donor × receiver Cartesian product. It uses a deterministic nearest-donor greedy planner.
5. Donor-particle selection no longer scans all particles for every transfer entry. The deposit builds a compact cell→particle index once, then each donor selection only scans particles in the donor cell.

## Expected effect

This patch should not change the intended physical sequence of operations. It removes redundant planning work and reduces the dominant algorithmic costs:

- full Cartesian sort: removed;
- repeated full plan builds per step: removed;
- per-transfer all-particle scans: replaced by per-donor-cell scans.

It is still a triage patch. Further optimisation may be needed, especially for long channel runs, but the 40× slowdown should drop substantially if the bottleneck was the resampling planner.

## Validation

Run at least:

```bash
./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection
./scripts/run_resampling_cadence_smoke_0129.sh
```

Then rerun the Poiseuille wallVP case and compare wall times for `classic`, `q6`, and `q6_resampling`.
