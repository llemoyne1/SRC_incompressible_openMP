# 0303 — CUDA SRC classic demo scripts with post-SRC resampling

This patch updates the demonstration layer so that the validated post-SRC CUDA
support-control modules can be used directly in the usual visualization runs.
The physical SRC classic step remains unchanged: streaming/advection, boundary
conditions, grid shift, SRC collision and thermostat keep their existing CUDA
paths.  Resampling is applied only after SRC classic, as a conservative
representative-particle remeshing module.

## Scripts

Updated existing demos:

- `scripts/run_demo_src_classic_cuda_taylor_green_forced_0283.sh`
- `scripts/run_demo_src_classic_cuda_poiseuille_periodic_forced_0283.sh`
- `scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh`
- `scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh`

New dedicated Von Karman script:

- `scripts/run_demo_src_resampling_cuda_von_karman_cylinder_0303.sh`

The Von Karman script is intentionally separate from
`run_demo_src_classic_cuda_von_karman_cylinder_0285.sh` so local experiments on
0285 do not affect the development demo suite.

Common helper:

- `scripts/src_gpu_resampling_demo_common_0303.sh`

Build and convenience launchers:

- `scripts/build_src_mpcd_cuda_resampling_demos_0303.sh`
- `scripts/run_demo_src_resampling_cuda_compare_suite_0303.sh`

## Default mode

By default, the updated scripts run with post-SRC resampling enabled:

```bash
RESAMPLING_ENABLE=1
GUARD_NMIN=12
GUARD_NTARGET=20
GUARD_NMAX=32
GUARD_EVERY=20
RESTORE_ENABLE=1
BOUNDARY_AWARE=1
OPEN_BOUNDARY_HALO_CELLS=1
BOUNDARY_HALO_CELLS=0
SOLID_HALO_CELLS=0
```

The passive 0295 support survey is enabled in both classic and resampling modes
so that post-processing can quantify the support distribution:

```bash
RESAMPLING_SURVEY_ENABLE=1
RESAMPLING_SURVEY_EVERY=${SUMMARY_EVERY}
```

## Output layout

Each script writes into an isolated 0303 directory with the mode encoded in the
path.  For example:

```text
runs/demo_src_resampling_cuda_backward_step_io_0303/classic_survey/
runs/demo_src_resampling_cuda_backward_step_io_0303/resampling_guard_nmin12_nt20_nmax32/
```

This makes it possible to run the same case with and without resampling and use
existing MATLAB/Python post-processing tools on the two output directories.

Each run also writes:

```text
logs/resampling_0303.env
output/summary_runtime.csv
output/cuda_resampling_support_survey_0295.csv
output/cuda_resampling_population_guard_0297.csv   # when resampling is active
```

## Build

```bash
OUT=build/src_mpcd_base_cuda_0303 \
CUDA_ARCH_FLAGS="--generate-code=arch=compute_89,code=sm_89 --generate-code=arch=compute_89,code=compute_89" \
bash scripts/build_src_mpcd_cuda_resampling_demos_0303.sh
```

The build helper delegates to the newest CUDA build script available in the
branch, starting from 0302 and falling back through earlier validated builders.

## Run one case with and without resampling

Example for backward step:

```bash
BIN=build/src_mpcd_base_cuda_0303 \
RESAMPLING_ENABLE=0 \
bash scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh

BIN=build/src_mpcd_base_cuda_0303 \
RESAMPLING_ENABLE=1 \
GUARD_NMIN=12 GUARD_NTARGET=20 GUARD_NMAX=32 \
bash scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh
```

## Run all demo cases in both modes

```bash
BIN=build/src_mpcd_base_cuda_0303 \
FORCE_REBUILD=0 \
bash scripts/run_demo_src_resampling_cuda_compare_suite_0303.sh
```

Cases can be selected with:

```bash
RUN_TG=1
RUN_POISEUILLE=1
RUN_STEP=1
RUN_SEGMENTED=1
RUN_VK=1
```

and modes with:

```bash
RUN_CLASSIC=1
RUN_RESAMPLING=1
```

## Von Karman notes

The new Von Karman script defaults to a moderate inlet velocity:

```bash
UIN=0.60
```

For strict reproducibility diagnostics, disable the thermostat:

```bash
THERMOSTAT_ENABLE=0 \
RESAMPLING_ENABLE=1 \
bash scripts/run_demo_src_resampling_cuda_von_karman_cylinder_0303.sh
```

For visualization and physical stress tests, the thermostat can remain enabled.
The thermostat-enabled Von Karman path is not intended as a bitwise OFF/ON
validator; it is a physical visualization/stress case.

## Scope

This patch does not modify the C++ core.  It only updates demonstration scripts,
adds a dedicated Von Karman resampling demo, and standardizes build/output
conventions for side-by-side visualization and post-processing.
