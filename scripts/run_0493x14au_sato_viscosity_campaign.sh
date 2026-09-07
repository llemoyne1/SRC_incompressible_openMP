#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
L="$ROOT/scripts/run_0493x14au_sato_liquid_viscosity.sh"
G="$ROOT/scripts/run_0493x14au_sato_gas_viscosity.sh"
for f in "$L" "$G"; do [[ -x "$f" ]] || { echo "[0493x14au] ERROR missing executable $f" >&2; exit 2; }; done

ARG="${1:-}"
case "$ARG" in
  ''|--preflight|--analyze-only|--check) ;;
  -h|--help)
    cat <<'USAGE'
0493x14au — viscosity qualification campaign for the x14at Sato analogue.
Runs liquid first, then gas, each at the primary 64h TG wavelength and at the
application-scale 64/3 h wavelength. Eight seeds are used for the primary fit;
the first four are reused for the paired wavelength check.

Usage:
  bash scripts/run_0493x14au_sato_viscosity_campaign.sh
  bash scripts/run_0493x14au_sato_viscosity_campaign.sh --preflight
  RESTART=1 bash scripts/run_0493x14au_sato_viscosity_campaign.sh
  bash scripts/run_0493x14au_sato_viscosity_campaign.sh --analyze-only
USAGE
    exit 0 ;;
  *) echo "[0493x14au] ERROR unknown argument: $ARG" >&2; exit 2 ;;
esac

BASE_ROOT="${BASE_ROOT:-runs/0493x14au_sato_viscosity}"
mkdir -p "$BASE_ROOT"
{
  echo "qualification=0493x14au-sato-viscosity-campaign"
  echo "timestamp=$(date -Is)"
  echo "head=$(git rev-parse HEAD 2>/dev/null || echo unavailable)"
  echo "binary=${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
  if [[ -x "${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}" ]]; then
    echo "binary_sha256=$(sha256sum "${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}" | awk '{print $1}')"
  fi
  echo "restart=${RESTART:-0}"
  echo "primarySeeds=${PRIMARY_SEEDS:-4932101,4932102,4932103,4932104,4932105,4932106,4932107,4932108}"
  echo "scaleSeeds=${SCALE_SEEDS:-4932101,4932102,4932103,4932104}"
  echo "liquidPath=src-q6-g-f"
  echo "gasPath=src"
  echo "primaryTGwavelengthOverH=64"
  echo "applicationTGwavelengthOverH=21.3333333333333"
  echo "satoNozzleDOverH=20"
} > "$BASE_ROOT/campaign_manifest.txt"
cat "$BASE_ROOT/campaign_manifest.txt"

export BASE_ROOT
if [[ -n "$ARG" ]]; then
  bash "$L" "$ARG"
  bash "$G" "$ARG"
else
  bash "$L"
  bash "$G"
fi

echo "[0493x14au] CAMPAIGN COMPLETE root=$BASE_ROOT"
echo "[0493x14au] MATLAB analysis: cd matlab && matlab -batch \"analyze_0493x14au_sato_viscosity_qualification\""
