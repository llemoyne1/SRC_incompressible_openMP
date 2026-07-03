# 0442 — CUDA shadow validator for resampling particle-state plan application

This step validates the particle-state mutation stage of the resident resampling roadmap.
It does **not** change the production solver and introduces no public solver parameter.

## Scope

The validator runs periodic, wall-free, no-solid synthetic cases and uses the CPU
weighted-resampling deposit to build the passive extraction/insertion operation list.
It then compares:

1. CPU production extraction + insertion on `ParticleState`.
2. CUDA persistent extraction + insertion on `CudaParticleState`, downloaded back to host.

This validates the final particle-state apply primitive after:

- 0439: CUDA deposit/classification shadow,
- 0440: CUDA poor/rich compaction shadow,
- 0441: CUDA transfer planner shadow.

## What is checked

For each case, the validator checks:

- CPU/GPU extraction and insertion operation counts,
- no invalid GPU operations,
- role and type arrays identical,
- `x/y/vx/vy/mass` arrays identical within tolerance,
- fluid/inactive role counts identical,
- active prefix remains valid,
- mass and momentum conservation relative to the initial state.

Cases:

- shear, uniform mass, no grid shift,
- shear, uniform mass, shifted grid,
- Taylor--Green, variable mass, no grid shift,
- Taylor--Green, variable mass, shifted grid.

The shifted cases are expected to exercise non-empty passive plans.

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
OUT=build/validate_cuda_resampling_particle_apply_shadow_0442 \
bash scripts/build_validate_cuda_resampling_particle_apply_shadow_0442.sh
```

## Run

```bash
BIN=build/validate_cuda_resampling_particle_apply_shadow_0442 \
RUN_ROOT=runs/0442_cuda_resampling_particle_apply_shadow_smoke \
NX=64 NY=32 GAMMA=20 INACTIVE_SLOTS=1024 SEED=1628638 \
bash scripts/run_validate_cuda_resampling_particle_apply_shadow_0442.sh
```

Expected summary:

```text
CUDA_RESAMPLING_PARTICLE_APPLY_SHADOW_0442 PASS cases=4/4
```
