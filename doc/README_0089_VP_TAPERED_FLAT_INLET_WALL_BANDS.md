# 0089 — Full-IO VP channel with tapered-flat inlet and wall-band diagnostics

This step closes the current inlet/outlet validation sequence after the successful full-IO VP Poiseuille-profile run and the stable but locally polluted full-IO VP flat-inlet run.

The flat-inlet run showed good global mass/flux/temperature balance, but visual inspection indicated a dense particle pocket attached to the upper wall near the inlet.  The likely cause is the incompatibility between a strict plug velocity imposed up to the wall and VP/no-slip wall dynamics.

## Additions

### C++ parameters

The patch extends `inletVelocitySpatialProfile` with:

```text
flat_taper_y
flat_taper_y_mean
```

Both aliases implement a plug-like profile in the channel core with a smooth wall taper over `inletVelocityWallTaperCells` cells.  The discrete cross-section mean velocity is preserved, so `UIN=0.05` remains the target mean inlet/outlet velocity.

New parameter:

```text
inletVelocityWallTaperCells = 2.0
```

The taper is applied consistently to:

```text
1. hard-cell inlet particles;
2. Q6 open-boundary velocity flux;
3. Q9 open-boundary mass flux.
```

Historical defaults remain unchanged:

```text
inletVelocitySpatialProfile = uniform
```

### Run script

```text
scripts/run_open_channel_full_io_vp_tapered_flat_q9_virial_excl0_0089.sh
```

Default case:

```text
full inlet/outlet, no aperture trimming
VP/no-slip top and bottom walls
Q9+virial complete method
q9OpenBoundaryExclusionCells = 0
virialOpenBoundaryExclusionCells = 0
thermal_soft Q9 limiter
inletVelocitySpatialProfile = flat_taper_y
inletVelocityWallTaperCells = 2.0
```

### MATLAB diagnostic

```text
matlab/analyze_open_channel_wall_bands_0089.m
```

This state-dump diagnostic separates the domain into x-regions:

```text
inlet
interior
outlet
allX
```

and y-bands:

```text
bottom
core
top
walls
allY
```

It reports mass, mean/std/max N, flux proxies, backflow fractions, and `Uy` RMS.  It is meant to quantify wall-attached pockets that can pollute global statistics while the core remains clean.

## Application

```bash
git status
unzip -o /path/to/0089_vp_tapered_flat_inlet_wall_bands_files_only.zip -d .
chmod +x scripts/run_open_channel_full_io_vp_tapered_flat_q9_virial_excl0_0089.sh

./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection
```

## Initial state

The same initial state used for the VP flat/Poiseuille inlet tests is suitable because the run ramps from zero velocity:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

generate_open_channel_classic_state( ...
    'output','../initial_state_open_channel_full_io_vp_flatinlet_48x24_g30_kbt0p0025_ux0p0.smpcd', ...
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
RUN_ROOT=runs/open_channel_full_io_vp_tapered_flat_0089_g30_smoke \
GAMMA=30 \
CASE_STEPS=2000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=1000 \
INLET_RAMP_END_TIME=1.0 \
INLET_VELOCITY_WALL_TAPER_CELLS=2.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_vp_tapered_flat_q9_virial_excl0_0089.sh
```

## Long run

```bash
RUN_ROOT=runs/open_channel_full_io_vp_tapered_flat_0089_g30 \
GAMMA=30 \
CASE_STEPS=80000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=5000 \
INLET_RAMP_END_TIME=40.0 \
INLET_VELOCITY_WALL_TAPER_CELLS=2.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_vp_tapered_flat_q9_virial_excl0_0089.sh
```

## Analysis

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_poiseuille_hard_inlet_free_outlet_0077( ...
    'root','..', ...
    'runRoot','runs/open_channel_full_io_vp_tapered_flat_0089_g30', ...
    'caseGlob','openchan_*', ...
    'lateFraction',0.50);

C = analyze_open_channel_full_io_q9_boundary_modes_0086( ...
    'root','..', ...
    'runRoot','runs/open_channel_full_io_vp_tapered_flat_0089_g30', ...
    'caseGlob','openchan_*', ...
    'lateFraction',0.50, ...
    'makePlots',true, ...
    'showFigures',true, ...
    'closeFigures',false);

W = analyze_open_channel_wall_bands_0089( ...
    'root','..', ...
    'runRoot','runs/open_channel_full_io_vp_tapered_flat_0089_g30', ...
    'caseGlob','openchan_*', ...
    'wallBandCells',3, ...
    'frameStride',1, ...
    'makePlots',true, ...
    'showFigures',true, ...
    'closeFigures',false);

cd('..')
```

## Success criteria

Compared with the strict flat-inlet VP run, the tapered-flat run should retain:

```text
Np close to Nx*Ny*gamma
outlet/inlet flux proxy close to 1
bounded kBT and max speed
no open-boundary vertical density wall
```

and improve:

```text
top-wall/inlet maxN and mass excess
wall-band stdN/maxN
core-only profile quality
late q9 low-mass/ramped activity
```
