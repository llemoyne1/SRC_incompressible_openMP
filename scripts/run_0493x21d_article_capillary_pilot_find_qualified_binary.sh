#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"
SEARCH_ROOT="${SEARCH_ROOT:-/mnt/e/SRC_MPCD_DEV}"
#EXPECTED="${EXPECTED_BIN_SHA256:-ab718f8f61b67959c157b78c05a37a8c7efa3dec7740d862ed12eecacd27090f}"
EXPECTED="${EXPECTED_BIN_SHA256:-422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc}"
BASENAME="src_mpcd_base_cuda_q6_resident_livevis_0486"
PILOT="$ROOT/scripts/run_0493x21d_article_capillary_pilot.sh"

cd "$ROOT"

[[ -f "$PILOT" ]] || {
  echo "[0493x21d-findbin] ERROR missing pilot runner: $PILOT" >&2
  exit 2
}

echo "===== 0493x21d QUALIFIED-BINARY RECOVERY / LAUNCH ====="
echo "[0493x21d-findbin] expectedSha256=$EXPECTED"
echo "[0493x21d-findbin] searchRoot=$SEARCH_ROOT"
echo "[0493x21d-findbin] policy=SEARCH_ONLY_NO_BUILD_NO_OVERWRITE"

# Explicitly forbid every common helper from building.
export FORCE_BUILD=0
export AUTO_BUILD=0
export BUILD_IF_STALE=0

declare -a candidates=()
while IFS= read -r -d '' f; do
  candidates+=("$f")
done < <(find "$SEARCH_ROOT" -type f -name "$BASENAME" -print0 2>/dev/null)

#if (( ${#candidates[@]} == 0 )); then
#  echo "[0493x21d-findbin] ERROR no candidate named $BASENAME found under $SEARCH_ROOT" >&2
#  exit 3
#fi

match=""
echo "[0493x21d-findbin] candidates=${#candidates[@]}"
for f in "${candidates[@]}"; do
  sha="$(sha256sum "$f" | awk '{print $1}')"
  mt="$(stat -c '%y' "$f" 2>/dev/null || echo UNKNOWN)"
  printf '[0493x21d-findbin] candidate sha256=%s mtime=%s path=%s\n' "$sha" "$mt" "$f"
  if [[ "$sha" == "$EXPECTED" ]]; then
    if [[ -n "$match" && "$match" != "$f" ]]; then
      echo "[0493x21d-findbin] NOTE multiple byte-identical qualified binaries found."
    fi
    match="$f"
  fi
done

if [[ -z "$match" ]]; then
  echo >&2
  echo "[0493x21d-findbin] STOP: no exact qualified binary found." >&2
  echo "[0493x21d-findbin] Nothing was built, copied, deleted, or overwritten." >&2
  echo "[0493x21d-findbin] Return the candidate list above; the next operation will be clean-worktree recovery if necessary." >&2
  exit 4
fi

[[ -x "$match" ]] || {
  echo "[0493x21d-findbin] ERROR exact-hash candidate is not executable: $match" >&2
  exit 5
}

echo
echo "[0493x21d-findbin] qualifiedBinary=FOUND"
echo "[0493x21d-findbin] path=$match"
echo "[0493x21d-findbin] sha256=$EXPECTED"
echo "[0493x21d-findbin] launching x21d with this exact binary; current build/ binary is left untouched."
echo

exec env \
  BIN="$match" \
  EXPECTED_BIN_SHA256="$EXPECTED" \
  FORCE_BUILD=0 \
  AUTO_BUILD=0 \
  BUILD_IF_STALE=0 \
  LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
  bash "$PILOT"
