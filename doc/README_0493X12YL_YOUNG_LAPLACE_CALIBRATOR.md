# 0493x12yl — paired Young–Laplace surface-tension calibrator

## Purpose

This calibrator measures the **mechanical/static surface tension of the exact
current SRC_GPU-SURF production free-surface chain**.  It is intentionally
separate from the capillary-wave dispersion test.

For each resolved drop radius and seed it runs a paired case:

- `sigma = 0` baseline, with the same kinetic-interface chain;
- `sigma = SIGMA_DECLARED` active case.

It reads the existing solved-Q6 static-drop pressure diagnostic and evaluates

    dp_cap = p(sigma) - p(0)
    dp_cap = sigma_eff * <kappa>_active

The sigma=0 subtraction removes the solved-Q6 gauge/background.  The measured
active-run curvature is used instead of replacing it by `1/R`.

No C++/CUDA source is modified and no new runtime diagnostic is introduced.

## Production chain locked by the runner

- `src-q6-g-f`
- x10o thermal-interface primitive ON
- CIC ON
- Q2/biquadratic interface ON
- x10u one-for-one relocation ON
- x10v equal-mass velocity swap ON
- x10p overlap recovery ON
- x10w limiter OFF
- x12a local thermal cooling ON
- resampling OFF
- virial density kick OFF

The default radii are deliberately larger than the x12a cooling radius, so
x12a remains selected but should be dynamically inactive.  The curvature
cutoff is also far below the resolved drop curvature; its actual tail clip
fraction is reported and enters qualification.

## Default campaigns

`PROFILE=quick`

- radii `R/h = 32 40`
- 1 seed
- 500 steps
- 4 solver runs total (2 paired radii)

`PROFILE=production`

- radii `R/h = 32 40 48`
- 3 seeds
- 1000 steps
- 18 solver runs total (9 active/baseline pairs)

The domain is `256 x 256`, `Lx=Ly=1`, hence `h=1/256`, matching the cell size
used by the current splash/capillary studies.

## Outputs

Under `$RUN_ROOT/analysis`:

- `young_laplace_calibration_0493x12yl.csv`: one-row calibration summary;
- `young_laplace_calibration_0493x12yl.json`: machine-readable summary;
- `young_laplace_pairs_0493x12yl.csv`: every active/baseline pair;
- `young_laplace_radii_0493x12yl.csv`: radius-averaged gains;
- `young_laplace_calibration_report_0493x12yl.txt`: compact report;
- `young_laplace_pressure_0493x12yl.png`: paired pressure law, if matplotlib is available;
- `young_laplace_gain_vs_radius_0493x12yl.png`: resolution consistency, if matplotlib is available.

The principal reported quantity is

    surfaceTensionEffectiveRaw = SIGMA_DECLARED * surfaceTensionGainRaw.

`surfaceTensionEffective` is populated only for a `PASS` result.  A `REVIEW`
or `INVALID` result never silently becomes a qualified calibration.

## Qualification

The production result is `PASS` when, simultaneously:

- origin-constrained Young–Laplace regression has centered `R² >= 0.90`;
- radius-to-radius gain relative standard deviation is at most 10%;
- free-intercept and origin-constrained slopes differ by at most 15%;
- maximum tail curvature-limiter clipping is at most 2%.

These thresholds are deliberately compatible with the historical x11c static
validation (`gain ~0.959`, `R² ~0.936`) while still rejecting a strongly
radius-dependent or limiter-contaminated result.

## Optional dimensionless evaluation

If `CHARACTERISTIC_U`, `CHARACTERISTIC_D`, and optionally
`KINEMATIC_VISCOSITY` / `GRAVITY_MAGNITUDE` are provided, the analyzer also
reports `We`, `Re`, `Oh`, and `Bo` using the calibrated surface tension.  This
is intended for the subsequent rigorous dimensioning of the target article
benchmark.

## Interpretation

This calibrator answers: **what mechanical surface tension results from the
selected numerical parameters?**

It does not require every capillary-wave mode to satisfy the inviscid continuum
dispersion law.  Short-wave dispersion is a separate resolution/domain-of-
validity measurement and must not be folded into the scalar Young–Laplace
surface tension.
