# 0073 — Backward-step run with Poiseuille-validated Q9 parameters

This run intentionally resets the Q9 parameters to the filtered-Q9 Poiseuille validation set from the `feature/elliptic-q6-core` branch, and applies them to the 48x24 backward-step inlet/outlet case.

No C++ source file is modified by this patch.

## Purpose

The 0072 backward-step run showed that the global inlet/outlet flux can eventually approach balance, but only after a very large compression in the upstream lower pocket and front-obstacle band. In 0072, Q9 was deliberately weak and velocity-limited:

```text
q9MassFluxProjectionStrength = 0.03
q9DensityRelaxationBeta      = 0.001
q9CorrectionVelocityLimiter  = 0.003
q9LowKMaxIndex               = 4
q9LowMassTreatment           = ramp_floor
```

The 0073 run removes that case-specific weakening and restores the prior validated filtered-Q9 parameter set.

## Default run

The default run is the complete chain only:

```text
method = q9_virial
Q6 velocity projection enabled through the method
Q9 mass-flux projection enabled
virial kick enabled
```

Optional `classic`, `q6`, and `q9` cases remain available through environment flags, but are disabled by default.

## Geometry and duration

```text
Lx = 2.0
Ly = 1.0
Nx = 48
Ny = 24
CASE_STEPS = 80000
dt = 0.001
Uin = 0.05
```

Thus:

```text
Tadv = Lx / Uin = 40
Tfinal = 80 = 2 Tadv
```

The backward-step obstacle is:

```text
x in [0.25, 0.65]
y in [0.0, 0.50]
```

## Q9 parameters restored from the validated Poiseuille run

The following defaults are copied from the Poiseuille filtered-Q9 validation, except for open-boundary and immersed-solid masks, which did not exist in the periodic-x / solid-y Poiseuille case:

```text
q6ProjectionStrength         = 1.0
projectionMaxIterations      = 500
projectionTolerance          = 1.0e-10
q9MassFluxProjectionStrength = 1.0
q9DensityRelaxationBeta      = 0.0005
q9TargetFilter               = elliptic_lowpass
q9LowKMaxIndex               = 2
q9EllipticLowPassPasses      = 1
q9MomentumCorrectionEnable   = true
q9CorrectionVelocityLimiter  = 0.0
q9MinCellMassForCorrection   = 0.0
q9LowMassTreatment           = suppress
q9MassFloorForCorrection     = 0.0
```

`q9CorrectionVelocityLimiter = 0.0` disables the limiter in the current C++ implementation.

The default particle statistics also match the Poiseuille validation scale as closely as possible for this inlet/outlet geometry:

```text
gamma = 40
kBT   = 0.01
```

To run with the previous 0072 physical particle scale instead, override:

```bash
GAMMA=20 KBT=0.0025 STATE_FILE=initial_state_backward_step_exact_fluid_48x24_g20_kbt0p0025_ux0p05.smpcd \
./scripts/run_backward_step_validated_q9_0073.sh
```

## Open-boundary and obstacle-specific parameters

These are retained from the 48x24 inlet/outlet backward-step setup because they have no counterpart in the periodic-x Poiseuille validation:

```text
bcLeft = inlet
bcRight = outlet
inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletReservoirCells = 3
q9OpenBoundaryExclusionCells = 3
q9ImmersedSolidHaloCells = 1
virialOpenBoundaryExclusionCells = 3
```

The Q9 immersed-solid halo remains one cell by default. This is the smallest conservative non-zero halo at 48x24. It can be forced to zero with:

```bash
Q9_IMMERSED_HALO_CELLS=0 ./scripts/run_backward_step_validated_q9_0073.sh
```

but that should be treated as a separate stress test.

## Generate initial state manually

If MATLAB is not available from the shell, generate the default `gamma=40`, `kBT=0.01` state from MATLAB:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

generate_backward_step_exact_fluid_state_0072( ...
    'output','../initial_state_backward_step_exact_fluid_48x24_g40_kbt0p01_ux0p05.smpcd', ...
    'Lx',2.0, ...
    'Ly',1.0, ...
    'Nx',48, ...
    'Ny',24, ...
    'gamma',40, ...
    'kBT',0.01, ...
    'Ux',0.05, ...
    'Uy',0.0, ...
    'xMin',0.25, ...
    'xMax',0.65, ...
    'yMin',0.0, ...
    'yMax',0.50);

cd('..')
```

## Smoke test

Because the Q9 velocity limiter is disabled, run a short smoke first:

```bash
RUN_ROOT=runs/backward_step_validated_q9_0073_smoke \
CASE_STEPS=1000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=500 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_backward_step_validated_q9_0073.sh
```

Inspect especially:

```text
kBTEstimate
maxParticleSpeed
q9CorrectionVelocityRms
q9CorrectionVelocityMaxAbs
q9CorrectionVelocityRawRms
q9CorrectionVelocityRawMaxAbs
q9VelocityLimitedCells
stdN
maxN
```

With the limiter disabled, `q9VelocityLimitedCells` should remain zero.

## Main 80000-step run

```bash
RUN_ROOT=runs/backward_step_validated_q9_0073 \
RUN_Q6=0 \
RUN_Q9=0 \
RUN_Q9_VIRIAL=1 \
RUN_CLASSIC=0 \
CASE_STEPS=80000 \
SUMMARY_EVERY=250 \
DUMP_STATE_EVERY=5000 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_backward_step_validated_q9_0073.sh
```

## Analysis

Reuse the 0072 analysis functions:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_backward_step_hard_inlet_budget_0072( ...
    'root','..', ...
    'runRoot','runs/backward_step_validated_q9_0073', ...
    'lateFraction',0.50);

V = make_backward_step_hard_inlet_visual_report_0072( ...
    'root','..', ...
    'runRoot','runs/backward_step_validated_q9_0073', ...
    'maxFramesPerCase',16);

cd('..')
```

## Quick runtime summary check

```bash
python3 - <<'PY'
import pandas as pd
from pathlib import Path

root = Path('runs/backward_step_validated_q9_0073')
for f in sorted(root.glob('backstep_*/summary_runtime.csv')):
    df = pd.read_csv(f)
    cols = [
        'step','time','Np','kBTEstimate','meanParticleSpeed','maxParticleSpeed',
        'stdN','maxN','q9Applied','q9CorrectionVelocityRms',
        'q9CorrectionVelocityMaxAbs','q9CorrectionVelocityRawRms',
        'q9CorrectionVelocityRawMaxAbs','q9CorrectionVelocityLimiter',
        'q9VelocityLimitedCells','q9DensityStdRatioEstimate',
        'virialKickApplied','virialDuAppliedRms','virialDuAppliedMaxAbs'
    ]
    cols = [c for c in cols if c in df.columns]
    print('\n===', f.parent.name, '===')
    print(df[cols].tail(12).to_string(index=False))
PY
```

## Interpretation

This run is intentionally aggressive. It tests whether the validated low-k Q9 formulation can absorb the strong backward-step compression without case-specific weakening or velocity clipping. The key question is not whether large kicks appear, but whether the method returns to bounded thermal and density statistics once the inlet/outlet through-flow is established.
