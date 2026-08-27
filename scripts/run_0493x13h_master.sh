#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; cd "$ROOT"
STAGES="${STAGES:-A,B,C}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x13h_L072_qualification}"
mkdir -p "$CAMPAIGN_ROOT/audit"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
{
  echo "campaign=0493x13h_L072_qualification"
  echo "createdUtc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "gitHead=$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
  echo "gitBranch=$(git branch --show-current 2>/dev/null || echo UNKNOWN)"
  echo "binary=$BIN"
  if [[ -f "$BIN" ]]; then echo "binarySha256=$(sha256sum "$BIN" | awk '{print $1}')"; else echo "binarySha256=MISSING"; fi
  echo "srcIncludeTreeSha256=$((find src include -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null || true) | sha256sum | awk '{print $1}')"
} > "$CAMPAIGN_ROOT/audit/environment_0493x13h.txt"
run_stage(){
 case "$1" in
  A) echo '[0493x13h-master] === A acoustic damping / cs nuL ==='; bash scripts/run_0493x13h_A_Cdamp_L072.sh;;
  B) echo '[0493x13h-master] === B density transport map ==='; bash scripts/run_0493x13h_B_density_transport_L072.sh;;
  C) echo '[0493x13h-master] === C targeted Mach sweep ==='; bash scripts/run_0493x13h_C_Mach_L072.sh;;
  *) echo "[0493x13h-master] unknown stage $1" >&2; exit 2;;
 esac
}
IFS=',' read -ra arr <<< "$STAGES";for s in "${arr[@]}";do run_stage "$s";done
echo "[0493x13h-master] COMPLETE stages=$STAGES"
