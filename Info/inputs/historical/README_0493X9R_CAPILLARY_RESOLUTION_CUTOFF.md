# 0493x9r — capillary resolution cutoff

## Purpose

The dripping-jet ablations isolate a small-scale failure mode of the current x9 capillary path:

- `g=0, sigma>0`: the bulk remains coherent;
- `g<0, sigma=0`: the jet stretches strongly but remains ordered;
- `g<0, sigma=75600`: ballistic liquid-particle ejections appear;
- reducing sigma delays and weakens the same ejection mechanism.

The observed raw curvature reaches values corresponding to radii below one grid cell. x9r tests whether the failure is caused by applying the full Laplace jump to geometries that are not spatially resolved.

## Numerical contract

New parameter:

```text
surfaceTensionMinRadiusCells = 0
```

`0` preserves the previous x9 path. For a positive value `rminCells`, x9r computes

```text
kappaLimit = 1 / (rminCells * min(dx,dy))
kappaEffective = clip(kappaFaceRaw, -kappaLimit, +kappaLimit)
phiGamma_cap = dt * sigma * kappaEffective / rhoARef
```

The limiter is applied **after interpolation to the physical `alpha=0.5` face** and only in the capillary `sigma*kappa` contribution.

The resident p3/x9m curvature array is not modified. LiveVis `kappa`/`curvature` therefore continues to show the raw geometrical estimate.

For the current jet, `h=0.005` and `surfaceTensionMinRadiusCells=3` give

```text
|kappa| <= 66.6666667
```

for the Laplace jump, while raw LiveVis values may still reach 250–350.

## Diagnostics

At the existing geometry-summary cadence, x9r writes

```text
output/cuda_surface_tension_limiter_0493x9r.csv
```

with:

- `kappaLimit`;
- `capillaryFaces`;
- `clippedFaces`;
- `clipFraction`;
- `capillaryKappaRawAbsMax`;
- `capillaryKappaEffectiveAbsMax`.

A stdlib-only analyzer is installed as `scripts/analyze_0493x9r_limiter.py`.

## Apply and build

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF

unzip -o 0493x9r_capillary_resolution_cutoff_bundle.zip
python3 x9r_bundle/tools/apply_0493x9r_capillary_resolution_cutoff.py

git diff --check -- . ':(exclude)livevis_control.kv'
bash -n scripts/run_0493x9q_dripping_jet_potential.sh
bash -n scripts/run_0493x9r_dripping_jet_cutoff.sh
python3 -m py_compile scripts/analyze_0493x9r_limiter.py
g++ -std=c++17 -Iinclude -fsyntax-only src/params_io_base.cpp

bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

No Git-clean guard is imposed by the installer.

## Aggressive causal test

The wrapper reproduces the difficult regime already characterized, with a 3-cell minimum resolved radius:

```bash
LIVE_VIS_ENABLE=1 \
LIVE_VIS_HOLD_ON_EXIT=0 \
LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0493x9r_dripping_jet_cutoff.sh
```

Defaults in the wrapper are:

```text
SIGMA_ACTIVE=75600
GRAVITY_Y=-0.05
KBT=0.00000125
SURFACE_TENSION_MIN_RADIUS_CELLS=3
CASES=capillary
```

Every value remains overridable from the shell.

The wrapper runs the existing x9q jet and then summarizes the limiter CSV when it exists.

## Interpretation

The first question is causal, not yet quantitative breakup physics.

A strong positive result is:

- raw `kappa` still reaches values well above 66.67;
- `capillaryKappaEffectiveAbsMax` remains bounded at 66.67;
- `clipFraction` stays small while the jet is well resolved and rises only as the filament becomes very thin;
- ballistic particle ejections disappear or are strongly delayed while the macroscopic bulb remains capillary.

If ejections remain essentially unchanged despite an active limiter, the next suspect is the subcell/cut-face transfer (`theta`) or B1 rather than the raw curvature amplitude itself.
