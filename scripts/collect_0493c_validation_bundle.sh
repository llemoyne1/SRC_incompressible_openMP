#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
STAMP="$(date +%Y%m%d_%H%M%S)"
HEAD="$(git rev-parse --short=12 HEAD)"
OUT="${1:-audit_0493c_${HEAD}_${STAMP}}"
WORK="${OUT%.tar.gz}"
ARCHIVE="${WORK}.tar.gz"
rm -rf "$WORK" "$ARCHIVE" "$ARCHIVE.sha256"
mkdir -p "$WORK/state" "$WORK/toolchain" "$WORK/results" "$WORK/sources"

{
  echo '=== git status --short ==='
  git status --short
  echo '=== git log -5 --oneline ==='
  git log -5 --oneline
  echo '=== git rev-parse HEAD ==='
  git rev-parse HEAD
  echo '=== git remote -v ==='
  git remote -v
  echo '=== git diff --stat ==='
  git diff --stat
  echo '=== git diff --cached --stat ==='
  git diff --cached --stat
} > "$WORK/state/git_state.txt"

git diff --check > "$WORK/state/git_diff_check.txt" 2>&1 || true
(nvcc --version || true) > "$WORK/toolchain/nvcc_version.txt" 2>&1
(nvidia-smi || true) > "$WORK/toolchain/nvidia_smi.txt" 2>&1
(g++ --version || true) > "$WORK/toolchain/gxx_version.txt" 2>&1
(uname -a || true) > "$WORK/toolchain/uname.txt" 2>&1

BIN="build/src_mpcd_base_cuda_q6_resident_livevis_0486"
if [[ -x "$BIN" ]]; then
  sha256sum "$BIN" > "$WORK/toolchain/binary_sha256.txt"
  (ldd "$BIN" || true) > "$WORK/toolchain/binary_ldd.txt" 2>&1
  stat "$BIN" > "$WORK/toolchain/binary_stat.txt"
fi

for root in \
  runs/0493b_universal_species_resampling_matrix \
  runs/0493c_species_resampling_qualification \
  runs/0493c_medium_qualification; do
  [[ -d "$root" ]] || continue
  dest="$WORK/results/$(basename "$root")"
  mkdir -p "$dest"
  find "$root" -type f \
    \( -name 'status_*.csv' -o -name 'qualification_*.csv' -o -name 'qualification_*.md' \
       -o -name 'params_*.kv' -o -name 'run_*.log' -o -name 'time_*.txt' \
       -o -name 'summary_runtime.csv' -o -name 'cuda_species_resident_maintenance_0490n.csv' \
       -o -name 'cuda_species_resident_fast_path_0490m.csv' \
       -o -name 'cuda_species_transfer_plan_0490k.csv' \
       -o -name 'cuda_species_mass_closure_0490i.csv' -o -name 'darcy_cost_*.csv' \) \
    -print0 | while IFS= read -r -d '' file; do
      rel="${file#$root/}"
      mkdir -p "$dest/$(dirname "$rel")"
      cp -a "$file" "$dest/$rel"
    done
done

for file in \
  README_0493B_UNIVERSAL_RESIDENT_PER_SPECIES.md \
  README_0493C_RESIDENT_QUALIFICATION.md \
  scripts/check_0493b_universal_species_resampling.sh \
  scripts/run_0493b_universal_species_resampling_matrix.sh \
  scripts/check_0493c_resident_qualification.sh \
  scripts/run_0493c_species_resampling_qualification.sh \
  scripts/run_0493c_medium_qualification.sh \
  scripts/analyze_0493c_resident_qualification.py \
  scripts/collect_0493c_validation_bundle.sh; do
  [[ -f "$file" ]] && cp -a "$file" "$WORK/sources/"
done

if [[ -x scripts/check_0493b_universal_species_resampling.sh ]]; then
  bash scripts/check_0493b_universal_species_resampling.sh > "$WORK/state/check_0493b.txt" 2>&1 || true
fi
if [[ -x scripts/check_0493c_resident_qualification.sh ]]; then
  bash scripts/check_0493c_resident_qualification.sh > "$WORK/state/check_0493c.txt" 2>&1 || true
fi

WORK_PARENT="$(cd "$(dirname "$WORK")" && pwd)"
WORK_BASE="$(basename "$WORK")"
( cd "$WORK_PARENT" && find "$WORK_BASE" -type f -print0 | sort -z | xargs -0 sha256sum ) > "$WORK/MANIFEST_SHA256.txt"
tar -C "$WORK_PARENT" -czf "$ARCHIVE" "$WORK_BASE"
sha256sum "$ARCHIVE" | tee "$ARCHIVE.sha256"
echo "[0493c-collect] archive=$ARCHIVE"
echo "[0493c-collect] sha256=$ARCHIVE.sha256"
