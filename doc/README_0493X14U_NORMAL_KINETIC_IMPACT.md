
# 0493x14u — normal kinetic gas/liquid momentum transfer

## Why this is the next benchmark

x14t established that the **thermodynamic gas pressure** is transmitted to
the liquid correctly.  x14u isolates the remaining normal interaction:

> when gas particles arrive at the interface with directed normal momentum,
> is the momentum lost by the specularly reflected gas actually transferred
> to the liquid?

This directly tests the current architectural choice:

    gasWallImpulseFeedback = NOT_APPLIED

without changing C++/CUDA.

## Geometry

Same already-qualified resident family as x14t fix2:

    y top specular wall
          stationary gas
    ------------------------- liquid/gas interface
          liquid slab 80h
    ------------------------- liquid/gas interface
          gas impact band 24h, +Uy
          stationary gas
    y bottom specular wall

x is periodic.  There is no contact line.

All cells have occupancy 20.  Therefore the initial thermodynamic pressure is
exactly equal on both sides:

    p_bottom = p_top = 20 kBT_G / h^2.

The default impact speed is U=0.1 and only the 24 cells immediately adjacent
to one interface are given the drift.  The external-wall neighborhoods remain
at zero mean velocity, making the early momentum budget much cleaner.

The mirrored `top_impact` case uses -U and is generated as the y-mirror of
`bottom_impact`.  `static` is the zero-drift control.

## Two x6g modes

Primary isolation:

    constant

with pConst=pRef.  Hence x6g contributes **zero gas pressure force at all
times**. Any liquid response is kinetic/common-SRC transfer.

Secondary production comparison:

    eos_accessible_volume

which is the x14s production gas-pressure law. This shows whether later gas
density changes create an indirect pressure response.

## Two independent observables

### 1. Initial kinetic-pressure acceleration

For a shifted Maxwellian incident on a specular wall,

    Pwall(U) = 2 n m [(U^2+s^2) Phi(U/s) + U s phi(U/s)]

with s^2=kBT/m.

The generator also evaluates the same incoming momentum flux directly from
the actual generated band velocities.  The default U=0.1 gives an initial
kinetic pressure excess of order 2e4 and therefore an expected liquid
acceleration close to 0.05, comparable to x14t.

The analyzer fits the antisymmetric liquid velocity during steps 1..20.

### 2. Direct momentum budget — the decisive metric

For the bottom/top mirror pair:

    P_L^a = (P_L,bottom - P_L,top)/2
    P_G^a = (P_G,bottom - P_G,top)/2

The initial directed gas momentum P_G^a(0) is known from the generator.

Define

    loss_G(t) = P_G^a(0) - P_G^a(t)

and

    G_mom(t) = P_L^a(t) / loss_G(t).

Interpretation in the constant-x6g isolation:

- G_mom ~ 1:
  gas kinetic momentum lost at reflection is recovered by the liquid through
  the existing interaction chain; explicit wall-impulse feedback is probably
  unnecessary.

- G_mom << 1:
  reflected gas momentum is disappearing into the fixed kinetic wall rather
  than being transferred to the liquid; this is direct evidence that an
  explicit gas->liquid impulse channel is missing.

The impact band is kept away from the external walls and the primary window
is only t<=0.04, so external-wall momentum exchange should not contaminate
the main result.

## Disk use

No state dumps are produced by default:

    DUMP_STATE_EVERY=0

The three ~88 MiB initial states are generated once and reused by both x6g
modes.  The returned tar.gz excludes those states.

## Install

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
unzip -o /path/to/0493x14u_normal_kinetic_impact_benchmark.zip

python3 -m py_compile \
  scripts/generate_0493x14u_normal_kinetic_impact.py \
  scripts/analyze_0493x14u_normal_kinetic_impact.py

bash -n scripts/run_ok_0493x14u_normal_kinetic_impact.sh
```

## Recommended run

The geometry and x14s chain are already smoke-tested by x14t, so the useful
next operation is the full short paired matrix:

```bash
X6G_MODES="constant eos_accessible_volume" \
CASES="static bottom_impact top_impact" \
STEPS=60 \
SUMMARY_EVERY=1 \
DUMP_STATE_EVERY=0 \
LIVE_VIS_ENABLE=0 \
bash scripts/run_ok_0493x14u_normal_kinetic_impact.sh
```

Return:

```text
runs/0493x14u_normal_kinetic_impact/0493x14u_normal_kinetic_impact_compact.tar.gz
```
