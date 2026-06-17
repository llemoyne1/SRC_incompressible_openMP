# 0342a CUDA-VIZ injection/fill resampling validation script

This script adapts the legacy `run_injection_fill_resampling_validation_0209a_step.sh` validation to the 0342a CUDA-VIZ executable.

It preserves the four original cases:

- `classic`
- `classic_resampling`
- `q6`
- `q6_resampling`

The script adds the 0341/0342 live visualization runtime controls:

- `LIVE_VIS_CONTROL_FILE`
- `LIVE_VIS_CONTROL_DIR`
- `LIVE_VIS_CONTROL_BASENAME`
- `LIVE_VIS_CONTROL_EVERY`
- `LIVE_VIS_CONTROL_LOG`
- `LIVE_VIS_COLORMAP`
- `SRC_LIVE_VIS_COLORMAP`

By default, each case gets its own control file:

```text
<run_root>/<case>/livevis_control.kv
```

The generated file contains:

```text
field = density
colormap = gray
clip = -1
gain = 1.0
smoothPasses = 2
```

Edit this file during the run to change the displayed field, colormap, gain, clip and smoothing without stopping the solver.

Available colormaps in 0342a:

- `blue_red`
- `gray`
- `thermal`

## Conservative CUDA behavior

The script uses `build/src_mpcd_base_cuda_livevis_0342a` and enables `srcClassicCudaModeEnable = true` in the parameter files, but it does not force the segmented resident CUDA inlet/outlet path by default.

This is intentional: the validation includes Q6/resampling cases, and the purpose of this adaptation is to preserve the legacy validation behavior while enabling CUDA-VIZ/livevis controls.

For an explicit experiment with the segmented resident path, set:

```bash
FILL_CUDA_SEGMENTED_RESIDENT=1
```

For Q6 cases as well, additionally set:

```bash
FILL_CUDA_SEGMENTED_RESIDENT_Q6=1
```

Do this only after comparing against the conservative default.

## Minimal smoke test

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-VIZ

unzip -o /mnt/data/src_gpu_viz_0342a_injection_fill_validation_script_files_only.zip
bash -n scripts/run_injection_fill_resampling_validation_0342a_livevis.sh

RUN_CASES=classic \
FILL_STEPS=200 \
FILL_SUMMARY_EVERY=100 \
FILL_DUMP_EVERY=200 \
LIVE_PROGRESS=1 \
AUTO_BUILD=1 \
./scripts/run_injection_fill_resampling_validation_0342a_livevis.sh
```

Check the livevis logs:

```bash
grep -R "livevis0335\|control reload\|colormap\|elapsed\|ERROR\|Fatal" \
  runs/validate_0342a_livevis_injection_fill_resampling_0139/logs/*.time
```

