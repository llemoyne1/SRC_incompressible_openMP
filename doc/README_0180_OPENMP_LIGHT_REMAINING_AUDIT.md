# 0180 — OpenMP-light remaining cleanup audit

This patch adds a read-only audit for the OpenMP-light branch after the 0179 cleanup staging.

It does not modify, remove, or move project files. It inventories the remaining tracked files and classifies them into broad categories such as:

- core source to keep;
- generic build/validation scripts to keep;
- profiling/dev-history scripts that should already be archived or reviewed;
- patch-era documentation that can likely move to `dev_history/doc/`;
- case-specific scripts/docs requiring manual review;
- root-level validation/profile artifacts to remove or archive.

## Usage

From the OpenMP-light worktree:

```bash
python3 scripts/audit_openmp_light_remaining_0180.py --root . --out cleanup_audit_0180
```

Optional, to include untracked non-build/non-run files:

```bash
python3 scripts/audit_openmp_light_remaining_0180.py --root . --out cleanup_audit_0180 --include-untracked
```

## Outputs

```text
cleanup_audit_0180/openmp_light_remaining_inventory_0180.csv
cleanup_audit_0180/openmp_light_remaining_summary_0180.csv
cleanup_audit_0180/openmp_light_remaining_profile_refs_0180.csv
cleanup_audit_0180/openmp_light_remaining_recommendations_0180.csv
```

## Intended next step

Use this audit to prepare a conservative 0181 cleanup patch. Do not remove files solely based on automatic classification; manually inspect files in the `review*` classes first.
