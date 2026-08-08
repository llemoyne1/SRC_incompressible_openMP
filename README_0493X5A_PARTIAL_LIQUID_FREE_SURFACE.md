# 0493x5a — partial liquid with a free-surface Q6-g solve

## Purpose

0493x4b validated the fused single-solve ordering on a completely filled closed
box:

```
tentative-force deposit -> Q6 solve -> fused force+Q6 apply
-> stream -> collision -> thermostat
```

0493x5a keeps that ordering and introduces a deliberately narrow first
free-surface case: one incompressible liquid species occupies only the lower
part of a static closed box; the upper part contains no active gas particles.
Resampling, Darcy, virial/capacity terms, immersed solids and open boundaries
remain excluded.

## New species-Q6 mode

```
speciesQ6Mode = free_surface_masked
q6ForceProjectionMode = prestream_single_fused
```

Exactly one registered species must declare `q6StrengthDeclared > 0`. Other
registered species are permitted but receive no direct Q6 correction. In
0493x5a the second, gas-labelled species is registered only as an absent future
phase.

The active pressure support is selected from the absolute liquid fill proxy

```
fill(c,s) = mass(c,s) / referenceCellMass(s)
```

using the existing control

```
speciesQ6MinOccupancyFraction
```

as the minimum fill fraction in this new mode. This intentionally differs from
`independent_masked`, where the same field remains the relative species
occupancy inside a mixed cell. No new threshold parameter is introduced.  The qualification runner uses a
default minimum fill of `0.25`, so a nominal `gamma=10` cell remains in the raw
support from three liquid particles upward.

## Free-surface pressure condition

An active liquid cell adjacent to an inactive cell uses a zero-gauge pressure
condition at their common face. The cell-centre-to-face distance is half a grid
spacing, so the masked Laplacian and the face correction use factor two on an
active/inactive face:

```
A_face(phi_c) = 2 phi_c / h^2
Delta u_face  = 2 strength phi_c / h
```

Solid exterior walls retain their existing impermeable boundary treatment.
Before the solve, a deterministic one-cell closing fills only a cavity whose
every in-domain von Neumann neighbour belongs to the raw liquid support.  This
prevents an isolated low-population bulk cell from becoming a pressure-release
hole, while a genuine liquid-empty interface remains open because it has an
inactive neighbour.  No extra tuning parameter is added.

The old `independent_masked` operator is unchanged and keeps factor one at its
masked interfaces.

## Fused force application

The species tentative deposit includes the body-force kick before the solve.
The new free-surface apply kernel then, in one particle pass:

1. applies the physical force to every active fluid particle;
2. applies the Q6 correction only to particles of the projected liquid species
   whose cell belongs to the saved pressure mask;
3. accumulates only the Q6 part in the pressure-momentum audit.

This distinction prepares the later liquid-plus-gas extension: an unprojected
gas will still receive the body force without receiving a liquid pressure
correction.

## Initial qualification runner

```
LIVE_PROGRESS=1 PREFLIGHT_ONLY=1 \
  bash scripts/run_0493x5a_partial_liquid_free_surface.sh

LIVE_PROGRESS=1 \
  bash scripts/run_0493x5a_partial_liquid_free_surface.sh
```

Defaults:

- grid: `200 x 200`;
- liquid fill height: `0.5`;
- `gamma=10` in the initial liquid cells;
- raw support threshold: `0.25` of the reference cell mass;
- liquid mass: `1000`;
- `kBT=0.05`;
- `dt=0.005`;
- gravity: `g_y=-0.5`;
- 1000 steps;
- no dynamic gas;
- no live visualization by default.

The state generator extension leaves all cells above the specified fill height
empty. The offline analyzer reports particle conservation, centre-of-mass
drift, occupied support, interface row and cell-population extrema.

## Intended interpretation

0493x5a is a first pressure-support experiment, not yet a general liquid-gas
model. It validates the free-surface discretisation on a broad, initially flat
Dirichlet interface. It does not yet address:

- dynamic compressible gas;
- mixed liquid-gas cells;
- fragmented droplets or spray support;
- topology regularisation of isolated holes;
- surface tension;
- resampling near the interface.

The retained regressions are the 0493x4b Taylor--Green equivalence, the full
liquid gravity test, and all existing `independent_masked` multi-boundary tests.
