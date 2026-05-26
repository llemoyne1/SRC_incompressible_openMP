# Combined translating + rotating immersed circle demonstration

This note adds a single demonstration run for a circular immersed solid that:

- translates slowly in `+x`, and
- rotates counter-clockwise.

The goal is demonstrative rather than benchmark-grade. It validates that the
same immersed-solid machinery can support combined rigid-body motion.

## 1. Initial state

Generate an initial state excluding the circle at its initial position:

```matlab
addpath('matlab')

generate_smpcd_state_uniform( ...
    'output', 'initial_state_circle_combined_64x64_g20.smpcd', ...
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
    'circleCx', 0.35, ...
    'circleCy', 0.50, ...
    'circleR', 0.12);
```

## 2. Run

```bash
./build/src_mpcd_base examples/params_immersed_circle_combined_motion_64x64.kv
```

The provided example uses:

- `immersedCircleVx = 0.003`
- `immersedCircleVy = 0.0`
- `immersedCircleOmega = 0.20`

with `dt = 0.001`, `nSteps = 50000`.

Hence over the full run:

- the center moves from `x=0.35` to `x=0.50`,
- the surface speed scale is `omega*R = 0.024`.

## 3. MATLAB demonstration helper

```matlab
addpath('matlab')

out = demo_immersed_circle_combined_motion( ...
    'runs/immersed_circle_combined_motion_64x64', ...
    'makePlots', true, ...
    'playAnimation', true, ...
    'animationField', 'omega', ...
    'timeAverageStartFraction', 0.5, ...
    'filterType', 'box', ...
    'filterWidth', 3, ...
    'temporalHalfWindow', 1, ...
    'pauseTime', 0.04);
```

This helper chains:

1. `validate_immersed_circle_smoke`
2. `validate_immersed_circle_translation`
3. `validate_immersed_circle_rotation`
4. `analyze_immersed_circle_time_average`
5. `play_smpcd_filtered_animation`

## 4. Expected qualitative outcomes

Expected outcomes for this first combined-motion demonstration:

- no particle penetration into the circle,
- conserved total mass,
- stable `kBT`,
- visible translation of the center path,
- non-zero near-wall tangential velocity,
- filtered animation showing a moving and rotating disturbance around the circle.

This is intended as a compact demonstration of capability, not yet as a
quantitative moving-body benchmark.
