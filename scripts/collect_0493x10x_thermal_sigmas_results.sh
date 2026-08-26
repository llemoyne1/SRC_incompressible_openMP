#!/usr/bin/env bash
set -euo pipefail
cd "${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"

python3 scripts/analyze_0493x10x_thermal_sigmas_sweep.py

LIST="0493x10x_thermal_sigmas_files.txt"
ARCHIVE="0493x10x_thermal_sigmas_results.tar.gz"
: > "$LIST"

for d in runs/0493x10x_C*_R*_g*; do
  [[ -d "$d" ]] || continue
  find "$d/output" -maxdepth 1 -type f \
    \( -name 'summary_runtime.csv' \
    -o -name 'state_step_*.smpcd' \
    -o -name 'cuda_phase_kinetic_crossing_*.csv' \
    -o -name 'cuda_phase_interface_stencil_*.csv' \) >> "$LIST" 2>/dev/null || true
  find "$d/params" -maxdepth 1 -type f -name '*.kv' >> "$LIST" 2>/dev/null || true
done
[[ -f 0493x10x_thermal_sigmas_summary.csv ]] && echo 0493x10x_thermal_sigmas_summary.csv >> "$LIST"
sort -u "$LIST" -o "$LIST"

echo "===== 0493x10x COLLECT ====="
echo "files=$(wc -l < "$LIST")"
tar -czf "$ARCHIVE" -T "$LIST"
ls -lh "$LIST" "$ARCHIVE" 0493x10x_thermal_sigmas_summary.csv
