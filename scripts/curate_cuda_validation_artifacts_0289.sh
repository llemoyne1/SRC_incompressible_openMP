#!/usr/bin/env bash
set -euo pipefail

# Copy only lightweight, curated CUDA validation summaries from the raw
# dev_history/artifacts tree.  The raw tree can contain thousands of dumps,
# logs and generated states; this script intentionally avoids broad recursive
# listings.

SRC_ROOT="${SRC_ROOT:-dev_history/artifacts}"
DST_ROOT="${DST_ROOT:-dev_history/validated}"

copied=0
missing=0

copy_one() {
  local src="$1"
  local dst_dir="$2"
  mkdir -p "$dst_dir"
  if [[ -f "$src" ]]; then
    cp -f "$src" "$dst_dir/"
    printf '[0289-curate] copied %s -> %s/\n' "$src" "$dst_dir"
    copied=$((copied + 1))
  else
    printf '[0289-curate] missing %s\n' "$src" >&2
    missing=$((missing + 1))
  fi
}

copy_glob() {
  local pattern="$1"
  local dst_dir="$2"
  local found=0
  mkdir -p "$dst_dir"
  shopt -s nullglob
  local files=( $pattern )
  shopt -u nullglob
  for src in "${files[@]}"; do
    if [[ -f "$src" ]]; then
      cp -f "$src" "$dst_dir/"
      printf '[0289-curate] copied %s -> %s/\n' "$src" "$dst_dir"
      copied=$((copied + 1))
      found=1
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    printf '[0289-curate] no match for %s\n' "$pattern" >&2
    missing=$((missing + 1))
  fi
}

# 0281: boundary-aware CUDA thermostat consolidated validation.
copy_glob "$SRC_ROOT/gpu_cuda_persistent_src_thermostat_consolidated_0281/cuda_persistent_src_thermostat_consolidated_0281*.csv" \
  "$DST_ROOT/cuda_0281"
copy_glob "$SRC_ROOT/gpu_cuda_persistent_src_thermostat_consolidated_0281/cuda_persistent_src_thermostat_consolidated_0281*_summary.txt" \
  "$DST_ROOT/cuda_0281"

# 0284: periodic fixed circular solid in the CUDA resident SRC classic path.
copy_one "$SRC_ROOT/gpu_cuda_persistent_src_thermostat_circle_0284/cuda_persistent_src_thermostat_circle_0284.csv" \
  "$DST_ROOT/cuda_0284"

# 0285: full-face inlet/outlet plus circular solid / Von Karman CUDA path.
copy_one "$SRC_ROOT/gpu_cuda_persistent_src_thermostat_circle_io_0285/cuda_persistent_src_thermostat_circle_io_0285.csv" \
  "$DST_ROOT/cuda_0285"

# 0286: final SRC classic full CUDA consolidated manifest.
copy_glob "$SRC_ROOT/gpu_cuda_src_classic_full_consolidated_0286/cuda_src_classic_full_consolidated_0286*.csv" \
  "$DST_ROOT/cuda_0286"
copy_glob "$SRC_ROOT/gpu_cuda_src_classic_full_consolidated_0286/cuda_src_classic_full_consolidated_0286*_summary.txt" \
  "$DST_ROOT/cuda_0286"

cat > "$DST_ROOT/README.md" <<'README_EOF'
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
README_EOF

printf '[0289-curate] done: copied=%d missing=%d dst=%s\n' "$copied" "$missing" "$DST_ROOT"
if [[ "$copied" -eq 0 ]]; then
  printf '[0289-curate] warning: no artifact was copied. Check SRC_ROOT=%s\n' "$SRC_ROOT" >&2
fi
