# 0177 — Disable internal-profile runtime overhead in OpenMP light mode

This patch is for the `clean/openmp-light` branch after 0176.

## Goal

0176 stopped writing internal developer profile CSV files unless
`MPCD_INTERNAL_PROFILES=1` was set. 0177 goes one step further: in the default
light mode, the fine-grained profile timers and profile accumulators are also
no-ops, so the production OpenMP branch does not pay the runtime cost of
internal instrumentation.

## Changed files

- `src/src_mpcd_base.cpp`
- `src/main_src_mpcd_base.cpp`
- `src/weighted_resampling.cpp`
- `src/q6_projection_adapter.cpp`
- `src/elliptic_projection.cpp`

## Behaviour

Default mode:

```bash
./build/src_mpcd_base params.kv
```

- no `phase_profile_*.csv`
- no `q6_cg_profile_*.csv`
- no `deposit_profile_*.csv`
- no `resampling_guard_profile_*.csv`
- profile timers do not call `steady_clock::now()`
- deposit/profile accumulators return immediately

Developer/profile mode:

```bash
MPCD_INTERNAL_PROFILES=1 ./build/src_mpcd_base params.kv
```

- internal profile files are produced as in 0176
- profile timers and accumulators are active

## Implementation notes

The environment flag is cached once per translation unit using a function-local
`static const bool`, avoiding repeated `getenv()` calls in hot paths.

The patch does not change numerical algorithms, particle roles, Q6 projection,
resampling, virial/capacity logic, or fluid summaries.

## Suggested validation

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh

RUN_ROOT=runs/openmp_light_smoke_0177 \
THREADS=4 \
STEPS=50 \
SUMMARY_EVERY=10 \
./scripts/run_openmp_light_smoke_0176.sh

MPCD_INTERNAL_PROFILES=1 \
RUN_ROOT=runs/openmp_light_profile_enabled_0177 \
THREADS=4 \
STEPS=50 \
SUMMARY_EVERY=10 \
./scripts/run_openmp_light_smoke_0176.sh
```

Expected:

- light run: no internal profile files;
- profile-enabled run: internal profile files produced;
- `validation_summary_0162.csv` remains physically consistent in both runs.
