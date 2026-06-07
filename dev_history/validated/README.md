# Curated validation artifacts

This directory stores lightweight, versionable validation evidence for major
SRC/MPCD milestones.  Raw generated trees under `dev_history/artifacts/` are
local working outputs and are intentionally ignored by Git.

Policy:

- keep small CSV/TXT summaries that identify the validated code path, active
  flags, grid sizes, compared metrics and PASS/FAIL verdicts;
- do not keep generated particle states, animation dumps, logs, timing files or
  large raw output directories;
- regenerate or refresh this directory with:

```bash
bash scripts/curate_cuda_validation_artifacts_0289.sh
```

Current curated CUDA milestones:

- `cuda_0281`: boundary-aware CUDA thermostat consolidation;
- `cuda_0284`: periodic fixed circular solid in the CUDA resident SRC classic path;
- `cuda_0285`: full-face inlet/outlet plus circular solid / Von Karman path;
- `cuda_0286`: final SRC classic full CUDA consolidated validation manifest.
