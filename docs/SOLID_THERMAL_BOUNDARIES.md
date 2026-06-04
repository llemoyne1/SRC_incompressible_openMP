# Generic solid thermal boundaries

This branch uses a unified solid-wall model for rectangular boundaries. The recommended configuration is now:

```text
bcBottom = solid
bcTop = solid
wallAccommodation = 1.0
wallVpGamma = 0.0
wallKBT = -1.0
wallThermalNoise = 1.0
```

The older `specular`, `bounceback`, and `wallVpEnable=true` paths remain available as debugging/legacy options, but the intended production path for no-slip/isothermal solid walls is `solid`.

## Numerical model

The model separates two roles.

1. **Geometric impermeability.** Real particles crossing a `solid` face are reflected specularly in the normal direction. This prevents leakage while not imposing a tangential bounceback rule directly on the streaming step.

2. **Thermal/mechanical coupling.** During the SRC/MPCD collision, every shifted collision cell cut by the solid receives an aggregate wall contribution:

```text
Mwall = wallAccommodation * wallVpGamma * wallVpMass * fsolid
Pwall = Mwall * Uwall + wallThermalNoise * sqrt(Mwall * wallKBT) * eta
```

where `fsolid` is the fraction of the shifted collision cell lying outside the fluid domain adjacent to the face, and `eta` is a deterministic Gaussian sample generated from the run seed, step, cell id and face id.

The cell velocity used for the real-particle rotation is then:

```text
Ucell = (Preal + Pwall) / (Mreal + Mwall)
```

Only real particles are rotated and stored. The wall contribution is not advected and is not written to `.smpcd` dumps.

## Parameters

Minimal solid-wall controls:

```text
wallAccommodation = 1.0   # [0,1], 0 slip-like, 1 full thermal wall coupling
wallVpGamma = 0.0         # 0 => infer Np/(Nx*Ny)
wallVpMass = 1.0
wallKBT = -1.0            # negative => inherit kBT
wallThermalNoise = 1.0    # 0 deterministic wall momentum, 1 thermal aggregate noise
```

Wall velocities can be specified per face:

```text
wallUxLeft = 0.0
wallUyLeft = 0.0
wallUxRight = 0.0
wallUyRight = 0.0
wallUxBottom = 0.0
wallUyBottom = 0.0
wallUxTop = 0.0
wallUyTop = 0.0
```

Legacy names `wallVpUx*`, `wallVpUy*`, and `wallVpKBT` are still accepted.

## Interpretation

- `wallAccommodation = 0` gives an impermeable but nearly slip-like solid wall.
- `wallAccommodation = 1` gives the strongest no-slip/isothermal coupling currently implemented.
- `wallThermalNoise = 0` is useful for deterministic debugging.
- `wallThermalNoise = 1` is the recommended thermal-wall setting.

The model is designed to generalize later to curved solid geometries by replacing the rectangular face solid-fraction computation with a geometry-provided solid fraction, wall velocity and wall temperature.

## Examples

```bash
./build/src_mpcd_base examples/params_channel_y_solid_thermal.kv
./build/src_mpcd_base examples/params_channel_x_solid_thermal.kv
./build/src_mpcd_base examples/params_poiseuille_y_solid_thermal_thermostat.kv
```

Poiseuille post-processing:

```matlab
addpath('matlab')
out = analyze_poiseuille_profile('runs/poiseuille_y_solid_thermal_thermostat', ...
    'flowComponent', 'Ux', ...
    'profileDirection', 'y', ...
    'fitStartFraction', 0.5, ...
    'excludeWallCells', 2);
```
