# Rotating fixed immersed circle

This validation step extends the analytic immersed circular solid with a local
rigid-body wall velocity corresponding to a fixed-center rotation.

The circle geometry remains fixed:

```text
immersedCircleCx = 0.5
immersedCircleCy = 0.5
immersedCircleR  = 0.12
```

but its local wall velocity is now

```text
U_wall(x,y) = U0 + omega ez x (x-C)
```

that is, in 2D,

```text
Ux = immersedCircleWallUx - immersedCircleOmega * (y - Cy)
Uy = immersedCircleWallUy + immersedCircleOmega * (x - Cx)
```

`immersedCircleOmega > 0` corresponds to counter-clockwise rotation. The uniform
velocity hooks `immersedCircleWallUx/Uy` should normally remain zero for the
fixed-center rotation validation. Translating circle geometry will be introduced
separately because it changes the signed-distance function in time.

## Example

```bash
./build/src_mpcd_base examples/params_immersed_circle_rotating_64x64.kv
```

The example uses:

```text
immersedCircleOmega = 0.2
immersedCircleR     = 0.12
```

so the surface speed is approximately:

```text
U_surface = omega R = 0.024
```

## MATLAB checks

Smoke validation:

```matlab
out = validate_immersed_circle_smoke( ...
    'runs/immersed_circle_rotating_64x64', ...
    'makePlots', true, ...
    'field', 'omega');
```

Time-averaged fields:

```matlab
avg = analyze_immersed_circle_time_average( ...
    'runs/immersed_circle_rotating_64x64', ...
    'fieldList', {'Ux','Uy','omega','speed'}, ...
    'timeAverageStartFraction', 0.5, ...
    'filterType', 'box', ...
    'filterWidth', 3, ...
    'showPlots', true);
```

A useful qualitative signature is a mean tangential velocity around the circle
and a localized vorticity layer near the immersed surface, while preserving:

```text
maxParticlesInsideCircle = 0
totalMassRelDrift        = 0
kBT                       ≈ target
```
