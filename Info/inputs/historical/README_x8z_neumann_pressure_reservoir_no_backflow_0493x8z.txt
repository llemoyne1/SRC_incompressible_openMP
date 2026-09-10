0493x8z -- Neumann virtual pressure reservoir with zero macroscopic backflow
=============================================================================

Purpose
-------
This patch is a minimal physics correction on top of 0493x8y.
The long x8y atomizer run showed that once the liquid occupied the outlet,
the coarse liquid mean normal velocity became negative. x8y copied that
negative mean into the exterior Maxwellian, making the virtual reservoir a
macroscopic liquid injector. The observed liquid growth rate was consistent
with the resulting incoming half-space flux.

Physics change
--------------
Keep ALL x8y mechanisms unchanged:
  * face-local phase support alpha_s^Gamma,
  * reference/pressure occupancy N_ref,
  * independent Poisson virtual populations,
  * species-resolved coarse velocity/temperature/mass,
  * two virtual exterior layers by default,
  * explicit streaming of virtual particles,
  * inactive-pool materialization only after an inward crossing.

Change only the mean NORMAL velocity used to center the exterior Maxwellian:

    u_n,ghost = max(u_n,interior, 0)    in outward-normal coordinates.

Implemented generically per face:
  * left   (outward -x): ux_ghost = min(ux_interior, 0)
  * right  (outward +x): ux_ghost = max(ux_interior, 0)
  * bottom (outward -y): uy_ghost = min(uy_interior, 0)
  * top    (outward +y): uy_ghost = max(uy_interior, 0)

The tangential mean is unchanged. The thermal variance is also unchanged and
is computed from the original coarse interior moments. Therefore microscopic
thermal inward crossings remain allowed; only a MACROSCOPIC inward reservoir
mean is forbidden.

Enable
------
The supplied wrapper enables both x8y and x8z:

  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_PRESSURE_RESERVOIR_0493X8Y=1
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_NO_BACKFLOW_0493X8Z=1

Expected startup marker
-----------------------

  [0493x8z-neumann] mode=virtual_pressure_reservoir_no_backflow ...
      normalMean=outward_clamp thermalInflow=preserved ...

Application
-----------
Apply to a worktree where x8y is already applied:

  git apply --check x8z_no_backflow_after_x8y.patch
  git apply         x8z_no_backflow_after_x8y.patch

Then rebuild with the normal CUDA build script.

200x400 accelerated qualification runner
-----------------------------------------

  scripts/run_x8z_pressure_reservoir_no_backflow_200x400.sh

sets by default:

  NX=200
  NY=400
  Lx=0.78125
  Ly=1.5625
  STEPS=1800
  DUMP_STATE_EVERY=250
  RECORD_EVERY=50

Hence the cell size is unchanged:

  h = 0.78125/200 = 1.5625/400 = 0.00390625.

The shortened domain is suitable for accelerated boundary-condition
qualification because the local Neumann discretization, h, dt, gamma and
species physics are unchanged. It does alter the global streamwise geometry,
so a final non-regression run on the longer domain remains required after the
boundary condition is qualified.
