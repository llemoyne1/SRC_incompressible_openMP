# GPU patch 0270 — wall-simple resident boundary-scan skip

## Scope

Patch 0270 is a narrow performance patch for the classic SRC CUDA resident
wall-simple/Poiseuille path.  It does not change Q6, resampling, virial,
thermostat, inlet/outlet, piston, or immersed-solid logic.

The 0269a performance profile showed that the wall-simple resident case was
still slower than the CPU baseline.  One avoidable component was the generic
CPU `apply_boundary_conditions()` pass after the CUDA wall-simple stream kernel.
For the validated static channel subset, the CUDA stream kernel already applies:

- periodic wrapping in `x`;
- bounded-wall reflection in `y`;
- wall hit/failure handling inside the CUDA kernel.

Running the generic CPU boundary pass afterwards is therefore a redundant full
particle scan.  In resident mode it is also architecturally undesirable because
the host `ParticleState` is intentionally stale between summary/final download
points.

## Change

When `MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=1` and the wall-simple CUDA
stream step is actually handled, the boundary phase is treated as already
covered and the CPU boundary pass is skipped.

The historical resident summary behavior is preserved: `BoundaryDiagnostics` is
left at its default zero values, matching the previous resident path in which
the CUDA stream had already put particles back inside the domain before the CPU
boundary pass observed them.

## Fallback

Set:

```bash
MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0270_DISABLE_BOUNDARY_SKIP=1
```

to return to the pre-0270 behavior and run the generic CPU boundary scan.

## Validation

Run:

```bash
bash scripts/run_cuda_classic_src_resident_perf_0270.sh
```

Expected outputs:

```text
dev_history/artifacts/gpu_cuda_classic_src_resident_perf_0270/
  cuda_classic_src_resident_perf_validation_0270.csv
  cuda_classic_src_resident_perf_summary_0270.csv
  cuda_classic_src_resident_perf_phases_0270.csv
```

The key signal is a reduced `boundary_s` for `poiseuille_wall_full_0261_*`, with
all consolidated validation suites remaining `PASS`.

## Architectural constraints preserved

The patch only optimizes the classic-only resident validator path.  It does not
block future reactivation of:

- Q6 CPU projection with explicit synchronization;
- resampling;
- virial correction;
- the future wall/solid/piston/inlet-outlet-aware CUDA thermostat.
