# 0493x9k — sheared-mirror ghost alpha for prescribed contact angle

Incremental patch on top of **0493x9j + fix1**.

x9j established that imposing the contact-angle condition through the
curvature-only scalar field is much better than x9i's hard replacement of a
few normals.  On the analytic `R=0.25` sessile caps it gave

- 60 deg: `kappa=4.0115` (+0.288%),
- 90 deg: `kappa=3.4449` (-13.88%),
- 120 deg: `kappa=2.0639` (-48.40%),

for exact `kappa=4`.

The remaining defect is consistent with x9j being a **first-derivative linear
extension**: deeper ghost layers are extrapolated from the first fluid row,
whereas Scharr `div(n)` needs a geometrically coherent continuation at multiple
ghost depths.

## x9k change of representation

For a ghost cell center a distance `d` behind a planar wall, x9k:

1. reflects the point across the physical wall into the fluid;
2. shifts that mirror point tangentially;
3. samples the real curvature-support alpha field there by linear/bilinear
   interpolation.

With

    nAB = -grad(alpha)/|grad(alpha)|
    nWall = fluid -> solid
    nAB.nWall = -cos(theta)

and local tangent derivative sign taken from the raw field,

    g_n / g_t = sign(g_t) * cot(theta).

The ghost and mirror centers are separated normally by `2*d`, hence

    Delta_t = 2*d * g_n/g_t.

The scalar closure is therefore

    alpha_ghost(t,+d) = alpha_fluid(t + Delta_t,-d).

For `theta=90 deg`, `cot(theta)=0`, so this reduces **exactly** to ordinary
mirror symmetry at every ghost depth:

    alpha(t,+d) = alpha(t,-d).

For a locally planar level set, the mapping is exact at every depth, rather
than only matching the first wall-normal derivative.

## Deliberate endpoint scope

x9k supports

    0 < phaseInterfaceContactAngleDegrees < 180

and deliberately rejects exactly 0 and 180 degrees.  No complete-wetting or
complete-dewetting special closure is introduced because those endpoints are
not needed for the current practical target and make `cot(theta)` singular.

There is **no new parameter or persistent feature flag**.

## Physics contract retained

x9k changes only virtual samples of the curvature-support field:

- physical `alpha_x6c` is unchanged;
- the physical `alpha=0.5` crossing used by x6f/x6g is unchanged;
- the p3 interior field remains the same three binomial passes;
- `surfaceTensionSigma`, `sigma*kappa`, `phiGamma`, CG and B1 are unchanged;
- no CSF/body-force term is added;
- static domain walls remain the qualification scope; chi-solid ghost
  extension is still deferred.

The existing x9j p3 kernels are routed through the x9k sampler.  Existing x9j
run data remain usable as the baseline; x9k writes a separate audit CSV.

## New audit

    output/cuda_contact_angle_mirror_0493x9k.csv

The scalar columns are intentionally identical to x9i/x9j so angle and
curvature can be compared directly.  The `contract` column identifies the
sheared-mirror closure.

## Deterministic mapping unit check

The bundle adds

    scripts/check_0493x9k_sheared_mirror_geometry.py

which verifies, without CUDA, that a planar scalar field at 60/90/120 degrees
is reproduced exactly by the first several mirror depths and that 90 degrees
is pure mirror symmetry.

## Qualification runner

`run_0493x9k_contact_angle_mirror.sh` reuses exactly the same sessile caps as
x9i/x9j:

- theta = 60, 90, 120 degrees;
- 320x200 square-cell grid;
- gamma=20;
- R=50 cells = 0.25;
- exact 2-D curvature = 4;
- sigma=256;
- one step by default;
- LiveVis ON by default;
- filtered recording OFF.

The runner incorporates the x9j-fix1 array handling, so `ANGLES="60 90 120"`
is passed correctly to `argparse`.

For this iteration the hard curvature gate is deliberately stronger than x9j:

    |kappa_contact - 4| / 4 <= 10%

for **all three angles**, together with the existing angle reconstruction gate.
The curvature standard deviation is reported but not yet a hard gate; x9j
showed that a good mean can coexist with substantial local scatter.

## Apply

From the repository root:

```bash
python3 x9k_bundle/tools/apply_0493x9k_sheared_mirror_ghost.py
```

The installer is semantic-anchor based, idempotent and has no Git working-tree
guard.

## Static checks + build

```bash
git diff --check -- . ':(exclude)livevis_control.kv'

bash -n scripts/run_0493x9k_contact_angle_mirror.sh
python3 -m py_compile \
  scripts/analyze_0493x9k_contact_angle_mirror.py \
  scripts/check_0493x9k_sheared_mirror_geometry.py

python3 scripts/check_0493x9k_sheared_mirror_geometry.py

bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

CUDA compilation/runtime on the project GPU is the authoritative source gate.

## Regression and run

Retain x9h first if desired:

```bash
LIVE_VIS_ENABLE=1 LIVE_VIS_HOLD_ON_EXIT=0 LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0493x9h_wall_geometry_provider.sh
```

Then x9k preflight:

```bash
PREFLIGHT_ONLY=1 LIVE_VIS_ENABLE=0 LIVE_PROGRESS=1 \
bash scripts/run_0493x9k_contact_angle_mirror.sh
```

and qualification:

```bash
LIVE_VIS_ENABLE=1 LIVE_VIS_HOLD_ON_EXIT=0 LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0493x9k_contact_angle_mirror.sh
```

The decisive lines are `mirrorMean`, `mirrorKappa`, `relBias`, `std`, and the
printed x9j baseline comparison for each angle.
