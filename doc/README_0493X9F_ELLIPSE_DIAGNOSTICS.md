# 0493x9f — true interface band + ellipse relaxation diagnostics

Incremental patch **on top of 0493x9e**.  It is diagnostic-only: it does not
change p3, `surfaceTensionSigma`, `phiGamma`, the x6f/x6g stencil, CG, B1,
streaming, collision, thermostat or resampling.

## What x9f adds

1. **True interfacial band**

   The old diagnostic mask `0.1 <= alpha <= 0.9` is removed from the x9e
   interface-velocity diagnostic and from LiveVis `curvature_interface`.
   A cell is now in the diagnostic band iff it is adjacent to at least one
   grid face whose two physical x6c alpha values straddle `alpha=0.5`.
   This is the same discrete crossing criterion used to locate the free
   surface.  No persistent mask is allocated.

2. **Real liquid centre of mass**

   `cuda_ellipse_shape_0493x9f.csv` records the mass-weighted position of all
   active fluid particles of the projected liquid type:

       xCM = sum(m_i x_i)/sum(m_i),  yCM = sum(m_i y_i)/sum(m_i).

   This is a position, not the mean liquid velocity reported historically by
   the x9e species diagnostics.

3. **Second-moment tensor**

   The mass-weighted central matrix

       M = [[<dx^2>, <dx dy>], [<dx dy>, <dy^2>]]

   is diagonalized at each summary sample.  For a uniformly filled ellipse,
   its eigenvalues are `a^2/4` and `b^2/4`, therefore x9f reports

       momentRadiusMajor = 2*sqrt(lambdaMajor)
       momentRadiusMinor = 2*sqrt(lambdaMinor)

   together with axis ratio, ellipticity `(a-b)/(a+b)`, and principal angle.
   These moment radii are the primary robust ellipse-shape observables.

4. **alpha=0.5 crossing radii**

   Each east/north crossing face is interpolated to its sub-cell alpha=0.5
   crossing point and its distance from the particle COM is accumulated.
   x9f reports `interfaceRadiusMin`, `interfaceRadiusMax`, mean/std and radial
   span.  Raw min/max are useful visual/diagnostic extrema but are more
   sensitive than the moment radii to isolated noisy alpha crossings.

## Default ellipse

`run_0493x9f_ellipse_relaxation.sh` uses

- 400 x 400, gamma=20, dt=0.002, kBT=0.125;
- semi-axes `RX_CELLS=50`, `RY_CELLS=32`;
- same initial area as the previously qualified R/h=40 circle because
  `50*32 = 40^2`;
- centered closed box, zero initial mean velocity;
- `SIGMA=256`, `STEPS=500` by default;
- resampling OFF, virial density kick OFF;
- LiveVis ON by default, field `curvature_interface`;
- filtered recording OFF.

The expected capillary signature is a decrease of the major moment radius,
an increase of the minor moment radius, and decay of axis ratio/ellipticity
toward one/zero while the equivalent area radius stays approximately constant.

## Files

- `tools/apply_0493x9f_ellipse_diagnostics.py`
- `scripts/run_0493x9f_ellipse_relaxation.sh`
- `scripts/run_0493x9f_ellipse_relaxation_sweep.sh`
- `scripts/analyze_0493x9f_ellipse_relaxation.py`
- `0493x9f_ellipse_diagnostics_review.diff`

Runtime outputs include:

- `output/cuda_static_drop_pressure_0493x9e.csv` (unchanged x9e pressure audit)
- `output/cuda_static_drop_velocity_0493x9e.csv` (interface column now true band)
- `output/cuda_ellipse_shape_0493x9f.csv`
- `ellipse_relaxation_0493x9f.json`

## Apply and build

From the repository root after extracting the bundle:

```bash
python3 x9f_bundle/tools/apply_0493x9f_ellipse_diagnostics.py
bash -n scripts/run_0493x9f_ellipse_relaxation.sh
bash -n scripts/run_0493x9f_ellipse_relaxation_sweep.sh
python3 -m py_compile scripts/analyze_0493x9f_ellipse_relaxation.py
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

The apply script is idempotent and does not impose a Git working-tree guard.
It checks that x9e is present and refuses a partial x9f source state.

## Preflight

```bash
PREFLIGHT_ONLY=1 LIVE_VIS_ENABLE=0 LIVE_PROGRESS=1 \
bash scripts/run_0493x9f_ellipse_relaxation.sh
```

## First comparison campaign

```bash
SIGMAS="0 256 512" STEPS=500 LIVE_VIS_ENABLE=1 \
bash scripts/run_0493x9f_ellipse_relaxation_sweep.sh
```

Each run has a separate output root under
`runs/0493x9f_ellipse_relaxation/seed493904_sigma*`.

For an individual visual run that should remain open at exit:

```bash
SIGMA=512 STEPS=500 LIVE_VIS_ENABLE=1 LIVE_VIS_HOLD_ON_EXIT=1 LIVE_PROGRESS=1 \
bash scripts/run_0493x9f_ellipse_relaxation.sh
```

## Validation performed while packaging

The patch was reconstructed and applied against the x9e state generated from
the provided repository snapshot and the x9a→x9e incremental chain.  The
semantic apply script was checked for exact source reproduction and
idempotence.  Both shell runners pass `bash -n`; Python scripts pass
`py_compile`; the x9f analyzer was exercised on synthetic CSV data.  CUDA
compilation/runtime must be performed on the project GPU environment.
