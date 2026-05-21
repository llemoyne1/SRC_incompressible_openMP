# Rectangular wall virtual particles

This branch keeps the C++ solver as a compact SRC/MPCD engine and adds the first wall-coupling layer through aggregate virtual particles.

## Scope

Implemented in this patch:

- rectangular faces only: left, right, bottom, top;
- compatible with any non-periodic wall pair in `x` and/or `y`;
- virtual particles are not stored in `.smpcd` states;
- virtual particles are sampled as aggregate mass/momentum contributions to collision cells cut by shifted-grid wall regions;
- real-particle dumps remain unchanged.

Not implemented yet:

- explicit solid geometry virtual particles, e.g. cylinder;
- inlet/outlet/open boundaries;
- wall-pressure mechanical diagnostics;
- mass-aware thermostat of the real fluid.

## Parameters

Enable wall virtual particles with:

```text
wallVpEnable = true
wallVpMode = stochastic_fraction
wallVpGamma = 0.0
wallVpMass = 1.0
wallVpKBT = -1.0
```

`wallVpGamma = 0.0` means that the code infers the expected full-cell virtual-particle count from the mean real occupancy:

```text
gamma = Np / (Nx * Ny)
```

`wallVpKBT < 0` means that virtual particles inherit `kBT` from the parameter file.

Wall velocities can be specified per face:

```text
wallVpUxLeft = 0.0
wallVpUyLeft = 0.0
wallVpUxRight = 0.0
wallVpUyRight = 0.0
wallVpUxBottom = 0.0
wallVpUyBottom = 0.0
wallVpUxTop = 0.0
wallVpUyTop = 0.0
```

The current examples use fixed walls.

## Collision-cell contribution

For each shifted collision cell, the code computes the part of the cell located outside the physical domain next to each wall face. For a face area fraction `f`, the expected number of virtual particles is:

```text
lambda = wallVpGamma * f
```

A Poisson sample `Nv ~ Poisson(lambda)` is drawn deterministically from the run seed, step, cell index and face id. Instead of storing `Nv` explicit particles, the code samples their aggregate momentum around the prescribed wall velocity:

```text
Mvp = Nv * wallVpMass
Pvp = Mvp * Uwall + Gaussian fluctuation with variance Nv * wallVpMass * wallVpKBT
```

The real-particle center-of-mass velocity in the cell is then computed from:

```text
Mcell = Mreal + Mvp
Pcell = Preal + Pvp
Ucell = Pcell / Mcell
```

Only real particles are rotated and advanced. Virtual particles exist only during the collision-moment calculation.

## Diagnostics

`summary_runtime.csv` contains two additional columns:

```text
virtualParticleCount
virtualMass
```

The existing `meanN/stdN/minN/maxN` diagnostics still refer to real-particle cell occupancy only.

## Examples

```bash
build/src_mpcd_base examples/params_channel_y_bounceback_vp.kv
build/src_mpcd_base examples/params_channel_x_bounceback_vp.kv
```

Then inspect in MATLAB:

```matlab
addpath('matlab')
plot_smpcd_summary('runs/channel_y_bounceback_vp')
postprocess_smpcd_run('runs/channel_y_bounceback_vp', 'field', 'speed')
```
