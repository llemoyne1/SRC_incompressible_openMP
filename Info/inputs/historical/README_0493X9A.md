# 0493x9a — passive curvature scaffold

This bundle targets the `snap_170826` / current `surf` source state.

## Scope

- builds resident outward normals from the existing x6c filtered `alpha`:
  `n = -grad(alpha)/|grad(alpha)|`;
- builds resident cell curvature `kappa = div(n)`;
- audits curvature interpolated to each physical `alpha=0.5` east/north crossing;
- writes `cuda_phase_curvature_0493x9a.csv` on the normal summary cadence;
- **does not** modify `phiGamma`, the Q6 RHS, B1, particle positions, or particle velocities;
- no `sigma` parameter exists in x9a.

The two resident geometry passes (normal + curvature) run at every Q6-G-F solve
when `MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=1`; the face audit/download is
summary-cadence only.  This makes x9a representative of the future capillary
geometry cost without changing the physics.

## Install from repository root

Unpack this bundle at the repository root, then:

```bash
python3 tools/apply_0493x9a_curvature.py
chmod +x scripts/run_0493x9a_ellipse_curvature.sh \
         scripts/generate_0493x9a_ellipse_state.py \
         scripts/analyze_0493x9a_curvature.py
```

The patch script is idempotent and uses semantic anchors; it does not require a
clean working tree and does not use `git apply`.

## Build

```bash
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

## Preflight only

```bash
PREFLIGHT_ONLY=1 LIVE_PROGRESS=1 \
  bash scripts/run_0493x9a_ellipse_curvature.sh
```

## First circle test (default 400x400)

Defaults are `Lx=Ly=1.5625`, `Nx=Ny=400`, `gamma=20`, `dt=0.002`,
`kBT=0.125`, `Rx=Ry=0.3125`, i.e. radius 80 cells.

```bash
LIVE_PROGRESS=1 \
  bash scripts/run_0493x9a_ellipse_curvature.sh
```

Expected analytic curvature in 2-D: `1/R = 3.2`.
The analysis is deliberately `PASS-structural` rather than imposing an accuracy
threshold before the first measured x9a result.

## Quasi-plane test with the same runner

A very large major semi-axis makes the two visible arcs nearly planar over the
box.  Here the minor-axis curvature proxy is `Ry/Rx^2 = 3.125e-5`:

```bash
RX=100 RY=0.3125 LIVE_PROGRESS=1 \
  BASE_RUN_ROOT=runs/0493x9a_plane_400 \
  bash scripts/run_0493x9a_ellipse_curvature.sh
```

An oblique quasi-plane can later be tested with `ANGLE_DEG`, e.g. `30`, though
its intersections with the closed-box walls should then be interpreted
separately from the interior arc.

## Generic ellipse

Example 100-cell x 50-cell semi-axes:

```bash
RX=0.390625 RY=0.1953125 LIVE_PROGRESS=1 \
  BASE_RUN_ROOT=runs/0493x9a_ellipse_100x50cells \
  bash scripts/run_0493x9a_ellipse_curvature.sh
```

The analyzer reports the analytic curvature bounds of an ellipse but does not
pretend that unweighted face-sample averages equal an arc-length average.

## Return after the first circle run

Please return:

- the console lines beginning `[0493x9a-analysis]`;
- `runs/.../curvature_0493x9a.json`;
- if the result is surprising, `output/cuda_phase_curvature_0493x9a.csv`.

Do not enable gas-pressure x6g or any surface-tension kick for x9a; this stage is
geometry-only.
