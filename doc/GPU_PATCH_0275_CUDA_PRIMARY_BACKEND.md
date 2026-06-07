# GPU patch 0275 — CUDA primary launcher, OpenMP opt-out

## Purpose

Patch 0275 changes the user-facing execution policy for the `SRC_GPU` branch:
CUDA is now the primary launch path for validated classic SRC resident cases,
while the full OpenMP/CPU route remains available as an explicit opt-out.

This patch deliberately avoids a hard-coded grid-size threshold.  The recent
performance runs showed that the crossover depends on grid size, particle count,
case family, diagnostics, and GPU/CPU hardware.  The policy is therefore simple:
for this CUDA/OpenMP branch, use CUDA by default where the resident path is
validated; use OpenMP only when requested.

## New launchers

Build:

```bash
bash scripts/build_src_mpcd_cuda_0275.sh
```

Run with CUDA-primary policy:

```bash
scripts/run_src_mpcd_cuda_primary_0275.sh params.kv
```

Run explicitly through the OpenMP/CPU path:

```bash
scripts/run_src_mpcd_openmp_0275.sh params.kv
```

or equivalently:

```bash
MPCD_BACKEND=openmp scripts/run_src_mpcd_cuda_primary_0275.sh params.kv
```

## CUDA-primary scope

When the parameter file is classic-only, i.e. it does not request Q6 projection,
resampling, closed-capacity/virial continuation, or the thermostat, the launcher
activates the validated resident CUDA classic-SRC stack:

- periodic resident 0260;
- wall-simple resident 0261;
- solid/rectangle resident 0262;
- inlet/outlet full-face resident 0263d plus 0268 pool optimization;
- inlet/outlet segmented resident 0264 plus 0269a pool optimization;
- 0270 wall boundary skip;
- 0271 async/fast diagnostics;
- 0272b collision safe fast path;
- 0273 collision-wrapper overhead reductions;
- 0274b fused stream/deposit for periodic and wall paths.

The wrapper appends a temporary `srcClassicCudaModeEnable = true` override only
in this classic-only case.  This makes CUDA the primary path without requiring
all existing classic input files to be edited.

## Q6, resampling, virial/capacity, and thermostat preservation

If the parameter file requests any of:

```text
projectionEnable = true
resamplingEnable = true
closedCapacityResponseEnable = true
thermostatEnable = true
```

the launcher does **not** force `srcClassicCudaModeEnable=true` and does **not**
activate the classic resident shortcuts.  The existing CPU/OpenMP continuation
stages remain authoritative.  This preserves the future ability to re-enable:

- Q6 CPU projection after CUDA SRC phases;
- resampling after an explicit GPU/host synchronization bridge;
- virial/capacity stages;
- the future wall/solid/piston/inlet-outlet aware CUDA thermostat.

In other words, 0275 makes CUDA primary for the validated classic resident subset
but does not collapse the architecture into an irreversible classic-only mode.

## Environment controls

- `MPCD_BACKEND=cuda` or `MPCD_RUNTIME_BACKEND=cuda`: CUDA-primary path
  (default).
- `MPCD_BACKEND=openmp`: explicit OpenMP/CPU path.
- `MPCD_CUDA_PRIMARY_VERBOSE=1`: print the selected policy.
- `MPCD_CUDA_PRIMARY_KEEP_TEMP=1`: keep the generated temporary params file.

Individual CUDA feature flags can still be overridden before invoking the
launcher.  For example, to disable the 0274 fused stream/deposit mode while
staying on the CUDA-primary path:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_FUSED_STREAM_DEPOSIT_0274=1 \
  scripts/run_src_mpcd_cuda_primary_0275.sh params.kv
```

## OpenMP role

The OpenMP path is not removed.  It is now an explicit backend option for:

- small calibration runs where CPU speed is preferred;
- debugging;
- checking CUDA/OpenMP equivalence;
- simulations using continuation stages not yet resident-safe on GPU.

