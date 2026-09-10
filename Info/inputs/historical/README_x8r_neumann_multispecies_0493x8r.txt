0493x8r — species-resolved Neumann kinetic continuation
========================================================

PURPOSE
-------
The legacy x8q Neumann kinetic bath aggregates all particle types in one bath
per boundary cell. 0493x8r adds a separate path with layout

    bath[spatial boundary cell][registered species]

so N, sumMass, momentum, kinetic energy, metadata source, particle type and
thermal fallback cannot mix species.

The legacy x8q device functions/kernels are left source-identical. x8r is
automatically selected only when all of the following hold:

  * openBoundaryOutletMode = neumann
  * speciesRegistryEnable = true
  * speciesRequireRegisteredTypes = true
  * more than one species is registered
  * MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_SPECIES_0493X8R_DISABLE is NOT set

The earlier diagnostic ablation gate remains available:

  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_KINETIC_0493X8Q_DISABLE=1

PATCH CHOICE
------------
A) Recommended for the current x8q-ablation worktree:

   git apply --check x8r_multispecies_after_x8q_ablation.patch
   git apply x8r_multispecies_after_x8q_ablation.patch

B) For a fresh tree at the supplied snapshot state (no ablation patch yet):

   git apply --check x8r_multispecies_from_snapshot.patch
   git apply x8r_multispecies_from_snapshot.patch

The cumulative patch B includes both the x8q ablation gate and x8r.
Do not apply both patches to the same tree.

WRAPPERS
--------
Copy the wrappers into scripts/:

   cp scripts/run_x8r_species_neumann_air_assisted_atomizer.sh <repo>/scripts/
   cp scripts/run_x8q_legacy_neumann_air_assisted_atomizer.sh <repo>/scripts/
   cp scripts/run_x8q_off_air_assisted_atomizer.sh <repo>/scripts/

Then rebuild the normal resident CUDA binary:

   bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

QUALIFICATION MATRIX
--------------------
Use the same restart dump for all branches, preferably state_step_4000.smpcd.

1) Corrected x8r species-resolved Neumann:

   RESTART=1 RESTART_STATE=/path/state_step_4000.smpcd \
   RESTART_TAG=from4000 STEPS=1500 CLEAN_RUN_ROOT=1 \
   bash scripts/run_x8r_species_neumann_air_assisted_atomizer.sh

2) Legacy x8q species-blind Neumann:

   RESTART=1 RESTART_STATE=/path/state_step_4000.smpcd \
   RESTART_TAG=from4000 STEPS=1500 CLEAN_RUN_ROOT=1 \
   bash scripts/run_x8q_legacy_neumann_air_assisted_atomizer.sh

3) Negative control, kinetic continuation OFF:

   RESTART=1 RESTART_STATE=/path/state_step_4000.smpcd \
   RESTART_TAG=from4000 STEPS=1500 CLEAN_RUN_ROOT=1 \
   bash scripts/run_x8q_off_air_assisted_atomizer.sh

EXPECTED DIAGNOSTIC RESULT
--------------------------
  x8q legacy  -> reproduces the outlet-triggered multiphase instability
  x8q OFF     -> stable but absorbing kinetic outlet
  x8r         -> stable while retaining Neumann kinetic continuation

IMPLEMENTATION NOTES
--------------------
* x8q legacy kernels are not edited; x8r uses separate CUDA kernels.
* x8r deposits the species baths before the normal boundary kernel acts.
* During x8r, legacy x8q bath accumulation is disabled only for that boundary
  kernel invocation; the Neumann outlet mode itself remains active.
* Each x8r bath entry selects its source particle from the same species only.
* If speciesThermostatEnable=true, the per-species thermostat target is used as
  the fallback kBT. Otherwise the legacy inlet/global fallback is retained.
* The code was structurally checked and git-apply checked against the supplied
  snapshot and the prior x8q-ablation state. CUDA compilation was not possible
  in the artifact-generation environment because nvcc/CUDA headers are absent;
  rebuild locally is therefore an explicit qualification step.
