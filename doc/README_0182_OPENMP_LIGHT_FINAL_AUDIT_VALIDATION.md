# 0182 — Final OpenMP-light audit and validation helper

This patch adds read-only tooling for the final cleanup/validation pass of the
`clean/openmp-light` branch.

## Files

- `scripts/audit_openmp_light_final_0182.py` performs a tracked-file hygiene audit.
- `scripts/run_openmp_light_final_validation_0182.sh` compares the light branch
  against a reference optimized worktree using the existing mono-configuration
  validation suite.

No source code or runtime behavior is changed.

## Audit

```bash
python3 scripts/audit_openmp_light_final_0182.py --root . --out cleanup_audit_0182
```

Outputs:

- `cleanup_audit_0182/openmp_light_final_inventory_0182.csv`
- `cleanup_audit_0182/openmp_light_final_summary_0182.csv`
- `cleanup_audit_0182/openmp_light_final_profile_refs_0182.csv`
- `cleanup_audit_0182/openmp_light_final_recommendations_0182.csv`

## Final validation against the optimized worktree

Default reference root is `../SRC_openMP_optimized`.

```bash
THREADS=8 \
STEPS=1000 \
SUMMARY_EVERY=100 \
./scripts/run_openmp_light_final_validation_0182.sh
```

If the reference worktree lives elsewhere:

```bash
REF_ROOT=/path/to/SRC_openMP_optimized ./scripts/run_openmp_light_final_validation_0182.sh
```

The script writes in the light worktree:

- `validation_compare_0182.csv`
- `validation_compare_summary_0182.csv`

Expected result: `Validation comparison: PASS` and `failed_metrics=0` for all
validation cases.

## Notes

- The light validation is run with `MPCD_INTERNAL_PROFILES=0`.
- The reference worktree build is optional via `BUILD_REF=1`; the light worktree
  is rebuilt by default (`BUILD_LIGHT=1`).
- The script does not commit or remove any files.
