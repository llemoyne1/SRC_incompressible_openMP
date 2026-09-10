0493x8y — Neumann virtual pressure/reference-density reservoir
==============================================================

Purpose
-------
x8x substantially reduced the outlet rarefaction but still allowed the virtual
reservoir density to follow a slowly developing outlet density deficit because
its total virtual occupancy was coarse-grained from the interior.

x8y changes ONE physical ingredient only:

    x8x: lambda_s = alpha_s(face) * Nbar_bulk
    x8y: lambda_s = alpha_s(face) * Nref

where Nref defaults to the solver inletTargetOccupancy (GAMMA in the current
air-assisted-atomizer runner). Species support still comes from the face cell;
species velocity, temperature and mass still come from the same x8x coarse
moments. Population remains independent Poisson sampling in temporary exterior
virtual cells; only streamed inward crossers consume inactive resident slots.

Base
----
The full patch x8y_pressure_reservoir_after_x8x.patch applies to a working tree
that already contains x8q + x8r + x8v + x8w + x8x, i.e. the current experimental
worktree used for the x8x run.

Apply
-----
  git apply --check /path/x8y_pressure_reservoir_after_x8x.patch
  git apply /path/x8y_pressure_reservoir_after_x8x.patch
  bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

Required log marker
-------------------
  [0493x8y-neumann] mode=virtual_pressure_reservoir_cells ...
  density=reference_target_occupancy targetN=8 ...

For the present runner, targetN should be 8 because inletTargetOccupancy=GAMMA.
The solver aborts if x8y is enabled with targetN <= 0.

Optional override
-----------------
  X8Y_TARGET_OCCUPANCY=8 bash scripts/run_x8y_pressure_reservoir_neumann_air_assisted_atomizer.sh

If X8Y_TARGET_OCCUPANCY is unset, inletTargetOccupancy is used.

Smoke run
---------
  STEPS=500 CLEAN_RUN_ROOT=1 \
    bash scripts/run_x8y_pressure_reservoir_neumann_air_assisted_atomizer.sh

Long liquid/outlet-contact run
------------------------------
The included long wrapper defaults to 3000 steps and dumps every 500 steps:

  CLEAN_RUN_ROOT=1 \
    bash scripts/run_x8y_pressure_reservoir_long_air_assisted_atomizer.sh

On the current 400x400 runner, liquid/outlet contact occurred around 1950-2000
steps in the previous A/B experiments, so 3000 steps gives useful post-contact
margin. Keep the same SEED and runner geometry for direct comparison.

Interpretation priorities
-------------------------
1. First 500 steps: outlet gas density deficit and normal-velocity bias.
2. Around 1800-2200: onset when liquid reaches x=Lx.
3. After contact: liquid population, mean liquid ux, gas density-wave emission,
   and any sustained upstream propagation from the outlet.
4. Track inserted/deleted particle balance when diagnostics are available.

This is still a physics-first experimental branch. Host candidate-count sync,
inactive-pool collection and insertion are intentionally left unoptimized.
