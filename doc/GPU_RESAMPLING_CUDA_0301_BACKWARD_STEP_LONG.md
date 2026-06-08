# 0301 — Backward-step long active validation for CUDA resampling

## Purpose

Patch 0301 adds a focused long/moderate validation campaign for the local post-SRC CUDA support-control chain:

```text
0295 passive support survey
0296 optional mass reconditioning
0297 local population guard
0298 relative-energy restoration
0299 boundary-aware candidate filtering
```

The backward step is the preferred next physical test because short 0300 sweeps already showed that it is the first default case where the guard actually triggers.  It also stresses the intended failure mode: particle depletion in the recirculation/shear region behind the step when the inlet velocity is large enough.

No new core C++ source is introduced in 0301.  The patch adds an isolated backward-step validation script, a long-run sweep script and a standard-library Python analyzer.

## Files

```text
scripts/build_src_mpcd_cuda_0301.sh
scripts/run_cuda_resampling_backward_step_validation_0301.sh
scripts/run_cuda_resampling_backward_step_long_0301.sh
scripts/analyze_cuda_resampling_backward_step_long_0301.py
doc/GPU_RESAMPLING_CUDA_0301_BACKWARD_STEP_LONG.md
```

`run_cuda_resampling_backward_step_validation_0301.sh` is self-contained and does not modify the older `run_demo_src_classic_cuda_backward_step_io_0283.sh` script.

## Default campaign

The default campaign is intentionally moderate:

```text
Nx = 96
Ny = 48
steps = 3000
dt = 8e-4
Uin = 0.45
summaryEvery = 100
dumpStateEvery = 1000
```

The default modes are:

```text
classic
guard0299_nmin10_nt20_nmax34
guard0299_nmin12_nt20_nmax32
guard0299_nmin14_nt20_nmax30
```

The passive survey 0295 is enabled for all modes so that the classic and active runs can be compared using the same support metrics.

## Recommended launch

```bash
OUT=build/src_mpcd_base_cuda_0301 \
CUDA_ARCH_FLAGS="--generate-code=arch=compute_89,code=sm_89 --generate-code=arch=compute_89,code=compute_89" \
bash scripts/build_src_mpcd_cuda_0301.sh

BIN=build/src_mpcd_base_cuda_0301 \
FORCE_REBUILD=0 \
NX=96 NY=48 \
STEPS=3000 \
UIN_GRID="0.45" \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=1000 \
GUARD_GRID="10:20:34 12:20:32 14:20:30" \
bash scripts/run_cuda_resampling_backward_step_long_0301.sh
```

For a more aggressive velocity sweep:

```bash
BIN=build/src_mpcd_base_cuda_0301 \
FORCE_REBUILD=0 \
NX=96 NY=48 \
STEPS=3000 \
UIN_GRID="0.30 0.45 0.60" \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=1000 \
GUARD_GRID="10:20:34 12:20:32 14:20:30" \
bash scripts/run_cuda_resampling_backward_step_long_0301.sh
```

## Outputs

```text
dev_history/artifacts/gpu_cuda_resampling_backward_step_long_0301/
  cuda_resampling_backward_step_long_0301_run_manifest.csv
  cuda_resampling_backward_step_long_0301_per_run.csv
  cuda_resampling_backward_step_long_0301_vs_classic.csv
  cuda_resampling_backward_step_long_0301_timeseries.csv
```

The analyzer records both final summaries and time-resolved support metrics from the passive survey and guard diagnostics.

## Interpretation

For active runs, strict equality with classic is not expected.  The relevant checks are:

```text
exitCode = 0
splitApplied / mergeApplied finite and interpretable
maxAbsCellMassError ~ machine precision
maxAbsCellMomentumError ~ machine precision
maxAbsCellKrelError0298 ~ machine precision
survey poor/empty cells reduced or bounded relative to classic
no runaway kBT, totalMass, Px/Py, or max speed
```

The most useful first comparison is usually:

```text
classic
vs
guard0299_nmin12_nt20_nmax32
vs
guard0299_nmin14_nt20_nmax30
```

If the long backward-step run still shows persistent empty/poor regions behind the step, the next algorithmic step should not be another global correction.  It should be a carefully bounded local extension, such as stronger local splitting, controlled use of inactive slots, or nearest-neighbour poor/rich transfer.
