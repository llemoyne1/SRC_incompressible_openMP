#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
file=src/src_mpcd_base.cpp
grep -q 'cudaPopulationGuardAuthoritative0493o1' "$file"
grep -q 'localSupportSplitOnlyRequested0493o1' "$file"
grep -q 'populationGuardEdited && !cudaPopulationGuardAuthoritative0493o1' "$file"
grep -q 'poorNonEmptyPairs0493o1' "$file"
git diff --check
echo '[0493o1-fix2-check] CUDA authority bypass: PASS'
