# Numerical safety guidelines for moving solid walls

This note gives practical limits for prescribed wall velocities, immersed-solid
rotation rates, immersed-solid translations and time step selection in the
SRC/MPCD base solver.

These are **documentation-level safeguards**. The solver intentionally does not
reject runs automatically from these criteria, because the acceptable range can
depend on the physical test. However, runs far outside these ranges should be
treated as numerically unsafe until specifically validated.

## 1. Definitions

For a uniform Cartesian grid,

```text
dx = Lx / Nx
dy = Ly / Ny
a  = min(dx, dy)
```

For a particle of mass `m`, a useful thermal speed scale is

```text
v_th = sqrt(kBT / m)
```

For a wall or immersed body, define the maximum imposed wall speed

```text
U_wall,max = max |U_wall(x,t)|
```

For a rotating circular solid of radius `R`,

```text
U_surface = |omega| * R
```

For a translating solid,

```text
U_surface ≈ sqrt(Vx^2 + Vy^2)
```

For a moving piston or active fluid-domain boundary,

```text
U_normal = |d yTop / dt|     or     |d xWall / dt|
```

## 2. Recommended step-displacement limits

The first safety criterion is that imposed wall motion should be small compared
with a collision cell over one time step.

Recommended safe range:

```text
U_wall,max * dt / a <= 0.05 to 0.10
```

For exploratory runs, avoid exceeding:

```text
U_wall,max * dt / a <= 0.20
```

For a rotating circle, use:

```text
|omega| * R * dt / a <= 0.05 to 0.10
```

For a translating immersed solid, use:

```text
sqrt(Vx^2 + Vy^2) * dt / a <= 0.05 to 0.10
```

For a piston or moving active-domain boundary, use:

```text
|U_normal| * dt / a <= 0.05 to 0.10
```

## 3. Low-Mach / thermal-speed criterion

The imposed wall speed should usually remain small compared with the thermal
speed scale. This is especially important for clean viscosity calibration and
weakly compressible/quasi-incompressible tests.

Recommended range:

```text
U_wall,max / v_th <= 0.1 to 0.3
```

For a rotating circle:

```text
|omega| * R / sqrt(kBT / wallVpMass) <= 0.1 to 0.3
```

For the current standard tests with

```text
kBT = 0.01
mass = 1.0
```

the thermal speed scale is

```text
v_th = 0.1
```

Thus a wall speed of `0.02` corresponds to

```text
U_wall / v_th = 0.2
```

which is a reasonable validation value.

## 4. Angular-speed criterion

For a circular cylinder rotating about its own centre, the geometry is fixed and
only the wall velocity changes. Therefore the main relevant limit is the surface
speed criterion above.

For non-circular rotating solids, the geometry itself changes orientation. Then
the angular increment per step should also remain small:

```text
|omega| * dt <= 0.01 to 0.05 rad
```

This criterion will become important for future polygon/SDF/STL solids.

## 5. Reflection robustness criterion

The current immersed-circle implementation uses a simple post-streaming
correction/reflection. It does not yet perform exact segment-surface impact-time
detection. Therefore very large particle or wall displacements can lead to
unreliable reflection behaviour.

For robust runs, monitor:

```text
maxParticlesInsideCircle = 0
totalMassRelDrift       = 0
kBT                     stable
hitsImmersed            non-explosive
```

If particles remain inside a solid at dumps, reduce one or more of:

```text
dt
bodyAccelerationX/Y
wall velocity
immersedCircleOmega
```

or increase spatial resolution.

## 6. Suggested starting values
