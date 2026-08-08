# 0493x6d — guarded resident cut-face geometry at zero interface pressure

## Purpose

0493x6d is the first stage that **consumes** the resident phase geometry built by
0493x6c.  It changes only the location of the zero-gauge free-surface Dirichlet
condition.  Gas pressure and surface tension are still absent, so any trajectory
change relative to x6c can be attributed to geometry alone.

The carrier/support mask remains the existing `free_surface_masked` mask.  The
physical interface is the filtered phase isovalue `alpha=0.5`; these two objects
remain deliberately distinct.

## Cut-face rule

For an in-domain face separating one active Q6 carrier cell from one inactive
cell, let `alpha_i` be the filtered phase field in the active cell and `alpha_o`
the value in the inactive neighbour.  A geometric cut face is used only if

- `alpha_i >= 0.5`,
- `alpha_o < 0.5`, and
- the reconstructed fraction
  `theta=(alpha_i-0.5)/(alpha_i-alpha_o)` is at least `0.10`.

The `0.10` lower bound is a fixed x6d conditioning guard, not a new simulation
parameter.  Faces that do not bracket `alpha=0.5`, or whose cut cell would be
smaller than this guard, retain the legacy half-cell factor.  This makes the
first active geometry patch conservative in scope and gives an explicit
fallback population to audit.

For a geometric face the Dirichlet contribution becomes

`A_Gamma(phi_c) = phi_c/(theta*h^2)`

instead of the x5a legacy `2*phi_c/h^2`.  The matching pressure correction uses

`delta u_n = phi_c/(theta*h)`

with the existing sign/orientation convention.  At `theta=0.5` both expressions
reduce exactly to the legacy half-cell coefficients.

## Performance contract

0493x6d adds **no new permanent CUDA grid pass and no new resident field**.  The
operator reads `phaseAlphaFiltered0493x6c` only when it encounters an
active/inactive face.  Interior liquid faces remain coefficient 1.  The existing
x6c audit kernel, which runs only at step 1 and `SUMMARY_EVERY`, is extended with
cut-face counters and theta extrema.

This is intentionally preferable to reconstructing face geometry in a separate
production kernel while the number and format of future cut-cell coefficients
are still being qualified.

## Unchanged physics

- `p_Gamma = 0` gauge pressure;
- no `p_g` coupling;
- no surface tension;
- no change to the Q6 support mask;
- no change to SRC multi-species collision;
- no change to force ordering, streaming or thermostat;
- no change to external BC, Darcy/chi or resampling paths.

## Run

```bash
LIVE_PROGRESS=1 \
STEPS=20 \
SUMMARY_EVERY=5 \
LIVE_VIS_ENABLE=0 \
LIVE_VIS_HOLD_ON_EXIT=0 \
bash scripts/run_0493x6d_cutface_geometry_zero_pressure.sh
```

The runner also executes the existing x6c resident-geometry analyzer and then
`scripts/analyze_0493x6d_cutface_geometry.py`.  The latter reports the fraction
of geometric faces, legacy fallbacks, small-theta fallbacks and the min/mean/max
of theta actually eligible for the x6d operator.
