# 0074 — Receded/thin backward-step with validated Q9 parameters

This run is a geometry-isolation test for the inlet/outlet backward-step case.
It keeps the reduced grid and particle scales used in the current backward-step
campaign, but moves and thins the obstacle so that Q6/Q9/virial have enough
space to act before the front face of the obstacle.

No C++ source is modified by this patch.

## Geometry and method

Default configuration:

```text
Lx = 2.0
Ly = 1.0
Nx = 48
Ny = 24
gamma = 20
kBT = 0.0025
dt = 0.001
Uin = 0.05
CASE_STEPS = 80000
```

Obstacle:

```text
immersedSolidXMin = 0.625
immersedSolidXMax = 0.750
immersedSolidYMin = 0.0
immersedSolidYMax = 0.25
```

With `dx = 2/48`, the front face is at column 15. With
`q9OpenBoundaryExclusionCells = 3` and `q9ImmersedSolidHaloCells = 1`, this
leaves roughly 11 Q9-active columns between the inlet open-boundary exclusion
and the obstacle halo, instead of only about 2 in the previous close-obstacle
case.

The default method is the complete chain only:

```text
method = q9_virial
RUN_Q9_VIRIAL = 1
RUN_Q6 = 0
RUN_Q9 = 0
RUN_CLASSIC = 0
```

Q9 parameters are reset to the validated Poiseuille elliptic-lowpass values:

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

The grid and thermal/particle scales are intentionally kept at the current
backward-step values, not the older Poiseuille `gamma=40`, `kBT=0.01` values.

## Apply

From the repository root:

```bash
unzip -o 0074_backward_step_receded_thin_validated_q9_files_only.zip -d .
chmod +x scripts/run_backward_step_receded_thin_validated_q9_0074.sh
./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection
```

## Generate the initial state manually from MATLAB

MATLAB is usually not available as a command-line executable on the target
machine. Generate the state from the MATLAB GUI/desktop:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

generate_backward_step_exact_fluid_state_0072( ...
    'output','../initial_state_backward_step_receded_thin_48x24_g20_kbt0p0025_ux0p05_x0p625_0p750_y0p25.smpcd', ...
    'Lx',2.0, ...
    'Ly',1.0, ...
    'Nx',48, ...
    'Ny',24, ...
    'gamma',20, ...
    'kBT',0.0025, ...
    'Ux',0.05, ...
    'Uy',0.0, ...
    'xMin',0.625, ...
    'xMax',0.750, ...
    'yMin',0.0, ...
    'yMax',0.25);

cd('..')
```

## Smoke

```bash
RUN_ROOT=runs/backward_step_receded_thin_validated_q9_0074_smoke \
CASE_STEPS=1000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=500 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_backward_step_receded_thin_validated_q9_0074.sh
```

Check immediately:

```text
kBTEstimate
maxParticleSpeed
q9CorrectionVelocityRms
q9CorrectionVelocityMaxAbs
q9DensityStdRatioEstimate
stdN
maxN
```

## Main run

```bash
RUN_ROOT=runs/backward_step_receded_thin_validated_q9_0074 \
CASE_STEPS=80000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=5000 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_backward_step_receded_thin_validated_q9_0074.sh
```

## MATLAB analysis and visuals

The existing 0072 analyzers are reused because they read the obstacle geometry
from `params_used.kv`.

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_backward_step_hard_inlet_budget_0072( ...
    'root','..', ...
    'runRoot','runs/backward_step_receded_thin_validated_q9_0074', ...
    'lateFraction',0.50);

V = make_backward_step_hard_inlet_visual_report_0072( ...
    'root','..', ...
    'runRoot','runs/backward_step_receded_thin_validated_q9_0074', ...
    'maxFramesPerCase',16);

cd('..')
```

This patch also fixes the MATLAB visual report bug where `q9LowMassRamp` was
requested but not stored in the local mask structure.

## Interpretation

This run tests whether the violent close-obstacle case was mainly caused by an
over-constrained geometry. A favorable result would show lower peaks in
`kBTEstimate`, `maxParticleSpeed`, `stdN`, `maxN`, and upstream/front-band mass,
while retaining natural inlet/outlet flux relaxation.
