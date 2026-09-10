0493x9e-fix2b — exact patch after the real x9e-fix2 state
================================================================

Why the previous patch failed
-----------------------------
The previous fix2b diff was generated against a synthetic source context.
Its first hunk expected NeumannRecycleWorkspace0493x9e near line 73, while
the reconstructed real x9e-fix2 source has that structure near line 254.

This package was rebuilt by replaying the actual source patch chain:
snapshot -> x8r -> x8v -> x8w -> x8x -> x8y -> x8z -> x9a -> x9b
-> x9c -> x9d-fix1 -> x9e -> compile-quote fix -> x9e-fix2.

Expected SHA-256 of the reconstructed PRE-PATCH x9e-fix2 source:
33c7759a8c7b70624d5270c697f38820fc4b44448a9048b86a6c9a1de4849f5d

What fix2b changes
------------------
It preserves x9e candidate generation and recycle-pool semantics.
Instead of requiring the overly strict dense-reservoir accounting condition,
it validates only slots actually deleted during the boundary pass:

- a fixed 8x256 CUDA checker scans deletedIndices only;
- it verifies deletedCount equals the 0315c deletion counters;
- it verifies every recorded old-prefix deleted slot is Fluid again;
- host fast path still requires expectedActive == oldActive;
- otherwise fallback remains compact_active_prefix_device_0315c;
- VERIFY_PREFIX=1 retains the full O(Nactive) prefix scan as an oracle and
  aborts if the targeted invariant ever disagrees with it.

Application
-----------
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF-x8q-ablation

sha256sum src/cuda_classic_src_io_resident_0263.cu

git apply --check /path/x9e_fix2b_deleted_list_invariant_after_fix2_exact.patch

# only if the check is silent:
git apply /path/x9e_fix2b_deleted_list_invariant_after_fix2_exact.patch

bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

Verification run
----------------
Lx=0.78125 Ly=1.5625 NX=200 NY=400 \
MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_VERIFY_PREFIX_0493X9E_FIX2=1 \
NEUMANN_PROFILE=x9e \
STEPS=250 \
CLEAN_RUN_ROOT=1 \
CASE_LABEL=0493x14av_x9e_fix2b_verify_200x400 \
bash scripts/run_ok_air_assisted_atomizer.sh \
2>&1 | tee /tmp/x9e_fix2b_verify_250.log

Check
-----
grep -E '0493x9e-neumann|0493x9e-fastpath|deleted-list invariant|step=250/250' \
  /tmp/x9e_fix2b_verify_250.log

Expected:
prefixFastPath=deleted_list_invariant
prefixVerifyScan=1
[0493x9e-fastpath] prefixRepair=skipped reason=deleted_list_invariant

Must NOT appear:
deleted-list invariant contradicted by full prefix verification

Validation performed when packaging
-----------------------------------
- replay of the actual patch chain through x9e-fix2: PASS
- git apply --check of this exact fix2b patch: PASS
- applying the patch reproduces the intended transformed source byte-for-byte
- git diff --check: PASS
- balanced (), {}, [] counts: PASS
- lexical scan for raw newlines inside C/C++ string literals: PASS

nvcc/GPU execution is not available in the packaging environment, so the
local CUDA build remains mandatory.
