# 0148 — MATLAB post-processing for closed-capacity inlet-only runs

This addendum adds:

```text
matlab/analyze_closed_capacity_inlet_only_0147.m
```

The script post-processes runs produced by:

```bash
scripts/run_closed_capacity_inlet_only_0147.sh
```

It is designed to diagnose the closed-domain capacity response introduced in
0147:

- mass accumulation and overfill ratio;
- Q6 weakening through the effective `q6ProjectionStrength`;
- virial stiffness/pressure/kick response;
- resampling remap attenuation and population guard activity;
- inlet particle budget, energy, temperature and momentum;
- one compact CSV summary per run root.

## Usage

From the repository root:

```matlab
cd matlab
R = analyze_closed_capacity_inlet_only_0147( ...
    '../runs/closed_capacity_inlet_only_0147');
```

or, explicitly:

```matlab
R = analyze_closed_capacity_inlet_only_0147( ...
    '../runs/closed_capacity_inlet_only_0147', ...
    'showFigures', true, ...
    'saveFigures', true);
```

By default the analysis directory is:

```text
<runRoot>/matlab_closed_capacity_0147
```

It contains:

```text
closed_capacity_0147_summary.csv
closed_capacity_0147_analysis.mat
*_mass_overfill.png/.fig
*_q6_divergence.png/.fig
*_virial.png/.fig
*_resampling.png/.fig
*_inlet_energy.png/.fig
```

## Interpretation

For a closed, initially full tank with a maintained inlet-only flux, the expected
signature is:

```text
totalMass increases
capacityOverfillRatio increases
capacityQ6ProjectionFactor decreases
q6ProjectionStrengthEffective decreases
capacityVirialKEffective increases
capacityVirialPressureMean increases
resampRemapMassCorrectionStrength decreases
```

The script tolerates missing columns so it can be used with nearby 0147 variants.
Missing diagnostics simply appear as `NaN` or blank curves.

