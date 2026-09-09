# 0493x9n — geometric qualification of x9m contact curvature

## Purpose

x9m passed the circular sessile-cap sweep from 30° to 150° with low contact-curvature bias and very small local dispersion. x9n is deliberately **scripts-only**: it does not change CUDA, alpha, normals, curvature, sigma, CG, B1, or any physical parameter. It tests whether the x9m off-support closure generalizes beyond the single `R=0.25` circular benchmark.

The production path under test remains exactly x9m:

`Young normal at wall face -> physical alpha=0.5 contact -> clean p3 normal at j=4 (4.5h) -> signed secant curvature`.

Runtime gate remains:

`MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=1`

Audit remains:

`output/cuda_contact_angle_offsupport_0493x9m.csv`

## Qualification matrix

Default grid and fluid parameters are unchanged from x9m: `320x200`, `Lx=1.6`, `Ly=1`, `h=0.005`, `gamma=20`, `dt=0.002`, `kBT=0.125`, `sigma=256`, one step per case.

### A. Locally planar contact interface

Angles:

`30 45 60 90 120 135 150`

The liquid region is a symmetric wedge whose two side interfaces are exactly straight near the bottom wall. It is capped horizontally at `20h`, well outside both the x9m anchor (`4.5h`) and the p3+Scharr support. Therefore the exact contact curvature is

`kappa = 0`.

Gate per case:

- contact-angle closure complete and angle mean within 2°, RMS <= 3°;
- `|mean kappa| <= 0.5`;
- contact-curvature standard deviation `<= 0.5`.

This is the anti-overfitting test: a closure tuned accidentally to circular caps must not manufacture curvature on a straight interface.

### B. Circular radius scaling

Angles:

`60 90 120`

Radii:

`R/h = 20, 40, 80`, i.e. `R = 0.10, 0.20, 0.40` on the default grid.

Exact curvature is `1/R`, spanning a factor four. Gate per case:

- angle gate as above;
- local curvature relative error <= 10%;
- standard deviation <= `max(0.5, 0.15*|kappa_exact|)`.

For each angle the analyzer also fits

`kappa_measured = slope * (1/R)`

through the origin and requires `0.9 <= slope <= 1.1` and `R² >= 0.98`.

### C. Non-circular variable-curvature interface

Two axis-aligned ellipses are used:

- wide: `a=56h=0.28`, `b=40h=0.20`;
- tall: `a=40h=0.20`, `b=56h=0.28`.

Angles:

`60 90 120`.

For an ellipse `x=a cos(t)`, `y=yc+b sin(t)`, the generator chooses `yc` so that the exact outward normal at the bottom-wall contact satisfies the same Young convention as the solver. The exact local contact curvature is evaluated analytically.

Because x9m is a finite-chord estimator between the wall and `4.5h`, the generator additionally records the ideal x9m secant curvature on the exact ellipse. The chosen aspect ratios keep this intrinsic secant-vs-local bias below about 6%, so the 10% local-curvature gate remains meaningful. The analyzer prints both errors:

- measured vs exact local curvature — qualification quantity;
- measured vs ideal finite-chord x9m value — diagnostic decomposition.

## Installation

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
unzip -o 0493x9n_geometric_qualification_bundle.zip
python3 x9n_bundle/tools/apply_0493x9n_geometric_qualification.py
```

x9n has **no source modification and requires no rebuild** if the x9m binary already used for the successful sweep is still current.

Static checks:

```bash
bash -n scripts/run_0493x9n_geometric_qualification.sh
python3 -m py_compile \
  scripts/generate_0493x9n_geometry_state.py \
  scripts/check_0493x9n_geometry.py \
  scripts/analyze_0493x9n_geometric_qualification.py

python3 scripts/check_0493x9n_geometry.py
```

Expected final line:

`[0493x9n-mapcheck] status=PASS`

## Optional preflight

```bash
PREFLIGHT_ONLY=1 \
LIVE_VIS_ENABLE=0 \
LIVE_PROGRESS=1 \
bash scripts/run_0493x9n_geometric_qualification.sh
```

## Full qualification

```bash
LIVE_VIS_ENABLE=1 \
LIVE_VIS_HOLD_ON_EXIT=0 \
LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0493x9n_geometric_qualification.sh
```

There are 22 one-step cases in the default matrix.

The analyzer writes:

`runs/0493x9n_geometric_qualification/x9n_geometry_summary.csv`

and ends with family results plus

`[0493x9n-check] status=PASS|FAIL`.

## Interpretation

A global PASS is strong evidence that x9m is a genuine local geometric closure rather than a fit to the original `R=0.25` circular cap: it must preserve zero curvature on straight contacts, scale as `1/R` over a factor four, and recover local curvature on non-circular interfaces.

If only ellipse cases miss the local-curvature gate while agreeing closely with the printed ideal x9m secant value, the remaining error is the expected finite-chord truncation of x9m rather than a failure of the wall/contact reconstruction. That would motivate reducing the anchor distance or using a higher-order local fit only if the dynamic sessile-drop validation demonstrates a practical need.
