#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434
CASE_LABEL=longitudinal_reduced_map_0493x20f

CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x20f_longitudinal_reduced_map}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
SKIP_EXISTING="${SKIP_EXISTING:-1}"
CONTINUE_ON_FAILURE="${CONTINUE_ON_FAILURE:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"

CELL_SIZE="0.00390625"
KBT="0.125"
MASS="1.0"
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
0493x20f — reduced longitudinal parameter map

Usage:
  bash scripts/run_0493x20f_longitudinal_reduced_map.sh --preflight
  bash scripts/run_0493x20f_longitudinal_reduced_map.sh --run
  bash scripts/run_0493x20f_longitudinal_reduced_map.sh --analyze
  bash scripts/run_0493x20f_longitudinal_reduced_map.sh --status

Five non-nominal representative configurations, one linear amplitude Ma_ref=0.10,
SRC vs production particle/field closure, 3 paired seeds. 30 solver runs total.
Nominal x20e is intentionally not repeated.
USAGE
}
ACTION="${1:---run}"
case "$ACTION" in --preflight|--run|--analyze|--status) ;; -h|--help) usage; exit 0;; *) echo "[x20f] bad action $ACTION" >&2; exit 2;; esac

for dep in scripts/src_mpcd_run_common_0434.sh scripts/generate_0493x13e_longitudinal_velocity_state.py scripts/analyze_0493w1_src_fluid_calibrator.py scripts/analyze_0493x20f_longitudinal_reduced_map.py; do
  [[ -f "$dep" ]] || { echo "[x20f] missing $dep" >&2; exit 2; }
done
mkdir -p "$CAMPAIGN_ROOT"
manifest="$CAMPAIGN_ROOT/manifest_0493x20f.csv"

python3 - "$manifest" "$CELL_SIZE" "$KBT" "$MASS" "$CS_REF" "$NX_NOM" "$NY_NOM" "$MODE_X" "$MACH" "$SEEDS" "$ACOUSTIC_CYCLES" "$SRC_DUMP_TARGET" "$CLOSURE_DUMP_EVERY" <<'PY'
import csv,math,sys
(out,h,kbt,mass,cs,nx,ny,mode,mach,seeds,cycles,src_target,closure_dump)=sys.argv[1:]
h=float(h);kbt=float(kbt);mass=float(mass);cs=float(cs);nx=int(nx);ny=int(ny);mode=int(mode);mach=float(mach);cycles=float(cycles);src_target=int(src_target);closure_dump=int(closure_dump)
seedv=[int(x) for x in seeds.split(',') if x.strip()]
# Exact article points. lambdaMean/h is kept only as internal traceability; ell is article notation.
cases=[
 dict(case_id='ell_low',sweep='ell',x=0.28723844188903158,ell=0.28723844188903158,gamma=8,alpha=120.0,rad=2.0943951023931953,dt=0.0031735664074561292),
 dict(case_id='ell_high',sweep='ell',x=0.7180961047225789,ell=0.7180961047225789,gamma=8,alpha=120.0,rad=2.0943951023931953,dt=0.007933916018640323),
 dict(case_id='gamma6',sweep='gamma',x=6.0,ell=0.5744768837780632,gamma=6,alpha=120.0,rad=2.0943951023931953,dt=0.0063471328149122585),
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
print(f'[x20f] manifest={out} cases={len(cases)} runs={len(rows)} Ma_ref={mach} U0={U:.9g} T_target={T:.9g}')
for c in cases:
  print(f"[x20f] case={c['case_id']:<9} ell={c['ell']:.9g} gamma={c['gamma']} alpha={c['alpha']:g} dt={c['dt']:.9g} steps={math.ceil(T/c['dt'])}")
PY

if [[ "$ACTION" == --status ]]; then
  total=0;done=0;failed=0
  while IFS=, read -r model case case_id sweep x ell gamma deg rad h dt kbt mass nx ny lx ly mode k wave mach U cs cycles steps dump summary T seed runDir; do
    [[ "$model" == model ]] && continue; total=$((total+1))
    [[ -f "$CAMPAIGN_ROOT/$runDir/RUN_COMPLETE_0493x20f" ]] && done=$((done+1))
    [[ -f "$CAMPAIGN_ROOT/$runDir/RUN_FAILED_0493x20f" ]] && failed=$((failed+1))
  done < "$manifest"
  echo "[x20f-status] complete=$done/$total failed=$failed"
  [[ -f "$CAMPAIGN_ROOT/analysis/longitudinal_map_aggregated.csv" ]] && cat "$CAMPAIGN_ROOT/analysis/longitudinal_map_aggregated.csv"
  exit 0
fi
if [[ "$ACTION" == --analyze ]]; then
  python3 scripts/analyze_0493x20f_longitudinal_reduced_map.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT"; exit 0
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

NX="$NX_NOM";NY="$NY_NOM";GAMMA=8;DT=0.0063471328149122585;PARTICLE_MASS="$MASS";ROTATION_ANGLE=2.0943951023931953
RANDOM_ROTATION_SIGN=true;GRID_SHIFT_ENABLE=true;THERMOSTAT_ENABLE=true;THERMOSTAT_MODE=cell_relative_rescale;THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT";THERMOSTAT_MIN_PARTICLES=3;SEED=4938601
Lx="$(awk -v n="$NX_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')";Ly="$(awk -v n="$NY_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
SUMMARY_EVERY=1;DUMP_STATE_EVERY=1
suite_defaults_common_0434;suite_compute_derived_0434

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
 if [[ "$model" == src ]]; then echo 'speciesRegistryEnable = false' >> "$params"; echo 'speciesQ6Enable = false' >> "$params"; fi
 GAMMA="$gamma" NX="$nx" NY="$ny" Lx="$lx" Ly="$ly" DT="$dt" KBT="$KBT" PARTICLE_MASS="$MASS" ROTATION_ANGLE="$rad" RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT="$KBT" THERMOSTAT_MIN_PARTICLES=3 SEED="$seed" SUMMARY_EVERY="$summary" DUMP_STATE_EVERY="$dump" suite_write_common_params_0434 "$model" >> "$params"
}
prepare(){ local model=$1 params=$2 nx=$3 ny=$4 lx=$5 ly=$6 gamma=$7; NX="$nx";NY="$ny";Lx="$lx";Ly="$ly";GAMMA="$gamma";suite_export_cuda_flags_0434 "$model" periodic; if [[ "$model" == src-q6-g-f ]];then export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1 MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0;fi;suite_preflight_run_ok_0492 "$params"; }
run_case(){
 local model=$1 case_id=$2 ell=$3 gamma=$4 deg=$5 rad=$6 dt=$7 seed=$8 steps=$9 dump=${10} summary=${11} runDir=${12} execute=${13}
 local dir="$CAMPAIGN_ROOT/$runDir" marker="$CAMPAIGN_ROOT/$runDir/RUN_COMPLETE_0493x20f" fail="$CAMPAIGN_ROOT/$runDir/RUN_FAILED_0493x20f"
 mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params"
 if [[ "$execute" == 1 && "$SKIP_EXISTING" == 1 && -f "$marker" ]];then echo "[x20f] SKIP $runDir";return 0;fi
 local lx ly U state meta params;lx="$(awk -v n="$NX_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')";ly="$(awk -v n="$NY_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')";U="$(awk -v ma="$MACH" -v c="$CS_REF" 'BEGIN{printf "%.17g",ma*c}')"
 state="$dir/init/longitudinal_0493x20f.smpcd";meta="$dir/init/longitudinal_0493x20f.meta.json";params="$dir/params/params_0493x20f.kv"
 python3 scripts/generate_0493x13e_longitudinal_velocity_state.py --output "$state" --metadata "$meta" --Lx "$lx" --Ly "$ly" --Nx "$NX_NOM" --Ny "$NY_NOM" --gamma "$gamma" --kBT "$KBT" --mass "$MASS" --seed "$seed" --mode-x "$MODE_X" --amplitude "$U" --mach-requested "$MACH" --sound-speed-reference "$CS_REF"
 write_params "$model" "$state" "$params" "$dir/output" "$NX_NOM" "$NY_NOM" "$lx" "$ly" "$dt" "$steps" "$gamma" "$rad" "$seed" "$summary" "$dump";prepare "$model" "$params" "$NX_NOM" "$NY_NOM" "$lx" "$ly" "$gamma"
 echo "[x20f] case=$case_id model=$model ell=$ell gamma=$gamma alpha=$deg seed=$seed steps=$steps"
 [[ "$execute" == 1 ]] || return 0;suite_ensure_binary_0434;rm -f "$marker" "$fail";set +e;/usr/bin/time -o "$dir/logs/time_0493x20f.txt" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" 2>&1 | tee "$dir/logs/run_0493x20f.log";rc=${PIPESTATUS[0]};set -e;if [[ $rc -ne 0 ]];then touch "$fail";return "$rc";fi;touch "$marker"
}

if [[ "$ACTION" == --preflight ]];then
 while IFS=, read -r model case case_id sweep x ell gamma deg rad h dt kbt mass nx ny lx ly mode k wave mach U cs cycles steps dump summary T seed runDir;do
  [[ "$model" == model ]] && continue;[[ "$seed" == 4938601 ]] || continue;run_case "$model" "$case_id" "$ell" "$gamma" "$deg" "$rad" "$dt" "$seed" "$steps" "$dump" "$summary" "preflight/$case_id/$model" 0
 done < "$manifest"
 python3 scripts/analyze_0493x20f_longitudinal_reduced_map.py --self-test;echo '[x20f] PREFLIGHT PASS';exit 0
fi

new=0;failed=0
while IFS=, read -r model case case_id sweep x ell gamma deg rad h dt kbt mass nx ny lx ly mode k wave mach U cs cycles steps dump summary T seed runDir;do
 [[ "$model" == model ]] && continue;before=0;[[ -f "$CAMPAIGN_ROOT/$runDir/RUN_COMPLETE_0493x20f" ]] && before=1;set +e;run_case "$model" "$case_id" "$ell" "$gamma" "$deg" "$rad" "$dt" "$seed" "$steps" "$dump" "$summary" "$runDir" 1;rc=$?;set -e
 if [[ $rc -ne 0 ]];then failed=$((failed+1));[[ "$CONTINUE_ON_FAILURE" == 1 ]] || exit "$rc";elif [[ $before == 0 ]];then new=$((new+1));fi
done < "$manifest"
python3 scripts/analyze_0493x20f_longitudinal_reduced_map.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT"
touch "$CAMPAIGN_ROOT/CAMPAIGN_COMPLETE_0493x20f";echo "[x20f] COMPLETE new=$new failed=$failed"
