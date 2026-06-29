# STEP_DARCY_0425 — Backward-step Darcy/chi validation scripts

## Purpose

This bundle adds an autonomous Darcy/chi backward-step script and a comparison launcher against the existing portable solid backward-step script.

The goal is to validate on a non-circular geometry the retained Darcy/chi treatment from the VK campaign:

```text
Darcy mean + outward bath + chi collision VP
```

with the current reference settings:

```bash
DARCY_INITIAL_DEACTIVATE_BELOW_CHI=0.05
DARCY_BRINKMAN_FORCING_MODE=mean_outward_bath
DARCY_CHI_COLLISION_VP_ENABLE=true
DARCY_CHI_COLLISION_VP_STRENGTH=0.25
```

## Added scripts

```text
scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh
scripts/run_backward_step_solid_vs_darcy_0425.sh
```

## Geometry

The default geometry matches the uploaded solid backward-step script:

```text
Lx = 2.0
Ly = 1.0
Nx = 128
Ny = 96
gamma = 20
step rectangle: x in [0, 1.05], y in [0, 0.42]
```

The Darcy script generates:

```text
RUN_ROOT/init/backward_step_darcy_<Nx>x<Ny>_g<gamma>.smpcd
RUN_ROOT/chi/chi_backward_step_<Nx>x<Ny>_x<STEP_XMAX>_y<STEP_YMAX>_f32.f32
```

The generated `chi` is binary:

```text
chi = 0 in the step solid
chi = 1 in the fluid
```

The initial state is generated with active fluid particles only outside the step rectangle, plus inactive reservoir slots.

## Boundary convention

For the Darcy/chi case, the script uses segmented open boundaries:

```text
left inlet  : y/Ly in [STEP_YMAX/Ly, 1]
right outlet: y/Ly in [0, 1]
top/bottom : solid walls
```

This avoids injecting particles directly into the chi-solid part of the step.

The uploaded solid reference script uses an immersed rectangle plus the portable inlet/outlet path. The comparison launcher runs it in `classic` mode to avoid adding resampling as a confounding factor.

## Comparison launcher

Run a short smoke test:

```bash
STEPS=1000 LIVE_VIS_HOLD_ON_EXIT=0 bash scripts/run_backward_step_solid_vs_darcy_0425.sh
```

Run the full comparison with the solid-script defaults:

```bash
LIVE_VIS_HOLD_ON_EXIT=0 bash scripts/run_backward_step_solid_vs_darcy_0425.sh
```

The launcher writes:

```text
runs/backward_step_solid_vs_darcy_0425/backward_step_compare_manifest_0425.csv
```

and launches:

```text
solid
darcy_mean_outward_chiVP_s025
```

## Notes

- The Darcy script is deliberately autonomous and regenerates both `chi` and initial state.
- The retained model is enabled by default.
- The comparison launcher uses the current `build/src_mpcd_base_cuda_q6_resident_0400_livevis` binary.
- Set `LIVE_VIS_HOLD_ON_EXIT=1` only for interactive inspection; for automated sequential runs keep it at `0`.
- For deeper comparison, an additional lightweight post-processing script can later be added for backward-step metrics: recirculation length, reverse-flow area, centerline profiles, and filtered vorticity/enstrophy.
