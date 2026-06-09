# 0315 — Portable split-safe CUDA resampling demo scripts

This patch adds five self-contained shell scripts for final visual/quality runs:

- `scripts/run_portable_tg_hole_resampling_0315.sh`
- `scripts/run_portable_poiseuille_resampling_0315.sh`
- `scripts/run_portable_box_segmented_x0_resampling_0315.sh`
- `scripts/run_portable_backward_step_resampling_0315.sh`
- `scripts/run_portable_von_karman_resampling_0315.sh`

The scripts deliberately do not source the historical `src_gpu_demo_common_*` or `src_gpu_resampling_demo_common_*` helpers.  Each script:

1. generates its own `.smpcd` initial state with an embedded Python generator;
2. writes its own `.kv` parameter file;
3. sets the CUDA resident classic-SRC flags explicitly;
4. sets the validated post-SRC resampling flags explicitly, including split-safety 0307;
5. creates a MATLAB helper file in the run directory.

Default mode is `RUN_MODES=resampling`.  To compare classic and resampling:

```bash
RUN_MODES="classic resampling" bash scripts/run_portable_backward_step_resampling_0315.sh
```

The nominal split-safe settings are:

```bash
MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1
MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=1
MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307=0.5
MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307=0.25
MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307=0
```

By default, the scripts use compact fluid-only dumps:

```bash
DUMP_ROLE_FILTER=fluid
SUMMARY_ROLE_FILTER=fluid
```

Set `DUMP_ROLE_FILTER=all` if restart-compatible dumps or inactive-slot visualization is required.  This is heavier when `INACTIVE_SLOTS` is large.

Von Karman supports two modes:

```bash
VK_MODE=io       # inlet/outlet full-face, default
VK_MODE=periodic # periodic x, wall y, circular obstacle
```

The scripts target a 0314-capable binary by default, but can be pointed at any compatible binary with:

```bash
BIN=build/src_mpcd_base_cuda_0314 bash scripts/run_portable_von_karman_resampling_0315.sh
```
