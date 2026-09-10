0493x9e — Neumann recycle-pool / balanced-prefix fast path
===========================================================

Purpose
-------
Performance-only optimization layered on the qualified x9c physics and the
conservative x9d-fix1 workspace/cache optimization.

Physics is unchanged:
- gas: x9a/x9c virtual pressure-reservoir Neumann continuation;
- liquid: x9b strict outflow (no liquid virtual reservoir);
- phase/interface: x9c zero-normal-gradient support continuation;
- exact x8x/x8y/x8z/x9a candidate generation, RNG and ghost candidate buffer
  are retained.

What x9e changes
----------------
1. During the boundary particle pass, every slot that becomes inactive is
   recorded in a persistent device deleted-slot buffer.
2. After the exact host-visible ghost candidate count is known (same as
   x9d-fix1), the insertion pool is built on GPU as:

       [ deleted slots from this same step | compact inactive tail ]

   No role[] scan over the inactive tail is performed on the x9e path.
3. Ghost and hard-inlet insertions use this pool with their existing kernels.
4. After insertion, one cheap linear role check is launched on the OLD active
   prefix.
5. If the step is exactly particle-balanced AND that old prefix is still full,
   the expensive 0315c/k scan/Thrust prefix repair is skipped completely.
6. Otherwise x9e falls back to the existing exact 0315c compaction path.

Why this is safe for the atomizer
---------------------------------
The atomizer runs previously showed a constant total fluid population. In that
regime, deleted outlet/inlet-reservoir slots can be recycled directly by the
same-step ghost/inlet insertions. If the mapping does not refill the prefix
exactly, the GPU prefix check detects it and the legacy exact repair runs.

Important runtime markers
-------------------------
Expected on stderr:

[0493x9e-neumann] mode=recycle_deleted_slots physics=x9c_unchanged ...

The key performance marker is:

[0493x9e-fastpath] prefixRepair=skipped reason=balanced_recycled_prefix_full

If the second marker never appears, x9e is falling back to 0315c and the gain
will be limited.

Recommended application (current worktree already has x9d-fix1)
----------------------------------------------------------------
  unzip x9e_neumann_recycle_opt_0493x9e.zip -d /tmp/x9e
  cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF-x8q-ablation
  git apply --check /tmp/x9e/x9e_neumann_recycle_opt_after_x9d_fix1.patch
  git apply         /tmp/x9e/x9e_neumann_recycle_opt_after_x9d_fix1.patch
  bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

Short benchmark
---------------
  STEPS=250 CLEAN_RUN_ROOT=1 \
    bash scripts/run_x9e_neumann_recycle_opt_200x400.sh 2>&1 | tee /tmp/x9e_250.log

  grep -E '0493x9e-neumann|0493x9e-fastpath|step=250/250' /tmp/x9e_250.log

Compare solver-internal wall time with the x9d-fix1 result (~44.6 s/250 steps
in the previous A/B/A) rather than external elapsed time while LiveVis hold-on-
exit is enabled.

Fallback / disable
------------------
Unset or set to 0:
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_POOL_0493X9E

x9d-fix1 remains available underneath and x9c physics is unchanged.

Scope
-----
The x9e fast path assumes the post-0315c active-prefix invariant and checks each
selected tail slot is actually inactive. Any inconsistency sets the existing
boundary overflow flag instead of silently overwriting a live slot.
