0493x9e-fix2b — first-fallback diagnostic patch
================================================

Purpose
-------
Diagnostic only. It does not change the x9e/fix2b fast-path decision,
recycle semantics, candidate generation, inlet/outlet physics, or 0315c fallback.

It adds:
- bit-coded reasons in deletedRefillHoleFlag:
    1 = recorded deletion count != boundary deletion counters
    2 = recorded deletion count > oldActive
    4 = recorded deleted index outside old active prefix
    8 = recorded deleted slot is still non-fluid after insertion
- one 4-byte D->H copy of deletedCount for reporting;
- a single [0493x9e-fix2b-diag] line on the first fallback.

Expected pre-patch source SHA-256
--------------------------------
03f14b73617e24cb7aa4503e199b372523e764df44631733a81cd46243f5ca54

Apply
-----
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF-x8q-ablation

sha256sum src/cuda_classic_src_io_resident_0263.cu

git apply --check /path/x9e_fix2b_first_fallback_diag_after_fix2b.patch
git apply /path/x9e_fix2b_first_fallback_diag_after_fix2b.patch

bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

Short diagnostic run
--------------------
Lx=0.78125 Ly=1.5625 NX=200 NY=400 \
MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_VERIFY_PREFIX_0493X9E_FIX2=1 \
NEUMANN_PROFILE=x9e \
STEPS=20 \
CLEAN_RUN_ROOT=1 \
CASE_LABEL=0493x14av_x9e_fix2b_diag_200x400 \
bash scripts/run_ok_air_assisted_atomizer.sh \
2>&1 | tee /tmp/x9e_fix2b_diag.log

Extract
-------
grep -E '0493x9e-neumann|0493x9e-fastpath|0493x9e-fix2b-diag|step=' \
  /tmp/x9e_fix2b_diag.log

Interpret refillFlag bits
-------------------------
0  : targeted deleted-list condition itself passed
1  : deletion count mismatch
2  : recorded deletion count exceeds oldActive
4  : recorded deleted index outside old prefix
8  : at least one recorded deleted slot remains non-fluid
combinations are sums, e.g. 9 = 1 + 8.

The diagnostic line also reports:
oldActive, deleted0315c, recordedDeleted, inletInserted, outletInserted,
expectedActive, netDelta, prefixHole, reservoirCells, reservoirTarget,
reservoirDeleted, inletBackflowDeleted, outletDeleted, fluidCounter.

Packaging validation
--------------------
- git apply --check against reconstructed exact fix2b state: PASS
- git diff --check: PASS
- applied result matches intended transformed source byte-for-byte: PASS
- no nvcc available in packaging environment; local CUDA build remains mandatory.
