# 0077 — Poiseuille / open-channel hard inlet and free outlet with validated Q9 parameters

## Scope

This patch adds a no-immersed-solid validation run for the `feature/inlet-outlet` branch.

The goal is to isolate the inlet/outlet machinery from immersed-solid effects:

- left boundary: hard-cell-density inlet with uniform imposed `Uin`;
- right boundary: passive/free outlet;
- bottom/top boundaries: solid channel walls;
- no immersed obstacle;
- Q6/Q9 parameters reset to the previously validated elliptic-Q6/Q9 Poiseuille values;
- no Q9 velocity limiter.

This is intended as the first finalization step for inlet/outlet before implementing segmented inlet/outlet apertures mixed with wall segments.

## Added files

```text
scripts/run_poiseuille_hard_inlet_free_outlet_validated_q9_0077.sh
matlab/analyze_poiseuille_hard_inlet_free_outlet_0077.m
doc/README_0077_POISEUILLE_HARD_INLET_FREE_OUTLET.md
```

## Default run

The default run launches only the complete current method:

```text
RUN_Q9_VIRIAL = 1
RUN_Q6 = 0
RUN_Q9 = 0
RUN_CLASSIC = 0
```

The optional flags remain available for comparison:

```bash
RUN_Q6=1
RUN_Q9=1
RUN_CLASSIC=1
```

## Default geometry and duration

```text
Lx = 2.0
Ly = 1.0
Nx = 48
Ny = 24
gamma = 20
kBT = 0.0025
Uin = 0.05
dt = 0.001
nSteps = 60000
```

The advective time is:

```text
Tadv = Lx/Uin = 40
```

so the default run covers:

```text
tFinal = 60 = 1.5 Tadv
```

## Validated Q6/Q9 parameters restored

The run uses the validated elliptic-Q6/Q9 Poiseuille parameters from the earlier `feature/elliptic-q6-core` validation:

```text
q6ProjectionStrength = 1.0
projectionMaxIterations = 500
projectionTolerance = 1.0e-10

q9MassFluxProjectionStrength = 1.0
q9DensityRelaxationBeta = 0.0005
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 2
q9EllipticLowPassPasses = 1
q9MomentumCorrectionEnable = true
q9CorrectionVelocityLimiter = 0.0
```

The low-mass regularization remains enabled for hard-open-boundary safety:

```text
q9LowMassTreatment = ramp_floor
q9MinCellMassForCorrection = 8.0
q9MassFloorForCorrection = 8.0
q9LowMassRampStart = 1.0
q9LowMassRampEnd = 8.0
```

## Mean-flow control

By default:

```text
keepMeanFlowEnable = false
```

This is deliberate: the test is meant to measure the natural response of a hard inlet and passive outlet, not a globally reset mean flow.

For a comparison run:

```bash
KEEP_MEAN_FLOW=true \
RUN_ROOT=runs/poiseuille_hard_inlet_free_outlet_validated_q9_0077_keepmean \
./scripts/run_poiseuille_hard_inlet_free_outlet_validated_q9_0077.sh
```

## Generate the initial state

If MATLAB is not available from the shell, generate the state once from the MATLAB UI:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

generate_open_channel_classic_state( ...
    'output','../initial_state_poiseuille_hard_inlet_48x24_g20_kbt0p0025_ux0p05.smpcd', ...
    'Lx',2.0, ...
    'Ly',1.0, ...
    'Nx',48, ...
    'Ny',24, ...
    'gamma',20, ...
    'kBT',0.0025, ...
    'inletUx',0.05);

cd('..')
```

## Smoke run

```bash
RUN_ROOT=runs/poiseuille_hard_inlet_free_outlet_validated_q9_0077_smoke \
CASE_STEPS=1000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=500 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_poiseuille_hard_inlet_free_outlet_validated_q9_0077.sh
```

## Main run

```bash
RUN_ROOT=runs/poiseuille_hard_inlet_free_outlet_validated_q9_0077 \
CASE_STEPS=60000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=5000 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_poiseuille_hard_inlet_free_outlet_validated_q9_0077.sh
```

## MATLAB analysis

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_poiseuille_hard_inlet_free_outlet_0077( ...
    'root','..', ...
    'runRoot','runs/poiseuille_hard_inlet_free_outlet_validated_q9_0077', ...
    'lateFraction',0.50);

cd('..')
```

The main summary file is:

```text
runs/poiseuille_hard_inlet_free_outlet_validated_q9_0077/analysis_0077/poiseuille_hard_inlet_free_outlet_summary_0077.csv
```

## Primary diagnostics

The validation should focus on:

```text
NpSlopeLate_perTime
stateOutletOverInletFluxProxyMeanLate
stateMassSlopeLate
stateStdNSlopeLate
kBTMeanLate
kBTMaxAll
stdNLate
maxNLate
q9CorrectionVelocityRmsMeanLate
q9CorrectionVelocityMaxAbsLateMax
q9DensityStdRatioMeanLate
q9LowMassSuppressedCellsMeanLate
q9VelocityLimitedCellsMeanLate
profileCenterMinusWallUxLate
profileQuadraticR2Late
```

Favorable behavior:

```text
NpSlopeLate_perTime -> 0
stateOutletOverInletFluxProxyMeanLate -> 1
stdN and maxN remain bounded
kBT remains bounded
q6/q9 residuals remain converged
q9 low-mass suppression remains non-pathological
Poiseuille-like profile develops between the y-walls
```

## Suggested commit

```bash
git add scripts/run_poiseuille_hard_inlet_free_outlet_validated_q9_0077.sh \
        matlab/analyze_poiseuille_hard_inlet_free_outlet_0077.m \
        doc/README_0077_POISEUILLE_HARD_INLET_FREE_OUTLET.md

git commit -m "0077 add Poiseuille hard-inlet free-outlet validation"
```

## 0078 note — gamma-relative low-mass thresholds

Patch 0078 updates this script so that the Q9 low-mass thresholds are gamma-relative by default.  The previous gamma=20 values `rampStart=1`, `rampEnd=8`, `massFloor=8`, `minMass=8` are represented as `0.05`, `0.40`, `0.40`, `0.40` times the reference gamma.  The effective absolute values remain visible in `summary_runtime.csv` under the existing columns `q9LowMassRampStart`, `q9LowMassRampEnd`, `q9MassFloorForCorrection`, and `q9MinCellMassForCorrection`.
