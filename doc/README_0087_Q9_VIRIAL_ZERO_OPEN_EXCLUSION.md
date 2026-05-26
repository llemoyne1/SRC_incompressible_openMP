# 0087 — Q9+virial with zero open-boundary exclusion

## Purpose

The 0086 full-inlet/full-outlet slip sweep showed that Q9 behaves cleanly when
`q9OpenBoundaryExclusionCells = 0`, while inactive open-boundary bands with
`q9OpenBoundaryExclusionCells > 0` can create a numerical interface/impedance
near the outlet.  The next missing check is the complete `q9_virial` method with
both Q9 and the virial closure active up to the open boundary.

This patch therefore allows:

```text
virialOpenBoundaryExclusionCells = 0
```

and adds a dedicated runner for the simplified full-height inlet/outlet, slip
wall channel.

## Code change

`src/params_io_base.cpp` no longer rejects `virialOpenBoundaryExclusionCells = 0`
when inlet/outlet boundaries and the virial kick are enabled.  Negative values
remain invalid.

The existing virial implementation already treats zero exclusion as: do not build
an open-boundary exclusion mask, and use all non-solid fluid cells for the virial
closure.  This patch only removes the older safety restriction from the parser.

## New runner

```text
scripts/run_open_channel_full_io_q9_virial_excl0_0087.sh
```

Default configuration:

```text
method                         = q9_virial
left boundary                  = full-height hard_cell_density inlet
right boundary                 = full-height outlet
bottom/top                     = specular / slip
immersedSolidEnable             = false
q9OpenBoundaryExclusionCells    = 0
virialOpenBoundaryExclusionCells = 0
q9CorrectionLimiterMode          = thermal_soft
q9CorrectionVelocityLimiterOverThermal = 0.5
q9MassFluxProjectionStrength     = 1.0
q9DensityRelaxationBeta          = 0.0005
q9TargetFilter                   = elliptic_lowpass
```

Optional comparison cases are available with:

```bash
RUN_Q6=1
RUN_Q9=1
```

but the default runs only the complete `q9_virial` case.

## Apply

```bash
git status
unzip -o /chemin/vers/0087_q9_virial_zero_open_exclusion_files_only.zip -d .
chmod +x scripts/run_open_channel_full_io_q9_virial_excl0_0087.sh
./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection
```

## Initial state

Use the same state as 0084/0086.  For `gamma=30`:

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

## Smoke

```bash
RUN_ROOT=runs/open_channel_full_io_q9_virial_excl0_0087_g30_smoke \
GAMMA=30 \
CASE_STEPS=2000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=1000 \
INLET_RAMP_END_TIME=1.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_q9_virial_excl0_0087.sh
```

Expected checks in `summary_runtime.csv`:

```text
q9OpenBoundaryExcludedCells = 0
virialOpenBoundaryExcludedCells = 0
q9CorrectionVelocityLimiter ≈ 0.025 for kBT=0.0025 and overThermal=0.5
```

## Long diagnostic run

```bash
RUN_ROOT=runs/open_channel_full_io_q9_virial_excl0_0087_g30 \
GAMMA=30 \
CASE_STEPS=80000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=5000 \
INLET_RAMP_END_TIME=40.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_q9_virial_excl0_0087.sh
```

## Analysis

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_poiseuille_hard_inlet_free_outlet_0077( ...
    'root','..', ...
    'runRoot','runs/open_channel_full_io_q9_virial_excl0_0087_g30', ...
    'caseGlob','openchan_*', ...
    'lateFraction',0.50);

C = analyze_open_channel_full_io_q9_boundary_modes_0086( ...
    'root','..', ...
    'runRoot','runs/open_channel_full_io_q9_virial_excl0_0087_g30', ...
    'caseGlob','openchan_*', ...
    'lateFraction',0.50, ...
    'makePlots',true, ...
    'showFigures',true, ...
    'closeFigures',false);

cd('..')
```

## Interpretation

If `q9_virial` with both exclusions set to zero behaves like the clean 0086 `Q9
excl0` cases, then the nominal inlet/outlet configuration should no longer use
open-boundary exclusion bands for Q9 or virial in full open-channel validations.

If the virial case remains unstable even with zero exclusions, the next suspect
is not the boundary exclusion interface but the virial closure itself under open
inlet/outlet transport.
