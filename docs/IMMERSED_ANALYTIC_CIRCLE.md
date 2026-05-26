# Immersed analytic circular solid

This step introduces one fixed analytic immersed circular solid. It is a first
minimal building block for later cylinders, internal obstacles and moving rigid
bodies.

The implementation deliberately reuses the generic `solid_thermal` wall model:
rectangular walls and the immersed circle are handled by the same aggregate
virtual-wall contribution during the SRC/MPCD collision. The circle adds no real
particles to `.smpcd` dumps.

## Parameters

```text
immersedCircleEnable = true
immersedCircleCx = 0.5
immersedCircleCy = 0.5
immersedCircleR = 0.12
immersedCircleFractionSamples = 4
immersedCircleWallUx = 0.0
immersedCircleWallUy = 0.0
immersedCircleOmega = 0.0   # fixed-center rotation, positive counter-clockwise

wallAccommodation = 1.0
wallVpGamma = 0.0        # 0 => infer mean real occupancy
wallVpMass = 1.0
wallKBT = -1.0           # negative => inherit kBT
wallThermalNoise = 1.0
```

The circle must lie inside the initial active fluid domain. The present geometry
is fixed-center: `immersedCircleOmega` prescribes a local tangential wall velocity
without moving the circular region itself. Translation of the circle center will
be introduced separately because it changes the signed-distance function in time.

## Particle reflection

After streaming and rectangular boundary handling, particles found inside the
circle are mirrored along the local radial normal. Their velocity is reflected
specularly in the wall frame:

```text
v_rel' = v_rel - 2 (v_rel . n) n
v'     = U_wall + v_rel'
```

This is a simple post-streaming correction. Swept intersection with the circle
can be added later if high velocities or very small obstacles require it.

## Collision coupling

For each shifted collision cell, the code estimates the fraction occupied by the
circle through regular sub-cell sampling. The aggregate wall mass and momentum
are added to the cell moments before computing the SRC cell velocity.

Runtime diagnostics include:

```text
hitsImmersed
virtualMassImmersed
```

These are control diagnostics only. Detailed wake, vorticity and particle
occupancy analyses remain post-processing tasks.

## Initial state

Generate a particle state excluding the circular solid:

```matlab
addpath('matlab')

generate_smpcd_state_uniform( ...
    'output', 'initial_state_circle.smpcd', ...
    'Lx', 1.0, 'Ly', 1.0, ...
    'Nx', 32, 'Ny', 32, ...
    'gamma', 80, ...
    'kBT', 0.01, ...
    'mass', 1.0, ...
    'type', 0, ...
    'seed', 12345, ...
    'excludeCircle', true, ...
    'circleCx', 0.5, ...
    'circleCy', 0.5, ...
    'circleR', 0.12);
```

## Smoke runs

```bash
./build/src_mpcd_base examples/params_immersed_circle_periodic_solid_thermal.kv
./build/src_mpcd_base examples/params_immersed_circle_forced_periodic_solid_thermal.kv
./build/src_mpcd_base examples/params_immersed_circle_rotating_64x64.kv
```

## MATLAB validation

```matlab
addpath('matlab')

out = validate_immersed_circle_smoke( ...
    'runs/immersed_circle_periodic_solid_thermal', ...
    'makePlots', true, ...
    'field', 'omega');
```
