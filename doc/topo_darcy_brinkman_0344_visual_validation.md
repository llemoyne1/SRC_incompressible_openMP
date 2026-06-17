# 0344 — Persistent livevis control and alpha visual sweep for Darcy/Brinkman topo

## Scope

This patch does not change the Darcy/Brinkman physics introduced in 0343.  It only
improves the validation workflow:

- the live visualization control file is now persistent at repository root by
  default: `livevis_control.kv`;
- the 0343 runner no longer overwrites this file on every run, unless
  `LIVE_VIS_CONTROL_RESET=1` or the file is missing;
- a new visual sweep runner is added:
  `scripts/run_topo_darcy_alpha_visual_sweep_0344.sh`.

The sweep is intended to verify visually that increasing `darcyAlphaMax` reduces
the macroscopic velocity inside the `chi=0` inclusion.

## Why the first 0343 velocity field can look unpenalized

The default 0343 validation is deliberately stable and strongly thermalized:

- `kBT = 5`,
- `gamma = 20`,
- imposed mean flow `U0 = 0.05`,
- live visualization grid `600 x 320`, finer than the simulation grid
  `360 x 96`.

The instantaneous velocity in a rendered live pixel is therefore dominated by
thermal sampling noise.  At the simulation-cell level, the order of magnitude of
cell-mean thermal noise is approximately

```text
sqrt(kBT/gamma) = sqrt(5/20) = 0.5,
```

already one order of magnitude larger than the imposed mean flow `U0=0.05`.  On
the finer live grid the number of particles per rendered pixel is lower, so the
instantaneous displayed `ux` or `speed` field can hide the Brinkman damping even
when the cell-mean kick is active.

## Recommended visual validation settings

The 0344 sweep uses lower-noise defaults:

```bash
GAMMA=40
KBT=0.1
U0=0.5
LIVE_VIS_NX=360
LIVE_VIS_NY=96
LIVE_VIS_FIELD=ux
LIVE_VIS_CLIP=0.5
LIVE_VIS_SMOOTH_PASSES=3
ALPHAS="0 20 80 320"
```

This keeps the visualization grid aligned with the simulation grid and makes the
mean-flow damping easier to see.

## Commands

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-TOPO

LIVE_VIS_CONTROL_RESET=1 \
LIVE_VIS_FIELD=chi \
LIVE_VIS_CLIP=1 \
FORCE_REBUILD=0 \
STEPS=200 \
bash scripts/run_topo_darcy_brinkman_viz_0343.sh
```

Then edit the root file directly while runs are active:

```text
livevis_control.kv
```

For a visual alpha sweep:

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-TOPO

ALPHAS="0 20 80 320" \
LIVE_VIS_FIELD=ux \
LIVE_VIS_CLIP=0.5 \
LIVE_VIS_SMOOTH_PASSES=3 \
GAMMA=40 \
KBT=0.1 \
U0=0.5 \
STEPS=2000 \
FORCE_REBUILD=0 \
bash scripts/run_topo_darcy_alpha_visual_sweep_0344.sh
```

The sweep writes:

```text
runs/topo_darcy_alpha_sweep_0344/alpha_sweep_0344_summary.csv
```

and one run directory per `alphaMax` value.
