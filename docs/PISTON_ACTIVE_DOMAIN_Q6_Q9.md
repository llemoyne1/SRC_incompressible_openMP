# Moving active-domain piston with Q6/Q9

This note documents the first C++ moving-active-domain integration for the
incompressible branch. The goal is to prepare piston and later virial/EOS tests
without introducing a piston-specific code path.

The rectangular active fluid domain is treated as a moving-wall geometry:

```text
fixed numerical box : [0,Lx] x [0,Ly]
active fluid domain : [fluidXMin(t),fluidXMax(t)] x [fluidYMin(t),fluidYMax(t)]
```

The wall velocities already used by the solid-wall reflection and `solid_thermal`
virtual-wall collision coupling are now also passed to the elliptic projection
adapters.

## What changed architecturally

The generic elliptic core still operates on cell fields and face fluxes. It now
supports prescribed non-periodic wall fluxes through `EllipticProjectionBC`:

```text
xLowFlux, xHighFlux, yLowFlux, yHighFlux
```

For fixed walls these fluxes are zero. For moving active-domain walls:

- Q6 uses wall normal velocities as prescribed velocity fluxes;
- Q9 uses `meanCellMass * wall normal velocity` as prescribed mass fluxes.

The Q6/Q9 adapters now deposit onto a projection grid mapped to the current
active-domain bounds. This keeps the moving-domain support in the same moving
wall machinery used by the boundary and collision code, rather than adding a
separate piston branch.

## Moving-domain divergence target

A moving closed domain is not compatible with a strictly zero mean divergence.
For a rectangular active domain the uniform geometric divergence rate is

```text
D_domain = (vxMax-vxMin)/(xMax-xMin) + (vyMax-vyMin)/(yMax-yMin)
```

For the standard top-piston case this is negative. Q6 uses this value as the
uniform target divergence. Q9 adds the corresponding mean mass-flux target,

```text
meanCellMass * D_domain
```

to the MATLAB-like filtered relaxation target. This preserves the expected mean
compression while keeping the low-k Q9 mechanism close to the validated MATLAB
logic.

## Generate the initial state

From the `matlab/` directory:

```matlab
addpath('.')
generate_piston_active_y095_state();
```

This writes:

```text
../initial_state_active_y095.smpcd
```

The state is generated inside the initial active domain `0 <= y <= 0.95`.

## Runs

From the repository root:

```bash
./build/src_mpcd_base examples/params_piston_y_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q6_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q9_filtered_solid_thermal_isothermal.kv
```

The classic case is the existing compressible active-domain piston. The Q6/Q9
cases use the same moving wall and the same `solid_thermal` coupling.

## Analysis

From `matlab/`:

```matlab
addpath('.')
out = validate_piston_q6_q9_active_domain('makePlots', true);
```

The validator checks:

- active wall motion and active area;
- density ratio versus `area(0)/area(t)`;
- total mass conservation;
- thermal stability;
- Q6/Q9 elliptic diagnostics;
- Q9 correction magnitude;
- particle-wall safety diagnostics.

## Relation to the future virial/EOS patch

This patch does not implement a virial pressure kick. It only validates that the
moving active-domain geometry is consistently visible to reflection, wall virtual
particles, Q6 and Q9. A later virial/EOS patch can then add pressure closure on
top of a moving-domain Q6/Q9 baseline.
