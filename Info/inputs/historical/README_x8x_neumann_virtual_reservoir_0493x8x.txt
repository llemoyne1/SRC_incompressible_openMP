0493x8x — NEUMANN VIRTUAL RESERVOIR CELLS (COARSE-GRAINED)
============================================================

Status
------
EXPERIMENTAL / PHYSICS-FIRST. This is not a qualified production boundary.
It is intended to test the physically motivated virtual-cell closure after the
x8w failure caused by copying the instantaneous occupancy of the boundary cell.
Performance optimization is deliberately deferred.

Expected base
-------------
Apply this patch on the experimental worktree AFTER x8w has been applied.
The source base is:
  x8q ablation gate -> x8r -> x8v -> x8w

Use:
  x8x_virtual_reservoir_after_x8w.patch

A source-only variant is also provided:
  x8x_virtual_reservoir_source_after_x8w.patch

Physical contract
-----------------
For each outlet tangential cell and registered species s, x8x separates two
quantities that x8w conflated:

1. Phase support at the outlet face
   The immediately adjacent physical cell supplies only the local species
   number fraction:
       alpha_s^Gamma = N_face,s / sum_r N_face,r
   If that single cell is momentarily empty, support falls back to the
   coarse-grained species fraction rather than interpreting one empty MPCD
   sample as vacuum.

2. Macroscopic reservoir state
   Density and species kinetic moments are averaged over K inward normal cells
   at the SAME tangential location. Default:
       K = 8
   The coarse total occupancy is
       Nbar_bulk = sum_r N_bulk,r / K
   and the expected exterior species occupancy is
       lambda_s = alpha_s^Gamma * Nbar_bulk.

3. Independent exterior realization
   Each virtual layer samples
       Nghost,s ~ Poisson(lambda_s)
   independently each step. Virtual positions are uniform in the exterior
   cell. Velocities are independent Gaussian samples from the coarse-grained
   species mean velocity and kBT. For fewer than four coarse particles of a
   species, the registered species thermostat target is used as the thermal
   fallback.

4. Geometric streaming
   Virtual particles are streamed for dt. Those remaining outside are simply
   discarded. Only particles that cross an actual outlet segment and finish
   inside the domain are written to the candidate buffer and later consume one
   inactive resident slot.

No exterior particle is persistent or resident.

Why this differs from x8w
-------------------------
x8w used:
    Nghost,s = instantaneous N_face,s
which couples O(1/sqrt(gamma)) MPCD occupancy noise directly back into the
incoming half-space. In the 500-step test this produced an early gas-density
layer at the outlet.

x8x instead uses:
    phase composition <- face cell
    total density      <- coarse normal average
    U_s, T_s, m_s      <- species coarse moments
    actual particles   <- new independent realization

Thus, in pure gas, alpha_gas=1 even if the face cell fluctuates from N=8 to
N=5, while the external density remains near the coarse-grained bulk value.

Runtime controls
----------------
Master activation:
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_RESERVOIR_0493X8X=1

Exterior depth (default 2, accepted 1..4):
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_RESERVOIR_0493X8X_LAYERS=2

Interior coarse-graining depth (default 8, accepted 1..32):
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_RESERVOIR_0493X8X_COARSE_LAYERS=8

The supplied wrapper sets the defaults and disables the x8r/x8v/x8w
experimental dispatches while leaving the x8q kinetic master gate enabled:
  scripts/run_x8x_virtual_reservoir_neumann_air_assisted_atomizer.sh

Mandatory runtime marker
------------------------
A valid run must print once:

  [0493x8x-neumann] mode=virtual_reservoir_cells layers=2 coarseLayers=8 support=face_count_fraction density=coarse_total_occupancy population=poisson moments=species_coarse independent=1 residentOutside=0 hostCountSync=legacy pool=legacy species=2

If this line is absent, do not interpret the run as x8x.

Application
-----------
From the current x8w experimental worktree:

  git status
  git apply --check /path/x8x_virtual_reservoir_after_x8w.patch
  git apply /path/x8x_virtual_reservoir_after_x8w.patch

Then rebuild:

  bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

The wrapper does not override Lx/Ly/Nx/Ny. Your local 400x400 runner therefore
remains the test geometry.

Recommended first test
----------------------
Do NOT immediately run through liquid/outlet contact. First test the gas-only
outlet regime where x8w failed early:

  STEPS=500 CLEAN_RUN_ROOT=1 \
    bash scripts/run_x8x_virtual_reservoir_neumann_air_assisted_atomizer.sh

Acceptance for this stage:
  - no monotone low/high density layer growing from the right outlet;
  - no upstream-propagating outlet wave;
  - gas rho/ux/uy comparable in character to the legacy x8q run;
  - runtime marker present;
  - no candidate/inactive-pool overflow.

Only if the 500-step test is clean should the run be extended to >=2500 steps
to test first liquid/outlet contact.

Flux consistency check
----------------------
For the 400x400 atomizer gas state:
  h = 1.5625/400 = 0.00390625
  dt = 0.00635
  m_g = 0.1
  kBT_g = 0.004
  sigma_g = sqrt(kBT_g/m_g) = 0.2
  gamma = 8

For zero mean normal velocity the analytic incoming half-flux per boundary cell
is
  gamma * sigma_g * dt/h / sqrt(2*pi) = 1.03763 particles/step.

A 200,000-sample Monte-Carlo of the implemented two-layer Poisson + uniform
position + Gaussian velocity + geometric crossing construction gave 1.03735,
with variance 1.04039. This is consistent with the expected Poisson half-flux;
the two-layer truncation is negligible for these parameters.

Deliberate non-optimizations
----------------------------
- Candidate count is still copied GPU->CPU each timestep.
- Existing inactive-slot collection/scan is unchanged.
- Candidate insertion uses the existing x8w insertion kernel.
- The particle scan for coarse moments is not fused with another kernel.
- No persistent temporal filtering/EMA is used yet.

These are intentional. Optimize only after the physical closure survives both
the early gas test and the multiphase outlet-contact test.

Known modeling limits of this first x8x
---------------------------------------
- Phase support is based on species number fraction in the face-adjacent cell,
  not yet on a reconstructed geometric interface fraction.
- Coarse-graining is normal-only; there is no tangential smoothing.
- Total ghost-cell density assumes the registered phase species share the MPCD
  occupancy field. This matches the present x14 air/liquid setup.
- A momentarily empty face cell uses the coarse species fraction as a fallback.
- For large lambda (>30), Poisson sampling uses a Gaussian approximation.
- Corner trajectories crossing two physical boundaries in one dt retain the
  x8w physics-first restriction.

Files
-----
  x8x_virtual_reservoir_after_x8w.patch
      Source + x8x wrapper. Recommended.

  x8x_virtual_reservoir_source_after_x8w.patch
      Source-only patch.

  VALIDATION.txt
      Mechanical and analytic checks performed before packaging.
