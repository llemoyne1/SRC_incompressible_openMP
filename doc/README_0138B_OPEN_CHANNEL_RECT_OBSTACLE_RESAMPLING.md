# 0138B — Open-channel fixed-rectangle obstacle validation

This patch replaces the attempted open-channel cylinder validation with an inlet/outlet-compatible fixed rectangular obstacle.

The current C++ safety guard for Q6 with inlet/outlet and immersed solids requires:

- `inletInjectionMode = hard_cell_density`
- `inletReservoirMode = hard_cell_density`
- `immersedSolidShape = rectangle`
- `projectionImmersedSolidMaskEnable = true`
- `projectionAllowUnmaskedImmersedSolid = false`

Therefore a circular open-channel obstacle cannot be run with Q6/resampling on this branch without a dedicated C++ extension of the Q6 inlet/outlet immersed-solid mask.  This 0138B case keeps the same validation purpose—open-boundary wake-like flow around a bluff body—but uses the supported fixed rectangle.

## MATLAB initialization

From repository root:

```bash
cd matlab
```

In MATLAB:

```matlab
prepare_open_channel_rect_obstacle_resampling_0138b( ...
    'output', '../init/open_channel_rect_obstacle_resampling_0138b/initial_state_open_channel_rect_obstacle_0138b.smpcd', ...
    'Lx', 4.0, 'Ly', 1.0, ...
    'Nx', 192, 'Ny', 48, 'gamma', 20, ...
    'rectXMin', 0.85, 'rectXMax', 1.10, ...
    'rectYMin', 0.38, 'rectYMax', 0.62, ...
    'populationMode', 'random', ...
    'populationStd', 6.0, 'populationMin', 4, 'populationMax', 36, ...
    'initialProfile', 'poiseuille', 'initialMeanUx', 0.05, ...
    'kBT', 0.001, ...
    'seed', 1380138, ...
    'makePreview', true);
```

## OpenMP run

From repository root:

```bash
./scripts/build_src_mpcd_base.sh

ORECT_STEPS=3000 \
ORECT_DUMP_EVERY=100 \
ORECT_SUMMARY_EVERY=25 \
ORECT_THREADS=8 \
./scripts/run_open_channel_rect_obstacle_resampling_validation_0138b.sh
```

Short smoke:

```bash
ORECT_STEPS=1000 \
ORECT_DUMP_EVERY=250 \
ORECT_SUMMARY_EVERY=10 \
ORECT_THREADS=8 \
./scripts/run_open_channel_rect_obstacle_resampling_validation_0138b.sh
```

More energetic inlet:

```bash
ORECT_INLET_UX=0.12 \
ORECT_STEPS=5000 \
ORECT_DUMP_EVERY=250 \
ORECT_SUMMARY_EVERY=25 \
ORECT_THREADS=8 \
./scripts/run_open_channel_rect_obstacle_resampling_validation_0138b.sh
```

## MATLAB post-processing

From repository root:

```bash
cd matlab
```

In MATLAB:

```matlab
analyze_open_channel_rect_obstacle_resampling_0138b('../runs/open_channel_rect_obstacle_resampling_0138b');
```

The analysis writes:

- `open_channel_rect_obstacle_summary_0138b.csv`
- per-case metrics and profiles
- final fields with rectangle overlay
- time series for mean flow, wake vorticity, backflow, probe signal, mass residual and solid leak.

## Notes

This is not a true circular-cylinder von Karman validation.  It is the compatible open-channel bluff-body validation for the current C++ guard. A true open-channel cylinder requires a later C++ patch that extends the Q6 inlet/outlet immersed-solid path to circular masks.
