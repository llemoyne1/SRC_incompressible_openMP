# GPU resampling CUDA 0300 — active validation and calibration

## Purpose

Patch 0300 does not add a new physical operator to the C++ core.  It adds a
compact validation/calibration harness for the CUDA post-SRC support-control
chain introduced in 0295--0299:

```text
SRC classic CUDA
-> optional 0296 mass reconditioning
-> optional 0297 local population guard
-> optional 0298 relative-energy restoration
-> 0299 boundary-aware candidate filtering
```

The purpose is to stop validating only non-perturbation.  Once the population
guard is active, strict equality against a guard-off run is no longer the right
criterion: the guard is expected to change the discrete particle
representation.  The relevant question becomes whether the representation is
improved without violating mass, momentum and relative-energy budgets.

## Isolation of Von Karman validation

The user-facing demonstration script

```text
scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh
```

may be edited locally for long exploratory runs.  The 0300 validation harness
therefore does **not** depend on that file.  It adds a dedicated validation case:

```text
scripts/run_cuda_resampling_von_karman_validation_0300.sh
```

This script is derived from the validated 0285 configuration, but has short-run
validation defaults and `THERMOSTAT_ENABLE=0` by default.  This keeps it usable
as a strict reproducibility witness.  Thermostatted Von Karman remains an
optional stress test, not the default strict validator, because the current
boundary-aware CUDA thermostat is not bit-reproducible OFF/OFF on the VK case.

## Default validation suite

The default active sweep uses the four reproducible cases retained at 0295:

```text
TG periodic
Poiseuille wall
backward step / rectangle
U-box segmented inlet/outlet
```

Von Karman is optional via `RUN_VK=1` and uses the new 0300-specific script.

## Modes

For each case, the sweep runs:

```text
classic
mass0296
guard0299_nmin8_nt20_nmax36
guard0299_nmin10_nt20_nmax34
guard0299_nmin12_nt20_nmax32
```

The guard modes activate the local population guard and the 0298 restoration.
By default the guard modes do not also activate mass reconditioning; set
`GUARD_WITH_MASS_RECONDITION=1` to test the combined path.

## Outputs

The sweep writes:

```text
dev_history/artifacts/gpu_cuda_resampling_active_sweep_0300/cuda_resampling_active_sweep_0300_run_manifest.csv
dev_history/artifacts/gpu_cuda_resampling_active_sweep_0300/cuda_resampling_active_sweep_0300_per_run.csv
dev_history/artifacts/gpu_cuda_resampling_active_sweep_0300/cuda_resampling_active_sweep_0300_vs_classic.csv
```

The per-run table collects final runtime summaries and CUDA resampling CSVs.
The `vs_classic` table reports compact deltas relative to the classic run of the
same case.

## Recommended commands

Build:

```bash
OUT=build/src_mpcd_base_cuda_0300 \
CUDA_ARCH_FLAGS="--generate-code=arch=compute_89,code=sm_89 --generate-code=arch=compute_89,code=compute_89" \
bash scripts/build_src_mpcd_cuda_0300.sh
```

Default four-case sweep:

```bash
BIN=build/src_mpcd_base_cuda_0300 \
FORCE_REBUILD=0 \
NX=64 \
NY=64 \
STEPS=80 \
GUARD_GRID="8:20:36 10:20:34 12:20:32" \
bash scripts/run_cuda_resampling_active_sweep_0300.sh
```

Optional isolated Von Karman sweep without using the editable 0285 demo:

```bash
BIN=build/src_mpcd_base_cuda_0300 \
FORCE_REBUILD=0 \
RUN_TG=0 \
RUN_POISEUILLE=0 \
RUN_STEP=0 \
RUN_SEGMENTED=0 \
RUN_VK=1 \
NX=64 \
NY=64 \
STEPS=80 \
VK_THERMOSTAT_ENABLE=0 \
bash scripts/run_cuda_resampling_active_sweep_0300.sh
```

Optional thermostatted VK stress test:

```bash
BIN=build/src_mpcd_base_cuda_0300 \
FORCE_REBUILD=0 \
RUN_TG=0 \
RUN_POISEUILLE=0 \
RUN_STEP=0 \
RUN_SEGMENTED=0 \
RUN_VK=1 \
NX=64 \
NY=64 \
STEPS=80 \
VK_THERMOSTAT_ENABLE=1 \
bash scripts/run_cuda_resampling_active_sweep_0300.sh
```

The thermostatted VK run should be interpreted as a physical stress test, not a
bitwise non-mutation test.

## Interpretation

A useful guard configuration should show:

```text
nonzero splitApplied and/or mergeApplied when the support actually needs it;
small maxAbsCellMassError;
small maxAbsCellMomentumError;
controlled maxAbsCellKrelError0298;
no artificial inlet/outlet compensation by the resampling layer;
stable totalMass, Px, Py and kBT trends relative to the case physics.
```

If the guard is active but `splitApplied=mergeApplied=0`, the thresholds are too
loose for that case or the initial support is already adequate.  If mass/momentum
errors are non-negligible, the next patch must address conservation before any
more aggressive resampling is attempted.  If many candidate cells are excluded by
`excludedOpenBoundaryCells0299`, this confirms that the 0299 boundary filter is
separating reservoir logic from internal support control.

## Next decisions after 0300

Depending on the 0300 sweep:

```text
If the local guard is sufficient:
    promote a conservative parameter set for default active experiments.

If poor cells persist but budgets are clean:
    add 0301 local activation improvements or short-range neighbor transfer.

If energy errors dominate:
    refine 0298 restoration before adding more mutation.

If open-boundary exclusions dominate:
    design a specific reservoir-aware support policy instead of bypassing 0299.
```
