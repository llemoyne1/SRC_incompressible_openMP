# 0493m — Equal-mass count-encoded binary Taylor–Green qualification

## Purpose

0493m separates inertial particle mass from the initial representation of composition.
All active particles start with exactly the same mass, while the species field is encoded by
integer counts `N1` and `N2` with `N1+N2=gamma` in every cell.

The default configuration reproduces the previous 64×64, mode-2, 1500-step experiment:

- `NX=NY=64`, `GAMMA=20`;
- `TG_MODE=2`, `TG_AMPLITUDE=0.08`;
- requested composition amplitude `0.15`;
- equal global counts and masses for species 1 and 2;
- `RUN_MODES='src src-resampling'`;
- active-fluid-only dumps every 10 steps;
- empty-refill must remain inactive.

The integer count quantization is globally balanced exactly. With the default geometry the
projected initial count amplitude is close to 0.15, with 7–13 particles of either species per cell.

## Outputs

The runner reuses the validated 0493k transport analyzer and 0493l particle-weight analyzer.
It additionally writes:

- `encoding_comparison_0493m.csv`;
- `encoding_comparison_0493m.md`.

These compare mass-carried and count-carried composition amplitudes against the earlier
weight-encoded run (`WEIGHT_REFERENCE_ROOT`, defaulting to
`runs/0493k_tg_binary_64_m2_pilot_1500`).

## Interpretation

This is a qualification, not a solver modification. It tests whether the resampling path:

1. generates a broad weight distribution from initially unit weights;
2. converts the count-encoded composition into weight encoding;
3. changes the decay or growth of the composition mode;
4. produces species-local kinetic-closure infeasibilities;
5. changes viscosity, diffusion, or radial mobility relative to SRC.

`LIVE_PROGRESS=1` is implemented with line-buffered `tee`, so progress remains visible while
being retained in each case log.
