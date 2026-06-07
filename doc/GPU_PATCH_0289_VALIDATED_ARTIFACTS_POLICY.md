# GPU patch 0289 — curated validation artifacts and Git hygiene

Patch 0289 separates two categories of development outputs:

1. **Raw local artifacts** under `dev_history/artifacts/`.
   These directories can contain generated `.smpcd` states, animation dumps,
   logs, timing files and many intermediate CSV files.  They are useful while a
   validation is running, but they should not be enumerated by `git status` or
   versioned wholesale.

2. **Curated validation evidence** under `dev_history/validated/`.
   This directory stores only small CSV/TXT summaries that are useful for future
   work: code path, active CUDA flags, grid sizes, compared metrics and PASS/FAIL
   verdicts.

The current curated CUDA milestones are:

| Directory | Meaning |
|---|---|
| `dev_history/validated/cuda_0281/` | Boundary-aware CUDA thermostat consolidation. |
| `dev_history/validated/cuda_0284/` | Periodic fixed circular solid in the CUDA resident SRC classic path. |
| `dev_history/validated/cuda_0285/` | Full-face inlet/outlet plus circular solid / Von Karman CUDA path. |
| `dev_history/validated/cuda_0286/` | Final SRC classic full CUDA consolidated validation manifest. |

## Usage

Refresh the curated directory from a local raw artifact tree with:

```bash
bash scripts/curate_cuda_validation_artifacts_0289.sh
```

The script is deliberately whitelist-based.  It does not run a broad `find` over
all generated outputs, because the raw artifact tree can be very large.

Optional source/destination override:

```bash
SRC_ROOT=dev_history/artifacts \
DST_ROOT=dev_history/validated \
bash scripts/curate_cuda_validation_artifacts_0289.sh
```

## Git status speed

After applying this patch, raw artifacts are ignored through `.gitignore`:

```gitignore
dev_history/artifacts/
runs/
build/
*.smpcd
*.time
*.log
```

For faster status checks on large working trees:

```bash
git config core.untrackedCache true
git update-index --test-untracked-cache
```

Useful commands:

```bash
# Quick status without enumerating untracked files
git status -uno

# Preview ignored generated files that could be removed
git clean -ndX

# Remove ignored generated files after checking the preview
git clean -fdX
```

Do not use `git clean -fdx` here unless you explicitly want to delete every
untracked non-ignored file too.  The uppercase `-X` variant is safer because it
only targets files already ignored by `.gitignore`.
