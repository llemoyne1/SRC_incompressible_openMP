# 0493x5a2 — dynamic liquid-vacuum free-surface dam break

## Scope

0493x5a established that `free_surface_masked` can maintain a flat, partially
filled liquid under gravity for 2000 steps. 0493x5a2 exercises the same
operator on a strongly deforming interface: a rectangular liquid column is
released in an otherwise empty closed box.

This patch changes no Q6 operator, force integration, collision, thermostat or
boundary-condition code. It adds a new generator profile, one qualification
runner and offline geometry/solver diagnostics. Dynamic gas remains absent.

## Initial state

The generator receives:

```
--empty-outside-column
```

It retains liquid particles only where

```
x < columnWidth and y < columnHeight
```

and creates no particles elsewhere. This option is mutually exclusive with
`--liquid-only` and `--liquid-fill-height`. Existing dam-break, full-liquid and
horizontal partial-fill profiles are covered by a small regression script.

Default dynamic case:

- box: `Lx=2`, `Ly=1`;
- grid: `300 x 150`, giving square cells;
- liquid column: width `0.5`, height `0.8`;
- nominal liquid population: `gamma=10`;
- liquid mass: `1000`;
- `kBT=0.05`, `dt=0.005`, `g_y=-0.5`;
- 1000 steps;
- no gas, resampling, Darcy, virial term or open boundary.

The projected liquid uses:

```
speciesQ6Mode = free_surface_masked
q6ForceProjectionMode = prestream_single_fused
speciesQ6MinOccupancyFraction = 0.25
```

## Qualification runner

Preflight:

```
LIVE_PROGRESS=1 PREFLIGHT_ONLY=1 \
  bash scripts/run_0493x5a2_dynamic_free_surface_dam_break.sh
```

Short smoke:

```
LIVE_PROGRESS=1 \
BASE_RUN_ROOT=runs/0493x5a2_dynamic_smoke_s20 \
STEPS=20 SUMMARY_EVERY=1 DUMP_STATE_EVERY=10 \
  bash scripts/run_0493x5a2_dynamic_free_surface_dam_break.sh
```

Default dynamic run:

```
LIVE_PROGRESS=1 \
  bash scripts/run_0493x5a2_dynamic_free_surface_dam_break.sh
```

The compact non-regression wrapper checks all four generator profiles and runs
the dynamic preflight. Set `RUN_SMOKE=1` to add the 20-step binary smoke.

## Offline diagnostics

The analyzer reads every state dump and the two existing Q6 audit files. It
reports a temporal series containing:

- liquid particle and mass conservation;
- centre-of-mass motion;
- maximum and 99/99.5-percentile front positions;
- occupied and pressure-support cell counts;
- low-population interfacial cells;
- maximum cell population;
- number and size of connected pressure-support components;
- enclosed inactive cavities;
- free-surface face count;
- Q6 convergence, active support, iterations and residual;
- resident deposit, solve, apply and total timings.

Outputs:

```
dynamic_free_surface_0493x5a2.json
dynamic_free_surface_0493x5a2.csv
```

`PASS-like` requires conserved liquid particle count, converged Q6 audit rows
and no cell population above the configurable `MAX_POPULATION_FACTOR * gamma`
(default factor 12). Interface fragmentation, enclosed cavities and front
motion are deliberately reported rather than used as hard failures: they may
be physical during impact and must be interpreted from the time series.

## Interpretation boundary

This is the decisive liquid-vacuum test before adding an explicit gas. A pass
supports proceeding to a compressible, non-projected gas species. A failure
must first be classified as one of:

- loss or fragmentation of the liquid pressure support;
- CG conditioning/convergence failure as topology changes;
- excessive local compression at impact;
- nonphysical diffusion or spray into the empty region.

The historical flat-interface 0493x5a case and 0493x4b Taylor--Green/full-box
qualifications remain the physical non-regressions.
