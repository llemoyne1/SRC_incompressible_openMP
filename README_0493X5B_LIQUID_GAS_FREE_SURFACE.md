# 0493x5b — liquid Q6-g with an explicit compressible gas

## Purpose

0493x5b adds the first two-species dynamic free-surface qualification on top of
0493x5a/0493x5a2.  It deliberately does not change the CUDA operator.  The
existing `free_surface_masked` path already has the required phase-selective
semantics:

- exactly one registered species has `q6StrengthDeclared > 0`;
- the liquid support is built from liquid mass only;
- the fused force kick is applied to every fluid particle;
- the Q6 pressure correction is applied only to the projected liquid type;
- the gas has `q6StrengthDeclared = 0` and remains compressible;
- the resident multispecies SRC collision supplies liquid-gas momentum exchange.

The pressure solve still uses the 0493x5a free-surface gauge `p=0` on
liquid/non-liquid faces.  Gas pressure is therefore coupled to the liquid only
through particle collisions in this stage; it is not inserted as a Dirichlet
pressure value in the Q6 operator.

## Runner

```bash
LIVE_PROGRESS=1 \
bash scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh
```

Default configuration:

- box `2 x 1`, grid `300 x 150`;
- liquid column `0.5 x 0.8`;
- ten particles per cell in both phases;
- liquid particle mass `1000`, gas particle mass `1`;
- `kBT=0.05`, `dt=0.005`, `g_y=-0.5`;
- liquid Q6 strength `1`, gas Q6 strength `0`;
- `speciesQ6Mode=free_surface_masked`;
- `q6ForceProjectionMode=prestream_single_fused`;
- no resampling, Darcy, capacity response, virial term, or open boundary.

Live visualization filters to the liquid type by default because the gas fills
all exterior cells.  Set `PARTICLE_TYPE_FILTER=-1` to visualize both species.

## Offline checks

`scripts/analyze_0493x5b_liquid_gas_free_surface.py` verifies:

- separate conservation of liquid and gas particle counts;
- convergence of every liquid Q6 solve;
- zero Q6 active cells and zero Q6-corrected particles for the gas;
- liquid support topology and population extrema;
- mixed liquid-gas cells and particles in the mixed layer;
- liquid front and center-of-mass evolution;
- gas occupancy and velocity statistics;
- resident Q6 timings.

The generated files are:

```text
liquid_gas_free_surface_0493x5b.json
liquid_gas_free_surface_0493x5b.csv
```

## Initial qualification sequence

Use a short dynamic smoke before the 1000-step comparison:

```bash
LIVE_PROGRESS=1 \
BASE_RUN_ROOT=runs/0493x5b_liquid_gas_smoke_s20 \
LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 \
STEPS=20 SUMMARY_EVERY=1 DUMP_STATE_EVERY=5 \
bash scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh
```

The liquid-vacuum 0493x5a2 run remains the reference for determining whether
explicit gas reduces or aggravates interface fragmentation and post-impact
liquid densification.
