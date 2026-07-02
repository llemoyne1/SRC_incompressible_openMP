#!/usr/bin/env bash
set -euo pipefail

# 0435c boundary-equivalence matrix runner.
# Runs 6 cases and copies each canonical 0434 output tree into runs/0435c_compare.

NX=${NX:-120}
NY=${NY:-30}
GAMMA=${GAMMA:-4}
STEPS=${STEPS:-100}

BASE=${BASE:-runs/0435c_compare}

PRE_BIN=${PRE_BIN:-build/src_mpcd_base_cuda_q6_resident_0400_livevis_pre0435c}
NEW_BIN=${NEW_BIN:-build/src_mpcd_base_cuda_q6_resident_0400_livevis_0435c}

LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-0}
FILTERED_RECORDING_ENABLE=${FILTERED_RECORDING_ENABLE:-0}

run_one() {
  local case_name="$1"
  local label="$2"
  local bin="$3"
  local shared="$4"
  local script="$5"
  local canonical_root="$6"

  local dst="${BASE}/${case_name}_${label}"
  local log="${dst}/run.log"

  echo
  echo "============================================================"
  echo "[0435c-eq] case=${case_name} label=${label}"
  echo "[0435c-eq] bin=${bin}"
  echo "[0435c-eq] shared0251=${shared}"
  echo "[0435c-eq] canonical=${canonical_root}"
  echo "[0435c-eq] dst=${dst}"
  echo "============================================================"

  if [[ ! -x "$bin" ]]; then
    echo "[0435c-eq] ERROR missing executable bin=$bin" >&2
    exit 127
  fi

  rm -rf "$canonical_root" "$dst"
  mkdir -p "$dst"

  env \
    BIN="$bin" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="$shared" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT="$shared" \
    RUN_MODES=src \
    NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
    FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
    bash "$script" 2>&1 | tee "$log"

  if [[ ! -d "${canonical_root}/src/output" ]]; then
    echo "[0435c-eq] ERROR expected output missing: ${canonical_root}/src/output" >&2
    echo "[0435c-eq] existing canonical tree:" >&2
    find "$canonical_root" -maxdepth 4 -type d -print 2>/dev/null >&2 || true
    exit 3
  fi

  cp -a "${canonical_root}/src" "$dst/src"
  echo "[0435c-eq] copied ${canonical_root}/src -> $dst/src"
}

inj_root="runs/0434_injection_type1_into_type2_${NX}x${NY}_g${GAMMA}"
io_root="runs/0434_io_box_same_face_${NX}x${NY}_g${GAMMA}"

run_one "injection" "ref_old_no_shared" "$PRE_BIN" 0 "scripts/run_0434_injection_type1_into_type2.sh" "$inj_root"
run_one "injection" "new_no_shared"     "$NEW_BIN" 0 "scripts/run_0434_injection_type1_into_type2.sh" "$inj_root"
run_one "injection" "new_shared"        "$NEW_BIN" 1 "scripts/run_0434_injection_type1_into_type2.sh" "$inj_root"

run_one "io_box" "ref_old_no_shared" "$PRE_BIN" 0 "scripts/run_0434_io_box_same_face.sh" "$io_root"
run_one "io_box" "new_no_shared"     "$NEW_BIN" 0 "scripts/run_0434_io_box_same_face.sh" "$io_root"
run_one "io_box" "new_shared"        "$NEW_BIN" 1 "scripts/run_0434_io_box_same_face.sh" "$io_root"

echo
echo "[0435c-eq] completed matrix. Outputs under $BASE"
find "$BASE" -maxdepth 4 -type f \( -name summary_runtime.csv -o -name cuda_persistent_src_collision_thermostat_0215.csv -o -name run.log \) -printf '%p\n' | sort
