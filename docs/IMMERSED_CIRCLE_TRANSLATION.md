# Translating immersed circular solid

This note documents the first translating immersed circular solid test. The
implementation keeps the same analytic circle representation used for the fixed
and rotating cases, but the center is now allowed to move linearly:

```text
Cx(t) = immersedCircleCx + immersedCircleVx * t
Cy(t) = immersedCircleCy + immersedCircleVy * t
```

The local wall velocity used by reflection and by the aggregate `solid_thermal`
wall coupling is

```text
Uwall(x,y,t) = Vc + Uoffset + omega ez x (x - C(t))
```

or in components:

```text
Uwall_x = immersedCircleVx + immersedCircleWallUx - immersedCircleOmega*(y-Cy(t))
Uwall_y = immersedCircleVy + immersedCircleWallUy + immersedCircleOmega*(x-Cx(t))
```

The legacy `immersedCircleWallUx/Uy` offsets should normally remain zero. Use
`immersedCircleVx/Vy` for true geometry translation.

## Parameters

The first validation case is:

```text
examples/params_immersed_circle_translating_64x64.kv
```

It uses:

```text
immersedCircleCx = 0.5
immersedCircleCy = 0.5
immersedCircleR  = 0.12
immersedCircleVx = 0.005
immersedCircleVy = 0.0
immersedCircleOmega = 0.0
nSteps = 50000
dt = 0.001
```

so the center moves from `x=0.50` to `x=0.75` over the run. The circle remains
inside the fixed numerical box and inside the active fluid domain.

## Initial state

The initial state should exclude the circle at its initial position:

```matlab
addpath('matlab')

generate_smpcd_state_uniform( ...
    'output', 'initial_state_circle_64x64_g20.smpcd', ...
    'Lx', 1.0, ...
    'Ly', 1.0, ...
    'Nx', 64, ...
    'Ny', 64, ...
    'gamma', 20, ...
    'kBT', 0.01, ...
    'mass', 1.0, ...
    'type', 0, ...
    'seed', 12345, ...
    'excludeCircle', true, ...
    'circleCx', 0.5, ...
    'circleCy', 0.5, ...
    'circleR', 0.12);
```

## Run

```bash
./build/src_mpcd_base examples/params_immersed_circle_translating_64x64.kv
```

## Validation

```matlab
addpath('matlab')

out = validate_immersed_circle_translation( ...
    'runs/immersed_circle_translating_64x64', ...
    'makePlots', true, ...
    'field', 'speed');
```

Expected smoke criteria:

```text
maxParticlesInsideCircle = 0
totalMassRelDrift       = 0
kBTMean                 close to 0.01
meanImmersedVirtualMass stable and close to the circle area estimate
```

## Numerical status

This is a deliberately conservative, slowly translating solid. Reflection is a
post-streaming correction against the current-time analytic circle. This is
adequate while the solid displacement per time step remains much smaller than a
cell width. For faster moving solids, the next refinement should be a swept
segment/surface intersection instead of post-correction only.
