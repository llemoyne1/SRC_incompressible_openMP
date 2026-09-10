0493x9e-fix3 — targeted exact prefix repair
=============================================

Diagnostic basis
----------------
Observed at step 1 on 200x400:
  oldActive       = 640000
  reservoirDeleted= 639
  outletDeleted   = 416
  deleted total   = 1055
  inletInserted   = 576
  outletInserted  = 418
  inserted total  = 994
  netDelta        = -61
  expectedActive  = 639939
  refillFlag      = 8
  prefixHole      = 1

This is legitimate hard-reservoir behavior, not a counter bug:
the 72 hard-reservoir cells are reset to 72*8 = 576 particles.
Therefore a balanced "skip all prefix repair" invariant cannot generally hold.

What fix3 does
--------------
The x9e recycle pool is unchanged:
  [recorded deleted slots | bounded compact inactive tail]

Fix3 replaces the O(Nactive)/O(capacity) 0315c repair on the normal x9e pool path
with a targeted exact repair over the mutation support only.

For each step:
1. use deletedIndices[] to locate old-prefix holes;
2. include possible growth holes in [oldActive, expectedActive);
3. bound all possible donors by the tail portion touched by the recycle pool;
4. pair the LOWEST hole with the HIGHEST active donor, matching 0315c ordering;
5. verify the modified support exactly;
6. set the new active size.

A work cap protects pathological steps. Any count/bound/work inconsistency falls
back to compact_active_prefix_device_0315c unchanged.

Default targeted work cap:
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_TARGETED_REPAIR_MAX_WORK_0493X9E_FIX3=4000000

Qualification oracle
--------------------
The existing:
  MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_VERIFY_PREFIX_0493X9E_FIX2=1

is retained. With it enabled, fix3 performs an additional FULL prefix scan AFTER
the targeted repair and aborts if a hole remains. This scan is qualification-only.

Expected pre-patch source SHA-256
--------------------------------
8b3623ad0dd52de04fc53d6969bc820bdfeffe9575b708445f5846a759a9d3bc

This is the reconstructed state after:
x9e -> fix2 -> fix2b -> first-fallback diagnostic patch.

Apply
-----
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF-x8q-ablation

sha256sum src/cuda_classic_src_io_resident_0263.cu

git apply --check /path/x9e_fix3_targeted_prefix_repair_after_diag.patch

# only if silent:
git apply /path/x9e_fix3_targeted_prefix_repair_after_diag.patch

bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

Check binary markers
--------------------
strings build/src_mpcd_base_cuda_q6_resident_livevis_0486 |   grep -E 'targeted_deleted_list_exact|0493x9e-fix3'

First qualification run
-----------------------
Lx=0.78125 Ly=1.5625 NX=200 NY=400 MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_VERIFY_PREFIX_0493X9E_FIX2=1 NEUMANN_PROFILE=x9e STEPS=250 CLEAN_RUN_ROOT=1 CASE_LABEL=0493x14av_x9e_fix3_verify_200x400 bash scripts/run_ok_air_assisted_atomizer.sh 2>&1 | tee /tmp/x9e_fix3_verify_250.log

Extract:
grep -E '0493x9e-neumann|0493x9e-fastpath|0493x9e-fix3-diag|targeted repair|step=250/250'   /tmp/x9e_fix3_verify_250.log

Expected normal-path marker:
  [0493x9e-fastpath] prefixRepair=targeted_deleted_list_exact ...

Must NOT appear:
  0493x9e-fix3 targeted repair contradicted by full prefix oracle

Fallback status codes
---------------------
0 : targeted kernel was not run / no result
1 : success
2 : invalid bounds
3 : deletedCount > oldActive
4 : deleted index outside old prefix
5 : targeted work cap exceeded
6 : hole/donor count mismatch
7 : donor unexpectedly unavailable during pairing
8 : residual prefix hole after repair
9 : residual active donor beyond expectedActive

Packaging validation
--------------------
- exact patch generated against reconstructed post-diagnostic source
- git apply --check: PASS
- applied source byte-identical to intended fix3 source
- git diff --check: PASS
- (), {}, [] counts balanced
- no raw newline detected inside C/C++ string literals
- nvcc/GPU execution unavailable here; local CUDA build remains mandatory.
