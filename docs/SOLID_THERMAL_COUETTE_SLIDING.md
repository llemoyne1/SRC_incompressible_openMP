# Solid thermal sliding-wall Couette validation

This validation checks that the generic `solid_thermal` wall model can impose a
purely tangential wall velocity. This is the first moving-wall test: the wall
geometry is still fixed, and only the tangential wall velocity used by the
thermal solid-wall coupling is non-zero.

Two transposed Couette runs are provided:

```text
examples/params_couette_y_solid_thermal_long.kv
examples/params_couette_x_solid_thermal_long.kv
```

The first case uses periodic `x`, solid `y` walls, a fixed bottom wall, and a top
wall sliding in `+x`. The expected mean profile is approximately linear in
`y`.

The second case is the transposed validation: periodic `y`, solid `x` walls, a
fixed left wall, and a right wall sliding in `+y`. The expected mean profile is
approximately linear in `x`.

Run the two cases from the repository root:

```bash
./build/src_mpcd_base examples/params_couette_y_solid_thermal_long.kv
./build/src_mpcd_base examples/params_couette_x_solid_thermal_long.kv
```

Then analyze them in MATLAB:

```matlab
addpath('matlab')

out = validate_solid_thermal_couette_sliding( ...
    'runs/couette_y_solid_thermal_long', ...
    'runs/couette_x_solid_thermal_long', ...
    'fitStartFraction', 0.5, ...
    'excludeWallCells', 2, ...
    'stationaryWindowFraction', 0.25);
```

The validation reports:

- the linear-fit quality of each mean profile;
- the measured velocity gradient;
- the expected gradient from the two wall velocities;
- slip estimates at both walls;
- a transposition comparison between `Ux(y)` and `Uy(x)`;
- temperature and thermostat-control diagnostics.

Passing this test validates tangential moving solid walls for aligned rectangular
boundaries. It does not validate normal wall motion or compression; those require
a time-dependent geometry and moving-wall reflection law.
