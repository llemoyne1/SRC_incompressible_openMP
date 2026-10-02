#!/usr/bin/env bash
# 0493x20g — non-destructive audit of SRC rotationAngle plumbing on the
# historical x20a/x20b/x20c/x20d standalone calibrator path.
#
# Runs four tiny 8-step TG probes:
#   DEVICE_ROTATION_0272 = 1: alpha=30,175 deg
#   DEVICE_ROTATION_0272 = 0: alpha=30,175 deg
# Same seed and initial-state generator in all cases.
# Existing scientific runs are never touched.
set -euo pipefail

TAG=0493x20g
ROOT="${ROOT:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

EXPECTED_CALIBRATOR_SHA="d76c33d8a6cdcd70df5dc0f71423ad10a2944c954987542ef7c43b2918406c49"
EXPECTED_BINARY_SHA="ab718f8f61b67959c157b78c05a37a8c7efa3dec7740d862ed12eecacd27090f"

# The x20a--x20d archive used this binary/calibrator family. Both are
# overridable so the audit can also be applied to another checkout.
BIN="${BIN:-$ROOT/build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
CALIBRATOR="${CALIBRATOR:-}"
RUN_ROOT="${RUN_ROOT:-$ROOT/runs/0493x20g_rotation_angle_audit}"
SEED="${SEED:-4938601}"
THREADS="${THREADS:-8}"

find_calibrator() {
  local c
  if [[ -n "$CALIBRATOR" ]]; then
    [[ -f "$CALIBRATOR" ]] || { echo "[$TAG] ERROR CALIBRATOR not found: $CALIBRATOR" >&2; exit 2; }
    readlink -f "$CALIBRATOR"
    return
  fi
  for c in \
    "$ROOT/scripts/calibrate_fluid_0493w1_standalone.sh" \
    "$ROOT/scripts/calibrate_fluid_0493w1_standalone_v4.sh" \
    "$ROOT/calibrate_fluid_0493w1_standalone.sh" \
    "$ROOT/calibrate_fluid_0493w1_standalone_v4.sh"; do
    if [[ -f "$c" ]]; then readlink -f "$c"; return; fi
  done
  echo "[$TAG] ERROR cannot locate historical standalone calibrator." >&2
  echo "Set CALIBRATOR=/path/to/calibrate_fluid_0493w1_standalone.sh" >&2
  exit 2
}

CALIBRATOR="$(find_calibrator)"
[[ -x "$BIN" ]] || { echo "[$TAG] ERROR binary not executable: $BIN" >&2; exit 127; }
for c in bash python3 awk sed grep sha256sum cmp tar base64 find sort readlink; do
  command -v "$c" >/dev/null || { echo "[$TAG] ERROR missing command: $c" >&2; exit 127; }
done

CAL_SHA="$(sha256sum "$CALIBRATOR" | awk '{print $1}')"
BIN_SHA="$(sha256sum "$BIN" | awk '{print $1}')"
HIST_CAL_MATCH=NO; [[ "$CAL_SHA" == "$EXPECTED_CALIBRATOR_SHA" ]] && HIST_CAL_MATCH=YES
HIST_BIN_MATCH=NO; [[ "$BIN_SHA" == "$EXPECTED_BINARY_SHA" ]] && HIST_BIN_MATCH=YES

mkdir -p "$RUN_ROOT"
WORK="$RUN_ROOT/_private_payload"
rm -rf "$WORK"
mkdir -p "$WORK"

# Extract the embedded payload exactly as the standalone wrapper does.
awk '/^__SRC_FLUID_0493W1_PAYLOAD_BELOW__$/ {f=1; next} f {print}' "$CALIBRATOR" > "$WORK/payload.b64"
[[ -s "$WORK/payload.b64" ]] || { echo "[$TAG] ERROR embedded payload marker not found in $CALIBRATOR" >&2; exit 3; }
base64 -d "$WORK/payload.b64" > "$WORK/payload.tar.gz"
tar -xzf "$WORK/payload.tar.gz" -C "$WORK"
TOOLS="$WORK/scripts"
BASE_RUNNER="$TOOLS/run_src_fluid_complete_direct.sh"
[[ -f "$BASE_RUNNER" ]] || { echo "[$TAG] ERROR direct runner absent from calibrator payload" >&2; exit 3; }

# Make private ON/OFF runner copies. Never modify repository files.
RUNNER_ON="$WORK/run_rotation_on.sh"
RUNNER_OFF="$WORK/run_rotation_off.sh"
cp "$BASE_RUNNER" "$RUNNER_ON"
cp "$BASE_RUNNER" "$RUNNER_OFF"

# The short probe is not a transport fit. Suppress the final analysis only;
# state generation, parameter writing, runtime selection and binary invocation
# remain exactly those of the historical calibrator payload.
sed -i "s/^analyze_all$/echo '[${TAG}] transport analysis intentionally skipped for 8-step probe'/" "$RUNNER_ON" "$RUNNER_OFF"

# OFF branch: change only the 0272 device-rotation fast-path switch in the
# private runner copy. Require exactly one textual replacement.
N0272="$(grep -o 'MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1' "$RUNNER_OFF" | wc -l | tr -d ' ')"
[[ "$N0272" == 1 ]] || { echo "[$TAG] ERROR expected exactly one 0272=1 assignment; found $N0272" >&2; exit 3; }
sed -i 's/MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1/MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=0/' "$RUNNER_OFF"
chmod +x "$RUNNER_ON" "$RUNNER_OFF"

COMMON_ENV=(
  ROOT="$ROOT"
  BIN="$BIN"
  SRC_FLUID_TOOLS_DIR="$TOOLS"
  SRC_FLUID_MODE=run
  CALIBRATION_PATH=src
  CALIBRATION_EXPERIMENTS=tg
  GAMMA=8
  KBT=0.125
  PARTICLE_MASS=1.0
  CELL_SIZE=0.00390625
  LAMBDA_OVER_H=0.72
  NX=64
  NY=64
  TG_MODE_X=1
  TG_MODE_Y=1
  TG_TIME=0.000001
  TG_DUMP_COUNT=8
  SEEDS="$SEED"
  RANDOM_ROTATION_SIGN=true
  GRID_SHIFT_ENABLE=true
  THERMOSTAT_ENABLE=true
  THERMOSTAT_MODE=cell_relative_rescale
  THERMOSTAT_EVERY=1
  THERMOSTAT_TARGET_KBT=0.125
  THERMOSTAT_MIN_PARTICLES=3
  THREADS="$THREADS"
  LIVE_PROGRESS=1
  CLEAN_RUN_ROOT=1
  SKIP_EXISTING=0
  MAX_DUMP_GB=1.0
)

run_probe() {
  local variant="$1" angle="$2" runner="$3"
  local rr="$RUN_ROOT/${variant}_alpha${angle}"
  local log="$RUN_ROOT/${variant}_alpha${angle}.log"
  echo "[$TAG] RUN variant=$variant alpha=$angle seed=$SEED"
  env "${COMMON_ENV[@]}" ROTATION_ANGLE_DEG="$angle" RUN_ROOT="$rr" \
    bash "$runner" >"$log" 2>&1
  [[ -f "$rr/tg_seed${SEED}/.complete" ]] || {
    echo "[$TAG] ERROR run did not complete: variant=$variant alpha=$angle" >&2
    tail -80 "$log" >&2 || true
    exit 4
  }
}

run_probe ON 30  "$RUNNER_ON"
run_probe ON 175 "$RUNNER_ON"
run_probe OFF 30  "$RUNNER_OFF"
run_probe OFF 175 "$RUNNER_OFF"

state_path() {
  local variant="$1" angle="$2" step="$3"
  local base="$RUN_ROOT/${variant}_alpha${angle}/tg_seed${SEED}"
  if [[ "$step" == init ]]; then
    printf '%s\n' "$base/init/tg.smpcd"
  else
    printf '%s\n' "$base/tg/output/state_step_$(printf '%08d' "$step").smpcd"
  fi
}

PARAM30_ON="$RUN_ROOT/ON_alpha30/tg_seed${SEED}/tg/params/params.kv"
PARAM175_ON="$RUN_ROOT/ON_alpha175/tg_seed${SEED}/tg/params/params.kv"
PARAM30_OFF="$RUN_ROOT/OFF_alpha30/tg_seed${SEED}/tg/params/params.kv"
PARAM175_OFF="$RUN_ROOT/OFF_alpha175/tg_seed${SEED}/tg/params/params.kv"

for p in "$PARAM30_ON" "$PARAM175_ON" "$PARAM30_OFF" "$PARAM175_OFF"; do
  [[ -f "$p" ]] || { echo "[$TAG] ERROR missing params: $p" >&2; exit 4; }
done

CSV="$RUN_ROOT/audit_rotation_angle_hashes.csv"
echo 'variant,alpha_deg,step,sha256' > "$CSV"
for variant in ON OFF; do
  for angle in 30 175; do
    for step in init 1 2 3 4 5 6 7 8; do
      f="$(state_path "$variant" "$angle" "$step")"
      [[ -f "$f" ]] || { echo "[$TAG] ERROR missing state $f" >&2; exit 4; }
      h="$(sha256sum "$f" | awk '{print $1}')"
      echo "$variant,$angle,$step,$h" >> "$CSV"
    done
  done
done

first_difference() {
  local variant="$1" s f30 f175
  for s in 1 2 3 4 5 6 7 8; do
    f30="$(state_path "$variant" 30 "$s")"
    f175="$(state_path "$variant" 175 "$s")"
    if ! cmp -s "$f30" "$f175"; then echo "$s"; return; fi
  done
  echo NONE
}

INIT_SAME=NO
cmp -s "$(state_path ON 30 init)" "$(state_path ON 175 init)" && INIT_SAME=YES
ON_FIRST_DIFF="$(first_difference ON)"
OFF_FIRST_DIFF="$(first_difference OFF)"
ON_STEP1_SAME=NO;  cmp -s "$(state_path ON 30 1)"  "$(state_path ON 175 1)"  && ON_STEP1_SAME=YES
ON_STEP8_SAME=NO;  cmp -s "$(state_path ON 30 8)"  "$(state_path ON 175 8)"  && ON_STEP8_SAME=YES
OFF_STEP1_SAME=NO; cmp -s "$(state_path OFF 30 1)" "$(state_path OFF 175 1)" && OFF_STEP1_SAME=YES
OFF_STEP8_SAME=NO; cmp -s "$(state_path OFF 30 8)" "$(state_path OFF 175 8)" && OFF_STEP8_SAME=YES

ANGLE30_ON="$(awk -F= '$1 ~ /^[[:space:]]*rotationAngle[[:space:]]*$/ {gsub(/[[:space:]]/,"",$2); print $2}' "$PARAM30_ON" | tail -1)"
ANGLE175_ON="$(awk -F= '$1 ~ /^[[:space:]]*rotationAngle[[:space:]]*$/ {gsub(/[[:space:]]/,"",$2); print $2}' "$PARAM175_ON" | tail -1)"

VERDICT=UNRESOLVED
IMPACT='Manual inspection required.'
if [[ "$INIT_SAME" != YES ]]; then
  VERDICT=INVALID_PROBE_INITIAL_STATES_DIFFER
  IMPACT='Probe invalid: initial states must be identical for the angle-only comparison.'
elif [[ "$ON_FIRST_DIFF" != NONE ]]; then
  VERDICT=HISTORICAL_PATH_ANGLE_SENSITIVE
  IMPACT='The exact historical x20a-x20d runtime path distinguishes 30 and 175 deg. This strongly localizes the x20f anomaly outside the historical transport calibrator path.'
elif [[ "$ON_FIRST_DIFF" == NONE && "$OFF_FIRST_DIFF" != NONE ]]; then
  VERDICT=DEVICE_ROTATION_0272_SUSPECT
  IMPACT='With historical fast-path ON, alpha is ignored; disabling DEVICE_ROTATION_0272 restores angle sensitivity. Historical x20a-x20d angle sweeps require re-audit/recomputation.'
elif [[ "$ON_FIRST_DIFF" == NONE && "$OFF_FIRST_DIFF" == NONE ]]; then
  VERDICT=ANGLE_IGNORED_BEYOND_0272
  IMPACT='Both fast and fallback branches ignore alpha in this binary/path. Historical angle-dependent results must be quarantined pending solver-level diagnosis.'
fi

CONFIDENCE=PATH_CURRENT
if [[ "$HIST_CAL_MATCH" == YES && "$HIST_BIN_MATCH" == YES ]]; then CONFIDENCE=EXACT_HISTORICAL_X20_PATH; fi

REPORT="$RUN_ROOT/audit_rotation_angle.txt"
cat > "$REPORT" <<REPORT_EOF
===== $TAG SRC ROTATION-ANGLE AUDIT =====
repoRoot=$ROOT
runRoot=$RUN_ROOT
seed=$SEED

calibrator=$CALIBRATOR
calibratorSha256=$CAL_SHA
expectedHistoricalCalibratorSha256=$EXPECTED_CALIBRATOR_SHA
historicalCalibratorShaMatch=$HIST_CAL_MATCH

binary=$BIN
binarySha256=$BIN_SHA
expectedHistoricalBinarySha256=$EXPECTED_BINARY_SHA
historicalBinaryShaMatch=$HIST_BIN_MATCH
confidence=$CONFIDENCE

probePhysics=SRC periodic historical standalone calibrator path
probeGrid=64x64
gamma=8
lambdaOverH=0.72
kBT=0.125
mass=1.0
seed=$SEED
steps=8
dumpEvery=1
anglesDeg=30,175
randomRotationSign=true
gridShiftEnable=true
thermostat=cell_relative_rescale every step

paramsRotationAngle30Rad=$ANGLE30_ON
paramsRotationAngle175Rad=$ANGLE175_ON
initialStatesIdentical=$INIT_SAME

DEVICE_ROTATION_0272_ON_firstDifferentStep=$ON_FIRST_DIFF
DEVICE_ROTATION_0272_ON_step1Identical=$ON_STEP1_SAME
DEVICE_ROTATION_0272_ON_step8Identical=$ON_STEP8_SAME

DEVICE_ROTATION_0272_OFF_firstDifferentStep=$OFF_FIRST_DIFF
DEVICE_ROTATION_0272_OFF_step1Identical=$OFF_STEP1_SAME
DEVICE_ROTATION_0272_OFF_step8Identical=$OFF_STEP8_SAME

VERDICT=$VERDICT
IMPACT=$IMPACT

hashTable=$CSV
logs:
  $RUN_ROOT/ON_alpha30.log
  $RUN_ROOT/ON_alpha175.log
  $RUN_ROOT/OFF_alpha30.log
  $RUN_ROOT/OFF_alpha175.log
REPORT_EOF

cat "$REPORT"
echo
echo "[$TAG] DONE"
echo "[$TAG] report=$REPORT"
echo "[$TAG] hashes=$CSV"
