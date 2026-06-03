# 0151 — Closed-capacity wall-load diagnostics

This patch adds an explicit wall-load diagnostic for the closed-capacity virial response introduced in 0147--0149.  The goal is to test whether a pressurized closed box would provide a meaningful normal pressure load for a future deformable-wall / rupture model.

## Scope

The patch does **not** couple the pressure back to a moving solid yet.  It only exposes the force that a later structural module should receive.

The diagnostic is active only through the existing closed-capacity path:

```text
closedCapacityResponseEnable = true
```

If this option is false, previously validated cases are unchanged except for extra zero-valued CSV columns.

## Wall-load model

For every solid portion of the outer rectangular boundary, the code computes

```text
Ptot = Pkin_est + Pvir
```

with

```text
Pvir = Kvir_eff * (Mcell / Mref_cell - 1)
Pkin_est = (Mcell / cellArea) * kBT
```

`kBT` is taken from `thermostatTargetKBT` when positive, otherwise from the global `kBT` parameter.  This is an equilibrium kinetic estimate, not yet the impact/wallVP impulse estimator.

The wall force is computed in two dimensions with unit depth:

```text
left   wall force = -Ptot * dy * ex
right  wall force = +Ptot * dy * ex
bottom wall force = -Ptot * dx * ey
top    wall force = +Ptot * dx * ey
```

The force sign convention is therefore: force exerted by the fluid on the wall, using the outward normal of the fluid domain.

For segmented boundaries, inlet/outlet apertures are excluded.  Example: if `bcLeft=solid` and `openBoundarySegment0=left inlet ...`, only the solid complement of the left face contributes to the left-wall load.

## New CSV columns

The following columns are appended to `summary_runtime.csv`:

```text
capacityWallLoadComputed
capacityWallKineticKBT
capacityWallSolidLengthLeft
capacityWallSolidLengthRight
capacityWallSolidLengthBottom
capacityWallSolidLengthTop
capacityWallSolidLengthTotal
capacityWallPressureKineticMeanLeft
capacityWallPressureKineticMeanRight
capacityWallPressureKineticMeanBottom
capacityWallPressureKineticMeanTop
capacityWallPressureVirialMeanLeft
capacityWallPressureVirialMeanRight
capacityWallPressureVirialMeanBottom
capacityWallPressureVirialMeanTop
capacityWallPressureTotalMeanLeft
capacityWallPressureTotalMeanRight
capacityWallPressureTotalMeanBottom
capacityWallPressureTotalMeanTop
capacityWallPressureKineticMeanAll
capacityWallPressureVirialMeanAll
capacityWallPressureTotalMeanAll
capacityWallForceKineticX
capacityWallForceKineticY
capacityWallForceVirialX
capacityWallForceVirialY
capacityWallForceTotalX
capacityWallForceTotalY
```

The `MeanAll` columns are length-weighted over all solid boundary portions.

## MATLAB post-processing

`matlab/analyze_closed_capacity_inlet_only_0147.m` now reads the new columns and creates an additional figure:

```text
*_wall_load.png / *_wall_load.fig
```

This figure shows:

1. kinetic, virial, and total mean wall pressure;
2. total pressure per side;
3. virial pressure per side;
4. total wall force components and magnitude.

The summary CSV produced by the MATLAB script also includes wall-pressure and wall-force extrema.

## Interpretation

This patch answers the first mechanical question for deformable-wall coupling:

```text
does the closed-capacity virial pressure become a large wall-normal load?
```

It does **not** yet validate wall mechanics.  A full deformable-wall coupling will still require:

- comparison against impact/wallVP impulse pressure;
- conservation/feedback of wall motion onto particles;
- a structural update using the computed wall traction;
- later extension from the outer rectangular box to immersed/deformable solid boundaries.
