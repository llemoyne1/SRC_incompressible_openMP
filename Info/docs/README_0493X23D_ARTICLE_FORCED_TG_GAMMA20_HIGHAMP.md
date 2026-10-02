# 0493x23d — forced Taylor–Green gamma=20, higher-signal discriminator

## Purpose

`0493x23d` complements `0493x23c`.  It asks whether the Taylor–Green validation
becomes substantially clearer when both sources of poor observability are
reduced:

1. occupancy noise is reduced by using `gamma=20`;
2. the coherent Taylor–Green velocity signal is doubled from `U0=0.05` to
   `U0=0.10`.

This is **not** a return to the over-forced x23a case.  The continuous forcing is
doubled together with the prescribed modal amplitude, so the ratio

```text
Af / U0 = 0.041
```

is unchanged from x23b/x23c.

The comparison remains exactly two paths starting from one shared particle
state:

```text
SRC
SRC + particle/field closure
```

No C++/CUDA equation is changed.

## Parameters

```text
grid                   256 x 256
Lx = Ly                 1.0
h                       1/256
gamma                   20
m                       1
kBT                     0.125
rotation angle          120 deg
dt                      0.0063471328149122585
seed                    1628605

TG mode                 (1,1)
U0                      0.10
TG forcing amplitude    0.00410
forcing                 continuous, divergence-free

steps                   10000
dump every              250
summary every           100
LiveVis                 OFF
filtered recording      OFF
resampling              OFF
```

The production liquid-closure path is unchanged from x23b/x23c:
`src-q6-g-f`, `prestream_single_fused`, resident x7j CG, 0407 disabled,
projection tolerance `1e-5`, maximum 800 iterations, density relaxation time
0.25, and no resampling.

## Why U0=0.10

For a cell-average velocity at `gamma=20`, `kBT=0.125`, the thermal variance per
velocity component scales as `kBT/gamma`.  A simple signal-plus-noise estimate
for the normalized TG correlation is

```text
C_TG ~ sqrt[(U0^2/2) / (U0^2/2 + 2 kBT/gamma)].
```

It gives approximately 0.30 for `U0=0.05` and approximately 0.53 for `U0=0.10`.
Thus x23d increases the modal signal enough to be visually discriminating while
remaining far below the x23a over-forced regime.

## Preflight

```bash
PREFLIGHT_ONLY=1 LIVE_PROGRESS=1 \
  bash scripts/run_0493x23d_article_forced_tg_gamma20_highamp.sh
```

The preflight generates no state and launches no solver.

## Run

```bash
LIVE_PROGRESS=1 \
  bash scripts/run_0493x23d_article_forced_tg_gamma20_highamp.sh
```

Default output root:

```text
article_forced_tg_gamma20_highamp_x23d/
```

The analyzer writes the same observables and article/check figures as x23b/x23c,
allowing direct comparison of the two gamma=20 conditions.


## fix1: override and output safety
`STEPS`, `DUMP_STATE_EVERY`, `U0`, `TG_FORCING_AMPLITUDE`, grid/thermal controls and seed now use shell-default semantics (`${VAR:-default}`). A generic inherited `ARTICLE_ROOT` is deliberately ignored. Use `X23D_ARTICLE_ROOT` for an explicit destination. Every default invocation receives a timestamped output root, and existing roots are never deleted unless `CLEAN_ARTICLE_ROOT=1` is explicitly supplied.
