# 0310 — CUDA inactive-slot scaling audit

## Purpose

Long resampling runs require a large inactive-slot reservoir for hard inlet and
population-guard activation.  A large reservoir is robust, but it can slow the
resident CUDA path if kernels still iterate over total particle capacity
(`fluid + inactive + latent`) rather than active fluid particles.

Patch 0310 adds a **short, bounded audit** to measure this scaling before any
larger refactor.  It does not change the C++/CUDA simulation code.

## Files

- `scripts/build_src_mpcd_cuda_0310.sh`
- `scripts/run_cuda_inactive_slots_scaling_0310.sh`
- `scripts/analyze_cuda_inactive_slots_scaling_0310.py`

## Fast default sweep

The default sweep is intentionally short and excludes `250000` inactive slots:

```bash
BIN=build/src_mpcd_base_cuda_0310 \
FORCE_REBUILD=0 \
bash scripts/run_cuda_inactive_slots_scaling_0310.sh
```

Defaults:

- case: backward step only;
- mode: resampling only;
- grid: `96 x 48`;
- steps: `600`;
- inactive slots: `8000 20000 50000 100000`;
- guard cadence: `GUARD_EVERY=20`;
- dumps suppressed by `DUMP_STATE_EVERY=999999`.

This is a timing audit, not a physical validation run.

## Optional fuller sweeps

Classic + resampling:

```bash
MODES="classic resampling" \
bash scripts/run_cuda_inactive_slots_scaling_0310.sh
```

Add Von Karman, still short:

```bash
RUN_VK=1 \
VK_NX=96 VK_NY=48 VK_STEPS=600 \
bash scripts/run_cuda_inactive_slots_scaling_0310.sh
```

Test a larger pool only when needed:

```bash
INACTIVE_SLOTS_GRID="8000 50000 100000 250000" \
STEP_STEPS=300 \
bash scripts/run_cuda_inactive_slots_scaling_0310.sh
```

## Outputs

The runner writes:

- `dev_history/artifacts/gpu_cuda_inactive_slots_scaling_0310/cuda_inactive_slots_scaling_0310_run_manifest.csv`
- `dev_history/artifacts/gpu_cuda_inactive_slots_scaling_0310/cuda_inactive_slots_scaling_0310_per_run.csv`
- `dev_history/artifacts/gpu_cuda_inactive_slots_scaling_0310/cuda_inactive_slots_scaling_0310_ratios.csv`

Important columns:

- `inactiveSlotsRequested`
- `NpLogged`, `fluidLogged`, `inactiveLogged`
- `elapsedSeconds`, `elapsedPerStep`
- `elapsedRatioVsBase`
- `sumSplitApplied`, `sumMergeApplied`
- `sumFlagDepositSeconds`, `sumFlagDownloadSeconds`

## Interpretation

If `elapsedRatioVsBase` grows roughly with `inactiveSlotsRequested` while
`fluidLogged` stays nearly constant, the dominant path is likely still scanning
total particle capacity.  The next optimization should then target active-index
lists, free-list use, or active-only dumps depending on which diagnostics scale.

If elapsed time is almost flat, the current kernels are already sufficiently
inactive-aware for the tested configuration, and the main remaining cost is more
likely guard frequency or physical case complexity.
