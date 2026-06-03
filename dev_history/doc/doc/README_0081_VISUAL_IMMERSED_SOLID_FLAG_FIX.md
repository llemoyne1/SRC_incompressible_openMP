# 0081 — Visualizer fix for `immersedSolidEnable=false`

## Purpose

This is a MATLAB-only diagnostic fix.  It does not change the C++ solver, the
boundary conditions, Q6, Q9, the virial kick, or any runtime parameters.

In open-channel/Poiseuille runs, `params_used.kv` can legitimately contain the
rectangle defaults

```text
immersedSolidShape = rectangle
immersedSolidXMin = 0.25
immersedSolidXMax = 0.65
immersedSolidYMin = 0.0
immersedSolidYMax = 0.50
```

while also explicitly setting

```text
immersedSolidEnable = false
```

The C++ run is then a no-immersed-solid run.  Before this fix,
`play_smpcd_filtered_animation.m` inferred a visual solid from the residual
rectangle coordinates and displayed a phantom backward-step in `solidAny`,
`maskCode`, `q9ImmersedHalo`, and overlays.

## Change

`play_smpcd_filtered_animation.m` now gives absolute priority to an explicit
immersed-solid enable flag:

- if `immersedSolidEnable=false` or `immersedEnable=false` is present, the visual
  solid fraction is forced to zero and no immersed geometry is drawn;
- if the flag is present and true, the geometry is reconstructed normally;
- if the flag is absent, legacy inference from geometry coordinates is preserved
  for old runs.

## Verification commands

For the Poiseuille run that contains residual immersed-solid coordinates but has
`immersedSolidEnable=false`, the following calls should no longer show the
phantom backward-step:

```matlab
runDir = '../runs/poiseuille_ramped_softlimited_q9_0080_g30/poiseuille_q9_virial_ramped_softlimited_hard_inlet_u0p05_48x24';

play_smpcd_filtered_animation(runDir, 'field','solidAny', ...
    'filterType','none', 'maskOverlay','none');

play_smpcd_filtered_animation(runDir, 'field','maskCode', ...
    'filterType','none', 'maskOverlay','none', 'clim',[0 7]);

play_smpcd_filtered_animation(runDir, 'field','q9ImmersedHalo', ...
    'filterType','none', 'maskOverlay','none');
```

Expected result for a no-solid Poiseuille run:

- `solidAny` is zero everywhere;
- no black immersed rectangle is drawn;
- `q9ImmersedHalo` is zero everywhere;
- `maskCode` only shows open-boundary/reservoir/Q9 low-mass categories, not a
  backward-step halo.

## Next non-cosmetic issue

This fix is necessary before diagnosing the outlet.  The next inlet/outlet task
is to instrument and then treat the wall/outlet corner, because the long
Poiseuille hard-inlet/free-outlet runs still show organized recirculation and a
mass deficit after the transient.

The next diagnostics should quantify, by bands near the right boundary:

- bottom-wall/outlet corner mass and mean velocity;
- core-outlet mass and mean velocity;
- top-wall/outlet corner mass and mean velocity;
- backflow fraction near outlet;
- outlet flux proxy by `y` band.

