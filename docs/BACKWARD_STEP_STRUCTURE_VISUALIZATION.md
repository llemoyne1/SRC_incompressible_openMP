# Backward-step high-signal classic visualization case

This note documents the non-canonical but useful high-signal periodic-x case
added after the first rectangle-step smoke/long validations.

## Motivation

The conservative long case
`examples/params_backward_step_classic_long_96x48.kv` validates the immersed
rectangle mechanics: no real particle remains inside the block, immersed wall
hits are non-zero, and a reversed downstream region is detectable after time
averaging. However, the mean flow is deliberately weak relative to the thermal
velocity, so coherent structures are not visually strong in instantaneous or
lightly averaged fields.

The high-signal case
`examples/params_backward_step_classic_structure_96x48.kv` keeps the same
geometry and initial state, but increases `bodyAccelerationX` from `0.003` to
`0.015` and lowers the thermostat target through `kBT = 0.0025`. The goal is to
improve the advective signal-to-thermal-noise ratio before moving to true
inlet/outlet boundary conditions.

This is still not a canonical backward-facing-step benchmark: `bcLeft` and
`bcRight` remain periodic. It is a diagnostic/visualization case for the classic
compressible immersed-solid implementation.

## Run

From the repository root:

```bash
./scripts/build_src_mpcd_base.sh
```

Generate the initial state if needed:

```matlab
cd matlab
generate_backward_step_state('output','../initial_state_backward_step_96x48_g20.smpcd');
cd ..
```

Run the high-signal case:

```bash
./scripts/run_backward_step_classic_structure.sh
```

The output directory is:

```text
runs/backward_step_classic_structure_96x48
```

## Post-processing

From `matlab/`:

```matlab
out = validate_backward_step_classic_long('../runs/backward_step_classic_structure_96x48','field','omega');
```

The validator now reports the late thermal velocity and ratios such as
`meanUxOverThermalLate` and `meanUxDownstreamOverThermal`. These are useful for
checking whether the mean flow is large enough to emerge from SRC/MPCD thermal
noise.

The plots also overlay the `Ux = 0` contour and a downsampled mean-velocity
quiver on selected fields. A dedicated recirculation mask plot highlights the
region where the time-averaged streamwise velocity is negative.

## Interpretation

Use this case only to check that the immersed rectangle produces a visible
separated/reversed region under stronger forcing. The physically cleaner next
milestone remains true classic inlet/outlet boundary conditions. Q6/Q9 should
still remain disabled on this internal-solid geometry until the elliptic
operator receives an internal solid mask.
