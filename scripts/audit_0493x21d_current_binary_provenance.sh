#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"
REF="${REF:-74297ce274fc0cd92a9f47a4de92b444ce671b5f}"
BIN="${BIN:-$ROOT/build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
REPORT="${REPORT:-$ROOT/runs/0493x21d_binary_provenance_audit.txt}"

cd "$ROOT"
mkdir -p "$(dirname "$REPORT")"

exec > >(tee "$REPORT") 2>&1

echo "===== 0493x21d CURRENT-BINARY PROVENANCE AUDIT ====="
echo "policy=READ_ONLY_NO_BUILD_NO_CHECKOUT_NO_MODIFICATION"
echo "root=$ROOT"
echo "referenceCommit=$REF"
echo

[[ -d .git ]] || { echo "ERROR: not a git work tree"; exit 2; }
git cat-file -e "$REF^{commit}" 2>/dev/null || {
  echo "ERROR: reference commit not available locally: $REF"
  exit 2
}
[[ -f "$BIN" ]] || { echo "ERROR: binary missing: $BIN"; exit 2; }

echo "===== BINARY ====="
echo "binary=$BIN"
echo "binarySha256=$(sha256sum "$BIN" | awk '{print $1}')"
echo "binaryMtime=$(stat -c '%y' "$BIN")"
echo "binarySize=$(stat -c '%s' "$BIN")"
echo

echo "===== GIT ====="
echo "head=$(git rev-parse HEAD)"
echo "branch=$(git branch --show-current || true)"
echo "referenceSubject=$(git show -s --format='%H %ci %s' "$REF")"
echo

# The 0486 executable is explicitly linked from source/header files plus the build script.
# Compare the complete source/header trees used by that build, not generated Info/ or article files.
SCOPES=(src include scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh)

echo "===== BUILD-RELEVANT WORKTREE STATUS ====="
git status --short -- "${SCOPES[@]}" || true
echo

echo "===== BUILD-RELEVANT DIFFERENCES VS REFERENCE COMMIT ====="
git diff --name-status "$REF" -- "${SCOPES[@]}" || true
echo

echo "===== CUDA CAPILLARY CORE CHECK ====="
for f in \
  src/cuda_q6_resident_0400.cu \
  src/src_mpcd_base.cpp \
  src/params_io_base.cpp \
  scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
do
  printf '%s currentSha256=' "$f"
  sha256sum "$f" | awk '{print $1}'
  printf '%s referenceSha256=' "$f"
  git show "$REF:$f" | sha256sum | awk '{print $1}'
  if git diff --quiet "$REF" -- "$f"; then
    echo "$f status=IDENTICAL_TO_REFERENCE"
  else
    echo "$f status=DIFFERS_FROM_REFERENCE"
  fi
done
echo

echo "===== X21C FIX2 MARKER CHECK ====="
if grep -RInE 'capillaryKappaEffectiveMean|capillaryKappaRawSum0493x9r|x21c-fix2|face-kappa' \
    src include 2>/dev/null; then
  echo "x21cFix2Markers=PRESENT"
else
  echo "x21cFix2Markers=ABSENT"
fi
echo

echo "===== DIFF: src/src_mpcd_base.cpp VS REFERENCE ====="
git diff --no-ext-diff --unified=8 "$REF" -- src/src_mpcd_base.cpp || true
echo

echo "===== DIFF: src/cuda_q6_resident_0400.cu VS REFERENCE ====="
git diff --no-ext-diff --unified=8 "$REF" -- src/cuda_q6_resident_0400.cu || true
echo

# Strong result only if every tracked build-relevant file equals the reference commit
# and there are no untracked source/header files. This does NOT pretend to prove the
# historical binary was built from a clean tree; it tells us whether the current rebuild
# was made from the canonical reference source state.
tracked_diff=0
if ! git diff --quiet "$REF" -- "${SCOPES[@]}"; then
  tracked_diff=1
fi

untracked_build_inputs="$(git ls-files --others --exclude-standard -- src include || true)"
if [[ -n "$untracked_build_inputs" ]]; then
  untracked=1
else
  untracked=0
fi

echo "===== DECISION ====="
if [[ "$tracked_diff" -eq 0 && "$untracked" -eq 0 ]]; then
  echo "sourceState=EXACT_REFERENCE_TRACKED_STATE"
  echo "meaning=current source/header/build-script tree matches commit $REF exactly"
  echo "nextAction=ALLOW_SOURCE_EQUIVALENCE_REVIEW"
else
  echo "sourceState=DIFFERS_FROM_REFERENCE"
  echo "trackedBuildInputDiff=$tracked_diff"
  echo "untrackedSourceOrHeaderFiles=$untracked"
  echo "nextAction=REVIEW_LISTED_DIFFS_BEFORE_USING_CURRENT_BINARY"
fi

if [[ -n "$untracked_build_inputs" ]]; then
  echo
  echo "===== UNTRACKED src/include FILES ====="
  printf '%s\n' "$untracked_build_inputs"
fi

echo
echo "report=$REPORT"
