0493x9e-fix2 — accounting-invariant prefix fast path
=====================================================

Goal
----
Keep the x9e physics and recycle pool exactly unchanged, but remove the
O(oldActive) role[] verification scan from the normal fast path.

Physics is unchanged:
  - x9c outlet phase continuation unchanged;
  - x9b strict liquid mass outflow unchanged;
  - x9a/x8z/x8y gas reservoir unchanged;
  - candidate generation/count remains host-exact;
  - recycle pool remains [deleted slots first | compact inactive tail];
  - ghost and hard-reservoir insertion kernels are unchanged;
  - exact 0315c fallback remains unchanged.

What changes
------------
Old x9e, on every recycle step:
  1. memset prefixHoleFlag;
  2. launch io_check_old_active_prefix_full_kernel_0493x9e over oldActive;
  3. synchronize with the rest of the boundary work;
  4. copy prefixHoleFlag D->H;
  5. skip 0315c only if balanced and the scan found no hole.

x9e-fix2 default path:
  - no prefix flag allocation/memset;
  - no prefix role scan;
  - no prefix flag D->H copy;
  - skip 0315c only when the existing accounting proves the old prefix is full.

Accounting proof used by the fast path
--------------------------------------
The fast path is accepted only when ALL conditions hold:

  A. x9e recycle pool is active.
  B. The hard-reservoir plan is dense:
       predicted reservoir particles == reservoirCells * inletTargetOccupancy.
     This rejects partial-cell / sparse pool-index geometries.
  C. outletParticlesInserted == exact Neumann ghostCount.
  D. inletParticlesInserted == dense reservoir pool requirement.
  E. total inserted == total deleted.
  F. expectedActive == oldActive.

Every deletion included in the deletion counters calls
record_recycled_deleted_slot_0493x9e at the same mutation site. Recycle-buffer
overflow is already fatal (overflowFlag=31). Since the recycle pool places all
deleted slots first and, under B/C/D, the insertion kernels consume a contiguous
prefix of pool ordinals, E implies that every deleted old-prefix slot has been
reactivated. Therefore the old active prefix is full without reading role[].

If any condition fails, x9e-fix2 uses the unchanged exact 0315c fallback.

Optional qualification verifier
--------------------------------
Set:
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_VERIFY_PREFIX_0493X9E_FIX2=1

to restore the old full role[] prefix scan. If the accounting invariant says
that the prefix is full but the scan finds a hole, x9e-fix2 throws a hard error.
This is intended for qualification/debug, not production timing.

Runtime markers
---------------
Normal production path:
  [0493x9e-neumann] ... prefixFastPath=balanced_accounting_invariant ... prefixVerifyScan=0 ...
  [0493x9e-fastpath] prefixRepair=skipped reason=balanced_accounting_invariant

Verifier path:
  [0493x9e-neumann] ... prefixVerifyScan=1 ...

Patch choice
------------
CURRENT worktree (x9e + compile-quote fix already applied):
  x9e_fix2_accounting_after_x9e.patch

Future rebuild from x9d-fix1 without x9e applied:
  x9e_fix2_accounting_after_x9d_fix1.patch
  (combined source patch: x9e recycle + compile quote correction + fix2)

Recommended application now
---------------------------
From:
  /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF-x8q-ablation

  git apply --check /path/x9e_fix2_accounting_after_x9e.patch
  git apply /path/x9e_fix2_accounting_after_x9e.patch
  bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

The unified base atomizer runner needs no additional patch. NEUMANN_PROFILE=x9e
continues to select x9e; after this source rebuild it automatically uses fix2.

Recommended first qualification
-------------------------------
1) 250-step verifier run (restores old scan and checks the proof):

  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_VERIFY_PREFIX_0493X9E_FIX2=1 \
  NEUMANN_PROFILE=x9e STEPS=250 CLEAN_RUN_ROOT=1 \
  CASE_LABEL=0493x14av_x9e_fix2_verify_200x400 \
  bash scripts/run_ok_air_assisted_atomizer.sh \
  2>&1 | tee /tmp/x9e_fix2_verify_250.log

2) Check:

  grep -E '0493x9e-neumann|0493x9e-fastpath|step=250/250' \
    /tmp/x9e_fix2_verify_250.log

There must be no "accounting invariant contradicted" error.

3) Production path, same case but verifier OFF:

  unset MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_VERIFY_PREFIX_0493X9E_FIX2
  NEUMANN_PROFILE=x9e STEPS=250 CLEAN_RUN_ROOT=1 \
  CASE_LABEL=0493x14av_x9e_fix2_prod_200x400 \
  bash scripts/run_ok_air_assisted_atomizer.sh \
  2>&1 | tee /tmp/x9e_fix2_prod_250.log

Compare the solver's internal wall= value, not shell elapsed time when LiveVis
hold-on-exit is active.

Expected performance
--------------------
This optimization removes one simple linear byte-role scan plus one scalar
memset/copy per step. It is structurally cleaner, but the scan is much cheaper
than 0315c itself, so the expected gain may be small. The verifier-OFF/ON A/B
above is the correct way to decide whether the change is worth retaining.
