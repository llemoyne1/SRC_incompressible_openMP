# 0075 — Receded/thin backward-step with validated Q9 parameters, lower Uin

This patch adds a lower-inlet-speed variant of the 0074 receded/thin
backward-step run. It keeps the same grid, particle scale, geometry, and
validated Q9/virial model parameters, but lowers the inlet velocity to test
whether the violent thermal/density transients observed at `Uin = 0.05` are
primarily caused by an overly aggressive inlet transient.

No C++ source is modified by this patch.

## Configuration

Default configuration:

```text
Lx = 2.0
Ly = 1.0
Nx = 48
Ny = 24
gamma = 20
kBT = 0.0025
dt = 0.001
Uin = 0.025
CASE_STEPS = 80000
```

The advective time is now:

```text
Tadv = Lx/Uin = 2.0/0.025 = 80
```

so the default run reaches approximately one advective time.

Obstacle:

```text
immersedSolidXMin = 0.625
immersedSolidXMax = 0.750
immersedSolidYMin = 0.0
immersedSolidYMax = 0.25
```

The default method is the complete chain only:

```text
method = q9_virial
RUN_Q9_VIRIAL = 1
RUN_Q6 = 0
RUN_Q9 = 0
RUN_CLASSIC = 0
```

Q9 parameters remain the validated elliptic-lowpass values used in the 0074
script:

```text
q6ProjectionStrength = 1.0
q9MassFluxProjectionStrength = 1.0
q9DensityRelaxationBeta = 0.0005
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 2
q9EllipticLowPassPasses = 1
q9MomentumCorrectionEnable = true
q9CorrectionVelocityLimiter = 0.0
```

## Additional MATLAB visual-report change

This patch also updates `matlab/make_backward_step_hard_inlet_visual_report_0072.m`:

```text
figure('Visible','on', ...)
```

and does not close generated figures automatically after saving PNG files. This
makes the generated panels directly inspectable from the MATLAB desktop.

## Apply

From the repository root:

```bash
unzip -o 0075_backward_step_receded_thin_validated_q9_uin025_files_only.zip -d .
chmod +x scripts/run_backward_step_receded_thin_validated_q9_uin025_0075.sh
./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection
```

## Generate the initial state manually from MATLAB

MATLAB is usually not available as a command-line executable on the target
machine. Generate the state from the MATLAB GUI/desktop:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

generate_backward_step_exact_fluid_state_0072( ...
    'output','../initial_state_backward_step_receded_thin_48x24_g20_kbt0p0025_ux0p025_x0p625_0p750_y0p25.smpcd', ...
    'Lx',2.0, ...
    'Ly',1.0, ...
    'Nx',48, ...
    'Ny',24, ...
    'gamma',20, ...
    'kBT',0.0025, ...
    'Ux',0.025, ...
    'Uy',0.0, ...
    'xMin',0.625, ...
    'xMax',0.750, ...
    'yMin',0.0, ...
    'yMax',0.25);

cd('..')
```

## Smoke

```bash
RUN_ROOT=runs/backward_step_receded_thin_validated_q9_uin025_0075_smoke \
CASE_STEPS=1000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=500 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_backward_step_receded_thin_validated_q9_uin025_0075.sh
```

## Main run

```bash
RUN_ROOT=runs/backward_step_receded_thin_validated_q9_uin025_0075 \
CASE_STEPS=80000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=5000 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_backward_step_receded_thin_validated_q9_uin025_0075.sh
```

## MATLAB analysis and visuals

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_backward_step_hard_inlet_budget_0072( ...
    'root','..', ...
    'runRoot','runs/backward_step_receded_thin_validated_q9_uin025_0075', ...
    'lateFraction',0.50);

V = make_backward_step_hard_inlet_visual_report_0072( ...
    'root','..', ...
    'runRoot','runs/backward_step_receded_thin_validated_q9_uin025_0075', ...
    'maxFramesPerCase',16);

cd('..')
```

## Interpretation targets

Compare against 0074 at `Uin = 0.05`:

```text
kBTEstimate peak and late values
maxParticleSpeed peak and late values
q9CorrectionVelocityRms / MaxAbs
stdN and maxN
meanFluidN / totalFluidMass
upstreamLowerMass and frontBandMass
outletOverInletFluxProxyMeanLate
q9DensityStdRatioEstimate
```

A favorable result is not necessarily a perfectly flat density field, but it
should show substantially reduced thermal runaway, fewer ballistic episodes, and
less severe local population spikes than the 0074 `Uin = 0.05` run.
