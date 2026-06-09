# 0309 — Visual demo scripts for split-safe CUDA resampling

This patch adds three visualization-oriented demo runners:

- `scripts/run_demo_visual_poiseuille_resampling_0309.sh`
- `scripts/run_demo_visual_backward_step_resampling_0309.sh`
- `scripts/run_demo_visual_von_karman_resampling_0309.sh`

and a convenience suite:

- `scripts/run_demo_visual_resampling_suite_0309.sh`

The scripts run `classic` and `resampling_split_safe` modes by default, with separate
run roots under `runs/visual_src_resampling_cuda_*_0309/`.

The nominal resampling mode is the 0308 split-safe configuration:

```bash
MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1
MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=1
MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307=0.5
MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307=0.25
MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307=0
```

Each script also writes a small MATLAB helper file in its run root, showing typical
`play_smpcd_dumps` calls using the role/mass/speed particle visualization tools.

Examples:

```bash
BIN=build/src_mpcd_base_cuda_0308 FORCE_REBUILD=0 \
bash scripts/run_demo_visual_poiseuille_resampling_0309.sh

BIN=build/src_mpcd_base_cuda_0308 FORCE_REBUILD=0 \
UIN=0.60 NX=128 NY=48 STEPS=6000 \
bash scripts/run_demo_visual_backward_step_resampling_0309.sh

BIN=build/src_mpcd_base_cuda_0308 FORCE_REBUILD=0 \
NX=196 NY=64 STEPS=12000 UIN=0.45 \
bash scripts/run_demo_visual_von_karman_resampling_0309.sh
```

Use `VIS_MODES=classic` or `VIS_MODES=resampling` to run only one mode.
