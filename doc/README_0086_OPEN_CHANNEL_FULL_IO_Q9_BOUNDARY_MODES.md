# 0086 — Full-IO/slip long Q9 boundary-mode diagnostics

## Purpose

The 0085 short exclusion sweep showed that the simplified full-height inlet/outlet slip channel is cleanest in Q6, while Q9 introduces a persistent density/velocity pattern even without no-slip walls, segmented outlet, or immersed solids.

This patch adds a longer diagnostic matrix without modifying the C++ core.  It is intended to isolate whether the defect comes from:

1. the Q9 open-boundary exclusion layer,
2. the Q9 low-k density relaxation target,
3. the virial kick,
4. or Q9/open-boundary coupling itself.

The configuration remains deliberately simple:

- full-height hard inlet on the left,
- full-height passive outlet on the right,
- specular/slip top and bottom boundaries,
- no immersed solid,
- ramped inlet velocity,
- thermal soft Q9 limiter,
- Q6/Q9 open fluxes balanced with `Uex = Uin`.

## Files

```text
scripts/run_open_channel_full_io_q9_boundary_modes_0086.sh
matlab/analyze_open_channel_full_io_q9_boundary_modes_0086.m
doc/README_0086_OPEN_CHANNEL_FULL_IO_Q9_BOUNDARY_MODES.md
```

## Default case matrix

The script runs these cases by default:

```text
1. Q6 baseline,       q9 exclusion = 3
2. Q9 only, beta=5e-4, q9 exclusion = 3
3. Q9 only, beta=5e-4, q9 exclusion = 1
4. Q9 only, beta=5e-4, q9 exclusion = 0
5. Q9 only, beta=0,    q9 exclusion = 0
6. Q9+virial, beta=5e-4, q9/virial exclusion = 1
```

`q9_virial` with virial exclusion `0` is not included because the current parser intentionally requires `virialOpenBoundaryExclusionCells > 0` for inlet/outlet virial use.

## Generate initial state

MATLAB command, from the repository root:

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
RUN_ROOT=runs/open_channel_full_io_q9_boundary_modes_0086_smoke \
GAMMA=30 \
CASE_STEPS=2000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=1000 \
INLET_RAMP_END_TIME=1.0 \
RUN_Q9_EXCL1_BETA=0 \
RUN_Q9_EXCL0_BETA=1 \
RUN_Q9_EXCL0_BETA0=1 \
RUN_Q9_VIRIAL_EXCL1_BETA=0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_q9_boundary_modes_0086.sh
```

## Long diagnostic run

Recommended default:

```bash
RUN_ROOT=runs/open_channel_full_io_q9_boundary_modes_0086_g30 \
GAMMA=30 \
CASE_STEPS=80000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=5000 \
INLET_RAMP_END_TIME=40.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_q9_boundary_modes_0086.sh
```

If runtime is too high, the most discriminating reduced set is:

```bash
RUN_ROOT=runs/open_channel_full_io_q9_boundary_modes_0086_g30_reduced \
GAMMA=30 \
CASE_STEPS=80000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=5000 \
INLET_RAMP_END_TIME=40.0 \
RUN_Q9_EXCL3_BETA=0 \
RUN_Q9_EXCL1_BETA=0 \
RUN_Q9_VIRIAL_EXCL1_BETA=0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_q9_boundary_modes_0086.sh
```

This reduced set keeps:

```text
Q6 baseline
Q9 beta=5e-4 exclusion=0
Q9 beta=0 exclusion=0
```

which tests whether Q9 itself remains problematic when the open-boundary exclusion interface is removed, and whether the density relaxation term is the trigger.

## Analysis

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_open_channel_full_io_q9_boundary_modes_0086( ...
    'root','..', ...
    'runRoot','runs/open_channel_full_io_q9_boundary_modes_0086_g30', ...
    'caseGlob','openchan_*', ...
    'lateFraction',0.50, ...
    'frameStride',1, ...
    'makePlots',true, ...
    'showFigures',true, ...
    'closeFigures',false);

cd('..')
```

The analyzer writes:

```text
analysis_0086_q9_boundary_modes/open_channel_full_io_q9_boundary_modes_runtime_summary_0086.csv
analysis_0086_q9_boundary_modes/open_channel_full_io_q9_boundary_modes_runtime_all_cases_0086.csv
analysis_0086_q9_boundary_modes/open_channel_full_io_q9_boundary_modes_column_timeseries_0086.csv
analysis_0086_q9_boundary_modes/open_channel_full_io_q9_boundary_modes_column_summary_0086.csv
```

It also produces plots for runtime metrics and column-density diagnostics.

## Interpretation

Key conclusions to look for:

### If Q9 exclusion=0 is clean

Then the main problem is likely the interface between the Q9-active domain and the Q9-excluded open-boundary layer.  The next core change should make Q9 reach the open boundary more consistently, or replace the excluded layer by a face-consistent boundary treatment.

### If Q9 exclusion=0 remains bad but beta=0 is clean

Then the low-k density relaxation target is the main trigger in the open channel.  The next step should reformulate or delay the density-relaxation component near open boundaries.

### If Q9 exclusion=0 and beta=0 remain bad

Then the defect is more fundamental to the Q9 mass-flux projection / open-flux coupling, rather than to the exclusion layer or density relaxation.  The next step should inspect the Q9 target mismatch and boundary mass-flux construction.

### If Q9 and Q9+virial are similar

The virial kick is not the source of the full-IO/slip artifact.  It can be treated after Q9/open-boundary coupling is repaired.
