# 0312 — Independent inactive-slot scaling audit

This patch replaces the previous inactive-slot sweep protocol with an audit that is deliberately independent from the visual/demo scripts.

## Motivation

The 0310 audit reused demonstration scripts.  That made the audit fragile because local edits of demo scripts could change the benchmark.  One such issue was a global inactive-slot override in the resampling demo common file, which caused all 0310 runs to use millions of inactive slots regardless of the requested value.

0312 avoids that failure mode:

- it does not call `run_demo_*` scripts;
- it does not source `src_gpu_demo_common_0283.sh`;
- it does not source `src_gpu_resampling_demo_common_0303.sh`;
- it generates its own `.smpcd` initial states;
- it writes its own `.kv` parameter files;
- it sets CUDA environment flags explicitly;
- it calls the binary directly;
- it checks that the logged inactive count matches the requested inactive count.

## Files

```text
scripts/build_src_mpcd_cuda_0312.sh
scripts/generate_src_gpu_audit_state_0312.py
scripts/run_cuda_inactive_slots_independent_audit_0312.sh
scripts/analyze_cuda_inactive_slots_independent_audit_0312.py
```

## Default sweep

The default sweep is intentionally short:

```text
case        : backward step only
mode        : resampling only
Nx x Ny     : 96 x 48
steps       : 400
guardEvery  : 20
inactive    : 8000 20000 50000 100000
dumps       : effectively disabled
```

`250000` inactive slots is intentionally not included by default.  To test it, use a very short run explicitly.

## Build

```bash
OUT=build/src_mpcd_base_cuda_0312 \
CUDA_ARCH_FLAGS="--generate-code=arch=compute_89,code=sm_89 --generate-code=arch=compute_89,code=compute_89" \
bash scripts/build_src_mpcd_cuda_0312.sh
```

## Run

```bash
BIN=build/src_mpcd_base_cuda_0312 \
FORCE_REBUILD=0 \
bash scripts/run_cuda_inactive_slots_independent_audit_0312.sh
```

## Optional checks

Classic plus resampling:

```bash
MODES="classic resampling" \
BIN=build/src_mpcd_base_cuda_0312 \
FORCE_REBUILD=0 \
bash scripts/run_cuda_inactive_slots_independent_audit_0312.sh
```

Very short 250000-slot check:

```bash
INACTIVE_SLOTS_GRID="8000 50000 100000 250000" \
STEP_STEPS=150 \
BIN=build/src_mpcd_base_cuda_0312 \
FORCE_REBUILD=0 \
bash scripts/run_cuda_inactive_slots_independent_audit_0312.sh
```

Von Karman light audit:

```bash
RUN_VK=1 \
VK_STEPS=300 \
VK_NX=96 \
VK_NY=48 \
BIN=build/src_mpcd_base_cuda_0312 \
FORCE_REBUILD=0 \
bash scripts/run_cuda_inactive_slots_independent_audit_0312.sh
```

## Outputs

```text
dev_history/artifacts/gpu_cuda_inactive_slots_independent_0312/
  cuda_inactive_slots_independent_0312_run_manifest.csv
  cuda_inactive_slots_independent_0312_per_run.csv
  cuda_inactive_slots_independent_0312_ratios.csv
```

Important columns:

```text
inactiveSlotsRequested
inactiveLogged
actualMatchesRequested
elapsedSeconds
elapsedRatioVsBase
NpLogged
fluidLogged
sumSplitApplied
sumSplitSkippedNoInactive
```

A run is marked `INVALID` if it completes but the binary logs an inactive count that does not match the requested slot count.  This prevents the previous 0310 failure mode from being silently interpreted as a valid scaling measurement.
