0493x9a -- Neumann virtual pressure reservoir: zero full mean drift on backflow
===============================================================================

Purpose
-------
x8z prevented a virtual pressure reservoir from carrying a MACROSCOPIC normal
mean velocity into the physical domain, but deliberately preserved its
coarse-grained tangential mean. The 200x400 atomizer qualification showed that
post-contact liquid can then spread along the outlet while the normal component
is clamped.

x9a changes only that backflow branch.

Physics
-------
For each outlet face, compute whether the coarse-grained interior mean has a
normal component directed into the physical domain.

If there is NO macroscopic backflow:
    u_reservoir = u_interior

If macroscopic backflow is detected and x9a is enabled:
    u_reservoir = (0, 0)

The thermal variance is NOT changed. Therefore microscopic Maxwellian inward
crossings remain present; only the MACROSCOPIC drift vector of the exterior
reservoir is removed while the backflow guard is active.

The x8y/x8z machinery is otherwise unchanged:
  - phase support from the face cell;
  - pressure/reference target occupancy;
  - species-separated coarse kinetic moments;
  - Poisson virtual population;
  - two virtual layers by default;
  - geometric streaming;
  - only crossing candidates consume inactive slots;
  - legacy host-count synchronization/pool path retained.

Environment gate
----------------
MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_ZERO_DRIFT_ON_BACKFLOW_0493X9A=1

The gate is effective only when x8y pressure reservoir and x8z no-backflow are
enabled. Turning x9a off recovers x8z behavior exactly.

Expected log marker
-------------------
[0493x9a-neumann] mode=virtual_pressure_reservoir_zero_drift_on_backflow ...
    backflowGuard=zero_full_mean_drift thermalInflow=preserved ...

Apply
-----
From a worktree where x8z is already applied:

  git apply --check /path/to/x9a_zero_tangential_drift_after_x8z.patch
  git apply         /path/to/x9a_zero_tangential_drift_after_x8z.patch

Then rebuild with the normal CUDA build script.

Recommended short-domain qualification
---------------------------------------
  CLEAN_RUN_ROOT=1 \
  bash scripts/run_x9a_pressure_reservoir_zero_drift_200x400.sh

Defaults preserve h from the 400x400 case:
  NX=200, NY=400, Lx=0.78125, Ly=1.5625
  STEPS=1800, DUMP_STATE_EVERY=250, RECORD_EVERY=50

The shortened domain is for fast boundary-condition development. A final
non-regression run on the longer domain remains required after qualification.
