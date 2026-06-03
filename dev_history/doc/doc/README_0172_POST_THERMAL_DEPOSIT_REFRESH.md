# 0172 — Specialized post-thermal deposit refresh

This diagnostic/optimization patch targets the repeated post-thermal
particle-to-cell deposit in the Q6 + weighted-resampling path.

## Rationale

The 0171 deposit profile showed that the `post_thermal` deposit is one of the
three dominant deposit contexts.  After late thermal renormalization, particle
positions, roles, masses, cell identifiers, cell classification masks and
candidate lists are unchanged.  Only velocities are modified.

Therefore the full `deposit_weighted_real_fluid(...)` call after thermal
renormalization is stronger than required: it rebuilds counts/masses,
classifications and candidate/planning structures although the topology is
unchanged.

## Change

0172 adds:

```cpp
refresh_weighted_real_fluid_velocity_deposit(...)
```

This function refreshes only:

- per-cell momentum `px`, `py`;
- per-cell mean velocity `ux`, `uy`;
- global momentum and velocity diagnostics;
- deposit profiling metadata.

It reuses the current deposit workspace for:

- `cellId`;
- `count`;
- `mass`;
- wet/dry/poor/rich classifications;
- candidate lists and mutation plans.

If the workspace is not compatible, it falls back to the full deposit to
preserve correctness.

## Scope intentionally not changed

0172 does not modify:

- Q6/CG projection;
- virial/capacity response;
- population guard;
- mass guard;
- remap;
- thermal-renormalization logic;
- particle roles;
- particle positions;
- particle masses;
- candidate selection rules.

## Validation run

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh

RUN_ROOT=runs/performance_profile_0172_post_thermal \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0172.sh
```

Expected files:

```text
perf_summary_0172.csv
phase_profile_0172.csv
phase_profile_top_0172.csv
q6_cg_profile_0172.csv
q6_cg_profile_top_0172.csv
resampling_guard_profile_0172.csv
resampling_guard_profile_top_0172.csv
deposit_profile_0172.csv
deposit_profile_top_0172.csv
```

## Acceptance criteria

- `resampling_post_thermal_deposit` should decrease significantly.
- The `post_thermal` context in `deposit_profile_0172.csv` should be dominated
  only by the velocity/momentum refresh phases.
- `q6Iterations`, `resampMRelRms`, `resampTransferPairs`, and
  `resampSelectedDonorParticles` should remain consistent.
- If the gain is significant, run the discriminant validation matrix before
  committing because this patch changes the implementation path for a deposit.
