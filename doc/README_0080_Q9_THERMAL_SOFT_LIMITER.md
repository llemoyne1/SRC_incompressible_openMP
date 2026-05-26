# 0080 — Q9 thermal soft correction limiter for ramped hard-inlet validation

## Purpose

Patch 0080 keeps the validated Q6/Q9 model parameters used in the earlier Poiseuille validation,

```text
q6ProjectionStrength = 1.0
q9MassFluxProjectionStrength = 1.0
q9DensityRelaxationBeta = 0.0005
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 2
q9EllipticLowPassPasses = 1
```

but adds a dimensionless Q9 correction-kick limiter.  The goal is not to retune Q9 per case, but to prevent unphysical ballistic kicks when a hard inlet imposes a finite ramp from rest to `Uin` and the mass-flux projection sees a strong transient density/flux mismatch.

The previous unbounded ramped hard-inlet runs showed that the global inlet/outlet flux can become balanced, but only after large correction bursts, very high `kBT`, large `maxParticleSpeed`, and strongly heterogeneous cell populations.  A finite correction speed is interpreted as a residual compressibility / finite pressure-relaxation speed rather than as a case-specific numerical cap.

## New parameters

The legacy absolute limiter is preserved:

```text
q9CorrectionVelocityLimiter = 0.0
```

New parameters are:

```text
q9CorrectionLimiterMode = absolute | none | thermal_soft | thermal_hard
q9CorrectionVelocityLimiterOverThermal = 0.5
q9CorrectionLimiterThermalKBT = 0.0
```

Meaning:

```text
none
    no Q9 correction velocity limiter.

absolute
    historical hard limiter using q9CorrectionVelocityLimiter.
    q9CorrectionVelocityLimiter = 0 disables it.

thermal_hard
    hard limiter with
    duLimit = q9CorrectionVelocityLimiterOverThermal * sqrt(kBTref).

thermal_soft
    smooth tanh limiter with the same duLimit:
    dU_applied = dU_raw * tanh(|dU_raw|/duLimit) / (|dU_raw|/duLimit).
```

The reference temperature is chosen as:

```text
if q9CorrectionLimiterThermalKBT > 0:
    kBTref = q9CorrectionLimiterThermalKBT
else if thermostatTargetKBT > 0:
    kBTref = thermostatTargetKBT
else:
    kBTref = kBT
```

For the current inlet/outlet runs with `kBT = 0.0025`, the default

```text
q9CorrectionLimiterMode = thermal_soft
q9CorrectionVelocityLimiterOverThermal = 0.5
```

gives

```text
duLimit = 0.5 * sqrt(0.0025) = 0.025.
```

This is much less restrictive than the earlier exploratory absolute limiter `0.003`, but it prevents the unbounded kicks of order `O(10)` to `O(100)` observed without any limiter.

## Added run script

```text
scripts/run_poiseuille_hard_inlet_free_outlet_ramped_softlimited_q9_0080.sh
```

It is the 0079 ramped hard-inlet Poiseuille/open-channel validation with the thermal soft limiter enabled by default.  It launches only the complete method by default:

```text
method = q9_virial
RUN_Q9_VIRIAL = 1
RUN_Q6 = 0
RUN_Q9 = 0
RUN_CLASSIC = 0
```

The original 0079 script is not changed, so unbounded comparison runs remain reproducible.

## Recommended gamma=30 smoke

Generate the initial state from MATLAB if needed:

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

Run:

```bash
RUN_ROOT=runs/poiseuille_ramped_softlimited_q9_0080_g30_smoke \
GAMMA=30 \
CASE_STEPS=2000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=1000 \
INLET_RAMP_END_TIME=1.0 \
Q9_CORRECTION_LIMITER_MODE=thermal_soft \
Q9_CORRECTION_LIMITER_OVER_THERMAL=0.5 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_poiseuille_hard_inlet_free_outlet_ramped_softlimited_q9_0080.sh
```

Expected runtime checks:

```text
q9MinCellMassForCorrection = 12
q9MassFloorForCorrection   = 12
q9LowMassRampStart         = 1.5
q9LowMassRampEnd           = 12
q9CorrectionVelocityLimiter = 0.025
```

The last value is the effective thermal limiter in velocity units.

## Recommended long comparison

For a physical ramped run:

```bash
RUN_ROOT=runs/poiseuille_ramped_softlimited_q9_0080_g30 \
GAMMA=30 \
CASE_STEPS=60000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=5000 \
INLET_RAMP_END_TIME=20.0 \
Q9_CORRECTION_LIMITER_MODE=thermal_soft \
Q9_CORRECTION_LIMITER_OVER_THERMAL=0.5 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_poiseuille_hard_inlet_free_outlet_ramped_softlimited_q9_0080.sh
```

Then analyze with the existing 0077 analyzer:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_poiseuille_hard_inlet_free_outlet_0077( ...
    'root','..', ...
    'runRoot','runs/poiseuille_ramped_softlimited_q9_0080_g30', ...
    'lateFraction',0.50);

cd('..')
```

Key diagnostics:

```text
kBTEstimate max and late mean
maxParticleSpeed max and final
q9CorrectionVelocityRawMaxAbs
q9CorrectionVelocityMaxAbs
q9CorrectionVelocityLimiter
q9VelocityLimitedCells
stdN / gamma
maxN / gamma
stateOutletOverInletFluxProxyMeanLate
profileQuadraticR2Late
```

## Commit suggestion

```bash
git add include/simulation_params.h \
        src/params_io_base.cpp \
        src/q9_projection_adapter.cpp \
        scripts/run_poiseuille_hard_inlet_free_outlet_ramped_softlimited_q9_0080.sh \
        doc/README_0080_Q9_THERMAL_SOFT_LIMITER.md

git commit -m "0080 add thermal soft limiter for Q9 correction kicks"
```
