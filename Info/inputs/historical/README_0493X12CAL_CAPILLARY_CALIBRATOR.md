# 0493x12cal — Production capillary-property calibrator

## Purpose

`0493x12cal` turns the validated capillary-wave benchmark into a production
calibrator, analogous in use to the existing SRC fluid transport calibrator.

The measured property is the **effective dynamic surface tension**

\[
\omega^2 = \frac{\sigma_\mathrm{eff}}{\rho_\mathrm{ref}}
           k^3\tanh(kH),
\qquad
\sigma_\mathrm{eff}
= \rho_\mathrm{ref}\frac{\omega_\mathrm{fit}^2}
{k^3\tanh(kH)} .
\]

The calibrator runs several resolved wavelengths and thermal realizations,
fits the early/high-SNR part of each trace, and publishes `sigma_eff` only when
cross-mode consistency passes the declared quality policy.

It uses only the Python standard library for analysis. `matplotlib` is optional
and only used to write a dispersion plot when available.

## Scope

The default path is the current liquid/vacuum production chain:

- `src-q6-g-f`;
- Q6 free-surface capillary Dirichlet condition;
- x10o thermal moving interface;
- CIC + Q2;
- x10v one-for-one equal-mass local velocity swap;
- x10w thermal phase limiter off;
- x12a local thermal cooling on;
- no resampling.

The waves are deliberately small-amplitude and low-curvature. Therefore this
tool calibrates the resolved capillary coefficient, **not** the
`surfaceTensionMinRadiusCells` sub-grid curvature limiter.

## Quick start

Check installation:

```bash
bash scripts/check_0493x12cal_capillary_calibrator.sh
```

Preflight only:

```bash
PREFLIGHT_ONLY=1 \
SIGMA_DECLARED=945 \
bash scripts/run_0493x12cal_capillary_calibrator.sh
```

Fast calibration:

```bash
PROFILE=quick \
SIGMA_DECLARED=945 \
RUN_ROOT=runs/capillary_calibration_sigma945_quick \
bash scripts/run_0493x12cal_capillary_calibrator.sh
```

Production calibration:

```bash
PROFILE=production \
SIGMA_DECLARED=945 \
RUN_ROOT=runs/capillary_calibration_sigma945 \
bash scripts/run_0493x12cal_capillary_calibrator.sh
```

`production` uses modes `2 3 4`, three independent thermal realizations, two
theoretical periods per case and about 80 recorded samples per period.
`quick` uses one realization and 1.5 periods.

## Use with a flow/impact scale

To obtain Weber directly:

```bash
PROFILE=production \
SIGMA_DECLARED=945 \
CHARACTERISTIC_U=0.36 \
CHARACTERISTIC_D=0.3125 \
RUN_ROOT=runs/capillary_calibration_sigma945 \
bash scripts/run_0493x12cal_capillary_calibrator.sh
```

The summary contains both

- `WeberDeclared`, using the input `SIGMA_DECLARED`;
- `WeberEffectiveRaw`, using the measured dynamic `sigma_eff`.

To also obtain Reynolds and Ohnesorge, either supply the calibrated kinematic
viscosity directly,

```bash
KINEMATIC_VISCOSITY=0.0006743265812
```

or point to the CSV/JSON produced by the transport calibrator:

```bash
TRANSPORT_CALIBRATION=runs/.../analysis/fluid_calibration_0493w1.csv
```

An optional positive `GRAVITY_MAGNITUDE` adds a Bond number.

## Main controls

- `SIGMA_DECLARED` — capillary coefficient to calibrate.
- `PROFILE=quick|production`.
- `MODES="2 3 4"` — Fourier modes.
- `REPLICATES` — independent thermal realizations.
- `RUN_PERIODS` — simulated theoretical periods per case.
- `SAMPLES_PER_PERIOD` — recorder temporal resolution.
- `FIT_PERIODS=1.0` — primary early-fit window.
- `SENSITIVITY_PERIODS=0.75,1.0,1.25`.
- `SURFACE_TENSION_MIN_RADIUS_CELLS` — retained in metadata; resolved waves
  should not touch this cutoff.
- `MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS`.
- all fluid parameters (`GAMMA`, `DT`, `KBT`, `LIQUID_MASS`,
  `ROTATION_ANGLE`, thermostat settings) should match the intended production
  fluid.

Advanced overrides:

- `STEPS_OVERRIDE`;
- `RECORD_EVERY_OVERRIDE`;
- `MAX_RECORD_GB`;
- `ALLOW_LARGE_RECORDINGS=1`;
- `ANALYZE_ONLY=1`.

## Outputs

Under `$RUN_ROOT/analysis`:

- `capillary_calibration_0493x12cal.csv` — one-row production property table;
- `capillary_calibration_0493x12cal.json` — machine-readable equivalent;
- `README_0493x12cal_RESULTS.md` — user-facing report;
- `capillary_calibration_cases_0493x12cal.csv` — every mode/seed fit;
- `capillary_calibration_modes_0493x12cal.csv` — grouped mode consistency;
- `traces/*.csv` — reconstructed interface Fourier traces;
- `capillary_calibration_dispersion_0493x12cal.png` when matplotlib is present.

The primary fields are:

- `surfaceTensionEffectiveRaw`;
- `surfaceTensionGain = sigma_eff / sigma_declared`;
- `surfaceTensionEffective` — populated only for a qualified `PASS`;
- `surfaceTensionGainModeRelativeStd`;
- `meanFitR2`.

## Quality policy

`PASS` requires:

- every requested mode to be usable;
- each grouped mode to contain a PASS fit;
- mean fit `R² >= 0.98`;
- relative cross-mode gain spread `<= 5%`.

`REVIEW` retains the raw estimate but deliberately does not publish it as the
qualified effective property. `INVALID` means the campaign must not be used as
a capillary calibration.

This mirrors the transport calibrator's principle: a raw estimator is always
available for diagnosis, while downstream dimensionless numbers should use a
qualified measured property whenever possible.

## Historical reference

The x11c validation on the earlier production chain found, without empirical
renormalization,

- paired Young–Laplace gain about `0.9587`;
- capillary-wave constrained slope `omega_num^2/omega_th^2 = 0.9884`;
- mean capillary-wave fit `R² ~= 0.9966`.

`0493x12cal` does not hard-code that gain. It re-measures it for the user's
actual numerical fluid, declared sigma and current production path.


## FIX2 analysis contract

The capillary-wave displacement is reconstructed from the **linear column
mass**, not from a clipped cellwise phase fraction:

\[
H_i(t)=\frac{\Delta y}{\gamma m_p}\sum_j m_{ij}(t).
\]

This makes the mean reconstructed height exactly consistent with total mass
and prevents thermal bulk-density fluctuations above the reference occupancy
from being irreversibly clipped into a false interface displacement.

For repeated thermal seeds, the signed Fourier quadratures are synchronized
and averaged **before** the production frequency fit:

\[
A^{\rm ens}_{c,s}(t)=\frac{1}{N_s}\sum_r A^{(r)}_{c,s}(t).
\]

Per-seed fits remain in `capillary_calibration_cases_0493x12cal.csv` as
diagnostics.  The production property comes from the ensemble-mode fits in
`capillary_calibration_modes_0493x12cal.csv`.

A non-PASS campaign is never labelled "calibrated" in the dispersion plot;
the plotted line is explicitly marked `raw slope (REVIEW|INVALID)`.
