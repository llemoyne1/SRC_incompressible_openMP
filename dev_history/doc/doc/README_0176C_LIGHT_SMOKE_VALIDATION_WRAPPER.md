# 0176c - OpenMP-light smoke script correction

This script-only fix replaces the hand-written smoke `params.kv` by a call to the existing
`run_validation_mono_config_0162.sh` launcher.  The previous smoke script wrote keys such
as `gamma`, which are not accepted by the base SRC/MPCD executable in this branch.

The smoke now runs with `MPCD_INTERNAL_PROFILES=0` and then verifies that internal coding
profiles are not produced:

- `phase_profile_*.csv`
- `q6_cg_profile_*.csv`
- `deposit_profile_*.csv`
- `resampling_guard_profile_*.csv`
- `post_guard_profile_*.csv`
- `post_guard_equivalence_*.csv`
- `post_guard_equivalence_trace_*.csv`

The normal validation/runtime summary remains expected.

Usage:

```bash
RUN_ROOT=runs/openmp_light_smoke_0176 \
THREADS=4 \
STEPS=50 \
./scripts/run_openmp_light_smoke_0176.sh
```

This patch changes only `scripts/run_openmp_light_smoke_0176.sh` and documentation.
