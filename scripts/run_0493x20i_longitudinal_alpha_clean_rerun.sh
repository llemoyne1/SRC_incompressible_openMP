#!/usr/bin/env bash
# 0493x20i — clean rerun of x20f longitudinal alpha branches only.
# Purpose: replace contaminated x20f alpha30/alpha175 runs with a fresh,
# non-reusing campaign while preserving the original x20f tree for forensics.
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ ! -f "$ROOT/scripts/src_mpcd_run_common_0434.sh" ]]; then
  ROOT="${ROOT_OVERRIDE:-$PWD}"
fi
[[ -f "$ROOT/scripts/src_mpcd_run_common_0434.sh" ]] || {
  echo "[x20i] ERROR repository root not found; run from SRC_GPU-SURF or set ROOT=/path/to/SRC_GPU-SURF" >&2
  exit 2
}
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL=longitudinal_alpha_clean_rerun_0493x20i
RUN_ROOT="${RUN_ROOT:-runs/0493x20i_longitudinal_alpha_clean}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"
CLEAN_ROOT="${CLEAN_ROOT:-1}"
CONTINUE_ON_FAILURE="${CONTINUE_ON_FAILURE:-0}"

CELL_SIZE=0.00390625
KBT=0.125
MASS=1.0
CS_REF="${CS_REF:-0.35512}"
NX_NOM="${NX_NOM:-64}"
NY_NOM="${NY_NOM:-16}"
MODE_X="${MODE_X:-1}"
MACH="${MACH:-0.10}"
SEEDS="${SEEDS:-4938601,4938602,4938603}"
ACOUSTIC_CYCLES="${ACOUSTIC_CYCLES:-3.4}"
SRC_DUMP_TARGET="${SRC_DUMP_TARGET:-120}"
CLOSURE_DUMP_EVERY="${CLOSURE_DUMP_EVERY:-2}"

usage(){ cat <<'USAGE'
0493x20i — clean longitudinal alpha rerun (30/175 deg only)

Usage:
  bash scripts/run_0493x20i_longitudinal_alpha_clean_rerun.sh --preflight
  bash scripts/run_0493x20i_longitudinal_alpha_clean_rerun.sh --run
  bash scripts/run_0493x20i_longitudinal_alpha_clean_rerun.sh --analyze
  bash scripts/run_0493x20i_longitudinal_alpha_clean_rerun.sh --status

Science matrix: alpha=30,175 deg x SRC/closure x 3 paired seeds = 12 runs.
No x20f directory is modified. --run defaults to CLEAN_ROOT=1 for this dedicated
replacement campaign, so stale outputs cannot be silently reused.
USAGE
}
ACTION="${1:---run}"
case "$ACTION" in
  --preflight|--run|--analyze|--status) ;;
  -h|--help) usage; exit 0 ;;
  *) echo "[x20i] ERROR bad action $ACTION" >&2; usage >&2; exit 2 ;;
esac

for dep in \
  scripts/src_mpcd_run_common_0434.sh \
  scripts/generate_0493x13e_longitudinal_velocity_state.py \
  scripts/analyze_0493x20i_longitudinal_alpha_clean.py; do
  [[ -f "$dep" ]] || { echo "[x20i] ERROR missing $dep" >&2; exit 2; }
done

if [[ "$ACTION" == --run && "$CLEAN_ROOT" == 1 ]]; then
  rm -rf "$RUN_ROOT"
fi
mkdir -p "$RUN_ROOT/audit"
manifest="$RUN_ROOT/manifest_0493x20i.csv"

python3 - "$manifest" "$CELL_SIZE" "$KBT" "$MASS" "$CS_REF" "$NX_NOM" "$NY_NOM" "$MODE_X" "$MACH" "$SEEDS" "$ACOUSTIC_CYCLES" "$SRC_DUMP_TARGET" "$CLOSURE_DUMP_EVERY" <<'PY'
import csv,math,sys
(out,h,kbt,mass,cs,nx,ny,mode,mach,seeds,cycles,src_target,closure_dump)=sys.argv[1:]
h=float(h);kbt=float(kbt);mass=float(mass);cs=float(cs);nx=int(nx);ny=int(ny);mode=int(mode);mach=float(mach);cycles=float(cycles);src_target=int(src_target);closure_dump=int(closure_dump)
seedv=[int(x) for x in seeds.split(',') if x.strip()]
cases=[
 dict(case_id='alpha30',sweep='alpha_deg',x=30.0,ell=0.5744768837780632,gamma=8,alpha=30.0,rad=math.radians(30.0),dt=0.0063471328149122585),
 dict(case_id='alpha175',sweep='alpha_deg',x=175.0,ell=0.5744768837780632,gamma=8,alpha=175.0,rad=math.radians(175.0),dt=0.0063471328149122585),
]
Lx=nx*h;Ly=ny*h;period=Lx/(cs*mode);T=cycles*period;U=mach*cs
rows=[]
for c in cases:
    steps=math.ceil(T/c['dt']); src_dump=max(1,round(steps/src_target))
    for model in ('src','src-q6-g-f'):
        dump=src_dump if model=='src' else closure_dump
        summary=dump if model=='src' else 1
        for seed in seedv:
            mtag='SRC' if model=='src' else 'closure'
            run=f"map/{c['case_id']}/{mtag}/seed{seed}"
            rows.append(dict(model=model,case=c['case_id'],case_id=c['case_id'],sweep=c['sweep'],x=c['x'],ell=c['ell'],gamma=c['gamma'],alpha_SRC_deg=c['alpha'],rotationAngleRad=c['rad'],h=h,dt=c['dt'],kBT=kbt,m=mass,Nx=nx,Ny=ny,Lx=Lx,Ly=Ly,modeX=mode,k=2*math.pi*mode/Lx,wavelength=Lx,mach=mach,U0=U,csReference=cs,acousticCycles=cycles,steps=steps,dumpEvery=dump,summaryEvery=summary,physicalTime=steps*c['dt'],seed=seed,runDir=run))
with open(out,'w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
print(f'[x20i] manifest={out} runs={len(rows)} U0={U:.9g} T_target={T:.9g}')
for c in cases:
    print(f"[x20i] case={c['case_id']} alpha={c['alpha']:g} rad={c['rad']:.17g} steps={math.ceil(T/c['dt'])}")
PY

if [[ "$ACTION" == --status ]]; then
  total=0; done=0; failed=0
  while IFS=, read -r model case case_id sweep x ell gamma deg rad h dt kbt mass nx ny lx ly mode k wave mach U cs cycles steps dump summary T seed runDir; do
    [[ "$model" == model ]] && continue
    total=$((total+1))
    [[ -f "$RUN_ROOT/$runDir/RUN_COMPLETE_0493x20i" ]] && done=$((done+1))
    [[ -f "$RUN_ROOT/$runDir/RUN_FAILED_0493x20i" ]] && failed=$((failed+1))
  done < "$manifest"
  echo "[x20i-status] complete=$done/$total failed=$failed"
  [[ -f "$RUN_ROOT/audit/angle_separation.txt" ]] && cat "$RUN_ROOT/audit/angle_separation.txt"
  [[ -f "$RUN_ROOT/analysis/longitudinal_map_aggregated.csv" ]] && cat "$RUN_ROOT/analysis/longitudinal_map_aggregated.csv"
  exit 0
fi

if [[ "$ACTION" == --analyze ]]; then
  python3 scripts/analyze_0493x20i_longitudinal_alpha_clean.py --campaign-root "$RUN_ROOT" --repo-root "$ROOT"
  exit 0
fi

export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS
INACTIVE_SLOTS=0; SUMMARY_ROLE_FILTER=fluid; DUMP_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false; RESAMPLING_MASS_GUARD_ENABLE=false
PROJECTION_BACKEND=cuda; PROJECTION_OPERATOR=auto_fv_cg; PROJECTION_MAX_ITERATIONS=2500; PROJECTION_TOLERANCE=1e-5
PROJECTION_MOMENTUM_CORRECTION_ENABLE=false; Q6_PROJECTION_STRENGTH=1.0
Q6_GF_DENSITY_RELAXATION_TIME=0.25; Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3; Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6; Q6_GF_DENSITY_TRACTION_GAIN=1.0
Q6_GF_MIN_FILL_FRACTION=0.10; Q6_GF_HAS_GAS_PHASE=0; Q6_GF_EXTERNAL_SPECIES=0
LIVE_VIS_ENABLE=0; FILTERED_RECORDING_ENABLE=0; RECORD_ENABLE=false; PARTICLE_TYPE_FILTER=-1

NX="$NX_NOM"; NY="$NY_NOM"; GAMMA=8; DT=0.0063471328149122585; PARTICLE_MASS="$MASS"
ROTATION_ANGLE=2.0943951023931953; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3; SEED=4938601
Lx="$(awk -v n="$NX_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
Ly="$(awk -v n="$NY_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
SUMMARY_EVERY=1; DUMP_STATE_EVERY=1
suite_defaults_common_0434
suite_compute_derived_0434

write_params(){
  local model=$1 state=$2 params=$3 outdir=$4 nx=$5 ny=$6 lx=$7 ly=$8 dt=$9 steps=${10} gamma=${11} rad=${12} seed=${13} summary=${14} dump=${15}
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $outdir
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
PARAMS
  if [[ "$model" == src ]]; then
    echo 'speciesRegistryEnable = false' >> "$params"
    echo 'speciesQ6Enable = false' >> "$params"
  fi
  GAMMA="$gamma" NX="$nx" NY="$ny" Lx="$lx" Ly="$ly" DT="$dt" KBT="$KBT" PARTICLE_MASS="$MASS" \
  ROTATION_ANGLE="$rad" RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true THERMOSTAT_ENABLE=true \
  THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT="$KBT" \
  THERMOSTAT_MIN_PARTICLES=3 SEED="$seed" SUMMARY_EVERY="$summary" DUMP_STATE_EVERY="$dump" \
    suite_write_common_params_0434 "$model" >> "$params"
}

prepare(){
  local model=$1 params=$2 nx=$3 ny=$4 lx=$5 ly=$6 gamma=$7 rad=$8 dt=$9 seed=${10} summary=${11} dump=${12}
  # x20i explicitly synchronizes every per-run global before runtime export.
  NX="$nx"; NY="$ny"; Lx="$lx"; Ly="$ly"; GAMMA="$gamma"; ROTATION_ANGLE="$rad"; DT="$dt"; SEED="$seed"
  KBT="$KBT"; PARTICLE_MASS="$MASS"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
  THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
  THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3; SUMMARY_EVERY="$summary"; DUMP_STATE_EVERY="$dump"
  suite_export_cuda_flags_0434 "$model" periodic
  if [[ "$model" == src-q6-g-f ]]; then
    export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
    export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  fi
  suite_preflight_run_ok_0492 "$params"
}

run_case(){
  local model=$1 case_id=$2 ell=$3 gamma=$4 deg=$5 rad=$6 dt=$7 seed=$8 steps=$9 dump=${10} summary=${11} runDir=${12} execute=${13}
  local dir="$RUN_ROOT/$runDir" marker="$RUN_ROOT/$runDir/RUN_COMPLETE_0493x20i" fail="$RUN_ROOT/$runDir/RUN_FAILED_0493x20i"
  if [[ "$execute" == 1 ]]; then
    # Dedicated clean campaign: never accept prior scientific payload silently.
    rm -rf "$dir"
  fi
  mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params" "$dir/audit"
  local lx ly U state meta params
  lx="$(awk -v n="$NX_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
  ly="$(awk -v n="$NY_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
  U="$(awk -v ma="$MACH" -v c="$CS_REF" 'BEGIN{printf "%.17g",ma*c}')"
  state="$dir/init/longitudinal_0493x20i.smpcd"
  meta="$dir/init/longitudinal_0493x20i.meta.json"
  params="$dir/params/params_0493x20i.kv"
  python3 scripts/generate_0493x13e_longitudinal_velocity_state.py \
    --output "$state" --metadata "$meta" --Lx "$lx" --Ly "$ly" --Nx "$NX_NOM" --Ny "$NY_NOM" \
    --gamma "$gamma" --kBT "$KBT" --mass "$MASS" --seed "$seed" --mode-x "$MODE_X" \
    --amplitude "$U" --mach-requested "$MACH" --sound-speed-reference "$CS_REF"
  write_params "$model" "$state" "$params" "$dir/output" "$NX_NOM" "$NY_NOM" "$lx" "$ly" "$dt" "$steps" "$gamma" "$rad" "$seed" "$summary" "$dump"
  prepare "$model" "$params" "$NX_NOM" "$NY_NOM" "$lx" "$ly" "$gamma" "$rad" "$dt" "$seed" "$summary" "$dump"
  {
    echo "case=$case_id"; echo "model=$model"; echo "alphaDeg=$deg"; echo "rotationAngleRad=$rad"; echo "seed=$seed"
    echo "binary=$(readlink -f "$BIN" 2>/dev/null || printf '%s' "$BIN")"
    [[ -f "$BIN" ]] && echo "binarySha256=$(sha256sum "$BIN" | awk '{print $1}')"
    echo "helperSha256=$(sha256sum scripts/src_mpcd_run_common_0434.sh | awk '{print $1}')"
    echo "generatorSha256=$(sha256sum scripts/generate_0493x13e_longitudinal_velocity_state.py | awk '{print $1}')"
    echo "paramsSha256=$(sha256sum "$params" | awk '{print $1}')"
    echo "initialSha256=$(sha256sum "$state" | awk '{print $1}')"
    awk -F= '$1 ~ /^[[:space:]]*(rotationAngle|rngSeed|dt)[[:space:]]*$/ {print}' "$params"
  } > "$dir/audit/provenance.txt"
  echo "[x20i] case=$case_id model=$model alpha=$deg seed=$seed steps=$steps"
  [[ "$execute" == 1 ]] || return 0
  suite_ensure_binary_0434
  rm -f "$marker" "$fail"
  set +e
  /usr/bin/time -o "$dir/logs/time_0493x20i.txt" -f 'elapsed=%e user=%U sys=%S' \
    "$BIN" "$params" 2>&1 | tee "$dir/logs/run_0493x20i.log"
  rc=${PIPESTATUS[0]}
  set -e
  if [[ $rc -ne 0 ]]; then touch "$fail"; return "$rc"; fi
  touch "$marker"
}

if [[ "$ACTION" == --preflight ]]; then
  while IFS=, read -r model case case_id sweep x ell gamma deg rad h dt kbt mass nx ny lx ly mode k wave mach U cs cycles steps dump summary T seed runDir; do
    [[ "$model" == model ]] && continue
    [[ "$seed" == 4938601 ]] || continue
    run_case "$model" "$case_id" "$ell" "$gamma" "$deg" "$rad" "$dt" "$seed" "$steps" "$dump" "$summary" "preflight/$case_id/$model" 0
  done < "$manifest"
  python3 scripts/analyze_0493x20i_longitudinal_alpha_clean.py --self-test
  echo '[x20i] PREFLIGHT PASS'
  exit 0
fi

failed=0
while IFS=, read -r model case case_id sweep x ell gamma deg rad h dt kbt mass nx ny lx ly mode k wave mach U cs cycles steps dump summary T seed runDir; do
  [[ "$model" == model ]] && continue
  set +e
  run_case "$model" "$case_id" "$ell" "$gamma" "$deg" "$rad" "$dt" "$seed" "$steps" "$dump" "$summary" "$runDir" 1
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    failed=$((failed+1))
    [[ "$CONTINUE_ON_FAILURE" == 1 ]] || exit "$rc"
  fi
done < "$manifest"
[[ $failed -eq 0 ]] || { echo "[x20i] ERROR failed solver runs=$failed" >&2; exit 3; }

# Hard scientific guard: at identical seed, SRC alpha30/175 must separate immediately.
python3 - "$RUN_ROOT" "$SEEDS" <<'PY'
import csv,hashlib,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); seeds=[s.strip() for s in sys.argv[2].split(',') if s.strip()]
def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(1<<20),b''): h.update(b)
    return h.hexdigest()
def dumps(d):
    out={}
    for p in pathlib.Path(d).glob('state_step_*.smpcd'):
        m=re.search(r'state_step_(\d+)\.smpcd$',p.name)
        if m: out[int(m.group(1))]=p
    return out
rows=[]; hard_fail=[]
for seed in seeds:
    for modeldir,model in [('SRC','src'),('closure','src-q6-g-f')]:
        d30=dumps(root/'map'/'alpha30'/modeldir/f'seed{seed}'/'output')
        d175=dumps(root/'map'/'alpha175'/modeldir/f'seed{seed}'/'output')
        common=sorted(set(d30)&set(d175)); first=None
        for st in common:
            if sha(d30[st]) != sha(d175[st]): first=st; break
        same_initial=(sha(root/'map'/'alpha30'/modeldir/f'seed{seed}'/'init'/'longitudinal_0493x20i.smpcd') ==
                      sha(root/'map'/'alpha175'/modeldir/f'seed{seed}'/'init'/'longitudinal_0493x20i.smpcd'))
        rows.append(dict(seed=seed,model=model,initialIdentical='YES' if same_initial else 'NO',firstDifferentStep=first if first is not None else 'NONE',commonDumpCount=len(common)))
        if model=='src' and (not same_initial or first is None): hard_fail.append((seed,same_initial,first))
a=root/'audit'; a.mkdir(exist_ok=True)
with open(a/'angle_separation.csv','w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
lines=['===== 0493x20i ANGLE SEPARATION GUARD =====']
for r in rows: lines.append(' '.join(f'{k}={v}' for k,v in r.items()))
if hard_fail:
    lines += ['', 'VERDICT=FAIL_ANGLE_SEPARATION', f'hardFailures={hard_fail!r}']
else:
    lines += ['', 'VERDICT=PASS_ANGLE_SEPARATION', 'impact=All paired SRC initial states are identical and alpha30/alpha175 trajectories separate in saved output for every seed.']
(a/'angle_separation.txt').write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))
if hard_fail: raise SystemExit(4)
PY

python3 scripts/analyze_0493x20i_longitudinal_alpha_clean.py --campaign-root "$RUN_ROOT" --repo-root "$ROOT"
{
  echo "runnerSha256=$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
  echo "binarySha256=$(sha256sum "$BIN" | awk '{print $1}')"
  echo "helperSha256=$(sha256sum scripts/src_mpcd_run_common_0434.sh | awk '{print $1}')"
  echo "generatorSha256=$(sha256sum scripts/generate_0493x13e_longitudinal_velocity_state.py | awk '{print $1}')"
  echo "analyzerSha256=$(sha256sum scripts/analyze_0493x20i_longitudinal_alpha_clean.py | awk '{print $1}')"
} > "$RUN_ROOT/audit/campaign_provenance.txt"
touch "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x20i"
echo "[x20i] COMPLETE runs=12 root=$RUN_ROOT"
echo "[x20i] separation=$RUN_ROOT/audit/angle_separation.txt"
echo "[x20i] analysis=$RUN_ROOT/analysis/longitudinal_map_aggregated.csv"
