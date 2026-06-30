# 0426 — Darcy demo fast resident CUDA flags

This differential bundle updates the Darcy/Brinkman demonstration scripts so that they all use the same optimized resident SRC collision/thermostat controls by default.

## Motivation

The backward-step ablation showed that the large slowdown was not caused by Darcy/chi, `alpha`, `chiVP`, `mean_outward_bath`, or segmented IO itself. The slow runs were missing the resident CUDA fast flags already present in the solid/full-face validation script. With the fast flags enabled, the physical backward-step Darcy case returned to the same order of runtime as the solid/full-face reference.

## Modified scripts

- `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `scripts/run_src_classic_cuda_darcy_chi_vonkarman_periodic_0416.sh`
- `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

## Added helper

Each script now defines and calls:

```bash
export_src_cuda_resident_fastflags_0426
```

The helper is enabled by default and can be disabled with:

```bash
MPCD_DARCY_FASTFLAGS_ENABLE=0
```

## Fast defaults added

```bash
MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM=1
MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK=256
MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319=1
```

All assignments use `${VAR:-default}`, so an explicit external value is preserved.

## Suggested validation

From the repository root:

```bash
STEPS=500 LIVE_VIS_ENABLE=0 TOPO_BENCHMARK_ENABLE=false DARCY_COST_EVERY=1000000 \
  TAG=step_darcy_fastflags_0426 \
  RUN_ROOT=runs/step_darcy_fastflags_0426 \
  bash scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh
```

Expected files:

```text
runs/step_darcy_fastflags_0426/logs/src_classic_darcy_step.time
runs/step_darcy_fastflags_0426/logs/environment_0425.env
runs/step_darcy_fastflags_0426/output/summary_runtime.csv
runs/step_darcy_fastflags_0426/output/darcy_cost_0343.csv
runs/step_darcy_fastflags_0426/output/params_used.kv
```

To check that the fast flags were captured:

```bash
grep -E 'MPCD_DARCY_FASTFLAGS_ENABLE|DEVICE_ROTATION|FAST_THERMOSTAT|FUSED_STREAM|SKIP_FINAL|SKIP_SETUP|SKIP_WORKSPACE|SKIP_HOST_CELLID|THREADS_PER_BLOCK' \
  runs/step_darcy_fastflags_0426/logs/environment_0425.env
```
