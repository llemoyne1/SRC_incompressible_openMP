# 0181 — OpenMP-light safe archive staging

This patch adds a conservative cleanup script for the `clean/openmp-light` branch.
It does not alter the solver, build system, or validation scripts.

The script reads the 0180 audit inventory and moves only the classifications that
were identified as safe archival candidates:

- `candidate_archive_doc` → `dev_history/doc/`
- `candidate_archive_script` → `dev_history/scripts/`
- `candidate_archive_other` → `dev_history/artifacts/`

It does **not** touch files classified as `review_*`, source code, headers,
`runs/`, or `build/`.

## Dry-run

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_openMP_light

python3 scripts/apply_openmp_light_archive_0181.py \
  --root .
```

This writes:

```text
cleanup_audit_0181/openmp_light_archive_manifest_0181.csv
```

Review the manifest before applying.

## Apply

```bash
python3 scripts/apply_openmp_light_archive_0181.py \
  --root . \
  --apply
```

By default, tracked files are moved with `git mv`.

## Validate after apply

```bash
git status -sb
git diff --stat

BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh

RUN_ROOT=runs/openmp_light_smoke_0181 \
THREADS=4 \
STEPS=50 \
SUMMARY_EVERY=10 \
./scripts/run_openmp_light_smoke_0176.sh

MPCD_INTERNAL_PROFILES=1 \
RUN_ROOT=runs/openmp_light_profile_enabled_0181 \
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

## Commit suggestion

```bash
git add scripts/apply_openmp_light_archive_0181.py \
        doc/README_0181_OPENMP_LIGHT_SAFE_ARCHIVE.md \
        dev_history \
        cleanup_audit_0181

git add -u

git commit -m "Archive remaining OpenMP-light development artifacts"
```

Check carefully that `runs/` and build outputs are not staged.
