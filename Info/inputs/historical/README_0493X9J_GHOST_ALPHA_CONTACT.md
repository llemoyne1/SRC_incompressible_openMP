# 0493x9j — ghost-alpha contact-angle closure

Incremental patch on top of **0493x9i + fix1**.  x9i proved that the wall
geometry/orientation contract and the prescribed angle are correct, but its
hard replacement of a few p3 normals created a discontinuity in `div(n)` and
large contact-curvature errors.  x9j removes that hard-normal closure from the
default production path and imposes the angle as a boundary condition on the
**curvature-only alpha field**.

## Physical/numerical contract

The physical free-surface geometry is unchanged:

- `alpha_x6c` is not modified;
- the physical `alpha=0.5` crossing used by x6f/x6g is not moved;
- `surfaceTensionSigma`, `phiGamma`, CG and B1 are unchanged;
- no CSF/body-force term is added.

For an active contact angle, x9j uses virtual alpha samples behind a static
domain wall during all three p3 binomial smoothing passes and during the Scharr
normal/curvature derivatives.

With `nAB = -grad(alpha)/|grad(alpha)|`, `nWall` pointing fluid -> solid, and
theta measured through phase A, the target remains

    nAB . nWall = -cos(theta).

For a local wall-tangent derivative `g_t`, the ghost scalar extension uses

    |grad alpha| = |g_t| / |sin(theta)|,
    g_n = grad(alpha).nWall = |grad alpha| cos(theta),
    alpha_ghost = alpha_wall + g_n d_ghost.

Near the degenerate 0/180 degree limits, x9j falls back to the local raw
gradient magnitude instead of evaluating a divergent cotangent.

The same ghost-alpha sampler is used to construct the virtual outside normals
needed by the Scharr divergence, so the wall-adjacent curvature no longer uses
the pre-x9j constant/clamped normal extension.

## x9i historical baseline

The old hard-normal closure remains only behind the test-only environment gate

    MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=1

and `run_0493x9i_contact_angle.sh` is updated automatically to set it.  This
keeps the already-qualified x9i baseline reproducible.  The default production
path and the x9j runner use ghost alpha.

## Current scope

x9j intentionally qualifies **static domain walls first**.  Contact-angle
runs that have only chi/wallVP geometry, or that mix chi-wall geometry with a
domain-wall contact closure, are rejected explicitly.  x9h remains the generic
solid-geometry provider; internal chi-solid ghost extension is a later step if
needed.

Corners where two domain walls meet are not part of the x9j qualification.
Ghost sampling is deterministic there, but a dedicated two-wall contact-line
closure may be added later.

## New audit

Active ghost-alpha contact runs write

    output/cuda_contact_angle_ghost_0493x9j.csv

with the same scalar observables as x9i: raw/ghost angle, angle/dot RMS error,
and contact curvature mean/RMS/std.  The CSV contract explicitly identifies the
ghost-alpha closure.

## Qualification runner

The x9j runner reuses the same analytic sessile caps as x9i:

- theta = 60, 90, 120 degrees;
- grid 320x200, square cells;
- R=50 cells = 0.25 by default;
- exact 2-D circle curvature `1/R = 4`;
- sigma=256;
- one step by default, so this is a geometric reconstruction test rather than a
  dynamic wetting test;
- LiveVis ON by default;
- filtered recording OFF.

The analyzer also reads the existing x9i baseline under
`runs/0493x9i_contact_angle` when available and prints the reduction of the
absolute curvature bias.  The intended first qualification is not perfect
machine-level curvature: it requires a physically signed curvature and a clear
improvement over the known x9i hard-normal artifact (plus a <=30% bias gate for
the nearly neutral 90-degree case).

## Apply

From the repository root:

```bash
python3 x9j_bundle/tools/apply_0493x9j_ghost_alpha_contact.py
```

The installer is semantic-anchor based, idempotent, has no Git working-tree
guard, and also updates the historical x9i runner with its explicit legacy
gate.

## Static checks and build

```bash
git diff --check -- . ':(exclude)livevis_control.kv'

bash -n scripts/run_0493x9i_contact_angle.sh
bash -n scripts/run_0493x9j_contact_angle_ghost.sh
python3 -m py_compile scripts/analyze_0493x9j_contact_angle_ghost.py

g++ -std=c++17 -Iinclude -fsyntax-only src/params_io_base.cpp
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

CUDA compilation/runtime remains the authoritative gate on the project GPU.

## Regression and qualification

First retain x9h:

```bash
LIVE_VIS_ENABLE=1 LIVE_VIS_HOLD_ON_EXIT=0 LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0493x9h_wall_geometry_provider.sh
```

Optional historical x9i reproduction after x9j:

```bash
LIVE_VIS_ENABLE=1 LIVE_VIS_HOLD_ON_EXIT=0 LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0493x9i_contact_angle.sh
```

Then x9j preflight and run:

```bash
PREFLIGHT_ONLY=1 LIVE_VIS_ENABLE=0 LIVE_PROGRESS=1 \
bash scripts/run_0493x9j_contact_angle_ghost.sh

LIVE_VIS_ENABLE=1 LIVE_VIS_HOLD_ON_EXIT=0 LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0493x9j_contact_angle_ghost.sh
```

The most important output lines are, for each theta, `ghostMean`, `ghostKappa`,
`relBias`, `std`, and the x9i baseline improvement factor.
