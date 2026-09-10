0493x8w — NEUMANN VIRTUAL CELLS, PHYSICS-FIRST
===============================================

Purpose
-------
Replace the unstable x8q/x8r/x8v kinetic continuation by explicit statistical
virtual cells outside an outlet, while preserving the existing pressure/Q6
Neumann boundary and the existing resident inactive-pool machinery.

This patch is intentionally NOT a performance optimization. It keeps the
legacy host count synchronization and inactive-slot collection so that the
physical boundary mechanism is the only important change.

Expected base
-------------
The main patch x8w_virtual_cells_after_x8v.patch is for the experimental
worktree where the previous patches have already been applied in this order:
  x8q ablation gate -> x8r species baths -> x8v microscopic replica.
It supersedes x8v at runtime; x8v code remains present but is not dispatched
when x8w is enabled.

Physical contract
-----------------
For each outlet face cell and each registered species:

1. Read ONLY the immediately adjacent physical cell at the pre-stream position.
2. Accumulate its species-resolved state:
       N_s, sum(m), sum(m u_x), sum(m u_y), sum(m |u|^2)
3. The exterior ghost-cell state is zero-normal-gradient:
       N_s^g = N_s^boundary,
       U_s^g = U_s^boundary,
       T_s^g = T_s^boundary,
       m_s^g = mean mass in that cell.
4. For each virtual layer, generate N_s statistically independent virtual
   particles with uniform position in the exterior cell and Gaussian velocity
   from (U_s^g,T_s^g).
5. Stream each virtual particle for dt.
6. Discard virtual particles that remain outside.
7. Only particles that cross an actual outlet segment and end inside the
   physical domain are stored as candidates.
8. Only these crossing candidates consume resident inactive slots.

Thus the incoming half-space is produced by geometric streaming of an exterior
cell population, not by an explicit half-Maxwellian flux formula.

Default virtual depth
---------------------
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_CELLS_0493X8W_LAYERS=2

Additional layers copy the SAME adjacent physical-cell state; they do not widen
the interior averaging stencil. Two layers represent incoming trajectories
originating up to 2h outside during one step. Increase only if the flight guard
shows that a relevant part of the velocity distribution can travel farther.
Maximum accepted value in this experimental patch: 4.

Activation
----------
The wrapper:
  scripts/run_x8w_virtual_cells_neumann_air_assisted_atomizer.sh

sets:
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_CELLS_0493X8W=1
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_CELLS_0493X8W_LAYERS=2

and disables the x8r and x8v experimental dispatches. The x8q kinetic ablation
switch is unset so that the pressure/Q6 Neumann contract remains Neumann and
the new kinetic mechanism can dispatch.

x8w requires:
  speciesRegistryEnable=true
  speciesRequireRegisteredTypes=true
  at least one registered species

The air-assisted atomizer runner already satisfies this contract.

Mandatory runtime marker
------------------------
A valid x8w run must print once:

  [0493x8w-neumann] mode=virtual_cells physics=streamed_independent layers=2 sourceCellLayers=1 species=2 residentOutside=0 hostCountSync=legacy pool=legacy

If this marker is absent, do not interpret the run as an x8w test.

Application
-----------
From the x8v experimental worktree:

  git status
  git apply --check /path/x8w_virtual_cells_after_x8v.patch
  git apply /path/x8w_virtual_cells_after_x8v.patch

Then rebuild:

  bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

The current runner geometry is NOT overridden by the wrapper. Therefore your
local 400x400 modification remains effective.

Recommended experiment
----------------------
Start from t=0 with exactly the same SEED and runner parameters used for the
400x400 legacy/species/replica comparisons.

First do a cheap early-failure run, because x8v failed almost immediately:

  STEPS=500 CLEAN_RUN_ROOT=1 \
    bash scripts/run_x8w_virtual_cells_neumann_air_assisted_atomizer.sh

If the boundary remains clean, rerun to at least 2500 steps (or beyond first
liquid/outlet contact):

  STEPS=2500 CLEAN_RUN_ROOT=1 \
    bash scripts/run_x8w_virtual_cells_neumann_air_assisted_atomizer.sh

For a same-tree legacy control:

  STEPS=2500 CLEAN_RUN_ROOT=1 \
    bash scripts/run_x8q_legacy_control_air_assisted_atomizer.sh

Primary physical criteria
-------------------------
1. Before liquid reaches outlet: no right-boundary density layer or wave.
2. At first liquid/outlet contact: no rapid phase invasion or sign reversal of
   mean liquid ux.
3. No monotone explosive growth of liquid particle count at fixed total slots.
4. outletParticlesDeleted and outletParticlesInserted remain finite and of the
   expected kinetic magnitude; their difference is the net particle outflow.
5. Gas rho/ux/uy remain regular away from physical spray structures.
6. Compare total wall time with x8q only AFTER the physical run is acceptable.

Known deliberate limitations
-----------------------------
- GPU->CPU candidate-count synchronization is still present.
- Existing inactive-pool collection/scan is unchanged.
- No persistent exterior particles are stored between timesteps.
- Virtual-cell statistics use the boundary-adjacent cell only.
- Virtual thermal state is Maxwellian from local species moments; for N<2 the
  registered species thermostat target is used as the thermal fallback.
- Corner trajectories that enter through one outlet and end outside another
  physical boundary within the same dt are discarded in this first version.
- No CUDA compilation was possible in the ChatGPT execution environment; nvcc
  compilation on the target worktree is the first mandatory local check.

Files
-----
  x8w_virtual_cells_after_x8v.patch
      Source + two runner wrappers. Recommended patch.

  x8w_virtual_cells_source_after_x8v.patch
      Source-only variant if you prefer to install wrappers manually.
