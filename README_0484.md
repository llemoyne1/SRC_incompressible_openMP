# SRC_GPU 0484 production resampling strip

Base expected by the patch:

- branch: `local/integ-debridee-test-0431`
- clean tree
- HEAD: `0cc7035`

Patch:

- `patches/0484_production_resampling_strip.diff`

Scope:

- keep functional CUDA resident resampling path active;
- keep compact host patchback 0473 because host-side post-edit/post-remap consumers still need coherent host state;
- disable production-unnecessary CPU/CUDA comparison shadows, full operation gate downloads, remap cell-count diagnostic downloads, and success-row detailed CSVs by default in the 0434/run_ok runner profile;
- keep explicit knobs to re-enable the 0477--0483 validation/debug behavior.

Apply:

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-INTEG
git status --short
git apply patches/0484_production_resampling_strip.diff
chmod +x scripts/run_0484_strip_smoke_src_only.sh
git diff --check
```

Build:

```bash
OUT=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0484 \
CUDA_ARCH_FLAGS='-arch=sm_89' \
bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
```

One-run smoke, no hidden compilation:

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0484 \
AUTO_BUILD=0 BUILD_IF_STALE=0 FORCE_BUILD=0 \
LIVE_PROGRESS=1 \
bash scripts/run_0484_strip_smoke_src_only.sh
```

Expected solver runs: `1`.

Expected important output:

```bash
cat runs/0484_strip_smoke_src_128/src-resampling/output/summary_runtime.csv | tail -3
find runs/0484_strip_smoke_src_128 -path '*/output/cuda_resampling_*.csv' -print | sort
```

The detailed success CSV files should be absent or limited to failure rows. Standard `summary_runtime.csv`, state output, and normal phase summaries remain available.

Commit after smoke:

```bash
git add src/cuda_resampling_pipeline_shadow_0445.cu \
        scripts/src_mpcd_run_common_0434.sh \
        scripts/run_0484_strip_smoke_src_only.sh \
        doc/RESAMPLING_CUDA_PRODUCTION_STRIP_0484.md

git commit -m "0484: strip production resampling diagnostics"
```
