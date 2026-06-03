# Immersed analytic solid: rectangle / backward-step smoke case

This patch generalizes the previous `immersed_circle` implementation into the
single module `immersed_solid`. The public C++ calls are now shape-neutral:

- `immersed_solid_enabled`
- `point_is_inside_immersed_solid`
- `apply_immersed_solid_reflection`
- `immersed_solid_fraction_in_cell`
- `immersed_solid_wall_velocity`

The currently supported analytic shapes are:

```text
immersedSolidShape = circle
immersedSolidShape = rectangle
```

The legacy `immersedCircle*` keys remain accepted as aliases for
`immersedSolidShape = circle`, so existing circle parameter files should keep
running unchanged.

## Rectangle / step parameters

```text
immersedSolidEnable = true
immersedSolidShape = rectangle
immersedSolidXMin = 0.25
immersedSolidXMax = 0.65
immersedSolidYMin = 0.0
immersedSolidYMax = 0.50
immersedSolidFractionSamples = 4
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0
```

The rectangle is axis-aligned. Translation through `immersedSolidVx/Vy` is
accepted, but rotation is intentionally not implemented for rectangles yet.

## First smoke case

The included first case is deliberately **classic compressible only**:

```bash
cd matlab
generate_backward_step_state('output','../initial_state_backward_step_96x48_g20.smpcd');
cd ..
./scripts/build_src_mpcd_base.sh
./build/src_mpcd_base examples/params_backward_step_classic_smoke_96x48.kv
```

The geometry is a bottom-attached rectangular block in a periodic-x channel.
The downstream vertical face acts as a backward-step-like separation edge. This
is a geometry/reflection/virtual-particle smoke case, not the final inlet/outlet
backward-facing-step benchmark.

Post-process with:

```matlab
cd matlab
out = validate_backward_step_smoke('../runs/backward_step_classic_smoke_96x48');
```

## Q6/Q9 status

Do not treat this rectangle smoke test as a validated Q6/Q9 immersed-solid case.
The elliptic core still operates on the rectangular fluid grid and does not yet
receive an internal solid mask. The next Q6/Q9 step should add face/cell solid
masking to the elliptic operator so that projection fluxes cannot cross the
immersed rectangle.
