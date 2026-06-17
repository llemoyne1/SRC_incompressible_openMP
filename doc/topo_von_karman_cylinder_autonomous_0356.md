# 0356f-topo: align autonomous VK with the portable 0337 periodic-circle path

This update fixes the parameter/path mismatch between the autonomous 0356 VK
runner and `run_portable_von_karman_resampling_0337_livevis.sh`.

The previous autonomous runner used an IO-fullface resident CUDA path even when
`bcLeft=periodic` and `bcRight=periodic`. The portable VK reference uses the
periodic-circle/wall-simple path instead.

## New/changed defaults

```text
VK_CUDA_PATH = periodic_circle
THERMOSTAT_SHARED_0251_0260 = 0
SEED = 1628505
SUMMARY_EVERY = 1000
INACTIVE_SLOTS = 7500
LIVE_VIS_CLIP = -20
LIVE_VIS_SMOOTH_PASSES = 3
```

`VK_CUDA_PATH=periodic_circle` disables the full-face IO resident flags and uses
the same CUDA family as the portable periodic-cylinder case.

## Clean comparison commands

### Portable reference, classic only

The portable script defaults to running both `classic` and `resampling`. For a
clean comparison against the autonomous runner, force classic only:

```bash
BIN=build/src_mpcd_base_cuda_livevis_0342a \
RUN_MODES=classic \
VK_MODE=periodic \
LIVE_VIS_FIELD=ux \
./scripts/run_portable_von_karman_resampling_0337_livevis.sh
```

### Autonomous immersed-solid run, matched path

```bash
BIN=build/src_mpcd_base_cuda_topo_0348a \
CYLINDER_MODEL=immersed \
VK_CUDA_PATH=periodic_circle \
THERMOSTAT_SHARED_0251_0260=0 \
ROTATION_ANGLE=1.5 \
LIVE_VIS_ENABLE=1 \
LIVE_VIS_FIELD=ux \
DUMP_STATE_EVERY=1000 \
TAG=topo_vk_0356f_immersed_solid_matched \
bash scripts/run_topo_von_karman_cylinder_autonomous_0356.sh
```

### Darcy-only run on the same periodic path

```bash
BIN=build/src_mpcd_base_cuda_topo_0348a \
CYLINDER_MODEL=darcy \
VK_CUDA_PATH=periodic_circle \
THERMOSTAT_SHARED_0251_0260=0 \
ROTATION_ANGLE=1.5 \
DARCY_ALPHA_MAX=5000 \
DARCY_Q=0.05 \
DARCY_INTERFACE_WIDTH=0.002 \
LIVE_VIS_ENABLE=1 \
LIVE_VIS_FIELD=ux \
DUMP_STATE_EVERY=1000 \
TAG=topo_vk_0356f_darcy5000_matched \
bash scripts/run_topo_von_karman_cylinder_autonomous_0356.sh
```

## Notes

The portable script writes `rotationAngle=1.5` rad, while the original user
parameters used `alphaDeg=90`, i.e. `pi/2`. The autonomous runner now accepts
`ROTATION_ANGLE=...` as an override, so use `ROTATION_ANGLE=1.5` for strict
comparison with the portable script.

The summary file now records:

```text
VK_CUDA_PATH
THERMOSTAT_SHARED_0251_0260
CYLINDER_MODEL
IMMERSED_SOLID_ENABLE
DARCY_ENABLE
```
