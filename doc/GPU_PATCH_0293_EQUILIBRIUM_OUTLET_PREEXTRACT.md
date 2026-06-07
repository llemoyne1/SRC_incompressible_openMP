# GPU patch 0293 — pre-insertion outlet extraction for equilibrium/forced outlet modes

This patch fixes the hard-inlet reservoir exhaustion observed in the CUDA full-face
Von Karman demo when `openBoundaryOutletMode = equilibrium_flux` is active.

## Issue

In patch 0291, outlet extraction was applied after the hard inlet reservoir refill.
For long compressible runs, this is too late: the inlet reservoir may need inactive
slots before the equilibrium outlet extraction has had a chance to free them.
The run can therefore stop with a message such as:

```text
Reservoir exhausted at step ... in full-face hard inlet reservoir
```

even though `equilibrium_flux` was requested.

## Fix

The resident CUDA inlet/outlet path now applies outlet extraction immediately after
particle boundary deletion and before rebuilding the inactive-slot pool used by the
hard inlet reservoir refill.

The order is now:

```text
streaming / boundary deletion
forced or equilibrium outlet extraction
inactive pool compaction
hard inlet reservoir refill
SRC collision / thermostat
```

For `equilibrium_flux`, the extraction target is predicted from the hard inlet
reservoir target for the current step, corrected by particles already deleted by
reservoir cleanup, backflow and natural outlet crossing.

For `forced_flux`, the user-specified extraction budget is also applied before
inlet refill, so it can free inactive slots before the reservoir consumes the pool.

## Scope

- Applies to CUDA full-face inlet/outlet 0263.
- Applies to CUDA segmented inlet/outlet 0264.
- Does not change Q6, resampling or virial/capacity paths.
- Does not add case-specific diagnostics.

## Updated demo

`run_demo_src_classic_cuda_von_karman_cylinder_0285.sh` now defaults to
`build/src_mpcd_base_cuda_0293` and keeps `OUTLET_MODE=equilibrium_flux` as the
Von Karman default. It also exposes the outlet mode and forced outlet parameters
through environment variables for quick tests.
