# Patch 0283 — SRC classic CUDA demonstration scripts

This patch adds self-contained demonstration launchers for the `SRC_GPU` branch.
They are intentionally restricted to the SRC classic step:

```text
advection / streaming
+ random grid shift
+ SRC rotation / collision
+ thermostat
```

The liquid closure modules remain disabled in all five demos:

```text
projectionEnable = false
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false
```

The default dump cadence is `dumpStateEvery = 100`, so the outputs are directly
usable for animation workflows based on `state_step_*.smpcd` dumps.

## Scripts

```bash
scripts/run_demo_src_classic_cuda_taylor_green_forced_0283.sh
scripts/run_demo_src_classic_cuda_poiseuille_periodic_forced_0283.sh
scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh
scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh
scripts/run_demo_src_classic_cuda_von_karman_cylinder_0283.sh
scripts/run_demo_src_classic_cuda_all_0283.sh
scripts/src_gpu_demo_common_0283.sh
```

Although the request mentioned four scripts, the enumerated list contains five
physical demonstrations; this patch therefore provides five individual scripts
plus one convenience runner.

## Demonstrations

### Taylor--Green forced, periodic

```bash
bash scripts/run_demo_src_classic_cuda_taylor_green_forced_0283.sh
```

Default output:

```text
runs/demo_src_classic_cuda_taylor_green_forced_0283/output
```

CUDA path: periodic resident CUDA stream/collision/thermostat.

### Periodic-x forced Poiseuille

```bash
bash scripts/run_demo_src_classic_cuda_poiseuille_periodic_forced_0283.sh
```

Default output:

```text
runs/demo_src_classic_cuda_poiseuille_periodic_forced_0283/output
```

CUDA path: wall-simple CUDA streaming + persistent CUDA SRC collision + CUDA
thermostat.

### Closed box, same-face inlet/outlet on x=0

```bash
bash scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh
```

Default output:

```text
runs/demo_src_classic_cuda_box_same_face_io_0283/output
```

CUDA path: segmented inlet/outlet resident CUDA + fused CUDA SRC thermostat.

### Backward step with inlet/outlet

```bash
bash scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh
```

Default output:

```text
runs/demo_src_classic_cuda_backward_step_io_0283/output
```

CUDA path: full-face inlet/outlet resident CUDA with rectangle/step obstacle +
fused CUDA SRC thermostat.

### Von Karman cylinder

```bash
bash scripts/run_demo_src_classic_cuda_von_karman_cylinder_0283.sh
```

Default output:

```text
runs/demo_src_classic_cuda_von_karman_cylinder_0283/output
```

Important scope note: the current CUDA immersed-solid fast path is rectangle
specific.  The cylinder script therefore keeps the circular immersed-solid
reflection on the CPU path while keeping the simulation in SRC classic mode and
using CUDA for the SRC collision/thermostat stage.  The rectangle backward-step
demo is the resident-CUDA immersed-solid demonstration.

## Useful overrides

All scripts accept environment overrides, for example:

```bash
STEPS=8000 DUMP_STATE_EVERY=100 THREADS=12 \
  bash scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh
```

Common overrides:

```text
NX, NY, GAMMA, STEPS, DT, KBT, SEED
SUMMARY_EVERY, DUMP_STATE_EVERY, THREADS
RUN_ROOT, CLEAN_RUN_ROOT, LIVE_PROGRESS, AUTO_BUILD, BIN
```

Case-specific examples:

```text
TG_U0, TG_FORCING_AMPLITUDE
BODY_AX, U0
UIN, UOUT
STEP_XMIN, STEP_XMAX, STEP_YMIN, STEP_YMAX
CYLINDER_CX, CYLINDER_CY, CYLINDER_R
```

## Output layout

Each script writes:

```text
runs/demo_*/init/*.smpcd
runs/demo_*/params/*.kv
runs/demo_*/logs/*.log
runs/demo_*/logs/*.time
runs/demo_*/output/summary_runtime.csv
runs/demo_*/output/state_step_*.smpcd
```

The `params/*.kv` files are intentionally kept so each demonstration is
reproducible and can be relaunched manually with the selected binary.


## 0283b runner fix

Patch 0283b removes legacy parameter keys that are not accepted by the current
`SRC_GPU` parser and adds explicit post-run checks for `summary_runtime.csv` and
`state_step_*.smpcd` animation dumps.  On failure, the runner now prints the
stderr/time tail, stdout/log tail and the head of the generated parameter file.
