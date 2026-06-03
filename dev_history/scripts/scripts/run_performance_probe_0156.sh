#!/usr/bin/env bash
set -euo pipefail

# 0156 — compact OpenMP scaling probe for the current SRC/MPCD executable.
# It deliberately avoids MATLAB by using the Python Taylor--Green generator.
# It writes perf_summary_0156.csv under RUN_ROOT.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

BIN=${BIN:-build/src_mpcd_base}
RUN_ROOT=${RUN_ROOT:-runs/performance_probe_0156}
NX=${NX:-64}
NY=${NY:-64}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-500}
DT=${DT:-0.001}
U0=${U0:-0.08}
KBT=${KBT:-0.001}
SEED=${SEED:-1560156}
SUMMARY_EVERY=${SUMMARY_EVERY:-$STEPS}
THREAD_LIST=${THREAD_LIST:-1 2 4 8}
CASE_LIST=${CASE_LIST:-classic q6 q6_resampling}

# Common binding defaults for reproducible OpenMP timings. Users may override.
export OMP_PROC_BIND=${OMP_PROC_BIND:-close}
export OMP_PLACES=${OMP_PLACES:-cores}
export OMP_DYNAMIC=${OMP_DYNAMIC:-false}

mkdir -p "$RUN_ROOT"
STATE="$RUN_ROOT/initial_tg_${NX}x${NY}_g${GAMMA}.smpcd"
CSV="$RUN_ROOT/perf_summary_0156.csv"

echo "[0156-perf] root       : $ROOT_DIR"
echo "[0156-perf] binary     : $BIN"
echo "[0156-perf] run root   : $RUN_ROOT"
echo "[0156-perf] grid/gamma : ${NX}x${NY} / $GAMMA"
echo "[0156-perf] steps      : $STEPS"
echo "[0156-perf] threads    : $THREAD_LIST"
echo "[0156-perf] cases      : $CASE_LIST"

if [[ ! -x "$BIN" ]]; then
  echo "Binary '$BIN' not found or not executable. Build first." >&2
  exit 127
fi

python3 scripts/generate_taylor_green_resampling_state_0126.py \
  --output "$STATE" \
  --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" \
  --flow-amplitude "$U0" --kBT "$KBT" --seed "$SEED" >/dev/null

write_params() {
  local label=$1
  local threads=$2
  local projection=$3
  local resampling=$4
  local out_dir="$RUN_ROOT/${label}_t${threads}"
  local params_file="$RUN_ROOT/params_${label}_t${threads}.kv"
  mkdir -p "$out_dir"
  cat > "$params_file" <<PARAMS
inputState = $STATE
outputDir = $out_dir

Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY

dt = $DT
nSteps = $STEPS

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $SEED

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
taylorGreenForcingAmplitude = 0.0

bcX = periodic
bcY = periodic

projectionEnable = $projection
projectionOperator = periodic_fv_cg
projectionMaxIterations = 300
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $KBT

summaryEvery = $SUMMARY_EVERY
dumpStateEvery = 0
numThreads = $threads

resamplingEnable = $resampling
PARAMS
  if [[ "$resampling" == "true" ]]; then
    cat >> "$params_file" <<PARAMS
resamplingTargetCellMass = $GAMMA
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = 0.75
resamplingRichCellMassFraction = 1.25
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = 10
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = 0.25
resamplingParticleMassMax = 4.0
resamplingLatentActivationEnable = false
PARAMS
  fi
  echo "$params_file"
}

printf 'case,threads,elapsed_s,user_s,sys_s,final_wall_s,q6_iterations,resamp_m_rel_rms,resamp_transfer_pairs,resamp_selected_particles\n' > "$CSV"

for label in $CASE_LIST; do
  for threads in $THREAD_LIST; do
    projection=false
    resampling=false
    case "$label" in
      classic) projection=false; resampling=false ;;
      q6) projection=true; resampling=false ;;
      q6_resampling) projection=true; resampling=true ;;
      *) echo "Unknown case '$label'" >&2; exit 2 ;;
    esac
    params_file=$(write_params "$label" "$threads" "$projection" "$resampling")
    log="$RUN_ROOT/${label}_t${threads}.log"
    timelog="$RUN_ROOT/${label}_t${threads}.time"
    echo "[0156-perf] running $label threads=$threads"
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params_file" > "$log" 2> "$timelog"
    elapsed=$(awk -F'[ =]' '/elapsed=/{print $2}' "$timelog")
    user=$(awk -F'[ =]' '/elapsed=/{print $4}' "$timelog")
    sys=$(awk -F'[ =]' '/elapsed=/{print $6}' "$timelog")
    final_wall=$(python3 - "$RUN_ROOT/${label}_t${threads}/summary_runtime.csv" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
row=rows[-1] if rows else {}
print(row.get('wallTime',''))
PY
)
    q6it=$(python3 - "$RUN_ROOT/${label}_t${threads}/summary_runtime.csv" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
row=rows[-1] if rows else {}
print(row.get('q6Iterations',''))
PY
)
    mrel=$(python3 - "$RUN_ROOT/${label}_t${threads}/summary_runtime.csv" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
row=rows[-1] if rows else {}
print(row.get('resampMRelRms',''))
PY
)
    pairs=$(python3 - "$RUN_ROOT/${label}_t${threads}/summary_runtime.csv" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
row=rows[-1] if rows else {}
print(row.get('resampTransferPairs',''))
PY
)
    selected=$(python3 - "$RUN_ROOT/${label}_t${threads}/summary_runtime.csv" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
row=rows[-1] if rows else {}
print(row.get('resampSelectedDonorParticles',''))
PY
)
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$label" "$threads" "$elapsed" "$user" "$sys" "$final_wall" "$q6it" "$mrel" "$pairs" "$selected" >> "$CSV"
  done
done

echo "[0156-perf] wrote $CSV"
