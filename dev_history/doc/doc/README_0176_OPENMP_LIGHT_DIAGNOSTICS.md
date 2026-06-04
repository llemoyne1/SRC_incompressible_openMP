# 0176 — OpenMP light diagnostics mode

This patch is the first cleanup step for the `clean/openmp-light` branch.

It does not remove the optimized OpenMP physics code. It only changes the default diagnostic policy:

- ordinary runtime/fluid summaries remain enabled;
- internal coding/profiling CSVs are disabled by default;
- set `MPCD_INTERNAL_PROFILES=1` to re-enable internal profile CSVs when needed.

Internal profile CSVs disabled by default include, depending on the current branch state:

- `phase_profile_*.csv`
- `q6_cg_profile_*.csv`
- `deposit_profile_*.csv`
- `resampling_guard_profile_*.csv`
- `post_guard_profile_*.csv`
- `post_guard_equivalence_*.csv`

## Apply

From the `SRC_openMP_light` worktree:

```bash
python3 scripts/apply_openmp_light_diagnostics_0176.py
```

Then check the diff:

```bash
git diff --stat
git diff -- src/main_src_mpcd_base.cpp src/weighted_resampling.cpp src/src_mpcd_base.cpp
```

## Build

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
```

If this worktree uses a different build script, use the repository-local production build command.

## Smoke test

```bash
RUN_ROOT=runs/openmp_light_smoke_0176 \
THREADS=4 \
STEPS=50 \
./scripts/run_openmp_light_smoke_0176.sh
```

Expected: ordinary runtime output is produced, while internal profile CSVs are absent.

## Re-enable internal profiles

For debugging or GPU-development comparison:

```bash
MPCD_INTERNAL_PROFILES=1 build/src_mpcd_base params.kv
```

This preserves the ability to use the light branch for occasional profiling without making those files the default production behavior.
