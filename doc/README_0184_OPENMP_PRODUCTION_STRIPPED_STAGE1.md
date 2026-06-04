# 0184 — openmp-production-stripped, stage 1

This stage removes the runtime branch that produced internal development/profile CSV files from the OpenMP code path.  The fluid-mechanics outputs are intentionally preserved: runtime summaries, dumps for post-processing, mass/particle/momentum/kBT summaries, useful Q6 residuals, global resampling counters, and virial/capacity diagnostics when enabled.

Removed from the C++ runtime path:

- `MPCD_INTERNAL_PROFILES` checks;
- `phase_profile_*.csv` writing;
- `q6_cg_profile_*.csv` writing;
- `deposit_profile_*.csv` writing;
- `resampling_guard_profile_*.csv` writing;
- `post_guard_profile_*.csv` writing;
- `post_guard_equivalence*.csv` writing.

The pass is conservative: profile data structures and phase names are still present as dead/no-op compatibility scaffolding.  They can be removed in a later stage after the four-case equivalence comparison is clean.

## Create the branch from the clean light snapshot

```bash
BASE=/mnt/e/SRC_MPCD_dev
ZIP=/mnt/c/Users/llemoyne/Downloads/SRC_incompressible_openMP-clean-openmp-light.zip

rm -rf "$BASE/_unpack_openmp_light_0183"
rm -rf "$BASE/SRC_openMP_production_stripped"
mkdir -p "$BASE/_unpack_openmp_light_0183"
unzip -q "$ZIP" -d "$BASE/_unpack_openmp_light_0183"
SNAP_ROOT="$(find "$BASE/_unpack_openmp_light_0183" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
rsync -a "$SNAP_ROOT"/ "$BASE/SRC_openMP_production_stripped"/
cd "$BASE/SRC_openMP_production_stripped"

git init
git add .
git commit -m "baseline: clean/openmp-light snapshot after 0176-0183"
git branch -M clean/openmp-light
git switch -c clean/openmp-production-stripped
```

Apply the files from `openmp_production_stripped_stage1_0184_files_only.zip` on top of this branch, then commit.

## Audit without `rg`

Portable source audit, limited to the C++ runtime path:

```bash
grep -RInE 'MPCD_INTERNAL_PROFILES|getenv\(|phase_profile_[^/]*\.csv|q6_cg_profile_[^/]*\.csv|deposit_profile_[^/]*\.csv|resampling_guard_profile_[^/]*\.csv|post_guard_profile_[^/]*\.csv|post_guard_equivalence[^/]*\.csv' src include || true
```

The expected result after 0184 is no C++ runtime match for `MPCD_INTERNAL_PROFILES`, `getenv`, or any internal profile output filename.  Some generic words such as `profile` remain because the dead scaffolding is intentionally kept for stage 2.

Portable generated-file audit:

```bash
find runs/openmp_production_stripped_smoke_0184 \
  \( -name 'phase_profile_*.csv' \
  -o -name 'q6_cg_profile_*.csv' \
  -o -name 'deposit_profile_*.csv' \
  -o -name 'resampling_guard_profile_*.csv' \
  -o -name 'post_guard_profile_*.csv' \
  -o -name 'post_guard_equivalence*.csv' \
  -o -name 'post_guard_equivalence_trace_*.csv' \) \
  -type f -print
```

The expected result is an empty output.

## Smoke test

```bash
BUILD_PROFILE=safe bash scripts/build_src_mpcd_base_optimized_0156.sh

THREADS=4 \
STEPS=50 \
SUMMARY_EVERY=10 \
RUN_ROOT=runs/openmp_production_stripped_smoke_0184 \
RUN_TAG=production_stripped_0184 \
bash scripts/run_openmp_production_stripped_smoke_0184.sh
```

## Light vs production-stripped comparison

Assuming the original `clean/openmp-light` checkout is available as `../SRC_openMP_light`:

```bash
THREADS=8 \
STEPS=1000 \
SUMMARY_EVERY=100 \
REF_ROOT=../SRC_openMP_light \
RUN_ROOT_REF=runs/validation_0184_light_ref \
RUN_ROOT_STRIPPED=runs/validation_0184_production_stripped \
bash scripts/run_openmp_production_stripped_validation_0184.sh

cat validation_compare_summary_0184.csv
```

Expected verdict: `PASS` on the four validation cases:

- `tg_periodic_full`;
- `poiseuille_wall_full`;
- `open_rect_obstacle_full`;
- `piston_virial_full`.
