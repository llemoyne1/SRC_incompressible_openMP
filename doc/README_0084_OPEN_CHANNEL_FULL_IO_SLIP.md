# 0084 — Full inlet/outlet with slip walls

## Purpose

This run is a deliberately simpler inlet/outlet validation case.  It removes, for now, the two effects that made the Poiseuille hard-inlet/free-outlet tests ambiguous:

1. no-slip / VP wall conflict at the outlet corners;
2. incompatible uniform inlet velocity next to no-slip walls.

The goal is to test only the core open-boundary machinery:

- full-height hard inlet on the left;
- full-height outlet on the right;
- the same open-boundary velocity imposed by Q6/Q9 at inlet and outlet, `Uex = Uin`;
- specular/slip top and bottom walls;
- no immersed solid;
- Q9 validated parameters with the thermal soft limiter.

This patch does not modify the C++ core.  It adds only a run script and this documentation.

## Files

```text
scripts/run_open_channel_full_io_slip_softlimited_q9_0084.sh
doc/README_0084_OPEN_CHANNEL_FULL_IO_SLIP.md
```

## Default configuration

```text
Lx = 2.0, Ly = 1.0
Nx = 48, Ny = 24
gamma = 30
kBT = 0.0025
Uin = Uex = 0.05
dt = 0.001
CASE_STEPS = 80000
bcLeft = inlet
bcRight = outlet
bcBottom = specular
bcTop = specular
wallVpEnable = false
wallAccommodation = 0.0
immersedSolidEnable = false
```

The inlet velocity is ramped by default:

```text
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0
inletVelocityRampEndTime = 40
inletVelocityRampProfile = smoothstep
```

For a short smoke, use `INLET_RAMP_END_TIME=1.0`.

## Q6/Q9 parameters

The script keeps the validated Q6/Q9 parameter set used in the current branch:

```text
q6ProjectionStrength = 1.0
q9MassFluxProjectionStrength = 1.0
q9DensityRelaxationBeta = 0.0005
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 2
q9EllipticLowPassPasses = 1
q9CorrectionLimiterMode = thermal_soft
q9CorrectionVelocityLimiterOverThermal = 0.5
```

For `kBT = 0.0025`, the thermal soft limiter has effective scale

```text
dU_limit = 0.5 * sqrt(kBT) = 0.025
```

The low-mass thresholds remain gamma-relative.

## Generate the initial state

MATLAB is not available on the cluster command line in the usual workflow, so generate the state once from MATLAB:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

generate_open_channel_classic_state( ...
    'output','../initial_state_open_channel_full_io_slip_48x24_g30_kbt0p0025_ux0p0.smpcd', ...
    'Lx',2.0, ...
    'Ly',1.0, ...
    'Nx',48, ...
    'Ny',24, ...
    'gamma',30, ...
    'kBT',0.0025, ...
    'inletUx',0.0);

cd('..')
```

For `gamma = 20`, use:

```matlab
generate_open_channel_classic_state( ...
    'output','../initial_state_open_channel_full_io_slip_48x24_g20_kbt0p0025_ux0p0.smpcd', ...
    'Lx',2.0,'Ly',1.0,'Nx',48,'Ny',24, ...
    'gamma',20,'kBT',0.0025,'inletUx',0.0);
```

## Smoke test

```bash
RUN_ROOT=runs/open_channel_full_io_slip_0084_g30_smoke \
GAMMA=30 \
CASE_STEPS=2000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=1000 \
INLET_RAMP_END_TIME=1.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_slip_softlimited_q9_0084.sh
```

Expected checks:

```text
bcBottom = specular
bcTop = specular
inletReservoirCells = 72 for gamma=30 full-height, 3 inlet columns, 24 rows
inletReservoirTargetParticles = 2160
q6OpenBoundaryFluxXLow ~= q6OpenBoundaryFluxXHigh ~= Uin(t)
q9OpenBoundaryMassFluxXLow ~= q9OpenBoundaryMassFluxXHigh
q9CorrectionVelocityLimiter ~= 0.025
q9VelocityLimitedCells non-pathological
kBT bounded
Np close to 48*24*gamma
```

## Long run

```bash
RUN_ROOT=runs/open_channel_full_io_slip_0084_g30 \
GAMMA=30 \
CASE_STEPS=80000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=5000 \
INLET_RAMP_END_TIME=40.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_slip_softlimited_q9_0084.sh
```

## Analysis

The existing Poiseuille/open-channel analyzer can still be used for mass, flux, and profile diagnostics, but the parabolic-profile `R2` should not be interpreted as a no-slip Poiseuille validation because the walls are slip/specular in this case.

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_poiseuille_hard_inlet_free_outlet_0077( ...
    'root','..', ...
    'runRoot','runs/open_channel_full_io_slip_0084_g30', ...
    'lateFraction',0.50);

cd('..')
```

Optionally inspect the same outlet-band diagnostics used in 0082:

```matlab
C = analyze_poiseuille_outlet_corner_bands_0082( ...
    'root','..', ...
    'runRoot','runs/open_channel_full_io_slip_0084_g30', ...
    'wallBandCells',3, ...
    'frameStride',1, ...
    'makePlots',true, ...
    'showFigures',true, ...
    'closeFigures',false);
```

## Interpretation

This is a first-rung validation.  Success means:

```text
mean density remains close to gamma;
total mass does not drift strongly;
outlet/inlet flux ratio remains close to one after the ramp;
no organized outlet-blocking recirculation appears;
thermal soft limiter remains active but not saturated everywhere;
kBT and max particle speed stay bounded.
```

If this case is clean, the next rung is to reintroduce VP/no-slip walls with an inlet/outlet Poiseuille profile.  Only after that should the harder case of uniform inlet velocity with VP/no-slip walls be retested.
