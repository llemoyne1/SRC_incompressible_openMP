# SRC transport calibrator v1

Permanent campaign-side interface for constitutive transport calibration in `SRC_GPU-SURF`.
It does not modify or instrument the C++/CUDA solver. It reuses the qualified x13 transverse-shear, x13h damped-longitudinal, and 0493w1 MSD observables.

## Install

Extract this bundle at the repository root, then run:

```bash
chmod +x scripts/calibrate_src_transport.sh scripts/check_src_transport.sh
bash scripts/check_src_transport.sh
```

The check performs syntax/import/self-tests plus SRC and Q6-G-F preflights; no production simulation is launched.

## Default full SRC calibration

```bash
bash scripts/calibrate_src_transport.sh
```

Default physical point: `gamma=8`, `alpha=120 deg`, `lambda/h=0.72`, `h=1/256`, `kBT=0.125`, `m=1`.
`dt` is derived automatically from `lambda/h` unless `DT_OVERRIDE` is supplied.

The default campaign runs:
- transverse shear: 6 seeds at the main wavelength and 6 at the locality wavelength;
- damped longitudinal SRC mode: 6 replicates;
- MSD: 6 seeds.

Live visualization defaults to `LIVE_VIS_ENABLE=1`, `LIVE_VIS_EVERY=1`, with heavy recording disabled and `LIVE_VIS_HOLD_ON_EXIT=0` for unattended multi-run execution.

## Partial viscosity-only calibration

Useful for an application path such as the future VK re-audit:

```bash
STAGES=S bash scripts/calibrate_src_transport.sh
```

The report treats unrequested acoustics/MSD as not requested, not as failed measurements. `S` is mandatory because transverse `nu_T` is the primary constitutive observable.

## Q6 / Q6-G-F path

```bash
CALIBRATION_PATH=src-q6-g-f STAGES=S \
  bash scripts/calibrate_src_transport.sh
```

The path-effective transverse viscosity is measured on the selected projected path. Standard longitudinal acoustics are not applied to Q6/Q6-G-F; when stage `C` is requested, the reported `c_s` and `nu_L` are explicitly labelled as underlying SRC reference values and path-effective sound remains `NOT_APPLICABLE_Q6`.

## Useful overrides

Physical point:
`GAMMA`, `ROTATION_ANGLE_DEG`, `LAMBDA_OVER_H`, `CELL_SIZE`, `KBT`, `PARTICLE_MASS`, `DT_OVERRIDE`.

Statistics / execution:
`SEEDS`, `BOOTSTRAP`, `STAGES`, `SKIP_EXISTING`, `ANALYZE_ONLY`, `PREFLIGHT_ONLY`, `RUN_ROOT`, `RUN_LABEL`, `BIN`.

Application scales:

```bash
CHARACTERISTIC_U=<U> CHARACTERISTIC_L=<L> \
  bash scripts/calibrate_src_transport.sh
```

This adds `Re`, `Ma`, and `Pe` to the report. Their statistical intervals are propagated from the relevant calibration intervals. The wavelength-locality difference is kept separately as a systematic/resolution qualifier and is not silently folded into a probabilistic confidence interval.

## Outputs

The output directory is generated automatically from the physical point and path unless `RUN_ROOT` is provided, e.g.

```text
runs/src_transport_G8_A120_L0p72_K0p125_H0p00390625_src/
```

Primary human-readable result:

```text
analysis/README_RESULTS.md
```

Machine-readable summaries:

```text
analysis/summary.json
analysis/summary.csv
```

Detailed analysis files:

```text
analysis/shear_runs.csv
analysis/shear_summary.csv
analysis/sound_runs.csv
analysis/sound_summary.csv
analysis/msd_runs.csv
analysis/msd_summary.csv
```

The report separates:
- `Measurement status`: quality/statistics of requested physical observables;
- `Wavelength locality`: main/local wavelength comparison;
- `Overall usability`: `QUALIFIED`, `USABLE`, or `UNRESOLVED`.

It begins with a **Value to use** section containing the recommended transport values, 95% statistical intervals, and the locality qualifier.

`summary.json` is strict JSON: unavailable/non-finite values are written as `null`.

## Resume / audit

`SKIP_EXISTING=1` is the default. A completed run is reused only when its stored signature matches the generated parameters/state, selected path environment, and binary hash. The campaign records Git HEAD/branch, binary SHA-256, seeds, generated parameter files, and per-run environment files.
