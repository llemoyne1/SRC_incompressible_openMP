# 0493x23c — forced Taylor–Green gamma=20 discriminator

## Purpose

This is a focused follow-up to x23b.  It tests whether the weak statistical
contrast at the nominal article point is primarily caused by the low cell
occupancy (`gamma=8`).  It is deliberately **not** a new forcing calibration.

Two matched simulations are run from one shared particle state:

- `SRC`
- `SRC + particle/field closure` (internal `src-q6-g-f`)

## Controlled change relative to x23b

The only physical control parameter changed is

```text
gamma: 8 -> 20
```

The following remain unchanged:

```text
grid                  256 x 256
Lx = Ly               1.0
h                      1/256
dt                     0.0063471328149122585
kBT                    0.125
particle mass          1
SRC rotation angle     120 deg
random rotation sign   true
grid shift             true
thermostat             cell_relative_rescale every step
U0                     0.05
TG forcing amplitude   0.00205
TG forcing mode        (1,1)
steps                  10000
seed                   1628605
resampling             off
LiveVis                off
filtered recording     off
```

The forcing is intentionally kept at the x23b value.  Retuning it at gamma=20
would confound the occupancy/noise test with a forcing change.  The measured
modal amplitude therefore remains the quantity to inspect; this run is first a
diagnostic discriminator, not an independently calibrated gamma=20 production
point.

The liquid-closure production path is unchanged: CUDA `auto_fv_cg`, tolerance
`1e-5`, max 800 iterations, `prestream_single_fused`, density relaxation time
0.25, particle thresholds 3 and 6, gain 1, minimum fill 0.10, resident x7j on,
0407 single-block off, and no resampling.

## Dump cadence

x23b used one state every 125 steps.  Since gamma=20 contains 2.5 times as many
particles, x23c uses

```text
dump every 250 steps
```

(41 states per run including step zero/final, subject to solver dump convention).
This halves I/O while retaining adequate temporal resolution.  It does not
change the dynamics.

## Preflight

```bash
PREFLIGHT_ONLY=1 LIVE_PROGRESS=1 \
bash scripts/run_0493x23c_article_forced_tg_gamma20.sh
```

## Run

```bash
LIVE_PROGRESS=1 \
bash scripts/run_0493x23c_article_forced_tg_gamma20.sh
```

Outputs are written below

```text
article_forced_tg_gamma20_x23c/
```

The analyzer is the same x23b analysis, apart from the campaign tag and Q6
bookkeeping already corrected in x23b.


## fix1: override and output safety
`STEPS`, `DUMP_STATE_EVERY`, `U0`, `TG_FORCING_AMPLITUDE`, grid/thermal controls and seed now use shell-default semantics (`${VAR:-default}`). A generic inherited `ARTICLE_ROOT` is deliberately ignored. Use `X23C_ARTICLE_ROOT` for an explicit destination. Every default invocation receives a timestamped output root, and existing roots are never deleted unless `CLEAN_ARTICLE_ROOT=1` is explicitly supplied.
