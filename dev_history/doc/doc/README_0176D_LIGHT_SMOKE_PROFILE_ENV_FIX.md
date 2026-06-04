# 0176d — OpenMP-light smoke wrapper profile-env fix

This script-only correction makes `scripts/run_openmp_light_smoke_0176.sh` respect a caller-supplied `MPCD_INTERNAL_PROFILES` value instead of forcing the light mode in all cases.

Default production/light smoke:

```bash
RUN_ROOT=runs/openmp_light_smoke_0176 \
THREADS=4 \
STEPS=50 \
SUMMARY_EVERY=10 \
./scripts/run_openmp_light_smoke_0176.sh
```

Expected result: no internal profile CSVs.

Development/profiling smoke:

```bash
MPCD_INTERNAL_PROFILES=1 \
RUN_ROOT=runs/openmp_light_profile_enabled_0176 \
THREADS=4 \
STEPS=50 \
SUMMARY_EVERY=10 \
./scripts/run_openmp_light_smoke_0176.sh
```

Expected result: at least one internal profile CSV such as `phase_profile_*.csv`, `q6_cg_profile_*.csv`, `deposit_profile_*.csv`, or `resampling_guard_profile_*.csv`.

No C++ code is changed by this patch.
