#!/usr/bin/env bash
set -euo pipefail
cd "${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"

LIST="0493x10w_fix1_static_qualification_files.txt"
ARCHIVE="0493x10w_fix1_static_qualification_results.tar.gz"
: > "$LIST"

for d in \
    runs/0493x10w_fix1_cold_control_* \
    runs/0493x10w_fix1_hot_sigma3000_*
do
    [ -d "$d" ] || continue
    find "$d/output" -maxdepth 1 -type f \
        \( -name 'state_step_*.smpcd' \
        -o -name 'cuda_phase_kinetic_crossing_*.csv' \
        -o -name 'cuda_phase_interface_stencil_*.csv' \
        -o -name '*interface*.csv' \) >> "$LIST" 2>/dev/null
    find "$d/params" -maxdepth 1 -type f -name '*.kv' >> "$LIST" 2>/dev/null
 done

sort -u "$LIST" -o "$LIST"
echo "===== CASES ====="
grep '/params/' "$LIST" || true
echo "case_count=$(grep -c '/params/' "$LIST" || true)"
tar -czf "$ARCHIVE" -T "$LIST"
ls -lh "$LIST" "$ARCHIVE"
