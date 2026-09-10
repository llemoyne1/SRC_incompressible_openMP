0493x9c-outlet — Neumann liquid interface-support continuation
==============================================================

Purpose
-------
This patch is an experimental continuation layered strictly on the x9b
configuration:

  GAS    : keep the existing x9a/x9b virtual pressure-reservoir closure.
  LIQUID : keep strict physical outflow; no incoming virtual liquid particles.
  PHASE  : preserve liquid interface support at Neumann outlet cells without
           synthesizing particle mass, momentum or energy.

The issue targeted here is the x9b "chopper" artefact: physical liquid particles
that stream beyond the computational outlet are correctly made inactive, but
the resulting loss of phase support in the last cell can be interpreted by the
surface/kinetic interface machinery as a new liquid/gas end-cap.  Capillary and
kinetic-interface operators can then detach fragments that would have remained
attached in an untruncated domain.

Physics contract
----------------
The particle boundary is unchanged from x9b:

    physical liquid crossing outward -> inactive
    virtual incoming liquid reservoir -> OFF

Only phase-A alpha support is modified on cells that belong to a segmented
Neumann pressure outlet.  The one-cell continuation is

    alpha_boundary_ext = max(alpha_boundary, alpha_one_cell_inward)

This is a support-preserving one-layer ghost proxy.  max() is deliberate: the
closure may restore support lost by truncation but can never weaken a genuinely
fuller boundary cell.

At corners shared by two outlet faces, the source is moved one cell inward along
both active outlet normals.  This gives one deterministic interior source and
avoids cross-face write/read ordering.

The continuation is applied to BOTH geometry paths used by the qualified
surface chain:

  1. x6c physical phase alpha, before x6f / surface-tension consumers;
  2. x10 CIC kinetic-interface alpha, after its filter.

Important non-effects
---------------------
The patch does NOT modify:

  * particle x/y/vx/vy/mass/type/role;
  * species-cell mass, count, momentum or occupancy diagnostics;
  * x14v liquidMassCIC (it is computed from real raw CIC before alpha support
    continuation);
  * gas pressure EOS counts;
  * x9b strict-liquid-outflow deletion rule;
  * gas virtual pressure reservoir.

Thus the patch is intended to change interface topology/support only, not mass
or momentum balances.

Runtime gate
------------

  MPCD_Q6_PHASE_OUTLET_GHOST_CONTINUATION_0493X9C_OUTLET=1

The gate requires x9b strict liquid outflow:

  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_LIQUID_STRICT_OUTFLOW_0493X9B=1

and x6c resident geometry.  It acts only on segmented Neumann outlet cells.

Expected log marker
-------------------

  [0493x9c-outlet] mode=phase_support_continuation mass=unchanged ...

Application
-----------
Apply on the worktree that already contains x9b:

  git apply --check x9c_outlet_phase_continuation_after_x9b.patch
  git apply x9c_outlet_phase_continuation_after_x9b.patch

Then rebuild with the normal CUDA build script.

Fast development run
--------------------

  CLEAN_RUN_ROOT=1 bash scripts/run_x9c_outlet_phase_continuation_200x400.sh

Defaults:
  NX=200 NY=400 Lx=0.78125 Ly=1.5625
  STEPS=1800 DUMP_STATE_EVERY=250 RECORD_EVERY=50

If the outlet no longer cuts attached liquid into artificial fragments, confirm
on the larger domain with:

  CLEAN_RUN_ROOT=1 bash scripts/run_x9c_outlet_phase_continuation_400x400.sh

Defaults:
  NX=400 NY=400 Lx=1.5625 Ly=1.5625
  STEPS=3000 DUMP_STATE_EVERY=500 RECORD_EVERY=100

Qualification question
----------------------
The patch is successful only if it preserves all x9b gains (stable gas, no
liquid reservoir mass creation) while reducing boundary-triggered liquid
fragment detachment.  A slight local geometric effect in the last cell is
expected; upstream topology or discharge must not be materially changed.

Naming note
-----------
The historical solver already contains x9c curvature-diagnostic code.  New
symbols and the environment gate are therefore explicitly suffixed
"0493x9c_outlet" / "0493X9C_OUTLET" to avoid semantic collision.
