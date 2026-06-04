# 0133 — Resampling thermal-renormalization fast path

This patch fixes a severe performance issue in the resampling branch.

## Problem

After patch 0129, thermal renormalization is intentionally attempted every
step.  In channel/Taylor--Green cases with many wet cells, the diagnostic
momentum-residual computation in `apply_resampling_local_thermal_renormalization`
scanned all particles once for every renormalized cell:

```text
O(Ncells * Nparticles) per step
```

For a 64 x 32 Poiseuille case with 40960 particles, this creates tens of
millions of unnecessary particle checks per time step and can dominate the
runtime.

## Fix

The post-renormalization cell momentum is now accumulated during the same
particle loop that applies the velocity rescaling.  The residual pass is then
only over cells:

```text
O(Nparticles + Ncells) per step
```

The physical operation is unchanged:

```text
v_p <- U_c + lambda_c (v_p - U_c)
```

with local preservation of the reference thermal energy and cell momentum to
roundoff.

## Validation

The cadence smoke test remains valid:

```bash
CXXFLAGS='--std=c++17 -O0 -Wall -Wextra -fopenmp' \
./scripts/run_resampling_cadence_smoke_0129.sh
```

Expected:

```text
[0129 resampling cadence smoke] OK
```

## Recommended performance check

Use a short Poiseuille run after applying the patch:

```bash
POIS_PROJECTION_OPERATOR=channel_fv_cg \
POIS_BODY_ACCEL=0.05 \
POIS_STEPS=1000 \
POIS_DUMP_EVERY=1000000 \
POIS_SUMMARY_EVERY=10 \
POIS_THREADS=8 \
./scripts/run_poiseuille_wallvp_resampling_validation_0131.sh
```

Compare the printed `wall=` values for `classic`, `q6`, and `q6_resampling`.
