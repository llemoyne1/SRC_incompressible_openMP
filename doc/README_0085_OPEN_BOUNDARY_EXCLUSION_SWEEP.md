# 0085 — Full-IO slip open-boundary exclusion sweep

## Purpose

The full-height inlet/outlet slip-wall diagnostic still shows a coherent density/velocity pattern near the outlet, even after removing no-slip walls, outlet segmentation, and immersed solids.  The dominant visual feature is close to the internal edge of the Q9/virial open-boundary exclusion band.

This patch adds only runner and analysis scripts.  It does not modify the C++ core.

The goal is to test whether the observed vertical density layer follows the width of the open-boundary exclusion band:

```text
q9OpenBoundaryExclusionCells
virialOpenBoundaryExclusionCells
```

If the layer moves from approximately `x = Lx - 3 dx` to `x = Lx - dx`, or disappears when the exclusion is zero, the issue is probably the interface between the active Q9/virial region and the open-boundary band.  If the pattern remains unchanged in Q6-only and all exclusion widths, the issue is more likely in the hard-inlet/outlet particle boundary itself.

## Files

```text
scripts/run_open_channel_full_io_exclusion_sweep_0085.sh
matlab/analyze_open_channel_full_io_exclusion_sweep_0085.m
doc/README_0085_OPEN_BOUNDARY_EXCLUSION_SWEEP.md
```

## Default matrix

The script reuses the 0084 full-height slip-wall configuration:

```text
left boundary  : full-height hard_cell_density inlet
right boundary : full-height outlet
bottom/top     : specular/slip
immersed solid : disabled
Uin = Uex      : ramped to 0.05
q9 limiter     : thermal_soft, C = 0.5
```

It runs by default:

```text
1. q6 only,       q9/virial exclusion = 3
2. q9 only,       q9 exclusion        = 3
3. q9+virial,     q9/virial exclusion = 3
4. q9+virial,     q9/virial exclusion = 1
5. q9+virial,     q9/virial exclusion = 0
```

The first case checks whether Q6 alone already creates the pattern.  The next two isolate Q9 and virial.  The final two determine whether the structure follows the exclusion width.

## Apply

```bash
git status
unzip -o /path/to/0085_open_boundary_exclusion_sweep_files_only.zip -d .
chmod +x scripts/run_open_channel_full_io_exclusion_sweep_0085.sh
./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection
```

## Generate the initial state

For the default `gamma=30` case:

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

The full matrix is still five runs.  For a fast check of script correctness, disable some cases:

```bash
RUN_ROOT=runs/open_channel_full_io_exclusion_sweep_0085_smoke \
GAMMA=30 \
CASE_STEPS=2000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=1000 \
INLET_RAMP_END_TIME=1.0 \
RUN_Q6_EXCL3=1 \
RUN_Q9_EXCL3=0 \
RUN_Q9_VIRIAL_EXCL3=1 \
RUN_Q9_VIRIAL_EXCL1=0 \
RUN_Q9_VIRIAL_EXCL0=1 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_exclusion_sweep_0085.sh
```

## Diagnostic run

A 40000-step run is enough to see the pattern that appeared in 0084:

```bash
RUN_ROOT=runs/open_channel_full_io_exclusion_sweep_0085_g30 \
GAMMA=30 \
CASE_STEPS=40000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=2500 \
INLET_RAMP_END_TIME=40.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_exclusion_sweep_0085.sh
```

## MATLAB analysis

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_open_channel_full_io_exclusion_sweep_0085( ...
    'root','..', ...
    'runRoot','runs/open_channel_full_io_exclusion_sweep_0085_g30', ...
    'caseGlob','openchan_*', ...
    'lateFraction',0.50, ...
    'makePlots',true, ...
    'showFigures',true, ...
    'closeFigures',false);

cd('..')
```

Outputs:

```text
runs/open_channel_full_io_exclusion_sweep_0085_g30/analysis_0085_exclusion_sweep/open_channel_full_io_exclusion_sweep_summary_0085.csv
runs/open_channel_full_io_exclusion_sweep_0085_g30/analysis_0085_exclusion_sweep/open_channel_full_io_exclusion_sweep_runtime_all_cases_0085.csv
runs/open_channel_full_io_exclusion_sweep_0085_g30/analysis_0085_exclusion_sweep/runtime_*.png
```

For visual inspection, use for example:

```matlab
runRoot = '../runs/open_channel_full_io_exclusion_sweep_0085_g30';
caseA = fullfile(runRoot,'openchan_q9_virial_fullio_slip_excl3_u0p05_48x24');
caseB = fullfile(runRoot,'openchan_q9_virial_fullio_slip_excl1_u0p05_48x24');
caseC = fullfile(runRoot,'openchan_q9_virial_fullio_slip_excl0_u0p05_48x24');

play_smpcd_filtered_animation(caseA,'field','N','filterType','none');
play_smpcd_filtered_animation(caseB,'field','N','filterType','none');
play_smpcd_filtered_animation(caseC,'field','N','filterType','none');
```

## Interpretation

The expected discriminants are:

```text
Q6-only already shows the pattern:
    the hard inlet/outlet particle boundary or Q6 open flux is suspect.

Q9-only shows the pattern, Q6 does not:
    the Q9 open-boundary coupling is suspect.

Q9+virial is worse than Q9-only:
    virial exclusion / virial pressure coupling near open boundaries amplifies the issue.

The layer moves/disappears when exclusion changes 3 -> 1 -> 0:
    the active-Q9/virial-to-open-band interface is the main cause.

The layer remains at x≈Lx for all exclusions:
    the outlet deletion boundary itself is the main cause.
```

This patch is meant to decide the next C++ change.  It intentionally avoids further changes to Q9, the limiter, or the outlet core until the exclusion-band mechanism is confirmed or rejected.
