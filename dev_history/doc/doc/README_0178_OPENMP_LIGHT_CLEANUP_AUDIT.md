# 0178 — OpenMP-light cleanup audit

This step is intentionally **read-only**. It does not remove, move, or edit existing code, scripts, or documentation.

The goal is to prepare the OpenMP-light cleanup by listing files into categories:

- `keep`: likely required for the light branch.
- `candidate_move_dev`: profiling/development scripts that may be moved out of the production-light surface.
- `candidate_move_dev_history`: patch-era documentation that may be archived.
- `code_profile_refs`: source files that still contain internal profiling references; these may remain if guarded by `MPCD_INTERNAL_PROFILES`.
- `review`: manual decision required.

## Usage

From the `clean/openmp-light` worktree:

```bash
python3 scripts/audit_openmp_light_cleanup_0178.py \
  --root . \
  --out cleanup_audit_0178
```

Outputs:

```text
cleanup_audit_0178/openmp_light_cleanup_inventory_0178.csv
cleanup_audit_0178/openmp_light_cleanup_summary_0178.csv
cleanup_audit_0178/openmp_light_profile_references_0178.csv
```

Please inspect or share these CSVs before any cleanup patch is generated.

## Recommended validation

The audit should not modify the repository:

```bash
git status -sb
git diff --stat
```

Expected: only the new audit script and this README are untracked/added if the 0178 zip has just been applied.
