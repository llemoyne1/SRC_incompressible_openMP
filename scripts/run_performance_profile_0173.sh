#!/usr/bin/env bash
set -euo pipefail

# 0173 — post-guard deposit profiling probe.
# Requires an executable built from the validated 0171 mutation-profile baseline plus this 0173 post-thermal refresh patch.
# Outputs:
#   RUN_ROOT/perf_summary_0173.csv
#   RUN_ROOT/phase_profile_0173.csv
#   RUN_ROOT/phase_profile_top_0173.csv
#   RUN_ROOT/q6_cg_profile_0173.csv
#   RUN_ROOT/q6_cg_profile_top_0173.csv

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

BIN=${BIN:-build/src_mpcd_base}
RUN_ROOT=${RUN_ROOT:-runs/performance_profile_0173}
NX=${NX:-64}
NY=${NY:-64}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-500}
DT=${DT:-0.001}
U0=${U0:-0.08}
KBT=${KBT:-0.001}
SEED=${SEED:-1560157}
SUMMARY_EVERY=${SUMMARY_EVERY:-$STEPS}
THREAD_LIST=${THREAD_LIST:-1 2 4 8}
CASE_LIST=${CASE_LIST:-classic q6 q6_resampling}

# Common binding defaults for reproducible OpenMP timings. Users may override.
export OMP_PROC_BIND=${OMP_PROC_BIND:-close}
export OMP_PLACES=${OMP_PLACES:-cores}
export OMP_DYNAMIC=${OMP_DYNAMIC:-false}

mkdir -p "$RUN_ROOT"
STATE="$RUN_ROOT/initial_tg_${NX}x${NY}_g${GAMMA}.smpcd"
PERF_CSV="$RUN_ROOT/perf_summary_0173.csv"
PHASE_CSV="$RUN_ROOT/phase_profile_0173.csv"
TOP_CSV="$RUN_ROOT/phase_profile_top_0173.csv"
Q6_CG_CSV="$RUN_ROOT/q6_cg_profile_0173.csv"
Q6_CG_TOP_CSV="$RUN_ROOT/q6_cg_profile_top_0173.csv"
RESAMP_GUARD_CSV="$RUN_ROOT/resampling_guard_profile_0173.csv"
RESAMP_GUARD_TOP_CSV="$RUN_ROOT/resampling_guard_profile_top_0173.csv"
DEPOSIT_CSV="$RUN_ROOT/deposit_profile_0173.csv"
DEPOSIT_TOP_CSV="$RUN_ROOT/deposit_profile_top_0173.csv"
POST_GUARD_CSV="$RUN_ROOT/post_guard_profile_0173.csv"
POST_GUARD_TOP_CSV="$RUN_ROOT/post_guard_profile_top_0173.csv"
PROFILE_SOURCE_TAG=${PROFILE_SOURCE_TAG:-auto}

find_profile_file() {
  local out_dir=$1
  local stem=$2
  local tag
  if [[ "$PROFILE_SOURCE_TAG" != "auto" ]]; then
    local candidate="$out_dir/${stem}_${PROFILE_SOURCE_TAG}.csv"
    [[ -f "$candidate" ]] && { echo "$candidate"; return 0; }
    return 1
  fi
  for tag in 0173 0172 0171 0169 0168 0166 0165 0163 0161 0160 0159 0158 0157; do
    local candidate="$out_dir/${stem}_${tag}.csv"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

cat <<INFO
[0173-profile] root       : $ROOT_DIR
[0173-profile] binary     : $BIN
[0173-profile] run root   : $RUN_ROOT
[0173-profile] grid/gamma : ${NX}x${NY} / $GAMMA
[0173-profile] steps      : $STEPS
[0173-profile] threads    : $THREAD_LIST
[0173-profile] cases      : $CASE_LIST
[0173-profile] profile tag: $PROFILE_SOURCE_TAG
INFO

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

printf 'case,threads,elapsed_s,user_s,sys_s,final_wall_s,q6_iterations,resamp_m_rel_rms,resamp_transfer_pairs,resamp_selected_particles\n' > "$PERF_CSV"
printf 'case,threads,phase,total_s,ms_per_step,percent_total\n' > "$PHASE_CSV"
printf 'case,threads,group,phase,total_s,ms_per_q6_step,percent_group_total\n' > "$Q6_CG_CSV"
printf 'case,threads,group,phase,total_s,ms_per_guard_step,percent_group_total\n' > "$RESAMP_GUARD_CSV"
printf 'case,threads,context,phase,total_s,ms_per_call,percent_context_total,calls,particles_visited,fluid_particles,cells\n' > "$DEPOSIT_CSV"
printf 'case,threads,group,phase,total_s,ms_per_call,percent_group_total,calls,value_total,value_per_call\n' > "$POST_GUARD_CSV"

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
    out_dir="$RUN_ROOT/${label}_t${threads}"
    log="$RUN_ROOT/${label}_t${threads}.log"
    timelog="$RUN_ROOT/${label}_t${threads}.time"
    echo "[0173-profile] running $label threads=$threads"
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params_file" > "$log" 2> "$timelog"
    elapsed=$(awk -F'[ =]' '/elapsed=/{print $2}' "$timelog")
    user=$(awk -F'[ =]' '/elapsed=/{print $4}' "$timelog")
    sys=$(awk -F'[ =]' '/elapsed=/{print $6}' "$timelog")
    final_wall=$(python3 - "$out_dir/summary_runtime.csv" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
row=rows[-1] if rows else {}
print(row.get('wallTime',''))
PY
)
    q6it=$(python3 - "$out_dir/summary_runtime.csv" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
row=rows[-1] if rows else {}
print(row.get('q6Iterations',''))
PY
)
    mrel=$(python3 - "$out_dir/summary_runtime.csv" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
row=rows[-1] if rows else {}
print(row.get('resampMRelRms',''))
PY
)
    pairs=$(python3 - "$out_dir/summary_runtime.csv" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
row=rows[-1] if rows else {}
print(row.get('resampTransferPairs',''))
PY
)
    selected=$(python3 - "$out_dir/summary_runtime.csv" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
row=rows[-1] if rows else {}
print(row.get('resampSelectedDonorParticles',''))
PY
)
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$label" "$threads" "$elapsed" "$user" "$sys" "$final_wall" "$q6it" "$mrel" "$pairs" "$selected" >> "$PERF_CSV"

    phase_src=""
    if phase_src=$(find_profile_file "$out_dir" "phase_profile"); then
      cp "$phase_src" "$out_dir/phase_profile_0173.csv"
      awk -F',' -v label="$label" -v threads="$threads" 'NR>1 {print label "," threads "," $0}' \
        "$phase_src" >> "$PHASE_CSV"
    else
      echo "[warn] Missing phase profile in $out_dir for tags 0173/0172/0171/0169/0168/0166/0165/0163/0161/0160/0159/0158/0157" >&2
    fi

    q6cg_src=""
    if q6cg_src=$(find_profile_file "$out_dir" "q6_cg_profile"); then
      cp "$q6cg_src" "$out_dir/q6_cg_profile_0173.csv"
      awk -F',' -v label="$label" -v threads="$threads" 'NR>1 {print label "," threads "," $0}' \
        "$q6cg_src" >> "$Q6_CG_CSV"
    else
      echo "[warn] Missing Q6/CG profile in $out_dir for tags 0173/0172/0171/0169/0168/0166/0165/0163/0161/0160/0159/0158/0157" >&2
    fi

    resamp_guard_src=""
    if resamp_guard_src=$(find_profile_file "$out_dir" "resampling_guard_profile"); then
      cp "$resamp_guard_src" "$out_dir/resampling_guard_profile_0173.csv"
      awk -F',' -v label="$label" -v threads="$threads" 'NR>1 {print label "," threads "," $0}' \
        "$resamp_guard_src" >> "$RESAMP_GUARD_CSV"
    else
      echo "[warn] Missing resampling guard profile in $out_dir for tags 0173/0172/0171/0169/0168/0166/0165/0163/0161/0160/0159/0158/0157" >&2
    fi

    deposit_src=""
    if deposit_src=$(find_profile_file "$out_dir" "deposit_profile"); then
      cp "$deposit_src" "$out_dir/deposit_profile_0173.csv"
      awk -F',' -v label="$label" -v threads="$threads" 'NR>1 {print label "," threads "," $0}' \
        "$deposit_src" >> "$DEPOSIT_CSV"
    else
      echo "[warn] Missing deposit profile in $out_dir for available profile tags" >&2
    fi

    post_guard_src=""
    if post_guard_src=$(find_profile_file "$out_dir" "post_guard_profile"); then
      cp "$post_guard_src" "$out_dir/post_guard_profile_0173.csv"
      awk -F',' -v label="$label" -v threads="$threads" 'NR>1 {print label "," threads "," $0}' \
        "$post_guard_src" >> "$POST_GUARD_CSV"
    else
      echo "[warn] Missing post-guard profile in $out_dir for available profile tags" >&2
    fi
  done
done

python3 - "$PHASE_CSV" "$TOP_CSV" <<'PY'
import csv, sys
phase_csv, top_csv = sys.argv[1], sys.argv[2]
rows=[]
with open(phase_csv, newline='') as f:
    for r in csv.DictReader(f):
        if r.get('phase') == 'total_profiled':
            continue
        try:
            r['_percent'] = float(r.get('percent_total','0') or 0.0)
        except ValueError:
            r['_percent'] = 0.0
        rows.append(r)
keys=[]
seen=set()
for r in rows:
    key=(r['case'], r['threads'])
    if key not in seen:
        seen.add(key)
        keys.append(key)
with open(top_csv, 'w', newline='') as f:
    fieldnames=['case','threads','rank','phase','total_s','ms_per_step','percent_total']
    w=csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for key in keys:
        subset=[r for r in rows if (r['case'], r['threads']) == key]
        subset.sort(key=lambda r: r['_percent'], reverse=True)
        for rank, r in enumerate(subset[:12], start=1):
            w.writerow({k: r.get(k,'') for k in fieldnames if k != 'rank'} | {'rank': rank})
PY


python3 - "$Q6_CG_CSV" "$Q6_CG_TOP_CSV" <<'PY'
import csv, sys
q6_csv, top_csv = sys.argv[1], sys.argv[2]
rows=[]
with open(q6_csv, newline='') as f:
    for r in csv.DictReader(f):
        if r.get('phase','').startswith('total_') or r.get('group') == 'metadata':
            continue
        try:
            r['_percent'] = float(r.get('percent_group_total','0') or 0.0)
        except ValueError:
            r['_percent'] = 0.0
        rows.append(r)
keys=[]
seen=set()
for r in rows:
    key=(r['case'], r['threads'], r['group'])
    if key not in seen:
        seen.add(key)
        keys.append(key)
with open(top_csv, 'w', newline='') as f:
    fieldnames=['case','threads','group','rank','phase','total_s','ms_per_q6_step','percent_group_total']
    w=csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for key in keys:
        subset=[r for r in rows if (r['case'], r['threads'], r['group']) == key]
        subset.sort(key=lambda r: r['_percent'], reverse=True)
        for rank, r in enumerate(subset[:14], start=1):
            w.writerow({k: r.get(k,'') for k in fieldnames if k != 'rank'} | {'rank': rank})
PY


python3 - "$RESAMP_GUARD_CSV" "$RESAMP_GUARD_TOP_CSV" <<'PYGUARD'
import csv, sys
guard_csv, top_csv = sys.argv[1], sys.argv[2]
rows=[]
with open(guard_csv, newline='') as f:
    for r in csv.DictReader(f):
        if r.get('phase','').startswith('total_') or r.get('group') == 'metadata':
            continue
        try:
            r['_percent'] = float(r.get('percent_group_total','0') or 0.0)
        except ValueError:
            r['_percent'] = 0.0
        rows.append(r)
keys=[]
seen=set()
for r in rows:
    key=(r['case'], r['threads'], r['group'])
    if key not in seen:
        seen.add(key)
        keys.append(key)
with open(top_csv, 'w', newline='') as f:
    fieldnames=['case','threads','group','rank','phase','total_s','ms_per_guard_step','percent_group_total']
    w=csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for key in keys:
        subset=[r for r in rows if (r['case'], r['threads'], r['group']) == key]
        subset.sort(key=lambda r: r['_percent'], reverse=True)
        for rank, r in enumerate(subset[:12], start=1):
            w.writerow({k: r.get(k,'') for k in fieldnames if k != 'rank'} | {'rank': rank})
PYGUARD


python3 - "$DEPOSIT_CSV" "$DEPOSIT_TOP_CSV" <<'PYDEPOSIT'
import csv, sys
deposit_csv, top_csv = sys.argv[1], sys.argv[2]
rows=[]
with open(deposit_csv, newline='') as f:
    for r in csv.DictReader(f):
        if r.get('phase') == 'total_deposit':
            continue
        try:
            r['_percent'] = float(r.get('percent_context_total','0') or 0.0)
        except ValueError:
            r['_percent'] = 0.0
        rows.append(r)
keys=[]
seen=set()
for r in rows:
    key=(r['case'], r['threads'], r['context'])
    if key not in seen:
        seen.add(key)
        keys.append(key)
with open(top_csv, 'w', newline='') as f:
    fieldnames=['case','threads','context','rank','phase','total_s','ms_per_call','percent_context_total','calls','particles_visited','fluid_particles','cells']
    w=csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for key in keys:
        subset=[r for r in rows if (r['case'], r['threads'], r['context']) == key]
        subset.sort(key=lambda r: r['_percent'], reverse=True)
        for rank, r in enumerate(subset[:12], start=1):
            w.writerow({k: r.get(k,'') for k in fieldnames if k != 'rank'} | {'rank': rank})
PYDEPOSIT


python3 - "$POST_GUARD_CSV" "$POST_GUARD_TOP_CSV" <<'PYPOSTGUARD'
import csv, sys
profile_csv, top_csv = sys.argv[1], sys.argv[2]
rows=[]
with open(profile_csv, newline='') as f:
    for r in csv.DictReader(f):
        if r.get('group') == 'metadata' or r.get('phase','').startswith('total_'):
            continue
        try:
            r['_percent'] = float(r.get('percent_group_total','0') or 0.0)
        except ValueError:
            r['_percent'] = 0.0
        rows.append(r)
keys=[]
seen=set()
for r in rows:
    key=(r['case'], r['threads'], r['group'])
    if key not in seen:
        seen.add(key)
        keys.append(key)
with open(top_csv, 'w', newline='') as f:
    fieldnames=['case','threads','group','rank','phase','total_s','ms_per_call','percent_group_total','calls','value_total','value_per_call']
    w=csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for key in keys:
        subset=[r for r in rows if (r['case'], r['threads'], r['group']) == key]
        subset.sort(key=lambda r: r['_percent'], reverse=True)
        for rank, r in enumerate(subset[:12], start=1):
            w.writerow({k: r.get(k,'') for k in fieldnames if k != 'rank'} | {'rank': rank})
PYPOSTGUARD

echo "[0173-profile] wrote $PERF_CSV"
echo "[0173-profile] wrote $PHASE_CSV"
echo "[0173-profile] wrote $TOP_CSV"
echo "[0173-profile] wrote $Q6_CG_CSV"
echo "[0173-profile] wrote $Q6_CG_TOP_CSV"
echo "[0173-profile] wrote $RESAMP_GUARD_CSV"
echo "[0173-profile] wrote $RESAMP_GUARD_TOP_CSV"
echo "[0173-profile] wrote $DEPOSIT_CSV"
echo "[0173-profile] wrote $DEPOSIT_TOP_CSV"
echo "[0173-profile] wrote $POST_GUARD_CSV"
echo "[0173-profile] wrote $POST_GUARD_TOP_CSV"
