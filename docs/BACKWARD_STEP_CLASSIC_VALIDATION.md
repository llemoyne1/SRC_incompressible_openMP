# Backward-step classic validation

This validation step follows the first `immersed_solid` rectangle smoke test. It
keeps the solver in **classic compressible SRC/MPCD** mode and uses a
bottom-attached rectangular immersed solid as a backward-step-like separation
edge in a periodic-x forced channel.

The case is intentionally not the final academic inlet/outlet backward-facing
step. It is a controlled intermediate milestone for checking:

- no real particles remain inside the immersed rectangle;
- immersed-wall reflection and virtual-particle collision contributions remain
  active over a longer run;
- the thermostat remains stable;
- a time-averaged reversed-flow/separated region is visible downstream of the
  vertical face of the block.

Q6/Q9 and virial kicks are disabled. They should stay disabled for this geometry
until the elliptic operator receives an internal solid mask or face-open/closed
coefficients; otherwise the projection can communicate through the solid block.

## Generate the initial state

From the repository root:

```matlab
cd matlab
generate_backward_step_state('output','../initial_state_backward_step_96x48_g20.smpcd');
cd ..
```

## Build

```bash
./scripts/build_src_mpcd_base.sh
```

## Run

The suite runs the smoke case and the longer validation case:

```bash
./scripts/run_backward_step_classic_validation.sh
```

To run only the longer case:

```bash
RUN_SMOKE=0 ./scripts/run_backward_step_classic_validation.sh
```

The longer case writes to:

```text
runs/backward_step_classic_long_96x48
```

## MATLAB post-processing

From the repository root:

```matlab
cd matlab
out = validate_backward_step_classic_long('../runs/backward_step_classic_long_96x48');
```

The validator writes three CSV files into the run directory when `writeTables` is
true:

```text
backward_step_classic_long_summary.csv
backward_step_lower_layer_profile.csv
backward_step_mean_fields.csv
```

The main reported quantities are:

- `maxParticlesInsideRectangle`;
- `totalImmersedHits`;
- late-time thermal statistics;
- lower-layer reversed-flow fraction;
- downstream vorticity RMS;
- approximate reattachment metrics based on cells and on the lower-layer mean
  profile.

These diagnostics are qualitative/semi-quantitative at this stage because the
case still uses periodic-x forcing, not inlet/outlet boundary conditions.
