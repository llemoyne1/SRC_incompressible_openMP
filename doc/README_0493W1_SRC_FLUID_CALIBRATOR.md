# 0493w1 — SRC fluid calibrator

This runner establishes the effective fluid represented by one exact SRC
configuration before that configuration is used in obstacle, wall, multiphase
or resampling studies.

## Three independent measurements

### 1. Taylor–Green transverse decay

The modal amplitude is fitted as

\[
A(t)=A_0\exp[-\nu(k_x^2+k_y^2)t],
\]

which gives the effective shear/kinematic viscosity `nu`.

### 2. Weak standing longitudinal mode

The state is initialized with a small density modulation and zero coherent
velocity:

\[
\rho(x,0)=\rho_0[1+\epsilon\cos(kx)],\qquad u_x(x,0)=0.
\]

fix2 no longer requires a complete acoustic oscillation.  At every state dump,
the analyzer measures the complex normalized density mode `rhoHat` and the
complex longitudinal momentum/velocity mode `uHat`.  With the Fourier
convention `exp(-ikx)`, the fitted linear model is

\[
\frac{d\widehat\rho}{dt}=-ik\widehat u,
\]

\[
\frac{d\widehat u}{dt}
 =-ikc_s^2\widehat\rho-\nu_L k^2\widehat u.
\]

For each thermal realization the modes are measured at identical dump times.
fix3 averages the complex modes across realizations, then integrates both
equations cumulatively from the initial state with the trapezoidal rule. The
momentum balance is fitted as a complex, two-parameter, non-negative
least-squares problem.  It directly provides:

- sound speed `c_s`;
- effective longitudinal kinematic viscosity `nu_L`;
- continuity and momentum residuals;
- regression condition number;
- acoustic damping ratio and eigenvalues;
- classification as `underdamped`, `critical` or `overdamped`.

For the fitted two-field model,

\[
\beta=\frac{\nu_L k^2}{2},\qquad
\zeta=\frac{\nu_L k}{2c_s}.
\]

The acoustic attenuation coefficient reported as `Gamma` is `nu_L/2` in this
specific closure.  The quantity `nu_L - nu` is only a longitudinal excess over
the Taylor–Green shear viscosity.  It must not be called a bulk viscosity when
thermal and thermostat contributions have not been separated.

A damped-cosine fit is retained only as an optional cross-check when the fitted
mode is underdamped and the observation window contains at least half a
predicted damped cycle.  It is not used to identify `c_s`.

### 3. Periodic equilibrium MSD

Persistent slots are followed through state dumps. Periodic increments are
unwrapped and centre-of-mass displacement is removed. In 2D,

\[
\langle |\Delta r|^2\rangle = 4D_{self}t.
\]

This provides the self-diffusion coefficient and therefore the Schmidt number

\[
Sc=\frac{\nu}{D_{self}}.
\]

## Configuration that defines the fluid

Preserve at least:

- `Lx`, `Ly`, `NX`, `NY` and therefore collision-cell size;
- `GAMMA`, `DT`, `KBT` and `PARTICLE_MASS`;
- `ROTATION_ANGLE`, `RANDOM_ROTATION_SIGN` and `GRID_SHIFT_ENABLE`;
- `THERMOSTAT_ENABLE`, `THERMOSTAT_MODE`, `THERMOSTAT_EVERY`, target `kBT` and minimum population.

Q6 and resampling are deliberately disabled: this characterizes the underlying
SRC fluid. A production thermostat must be enabled identically in the
calibrator because raw SRC and thermostatted SRC are different effective
fluids.

The preflight prints the complete SRC configuration and labels it `raw_src` or
`thermostatted_src`.

## Usage

```bash
PREFLIGHT_ONLY=1 bash scripts/run_0493w1_src_fluid_calibrator.sh
LIVE_PROGRESS=1 bash scripts/run_0493w1_src_fluid_calibrator.sh
```

Example reproducing the current segmented-Darcy collision/thermostat settings
while using a smaller periodic box with the same collision-cell size:

```bash
Lx=0.5 Ly=0.5 NX=64 NY=64 GAMMA=20 \
DT=0.001 KBT=0.001 PARTICLE_MASS=1 \
ROTATION_ANGLE=1.5707963267948966 \
RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true \
THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale \
THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT=0.001 \
SOUND_MODE_X=2 SOUND_STEPS=2500 SOUND_DUMP_COUNT=250 \
CHARACTERISTIC_U=0.15 CHARACTERISTIC_L=0.24 \
PREFLIGHT_ONLY=1 \
bash scripts/run_0493w1_src_fluid_calibrator.sh
```

## fix3 acoustic defaults

```text
SOUND_MODE_X=2
SOUND_DENSITY_AMPLITUDE=0.08
SOUND_REPLICATES=4
SOUND_STEPS=1200
SOUND_DUMP_COUNT=120
```

The dump cadence is derived from `SOUND_DUMP_COUNT`. Independent sound states
use deterministic seeds separated by `SOUND_SEED_STRIDE`.

The ideal isothermal and adiabatic-2D sound-speed proxies remain in the
preflight only as contextual scales.  They do not initialize the coherent
velocity, size the default run, or enter the primary fit.  Consequently, the
reported proxy cycle count may be below one without invalidating the
hydrodynamic regression.

Preflight warns when:

- fewer than 40 regression intervals are available;
- the fastest proxy period would have fewer than 12 samples;
- the sound wavelength contains fewer than 16 collision cells;
- the estimated dump volume exceeds `MAX_DUMP_GB`.

The final result is marked `REVIEW` rather than aborted when the longitudinal
fit is poorly conditioned, continuity or momentum residuals are excessive, or
`c_s^2` reaches the non-negative constraint.

## Outputs

```text
runs/0493w1_src_fluid_calibrator/analysis/fluid_calibration_0493w1.csv
runs/0493w1_src_fluid_calibrator/analysis/fluid_calibration_0493w1.json
runs/0493w1_src_fluid_calibrator/analysis/README_0493w1_RESULTS.md
runs/0493w1_src_fluid_calibrator/analysis/tg_decay_0493w1.csv
runs/0493w1_src_fluid_calibrator/analysis/sound_mode_0493w1.csv
runs/0493w1_src_fluid_calibrator/analysis/msd_0493w1.csv
```

The calibration includes viscosity, measured sound speed, longitudinal
viscosity, self-diffusion, Schmidt number, damping regime, density and kinetic
scales, thermal ballistic-step/mean-free-path proxies, cell CFL values and,
when characteristic scales are supplied, Reynolds, Mach, mass Péclet and
Knudsen proxies.

The MSD run defaults to an at-most `64x64` box preserving collision-cell size.
Use `MSD_GRID_MODE=full` to include the full-box finite-size effect. Preflight
estimates dump volume and enforces `MAX_DUMP_GB`.

## fix3 — ensemble acoustics and physical-fluid presweep

fix3 addresses weak longitudinal signal by generating independent thermal sound
realizations (`SOUND_REPLICATES`, default 4), averaging their complex density
and velocity modes, then fitting cumulative balances from time zero. The default
sound density amplitude is 0.08 and the default short campaign is 1200 steps
with 120 requested dumps.

Each property now has an independent status: `viscosityStatus`, `soundStatus`
and `diffusionStatus`. A failed sound fit keeps the raw diagnostic but does not
publish a measured Mach number. The report instead retains the ideal
isothermal/adiabatic-2D Mach proxy interval.

Taylor--Green uses an adaptive pre-noise-floor fit window and reports the
spread of viscosity over acceptable windows. The physical report also gives
`Re/Ma = c_s L/nu`, `Re` attainable at `Ma=0.3`, and `Ma` required for `Re=50`.

A candidate-family runner is provided:

```bash
PREFLIGHT_ONLY=1 PROFILE=physical6 \
  bash scripts/run_0493w1_src_fluid_presweep.sh

LIVE_PROGRESS=1 PROFILE=physical6 \
  bash scripts/run_0493w1_src_fluid_presweep.sh
```

The default six candidates vary collision-cell size (`1/192`, `1/256`,
`1/384`), collision interval (`0.002`, `0.004`) and `kBT` (`0.03`, `0.125`),
while preserving gamma 20, 90-degree SRC rotation, random shift and the
cell-relative thermostat. They span a thermal ballistic displacement of roughly
0.08 to 0.45 collision cell per step and are ranked using validated measured
transport properties rather than theoretical viscosity proxies.
