0493x8v — microscopic Neumann replica (physics-first patch)
===========================================================

Purpose
-------
Test a kinetic Neumann closure that preserves the reason x8q was introduced
(the incoming thermal half-space must not be replaced by vacuum) without the
x8q/x8r bath reconstruction that failed when a liquid/gas interface reached
an outlet.

x8v physics
-----------
For each real FLUID particle that survives the physical boundary step:
  1. Recover its pre-stream position x_pre = x_post - v*dt.
  2. Consider only sources within SOURCE_LAYERS cells of an outlet
     (default SOURCE_LAYERS=1).
  3. Mirror x_pre geometrically across the outlet face, keeping the exact
     source velocity, type and mass.
  4. Stream the virtual mirror for the same dt.
  5. Materialize one incoming ghost only if that virtual copy actually crosses
     the same outlet during dt and ends strictly inside the domain.
  6. Evaluate segmented-outlet membership at the actual crossing point.

Thus no mixed or per-species bath is fitted.  Phase support is represented by
actual labelled particles locally present at the face-scale.  A phase deeper
than the source layer cannot seed the outlet.  The default one-cell source
layer is intentionally stricter than the historical two-cell x8q bath.

What this patch removes in x8v mode
-----------------------------------
  * x8q/x8r bath accumulation;
  * atomics for N, M, Px, Py, Mvv;
  * Maxwellian moment fit;
  * erfc/exp incoming-flux reconstruction;
  * inverse-CDF sampling of the incoming normal velocity;
  * random source-type selection.

What this first patch deliberately keeps
-----------------------------------------
  * the existing inactive-slot/pool machinery;
  * the existing device->host candidate-count synchronization;
  * the existing Q6/pressure Neumann condition;
  * all inlet, Darcy, surface/interface and thermostat physics.

This is intentional: first qualify the physical closure; optimize pool/sync only
if the physics works.  Corner-crossing virtual replicas whose final tangential
position leaves the domain are skipped rather than being given a second
boundary treatment.  This does not affect the present full-right atomizer
outlet away from the corners, but it is a declared limitation of x8v-physics.

Activation and log marker
-------------------------
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_REPLICA_0493X8V=1
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_REPLICA_0493X8V_SOURCE_LAYERS=1

The binary prints once:
  [0493x8v-neumann] mode=microscopic_mirror_replica sourceLayers=1 ...

Patch choice
------------
Use exactly ONE patch:

A) Current experimental worktree with x8q ablation + x8r already applied:
   x8v_replica_after_x8r.patch

B) Worktree with x8q ablation but without x8r:
   x8v_replica_after_x8q_ablation.patch

C) Clean snap_070926_2 source state:
   x8v_replica_from_snapshot.patch
   (includes the x8q diagnostic-ablation switch needed by the A/B wrappers,
    but does NOT include x8r.)

Suggested application on the current x8r worktree
--------------------------------------------------
  git status
  git apply --check /path/x8v_replica_after_x8r.patch
  git apply /path/x8v_replica_after_x8r.patch
  cp /path/scripts/run_*neumann_air_assisted_atomizer.sh scripts/
  chmod +x scripts/run_*neumann_air_assisted_atomizer.sh
  bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

A/B/C experiment from t=0 on the current 400x400 runner
--------------------------------------------------------
Run sequentially, same SEED and same runner defaults:

  CLEAN_RUN_ROOT=1 bash scripts/run_x8q_legacy_neumann_air_assisted_atomizer.sh
  CLEAN_RUN_ROOT=1 bash scripts/run_x8q_off_neumann_air_assisted_atomizer.sh
  CLEAN_RUN_ROOT=1 bash scripts/run_x8v_replica_neumann_air_assisted_atomizer.sh

Do not override NX/NY/Lx/Ly in these wrappers: they intentionally inherit the
current run_ok_air_assisted_atomizer.sh, including the user's 400x400 change.

Primary comparison
------------------
  * onset time when liquid reaches x=Lx;
  * gas rho/ux/uy field near the outlet;
  * liquid N, mean ux and kinetic energy;
  * outletParticlesDeleted / outletParticlesInserted if printed;
  * wall-clock / step versus x8q legacy.

Expected discriminating result
-------------------------------
  x8q legacy : known outlet instability;
  x8q OFF    : stable but absorbing/vacuum kinetic control;
  x8v        : target = stable while retaining a non-zero microscopic incoming
               thermal half-space.

If x8v remains unstable, the next diagnostic should be an explicit face-phase
trace/reconstruction.  Do not add it before this cheaper microscopic-support
test has been evaluated.
