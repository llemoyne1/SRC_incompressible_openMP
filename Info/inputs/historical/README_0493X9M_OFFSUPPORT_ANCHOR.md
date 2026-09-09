# 0493x9m — off-support contact-curvature anchor

## Purpose

x9l imposed the Young normal at the correct wall face, but connected it to a raw p3 normal at `j=1` (centre `1.5 h`). That anchor is still inside the wall-contaminated support: three 3x3 binomial passes give radius 3 and the Scharr normal adds radius 1. The first raw p3 normal whose scalar support no longer crosses the wall is therefore `j=4`, centred at `4.5 h`.

A first idea was to interpolate the near-wall normal field from the wall face to that clean anchor. That still manufactures a large artificial `div(n)` over the interpolation layer. x9m therefore uses the off-support anchor differently: it estimates only the **contact curvature** from the wall-face Young normal and the clean p3 normal on the actual A/B interface.

## Closure

The physical interface field and the qualified p3 geometry remain unchanged:

- `alpha_x6c`: unchanged;
- curvature-only `alphaK` / p3 smoothing: unchanged;
- raw p3 normals: unchanged;
- standard p3/Scharr curvature: built first everywhere.

For each contact cell x9m then:

1. constructs the Young normal at the physical wall face, with the existing convention
   `n_AB · n_wall = -cos(theta_A)`;
2. locates the physical `alpha=0.5` crossing in the boundary cell-centre layer and projects it by half a normal cell to the wall face;
3. predicts where that interface should reach layer `j=4`, then snaps to the nearest actual physical `alpha=0.5` crossing in that layer;
4. interpolates the **raw p3 normal** at that crossing;
5. forms the physical chord from the wall contact point to the clean anchor crossing;
6. uses the circular-arc secant identity

   `kappa = 2 sin(DeltaPhi/2) / L`

   with the signed normal rotation and chord orientation;
7. overwrites only the contact-cell curvature value. No alpha or normal sample is overwritten.

This is deliberately a local experimental closure. It is not an empirical sigma renormalization.

## Scope

- qualified target range: `30° <= theta <= 150°`;
- parameter validity: `0 < theta < 180°`; exact endpoints are intentionally unsupported;
- static domain walls only in x9m;
- combined chi-wall contact closure remains deferred;
- x9m has its own environment gate and leaves x9l/x9k reproducible.

Runtime gate used by the runner:

`MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=1`

Audit:

`output/cuda_contact_angle_offsupport_0493x9m.csv`

## Apply

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
unzip -o 0493x9m_offsupport_anchor_bundle.zip
python3 x9m_bundle/tools/apply_0493x9m_offsupport_anchor.py
```

Static checks:

```bash
git diff --check -- . ':(exclude)livevis_control.kv'

bash -n scripts/run_0493x9m_contact_angle_offsupport.sh
python3 -m py_compile \
  scripts/analyze_0493x9m_contact_angle_offsupport.py \
  scripts/check_0493x9m_offsupport_geometry.py

python3 scripts/check_0493x9m_offsupport_geometry.py
```

The geometry checker verifies:

- p3 radius 3 + Scharr radius 1 -> clean anchor layer `j=4`;
- the 30–150° planar offset remains inside the CUDA crossing-search window;
- the signed secant formula returns exactly `1/R` on analytic circular arcs.

Then build:

```bash
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

## Preflight

```bash
PREFLIGHT_ONLY=1 \
LIVE_VIS_ENABLE=0 \
LIVE_PROGRESS=1 \
bash scripts/run_0493x9m_contact_angle_offsupport.sh
```

## Qualification sweep

```bash
LIVE_VIS_ENABLE=1 \
LIVE_VIS_HOLD_ON_EXIT=0 \
LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0493x9m_contact_angle_offsupport.sh
```

Default sweep:

`30 45 60 75 90 105 120 135 150`

Each case remains a one-step static sessile-cap test with `R=0.25`, so the exact circular curvature is `4`.

The analyzer gates, for every angle:

- all contact candidates must obtain a clean anchor;
- mean angle within 2 degrees and RMS angle error <= 3 degrees;
- `|kappa/4 - 1| <= 10%`.

Curvature standard deviation is reported but remains informational for this first x9m experiment. Existing x9l and x9k runs are printed as baselines when present.

## Interpretation

A PASS would support the hypothesis that the dominant x9l failure was anchoring the wall closure inside the p3+Scharr support. A FAIL is still discriminating: if a clean j=4 endpoint does not recover the circular curvature, stop extending/interpolating wall normals and move to a dedicated local interface reconstruction (height function / constrained quadratic fit) rather than adding angle-dependent corrections.
