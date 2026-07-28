#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

grep -q 'massSquared' include/cuda_species_cell_fields_0490h.h
grep -q 'massSquared' src/cuda_species_cell_fields_0490h.cu
grep -q 'localSupportSplitOnly0493o1' include/cuda_resampling_population_guard_0297.h
grep -q 'apply_local_support_split_only_0493o1' src/cuda_resampling_population_guard_0297.cu
test -f include/cuda_local_support_split_0493o1.cuh
test -f scripts/test_0493o1_reference_planner.py
python3 scripts/test_0493o1_reference_planner.py

echo '[0493o1-check] static anchors: PASS'
git diff --check
echo '[0493o1-check] git diff --check: PASS'
