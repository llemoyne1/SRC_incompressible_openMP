# 0082 — Poiseuille outlet corner-band diagnostics

This diagnostic patch targets the suspected wall/outlet corner pathology in the hard-inlet/free-outlet Poiseuille runs.

It does not change the C++ solver.  It adds a MATLAB state-dump analysis that splits the right outlet and the upstream pre-outlet region into y-bands:

- `bottom`: near the lower wall;
- `core`: away from the two walls;
- `top`: near the upper wall;
- `all`: full outlet height.

For each band and dump frame, the analysis reports:

- mass, mean/std/max cell population;
- mean `Ux`, mean `Uy`, `Uy` RMS, mean/max speed;
- net, positive and negative flux proxies `sum(N*Ux)`;
- negative-flux fraction;
- backflow mass fraction.

The goal is to distinguish a uniform outlet-throughput issue from a corner-driven recirculation/backflow issue.

## Run on an existing 0080 case

From MATLAB:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_poiseuille_outlet_corner_bands_0082( ...
    'root','..', ...
    'runRoot','runs/poiseuille_ramped_softlimited_q9_0080_g30', ...
    'wallBandCells',3, ...
    'frameStride',1, ...
    'makePlots',true, ...
    'showFigures',true, ...
    'closeFigures',false);

cd('..')
```

The output directory is:

```text
runs/poiseuille_ramped_softlimited_q9_0080_g30/analysis_0082_outlet_corner_bands/
```

Important files:

```text
outlet_corner_band_timeseries_all_cases.csv
outlet_corner_band_summary_all_cases.csv
outlet_band_netFluxProxy.png
outlet_band_negativeFluxFraction.png
outlet_band_mass.png
outlet_band_meanN.png
outlet_band_maxN.png
outlet_band_uyRms.png
preoutlet_band_netFluxProxy.png
preoutlet_band_negativeFluxFraction.png
preoutlet_band_mass.png
preoutlet_band_uyRms.png
```

## Interpretation

A wall/outlet corner problem is indicated by one or more of:

- bottom/top outlet bands with strong negative flux fraction compared with the core;
- bottom/top outlet bands with persistent mass accumulation or depletion not seen in the core;
- large `Uy` RMS in the top/bottom outlet bands;
- pre-outlet bottom/top bands showing backflow while the core remains outward.

A mostly uniform outlet problem is indicated by similar behavior in `bottom`, `core`, and `top` bands.

## Notes

This patch follows 0081: `play_smpcd_filtered_animation.m` must respect `immersedSolidEnable=false`; otherwise the visual masks may show a ghost immersed rectangle from residual geometry parameters in `params_used.kv`.
