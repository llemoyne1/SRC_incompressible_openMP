#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL=src_G08_reproducibility_0493x13g
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x13g_G08_reproducibility}"
RUN_ROOT="$CAMPAIGN_ROOT/H_reproducibility"
ANALYSIS_ROOT="$CAMPAIGN_ROOT/analysis"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"

PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
CLEAN_ROOT="${CLEAN_ROOT:-0}"
SKIP_EXISTING="${SKIP_EXISTING:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"
PREFLIGHT_FIRST_ONLY="${PREFLIGHT_FIRST_ONLY:-1}"

REPEAT_REPS="${REPEAT_REPS:-6}"
REPEAT_SEED="${REPEAT_SEED:-4931411}"
INDEPENDENT_SEEDS="${INDEPENDENT_SEEDS:-4931412,4931413,4931414,4931415,4931416,4931417,4931418}"
SHEAR_NX="${SHEAR_NX:-32}"
SHEAR_NY="${SHEAR_NY:-256}"
SHEAR_AMPLITUDE="${SHEAR_AMPLITUDE:-0.05}"
TARGET_EFOLDS="${TARGET_EFOLDS:-1.4}"
DUMP_COUNT="${DUMP_COUNT:-96}"

GAMMA_FIXED=8
CELL_SIZE="0.00390625"
KBT="0.125"
MASS="1.0"
ALPHA_DEG="120.0"
ALPHA_RAD="2.0943951023931953"
LAMBDA_LIST="${LAMBDA_LIST:-0.48,0.72}"

for dep in \
  scripts/generate_0493x13b_shear_state.py \
  scripts/analyze_0493x13b_constitutive_transport.py \
  scripts/analyze_0493x13g_H_reproducibility.py; do
  [[ -f "$dep" ]] || { echo "[0493x13g] missing dependency $dep" >&2; exit 2; }
done

if [[ "$ANALYZE_ONLY" == 1 ]]; then
  python3 scripts/analyze_0493x13g_H_reproducibility.py \
    --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT"
  exit 0
fi

[[ "$CLEAN_ROOT" == 1 ]] && rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/shared_init" "$RUN_ROOT/audit" "$ANALYSIS_ROOT"
rm -f "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13g_Hrepro"

NX="$SHEAR_NX"; NY="$SHEAR_NY"; GAMMA="$GAMMA_FIXED"; DT=.004231421876608172
PARTICLE_MASS="$MASS"; ROTATION_ANGLE="$ALPHA_RAD"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3; SEED="$REPEAT_SEED"

export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS
INACTIVE_SLOTS=0; SUMMARY_ROLE_FILTER=fluid; DUMP_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false; RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false; PROJECTION_BACKEND=cuda; PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=100; PROJECTION_TOLERANCE=1e-12
PROJECTION_MOMENTUM_CORRECTION_ENABLE=true; Q6_PROJECTION_STRENGTH=1.0
LIVE_VIS_ENABLE=0; FILTERED_RECORDING_ENABLE=0; RECORD_ENABLE=false; PARTICLE_TYPE_FILTER=-1
suite_defaults_common_0434
suite_compute_derived_0434
[[ "$PREFLIGHT_ONLY" == 1 ]] || suite_ensure_binary_0434

sha_file() { sha256sum "$1" | awk '{print $1}'; }
BINARY_SHA="MISSING"
[[ -f "$BIN" ]] && BINARY_SHA="$(sha_file "$BIN")"
GIT_HEAD="$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
GIT_BRANCH="$(git branch --show-current 2>/dev/null || echo UNKNOWN)"
SRC_INCLUDE_TREE_SHA="$( (find src include -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null || true) | sha256sum | awk '{print $1}')"
{
  echo "campaign=0493x13g_G08_reproducibility"
  echo "createdUtc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "gitHead=$GIT_HEAD"
  echo "gitBranch=$GIT_BRANCH"
  echo "binary=$BIN"
  echo "binarySha256=$BINARY_SHA"
  echo "srcIncludeTreeSha256=$SRC_INCLUDE_TREE_SHA"
  echo "repeatReps=$REPEAT_REPS"
  echo "repeatSeed=$REPEAT_SEED"
  echo "independentSeeds=$INDEPENDENT_SEEDS"
  echo "lambdaOverH=$LAMBDA_LIST"
} > "$RUN_ROOT/audit/environment_0493x13g.txt"

manifest="$RUN_ROOT/manifest_0493x13g_Hrepro.csv"
python3 - "$manifest" "$LAMBDA_LIST" "$REPEAT_REPS" "$REPEAT_SEED" "$INDEPENDENT_SEEDS" "$SHEAR_NX" "$SHEAR_NY" "$CELL_SIZE" "$KBT" "$MASS" "$SHEAR_AMPLITUDE" "$TARGET_EFOLDS" "$DUMP_COUNT" <<'PY'
import csv,math,sys
out,lams,nrep,rseed,iseeds,nx,ny,h,kbt,mass,amp,efolds,dumps=sys.argv[1:]
nrep=int(nrep);rseed=int(rseed);nx=int(nx);ny=int(ny);h=float(h);kbt=float(kbt);mass=float(mass);amp=float(amp);efolds=float(efolds);dumps=int(dumps)
LAM=[float(x) for x in lams.split(',') if x.strip()]
ISEED=[int(x) for x in iseeds.split(',') if x.strip()]
gamma=8;alpha=120.0;rad=math.radians(alpha);vmean=math.sqrt(math.pi*kbt/(2*mass));fg=(gamma-1+math.exp(-gamma))/gamma;q=fg*(1-math.cos(rad));rows=[];seq=0

def add(lam,track,rep,state_seed,runtime_seed):
    global seq
    dt=lam*h/vmean;nu=kbt*dt/mass*(1/q-.5)+h*h*q/(12*dt);Lx=nx*h;Ly=ny*h;k=2*math.pi/Ly;T=efolds/(nu*k*k);steps=math.ceil(T/dt);dump=max(1,math.ceil(steps/dumps));seq+=1
    key=f'A120_L{int(round(lam*100)):03d}'
    rows.append(dict(sequence=seq,candidate=key,track=track,replicateIndex=rep,stateSeed=state_seed,runtimeSeed=runtime_seed,gamma=gamma,rotationAngleDeg=alpha,rotationAngleRad=rad,targetLambdaMeanOverCell=lam,dt=dt,cellSize=h,lambdaPhysical=lam*h,viscositySRDKinematic=nu,Nx=nx,Ny=ny,Lx=Lx,Ly=Ly,wavelengthCells=ny,modeY=1,amplitude=amp,steps=steps,dumpEvery=dump,physicalTime=steps*dt,targetEfolds=efolds,kLambda=k*lam*h,runDir=f'{track}/{key}/rep{rep:02d}_seed{runtime_seed}',estimatedParticleSteps=nx*ny*gamma*steps))

# Interleave the two parameter points within each replicate/seed to reduce temporal drift.
for rep in range(nrep):
    for lam in LAM:add(lam,'repeat_same',rep,rseed,rseed)
for j,seed in enumerate(ISEED,1):
    for lam in LAM:add(lam,'independent',j,seed,seed)
with open(out,'w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
print(f'[0493x13g] manifest actualRuns={len(rows)} repeat={nrep*len(LAM)} independentNew={len(ISEED)*len(LAM)} particleSteps={sum(int(r["estimatedParticleSteps"]) for r in rows)}')
PY

# Generate one byte-identical shared initial state per parameter point for the repeat track.
python3 - "$manifest" "$RUN_ROOT/shared_init" "$ROOT" "$REPEAT_SEED" <<'PY'
import csv,subprocess,sys
from pathlib import Path
manifest,shared,root,rseed=sys.argv[1:];shared=Path(shared);root=Path(root);rseed=int(rseed)
rows=list(csv.DictReader(open(manifest,newline='')))
seen=set()
for r in rows:
    if r['track']!='repeat_same' or r['candidate'] in seen: continue
    seen.add(r['candidate']);out=shared/f"{r['candidate']}_seed{rseed}.smpcd"
    cmd=['python3',str(root/'scripts/generate_0493x13b_shear_state.py'),'--output',str(out),'--Lx',r['Lx'],'--Ly',r['Ly'],'--Nx',r['Nx'],'--Ny',r['Ny'],'--gamma',r['gamma'],'--kBT','0.125','--mass','1.0','--seed',str(rseed),'--mode-y',r['modeY'],'--amplitude',r['amplitude']]
    subprocess.run(cmd,check=True)
PY

audit_csv="$RUN_ROOT/audit/run_audit_0493x13g.csv"
if [[ ! -f "$audit_csv" ]]; then
  echo 'sequence,candidate,track,replicateIndex,stateSeed,runtimeSeed,startUtc,endUtc,exitCode,binarySha256,stateSha256' > "$audit_csv"
fi

runs_done=0; runs_skipped=0; preflight_done=0
while IFS=, read -r sequence candidate track rep stateSeed runtimeSeed gamma deg rad lam dt h lamphys nuSrd nx ny lx ly wc mode amp steps dump T efolds klambda runDir particleSteps; do
  [[ "$sequence" == sequence ]] && continue
  if [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_ONLY" == 1 ]]; then
    # One repeat and one independent preflight per candidate.
    if [[ "$track" == repeat_same && "$rep" != 0 ]]; then continue; fi
    if [[ "$track" == independent && "$rep" != 1 ]]; then continue; fi
  fi
  dir="$RUN_ROOT/$runDir"; marker="$dir/RUN_COMPLETE_0493x13g_Hrepro"
  if [[ "$PREFLIGHT_ONLY" != 1 && "$SKIP_EXISTING" == 1 && -f "$marker" ]]; then
    echo "[0493x13g] SKIP $candidate $track rep=$rep seed=$runtimeSeed";runs_skipped=$((runs_skipped+1));continue
  fi
  mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params"
  if [[ "$track" == repeat_same ]]; then
    state="$RUN_ROOT/shared_init/${candidate}_seed${REPEAT_SEED}.smpcd"
  else
    state="$dir/init/shear_0493x13g.smpcd"
    python3 scripts/generate_0493x13b_shear_state.py --output "$state" --Lx "$lx" --Ly "$ly" --Nx "$nx" --Ny "$ny" --gamma "$gamma" --kBT "$KBT" --mass "$MASS" --seed "$stateSeed" --mode-y "$mode" --amplitude "$amp"
  fi
  state_sha="$(sha_file "$state")"
  if [[ "$PREFLIGHT_ONLY" != 1 && "$BINARY_SHA" != MISSING ]]; then
    now_sha="$(sha_file "$BIN")"
    [[ "$now_sha" == "$BINARY_SHA" ]] || { echo "[0493x13g] ERROR binary changed during campaign: $BINARY_SHA -> $now_sha" >&2;exit 3; }
  fi
  SUMMARY_EVERY="$dump";DUMP_STATE_EVERY="$dump"
  cat > "$dir/params/params_0493x13g.kv" <<PARAMS
inputState = $state
outputDir = $dir/output
Lx = $lx
Ly = $ly
Nx = $nx
Ny = $ny
dt = $dt
nSteps = $steps
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
keepMeanFlowEnable = false
taylorGreenForcingEnable = false
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
speciesRegistryEnable = false
speciesQ6Enable = false
PARAMS
  GAMMA="$gamma" DT="$dt" KBT="$KBT" PARTICLE_MASS="$MASS" ROTATION_ANGLE="$rad" RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT="$KBT" THERMOSTAT_MIN_PARTICLES=3 SEED="$runtimeSeed" suite_write_common_params_0434 src >> "$dir/params/params_0493x13g.kv"
  suite_export_cuda_flags_0434 src periodic
  suite_preflight_run_ok_0492 "$dir/params/params_0493x13g.kv"
  echo "[0493x13g] seq=$sequence candidate=$candidate track=$track rep=$rep stateSeed=$stateSeed runtimeSeed=$runtimeSeed lambda/h=$lam steps=$steps"
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then preflight_done=$((preflight_done+1));continue;fi
  start_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)";rm -f "$marker";set +e
  /usr/bin/time -o "$dir/logs/time_0493x13g.txt" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$dir/params/params_0493x13g.kv" 2>&1 | tee "$dir/logs/run_0493x13g.log"
  rc=${PIPESTATUS[0]};set -e;end_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$sequence" "$candidate" "$track" "$rep" "$stateSeed" "$runtimeSeed" "$start_utc" "$end_utc" "$rc" "$BINARY_SHA" "$state_sha" >> "$audit_csv"
  [[ $rc -eq 0 ]] || exit "$rc"
  touch "$marker";runs_done=$((runs_done+1))
done < "$manifest"

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  echo "[0493x13g] PREFLIGHT PASS checked=$preflight_done"
  exit 0
fi
python3 scripts/analyze_0493x13g_H_reproducibility.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT"
touch "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13g_Hrepro"
echo "[0493x13g] CAMPAIGN COMPLETE new=$runs_done skipped=$runs_skipped"
