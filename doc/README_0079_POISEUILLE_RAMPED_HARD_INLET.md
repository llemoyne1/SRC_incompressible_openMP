# 0079 — Poiseuille hard-inlet/free-outlet with progressive inlet ramp

## Purpose

Patch 0079 keeps the inlet/outlet validation focused on a straight channel, without immersed solid, but removes the impulsive start used in 0077.  The hard inlet still targets the same final uniform velocity `Uin`; however, the velocity imposed on reservoir particles and the matching Q6/Q9 open-boundary flux targets are multiplied by a time-ramp factor.

This is intended to test whether the violent Q9 transient observed with `Uin=0.05` comes from imposing the full hard-inlet velocity at `t=0`, rather than from the final inlet/outlet condition itself.

## New parameters

The following keys are now accepted in `.kv` parameter files:

```text
inletVelocityRampEnable = true|false
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 20.0
inletVelocityRampInitialFactor = 0.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = linear|smoothstep
```

When enabled, the stored inlet velocity values remain the final target values.  The effective inlet velocity is

```text
Uin_effective(t) = rampFactor(t) * Uin_target
```

The same factor is used consistently by:

```text
hard_cell_density reservoir particle generation
Q6 open-boundary velocity flux
Q9 open-boundary mass-flux target
```

The default profile in the 0079 script is `smoothstep`, ramping from 0 to 1 over `t=0..20`.

## Script

```text
scripts/run_poiseuille_hard_inlet_free_outlet_ramped_q9_0079.sh
```

Default case:

```text
Lx = 2.0
Ly = 1.0
Nx = 48
Ny = 24
gamma = 20
kBT = 0.0025
Uin = 0.05
CASE_STEPS = 60000
INLET_RAMP_END_TIME = 20.0
method = q9_virial
q9MassFluxProjectionStrength = 1.0
q9DensityRelaxationBeta = 0.0005
q9CorrectionVelocityLimiter = 0.0
```

The initial state defaults to `INIT_UX=0.0`, i.e. a channel at rest.  The inlet then ramps to the final target velocity.

## Manual state generation

MATLAB is not always available from the shell.  For the default gamma=20 run:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

generate_open_channel_classic_state( ...
    'output','../initial_state_poiseuille_hard_inlet_48x24_g20_kbt0p0025_ux0p0.smpcd', ...
    'Lx',2.0, ...
    'Ly',1.0, ...
    'Nx',48, ...
    'Ny',24, ...
    'gamma',20, ...
    'kBT',0.0025, ...
    'inletUx',0.0);

cd('..')
```

For the short gamma=30 conformity smoke:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

generate_open_channel_classic_state( ...
    'output','../initial_state_poiseuille_hard_inlet_48x24_g30_kbt0p0025_ux0p0.smpcd', ...
    'Lx',2.0, ...
    'Ly',1.0, ...
    'Nx',48, ...
    'Ny',24, ...
    'gamma',30, ...
    'kBT',0.0025, ...
    'inletUx',0.0);

cd('..')
```

## Short gamma=30 smoke

Use a short ramp so that the final velocity is reached during the smoke:

```bash
RUN_ROOT=runs/poiseuille_ramped_q9_0079_g30_smoke \
GAMMA=30 \
CASE_STEPS=2000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=1000 \
INLET_RAMP_END_TIME=1.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_poiseuille_hard_inlet_free_outlet_ramped_q9_0079.sh
```

Expected conformity checks in `summary_runtime.csv`:

```text
q9MinCellMassForCorrection = 12
q9MassFloorForCorrection   = 12
q9LowMassRampStart         = 1.5
q9LowMassRampEnd           = 12
q9VelocityLimitedCells     = 0
```

The effective inlet speed is visible through `inletMeanUx`; after `t >= 1`, it should be close to `0.05` up to thermal noise and reservoir rescaling.

## Main ramped run

```bash
RUN_ROOT=runs/poiseuille_hard_inlet_free_outlet_ramped_q9_0079 \
CASE_STEPS=60000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=5000 \
INLET_RAMP_END_TIME=20.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_poiseuille_hard_inlet_free_outlet_ramped_q9_0079.sh
```

## Analysis

The existing 0077 analyzer is reused:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_poiseuille_hard_inlet_free_outlet_0077( ...
    'root','..', ...
    'runRoot','runs/poiseuille_hard_inlet_free_outlet_ramped_q9_0079', ...
    'lateFraction',0.50);

cd('..')
```

Primary quantities to compare against the impulsive 0077 run:

```text
kBTMaxAll and kBTMeanLate
maxParticleSpeed max/final
q9CorrectionVelocityRms and q9CorrectionVelocityMaxAbs
NpSlopeLate_perTime
stateOutletOverInletFluxProxyMeanLate
stdNLate and maxNLate
profileQuadraticR2Late
profileCenterMinusWallUxLate
```

## Interpretation

A successful ramped run should retain the favorable global inlet/outlet behavior,

```text
outletFluxProxy / inletFluxProxy -> 1
```

while reducing the early violent Q9 events seen in the impulsive run.  The final method parameters are not retuned; only the start-up path is regularized.
