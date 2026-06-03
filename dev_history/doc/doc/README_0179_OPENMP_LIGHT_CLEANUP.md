# 0179 — OpenMP-light cleanup staging

This patch adds a conservative cleanup helper for the `clean/openmp-light` branch.

It does not modify C++ code and does not remove production behavior. Its purpose is to move development/profiling artifacts out of the top-level production paths while keeping them available under `dev_history/`.

## Default behavior

The helper is dry-run by default:

```bash
python3 scripts/apply_openmp_light_cleanup_0179.py --root .
```

It prints the planned moves and writes:

```text
cleanup_audit_0179/openmp_light_cleanup_manifest_0179.csv
```

## Apply the conservative cleanup

```bash
python3 scripts/apply_openmp_light_cleanup_0179.py --root . --apply
```

This moves only the categories explicitly verified as tracked before this patch:

```text
validation_compare*.csv*                  -> dev_history/validation_comparisons/
scripts/run_performance_profile_*.sh      -> dev_history/scripts/performance_profiles/
scripts/apply_openmp_light_diagnostics_0176.py -> dev_history/scripts/light_diagnostics/
```

It does not touch:

```text
src/
include/
scripts/build*
scripts/run_validation_mono_config_0162.sh
scripts/compare_validation_mono_config_0162.py
scripts/generate_validation_state_0162.py
scripts/run_openmp_light_smoke_0176.sh
runs/
```

## Optional doc history move

After reviewing the manifest, patch-era documentation can also be archived:

```bash
python3 scripts/apply_openmp_light_cleanup_0179.py --root . --apply --move-doc-history
```

This additionally moves:

```text
doc/README_[0-9]*.md       -> dev_history/doc/patch_history/
doc/NEXT_CHAT_PROMPT*.md   -> dev_history/doc/patch_history/
```

Use this optional mode only after checking that no production documentation is mixed into those names.

## Validation after cleanup

Run the existing light smoke tests:

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh

RUN_ROOT=runs/openmp_light_smoke_0179 \
THREADS=4 \
STEPS=50 \
SUMMARY_EVERY=10 \
./scripts/run_openmp_light_smoke_0176.sh

MPCD_INTERNAL_PROFILES=1 \
RUN_ROOT=runs/openmp_light_profile_enabled_0179 \
THREADS=4 \
STEPS=50 \
SUMMARY_EVERY=10 \
./scripts/run_openmp_light_smoke_0176.sh
```

Expected:

```text
PASS: no internal profile files produced in light mode.
PASS: internal profiles produced when explicitly enabled (... files).
```
