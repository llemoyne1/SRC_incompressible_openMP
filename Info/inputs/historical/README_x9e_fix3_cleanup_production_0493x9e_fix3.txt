0493x9e-fix3 — production cleanup after long validation
========================================================

Validated pre-cleanup state
---------------------------
Expected SHA-256 before applying this patch:
53ca772801f7ecbba2591b0373a576124e07b82108a0f109566a76e9ef319847

This corresponds to the validated x9e/fix3 source after:
- x9e recycle pool,
- fix2/fix2b development,
- first-fallback instrumentation,
- x9e-fix3 targeted exact prefix repair.

Cleanup scope
-------------
Removed as qualification-only / chantier-specific:
- MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_VERIFY_PREFIX_0493X9E_FIX2 handling;
- full role[0:expectedActive] prefix-oracle kernel;
- prefixHoleFlag workspace/allocation/memset/copy;
- detailed holes/donors/swaps/work result structure and prints;
- detailed x9e-fix3 first-fallback diagnostic line;
- separate per-step D->H copy of deletedCount used only to qualify the invariant.

Production path retained
------------------------
- x9e deleted-slot-first recycle pool unchanged;
- exact host boundary counters unchanged;
- device deletedCount is checked directly by the targeted repair kernel against
  the expected deletion count derived from the already-copied boundary counters;
- targeted lowest-hole/highest-donor repair algorithm unchanged;
- exact verification over the mutation support retained (statuses 8/9);
- max-work guard retained; environment lookup is now cached on first use;
- exact compact_active_prefix_device_0315c fallback retained;
- one one-time fast-path marker retained;
- one one-time fallback warning with compact status code retained.

Normal-path runtime cleanup
---------------------------
- removes one cudaMemcpy D->H scalar transaction for deletedCount per boundary step;
- reduces targeted-repair result D->H payload to one int status;
- removes repeated VERIFY_PREFIX environment checks;
- removes all full-prefix qualification-oracle machinery from the binary.

Expected SHA-256 after applying this patch:
c3eedb29ba0f98ad8d5701587cb87584abec5592e025d25dc53703d81b431b40

Apply
-----
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF-x8q-ablation

sha256sum src/cuda_classic_src_io_resident_0263.cu

git apply --check /path/x9e_fix3_cleanup_production_after_validated_fix3.patch

# only if --check is silent:
git apply /path/x9e_fix3_cleanup_production_after_validated_fix3.patch

bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh

Post-build marker check
-----------------------
strings build/src_mpcd_base_cuda_q6_resident_livevis_0486 | \
  grep -E '0493x9e-neumann|0493x9e-fastpath|0493x9e-fallback|VERIFY_PREFIX|prefix oracle'

Expected production markers include:
  [0493x9e-neumann] ... prefixRepair=targeted_deleted_list_exact ...
  [0493x9e-fastpath] prefixRepair=targeted_deleted_list_exact fallback=0315c_exact

VERIFY_PREFIX / full-prefix-oracle strings should no longer be present.

Minimal post-cleanup smoke
--------------------------
No new long run is required by default. A 400x400 / 250-step smoke is enough
because the pre-cleanup algorithm already passed 3000 steps.

cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF-x8q-ablation
unset MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_VERIFY_PREFIX_0493X9E_FIX2

Lx=1.5625 \
Ly=1.5625 \
NX=400 \
NY=400 \
STEPS=250 \
SEED=493215 \
NEUMANN_PROFILE=x9e \
LIVE_PROGRESS=1 \
LIVE_VIS_ENABLE=0 \
LIVE_VIS_HOLD_ON_EXIT=0 \
RECORD_ENABLE=false \
FILTERED_RECORDING_ENABLE=0 \
ANALYZE_ENABLE=0 \
DUMP_STATE_EVERY=1000 \
CLEAN_RUN_ROOT=1 \
CASE_LABEL=0493x14av_x9e_fix3_cleanup_smoke_400x400 \
bash scripts/run_ok_air_assisted_atomizer.sh \
2>&1 | tee /tmp/x9e_fix3_cleanup_smoke.log

Check:
grep -E '0493x9e-neumann|0493x9e-fastpath|0493x9e-fallback|step=250/250|done' \
  /tmp/x9e_fix3_cleanup_smoke.log

Expected:
- targeted_deleted_list_exact selected;
- fast-path marker present;
- no x9e-fallback marker in the validated atomizer case;
- step=250/250 and done.

Packaging validation performed
-------------------------------
- generated against exact validated pre-cleanup source hash above;
- git apply --check on fresh exact source: PASS;
- applied result byte-identical to intended cleaned source: PASS;
- git diff --check: PASS;
- (), {}, [] counts balanced;
- no raw newline detected inside C/C++ string literals.

CUDA compilation/GPU execution are not available in the packaging environment;
the local build and short smoke remain mandatory.
