#!/usr/bin/env bash
# 0493x20j — final alpha=175 deg long-wave longitudinal qualification.
# Stage 1: SRC only at Nx=128, Ny=16, modeX=1, Ma=0.10, 3 paired seeds.
# Stage 2: closure runs only if SRC resolves a propagative mode with c within 10% of c_ref.
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [[ ! -f "$ROOT/scripts/src_mpcd_run_common_0434.sh" ]]; then
  ROOT="${ROOT_OVERRIDE:-$PWD}"
fi
[[ -f "$ROOT/scripts/src_mpcd_run_common_0434.sh" ]] || {
  echo "[x20j] ERROR repository root not found; run from SRC_GPU-SURF or set ROOT=/path/to/SRC_GPU-SURF" >&2
  exit 2
}
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL=longitudinal_alpha175_longwave_0493x20j
RUN_ROOT="${RUN_ROOT:-runs/0493x20j_longitudinal_alpha175_longwave}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"
CONTINUE_ON_FAILURE="${CONTINUE_ON_FAILURE:-0}"

CELL_SIZE="${CELL_SIZE:-0.00390625}"
KBT="${KBT:-0.125}"
MASS="${MASS:-1.0}"
CS_REF="${CS_REF:-0.35512}"
NX_LONG="${NX_LONG:-128}"
NY_LONG="${NY_LONG:-16}"
MODE_X="${MODE_X:-1}"
MACH="${MACH:-0.10}"
ALPHA_DEG="${ALPHA_DEG:-175.0}"
GAMMA_LONG="${GAMMA_LONG:-8}"
DT_LONG="${DT_LONG:-0.0063471328149122585}"
SEEDS="${SEEDS:-4938601,4938602,4938603}"
ACOUSTIC_CYCLES="${ACOUSTIC_CYCLES:-3.4}"
SRC_DUMP_TARGET="${SRC_DUMP_TARGET:-120}"
CLOSURE_DUMP_EVERY="${CLOSURE_DUMP_EVERY:-4}"
SRC_C_REL_TOL="${SRC_C_REL_TOL:-0.10}"

usage(){ cat <<'USAGE'
0493x20j — alpha=175 deg long-wave longitudinal qualification

Usage:
  bash scripts/run_0493x20j_longitudinal_alpha175_longwave.sh --preflight
  bash scripts/run_0493x20j_longitudinal_alpha175_longwave.sh --src
  bash scripts/run_0493x20j_longitudinal_alpha175_longwave.sh --closure
  bash scripts/run_0493x20j_longitudinal_alpha175_longwave.sh --run
  bash scripts/run_0493x20j_longitudinal_alpha175_longwave.sh --analyze
  bash scripts/run_0493x20j_longitudinal_alpha175_longwave.sh --status

Default science point:
  alpha=175 deg, gamma=8, h=1/256, dt=0.0063471328149122585,
  Nx=128, Ny=16, modeX=1, Ma=0.10, seeds=4938601..4938603.

--run is sequential and economical:
  1) clean dedicated x20j root;
  2) run 3 SRC seeds;
  3) analyze and require PROPAGATIVE_RESOLVED with |c-c_ref|/c_ref <= 10%;
  4) only if that passes, run the 3 closure seeds and analyze again.

No x20f/x20i directory is modified.
USAGE
}

ACTION="${1:---run}"
case "$ACTION" in
  --preflight|--src|--closure|--run|--analyze|--status) ;;
  -h|--help) usage; exit 0 ;;
  *) echo "[x20j] ERROR bad action $ACTION" >&2; usage >&2; exit 2 ;;
esac

for dep in \
  scripts/src_mpcd_run_common_0434.sh \
  scripts/generate_0493x13e_longitudinal_velocity_state.py \
  scripts/analyze_0493w1_src_fluid_calibrator.py \
  scripts/analyze_0493x20j_longitudinal_alpha175_longwave.py; do
  [[ -f "$dep" ]] || { echo "[x20j] ERROR missing $dep" >&2; exit 2; }
done

mkdir -p "$RUN_ROOT/audit"
manifest="$RUN_ROOT/manifest_0493x20j.csv"

write_manifest(){
python3 - "$manifest" "$CELL_SIZE" "$KBT" "$MASS" "$CS_REF" "$NX_LONG" "$NY_LONG" "$MODE_X" "$MACH" "$ALPHA_DEG" "$GAMMA_LONG" "$DT_LONG" "$SEEDS" "$ACOUSTIC_CYCLES" "$SRC_DUMP_TARGET" "$CLOSURE_DUMP_EVERY" <<'PY'
import csv,math,sys
(out,h,kbt,mass,cs,nx,ny,mode,mach,adeg,gamma,dt,seeds,cycles,src_target,closure_dump)=sys.argv[1:]
h=float(h);kbt=float(kbt);mass=float(mass);cs=float(cs);nx=int(nx);ny=int(ny);mode=int(mode);mach=float(mach)
adeg=float(adeg);gamma=int(gamma);dt=float(dt);cycles=float(cycles);src_target=int(src_target);closure_dump=int(closure_dump)
rad=math.radians(adeg); seedv=[int(x) for x in seeds.split(',') if x.strip()]
Lx=nx*h; Ly=ny*h; period=Lx/(cs*mode); T=cycles*period; U=mach*cs
steps=math.ceil(T/dt); src_dump=max(1,round(steps/src_target))
rows=[]
for model in ('src','src-q6-g-f'):
    dump=src_dump if model=='src' else closure_dump
    summary=dump if model=='src' else 1
    for seed in seedv:
        mtag='SRC' if model=='src' else 'closure'
        run=f"longwave/alpha175/{mtag}/seed{seed}"
        rows.append(dict(model=model,case='alpha175_longwave',case_id='alpha175_longwave',sweep='alpha_deg_longwave',x=adeg,
            ell=0.5744768837780632,gamma=gamma,alpha_SRC_deg=adeg,rotationAngleRad=rad,h=h,dt=dt,kBT=kbt,m=mass,
            Nx=nx,Ny=ny,Lx=Lx,Ly=Ly,modeX=mode,k=2*math.pi*mode/Lx,wavelength=Lx,mach=mach,U0=U,csReference=cs,
            acousticCycles=cycles,steps=steps,dumpEvery=dump,summaryEvery=summary,physicalTime=steps*dt,seed=seed,runDir=run))
with open(out,'w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n'); w.writeheader(); w.writerows(rows)
print(f'[x20j] manifest={out} runs={len(rows)} Nx={nx} Ny={ny} wavelength={Lx:.9g} k={2*math.pi/Lx:.9g}')
print(f'[x20j] alpha={adeg:g} gamma={gamma} Ma={mach:g} U0={U:.9g} period_ref={period:.9g} T_target={T:.9g} steps={steps}')
print(f'[x20j] dumps SRC every {src_dump}; closure every {closure_dump}')
PY
}
write_manifest

if [[ "$ACTION" == --status ]]; then
  total=0; done=0; failed=0
  while IFS=, read -r model case case_id sweep x ell gamma deg rad h dt kbt mass nx ny lx ly mode k wave mach U cs cycles steps dump summary T seed runDir; do
    [[ "$model" == model ]] && continue
    total=$((total+1))
    [[ -f "$RUN_ROOT/$runDir/RUN_COMPLETE_0493x20j" ]] && done=$((done+1))
    [[ -f "$RUN_ROOT/$runDir/RUN_FAILED_0493x20j" ]] && failed=$((failed+1))
  done < "$manifest"
  echo "[x20j-status] complete=$done/$total failed=$failed"
  [[ -f "$RUN_ROOT/audit/src_longwave_gate.txt" ]] && cat "$RUN_ROOT/audit/src_longwave_gate.txt"
  [[ -f "$RUN_ROOT/audit/final_longwave_verdict.txt" ]] && cat "$RUN_ROOT/audit/final_longwave_verdict.txt"
  [[ -f "$RUN_ROOT/analysis/longitudinal_map_aggregated.csv" ]] && cat "$RUN_ROOT/analysis/longitudinal_map_aggregated.csv"
  exit 0
fi

if [[ "$ACTION" == --analyze ]]; then
  python3 scripts/analyze_0493x20j_longitudinal_alpha175_longwave.py --campaign-root "$RUN_ROOT" --repo-root "$ROOT"
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

NX="$NX_LONG"; NY="$NY_LONG"; GAMMA="$GAMMA_LONG"; DT="$DT_LONG"; PARTICLE_MASS="$MASS"
ROTATION_ANGLE="$(python3 - <<PY
import math
print(format(math.radians(float('$ALPHA_DEG')),'.17g'))
PY
)"
RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3; SEED=4938601
Lx="$(awk -v n="$NX_LONG" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
Ly="$(awk -v n="$NY_LONG" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
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
  NX="$nx"; NY="$ny"; Lx="$lx"; Ly="$ly"; GAMMA="$gamma"; ROTATION_ANGLE="$rad"; DT="$dt"; SEED="$seed"
  PARTICLE_MASS="$MASS"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
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
  local model=$1 gamma=$2 deg=$3 rad=$4 dt=$5 seed=$6 steps=$7 dump=$8 summary=$9 runDir=${10} execute=${11}
  local dir="$RUN_ROOT/$runDir" marker="$RUN_ROOT/$runDir/RUN_COMPLETE_0493x20j" fail="$RUN_ROOT/$runDir/RUN_FAILED_0493x20j"
  if [[ "$execute" == 1 ]]; then rm -rf "$dir"; fi
  mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params" "$dir/audit"
  local lx ly U state meta params
  lx="$(awk -v n="$NX_LONG" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
  ly="$(awk -v n="$NY_LONG" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
  U="$(awk -v ma="$MACH" -v c="$CS_REF" 'BEGIN{printf "%.17g",ma*c}')"
  state="$dir/init/longitudinal_0493x20j.smpcd"
  meta="$dir/init/longitudinal_0493x20j.meta.json"
  params="$dir/params/params_0493x20j.kv"
  python3 scripts/generate_0493x13e_longitudinal_velocity_state.py \
    --output "$state" --metadata "$meta" --Lx "$lx" --Ly "$ly" --Nx "$NX_LONG" --Ny "$NY_LONG" \
    --gamma "$gamma" --kBT "$KBT" --mass "$MASS" --seed "$seed" --mode-x "$MODE_X" \
    --amplitude "$U" --mach-requested "$MACH" --sound-speed-reference "$CS_REF"
  write_params "$model" "$state" "$params" "$dir/output" "$NX_LONG" "$NY_LONG" "$lx" "$ly" "$dt" "$steps" "$gamma" "$rad" "$seed" "$summary" "$dump"
  prepare "$model" "$params" "$NX_LONG" "$NY_LONG" "$lx" "$ly" "$gamma" "$rad" "$dt" "$seed" "$summary" "$dump"
  {
    echo "case=alpha175_longwave"; echo "model=$model"; echo "alphaDeg=$deg"; echo "rotationAngleRad=$rad"; echo "seed=$seed"
    echo "Nx=$NX_LONG"; echo "Ny=$NY_LONG"; echo "Lx=$lx"; echo "Ly=$ly"; echo "modeX=$MODE_X"; echo "Ma=$MACH"
    echo "binary=$(readlink -f "$BIN" 2>/dev/null || printf '%s' "$BIN")"
    [[ -f "$BIN" ]] && echo "binarySha256=$(sha256sum "$BIN" | awk '{print $1}')"
    echo "helperSha256=$(sha256sum scripts/src_mpcd_run_common_0434.sh | awk '{print $1}')"
    echo "generatorSha256=$(sha256sum scripts/generate_0493x13e_longitudinal_velocity_state.py | awk '{print $1}')"
    echo "paramsSha256=$(sha256sum "$params" | awk '{print $1}')"
    echo "initialSha256=$(sha256sum "$state" | awk '{print $1}')"
    awk -F= '$1 ~ /^[[:space:]]*(rotationAngle|rngSeed|dt)[[:space:]]*$/ {print}' "$params"
  } > "$dir/audit/provenance.txt"
  echo "[x20j] model=$model alpha=$deg seed=$seed Nx=$NX_LONG steps=$steps dump=$dump"
  [[ "$execute" == 1 ]] || return 0
  suite_ensure_binary_0434
  rm -f "$marker" "$fail"
  set +e
  /usr/bin/time -o "$dir/logs/time_0493x20j.txt" -f 'elapsed=%e user=%U sys=%S' \
    "$BIN" "$params" 2>&1 | tee "$dir/logs/run_0493x20j.log"
  rc=${PIPESTATUS[0]}
  set -e
  if [[ $rc -ne 0 ]]; then touch "$fail"; return "$rc"; fi
  touch "$marker"
}

run_model_from_manifest(){
  local wanted=$1 execute=$2 failed=0
  while IFS=, read -r model case case_id sweep x ell gamma deg rad h dt kbt mass nx ny lx ly mode k wave mach U cs cycles steps dump summary T seed runDir; do
    [[ "$model" == model ]] && continue
    [[ "$model" == "$wanted" ]] || continue
    set +e
    run_case "$model" "$gamma" "$deg" "$rad" "$dt" "$seed" "$steps" "$dump" "$summary" "$runDir" "$execute"
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
      failed=$((failed+1))
      [[ "$CONTINUE_ON_FAILURE" == 1 ]] || return "$rc"
    fi
  done < "$manifest"
  [[ $failed -eq 0 ]] || { echo "[x20j] ERROR failed $wanted runs=$failed" >&2; return 3; }
}

analyze(){
  python3 scripts/analyze_0493x20j_longitudinal_alpha175_longwave.py --campaign-root "$RUN_ROOT" --repo-root "$ROOT"
}

src_gate(){
  python3 - "$RUN_ROOT/analysis/longitudinal_map_aggregated.csv" "$CS_REF" "$SRC_C_REL_TOL" "$RUN_ROOT/audit/src_longwave_gate.txt" <<'PY'
import csv,math,sys
p,cs,tol,out=sys.argv[1:]; cs=float(cs); tol=float(tol)
rows=list(csv.DictReader(open(p,newline='')))
r=next((q for q in rows if q.get('model')=='src' and q.get('case_id')=='alpha175_longwave'),None)
if r is None:
    txt='VERDICT=FAIL_SRC_LONGWAVE\nreason=missing SRC aggregate\n'; open(out,'w').write(txt); print(txt,end=''); raise SystemExit(4)
status=r.get('acousticModeStatus',''); c=r.get('c_resolved','NA')
dstatus=r.get('dampedAcousticModeStatus',''); dc=r.get('c_damped_resolved','NA')
def relerr(v):
    try:
        x=float(v); return abs(x-cs)/cs if math.isfinite(x) else math.inf
    except Exception: return math.inf
rel=relerr(c); drel=relerr(dc)
primary_ok=(status=='PROPAGATIVE_RESOLVED' and rel<=tol)
damped_ok=(dstatus=='PROPAGATIVE_DAMPED_RESOLVED' and drel<=tol)
ok=primary_ok or damped_ok
method='ZERO_CROSSING' if primary_ok else ('DAMPED_FIT_FALLBACK' if damped_ok else 'NONE')
lines=['===== 0493x20j SRC LONG-WAVE GATE =====',
       f'acousticModeStatus={status}',f'c_resolved={c}',f'c_relative_error={rel:.17g}',
       f'dampedAcousticModeStatus={dstatus}',f'c_damped_resolved={dc}',f'c_damped_relative_error={drel:.17g}',
       f'c_reference={cs:.17g}',f'c_relative_tolerance={tol:.17g}',f'gateMethod={method}',
       f'VERDICT={"PASS_SRC_LONGWAVE" if ok else "FAIL_SRC_LONGWAVE"}']
open(out,'w').write('\n'.join(lines)+'\n'); print('\n'.join(lines))
raise SystemExit(0 if ok else 5)
PY
}

final_verdict(){
  python3 - "$RUN_ROOT/analysis/longitudinal_map_aggregated.csv" "$RUN_ROOT/audit/final_longwave_verdict.txt" <<'PY'
import csv,sys
p,out=sys.argv[1:]; rows=list(csv.DictReader(open(p,newline='')))
def get(model): return next((r for r in rows if r.get('case_id')=='alpha175_longwave' and r.get('model')==model),None)
s=get('src'); q=get('src-q6-g-f')
ss=s.get('acousticModeStatus','MISSING') if s else 'MISSING'; qs=q.get('acousticModeStatus','MISSING') if q else 'MISSING'
sd=s.get('dampedAcousticModeStatus','MISSING') if s else 'MISSING'; qd=q.get('dampedAcousticModeStatus','MISSING') if q else 'MISSING'
if ss=='PROPAGATIVE_RESOLVED': src_resolved=True; src_method='ZERO_CROSSING'
elif sd=='PROPAGATIVE_DAMPED_RESOLVED': src_resolved=True; src_method='DAMPED_FIT_FALLBACK'
else: src_resolved=False; src_method='NONE'
closure_resolved=(qs=='PROPAGATIVE_RESOLVED' or qd=='PROPAGATIVE_DAMPED_RESOLVED')
if src_resolved and not closure_resolved:
    verdict='PASS_LONGWAVE_DISCRIMINATION' if src_method=='ZERO_CROSSING' else 'PASS_LONGWAVE_DISCRIMINATION_DAMPED_FALLBACK'
elif not src_resolved: verdict='FAIL_OR_REVIEW_SRC_NOT_RESOLVED'
elif closure_resolved: verdict='REVIEW_CLOSURE_PROPAGATIVE'
else: verdict='REVIEW_INCOMPLETE'
lines=['===== 0493x20j FINAL LONG-WAVE VERDICT =====',f'SRC_primary={ss}',f'SRC_damped={sd}',f'SRC_method={src_method}',
       f'closure_primary={qs}',f'closure_damped={qd}',f'VERDICT={verdict}']
open(out,'w').write('\n'.join(lines)+'\n'); print('\n'.join(lines))
PY
}

if [[ "$ACTION" == --preflight ]]; then
  # One seed/model is enough to validate the generated parameter/runtime path.
  while IFS=, read -r model case case_id sweep x ell gamma deg rad h dt kbt mass nx ny lx ly mode k wave mach U cs cycles steps dump summary T seed runDir; do
    [[ "$model" == model ]] && continue
    [[ "$seed" == 4938601 ]] || continue
    run_case "$model" "$gamma" "$deg" "$rad" "$dt" "$seed" "$steps" "$dump" "$summary" "preflight/$model" 0
  done < "$manifest"
  python3 scripts/analyze_0493x20j_longitudinal_alpha175_longwave.py --self-test
  echo '[x20j] PREFLIGHT PASS'
  exit 0
fi

if [[ "$ACTION" == --src || "$ACTION" == --run ]]; then
  if [[ "$ACTION" == --run ]]; then
    rm -rf "$RUN_ROOT"
    mkdir -p "$RUN_ROOT/audit"
    write_manifest
  else
    # A deliberate --src starts a clean x20j campaign too.
    rm -rf "$RUN_ROOT"
    mkdir -p "$RUN_ROOT/audit"
    write_manifest
  fi
  run_model_from_manifest src 1
  analyze
  if ! src_gate; then
    echo "[x20j] SRC long-wave gate did not pass; closure NOT launched." >&2
    echo "[x20j] inspect $RUN_ROOT/audit/src_longwave_gate.txt" >&2
    exit 5
  fi
  [[ "$ACTION" == --src ]] && { echo "[x20j] SRC stage PASS; closure may now be launched with --closure"; exit 0; }
fi

if [[ "$ACTION" == --closure ]]; then
  # Re-analyze/regate automatically so an existing SRC-only x20j campaign can be
  # continued after installing the strongly-damped fallback without rerunning SRC.
  if [[ ! -f "$RUN_ROOT/longwave/alpha175/SRC/seed4938601/RUN_COMPLETE_0493x20j" ]]; then
    echo '[x20j] ERROR completed SRC stage not found; run --src first' >&2; exit 2
  fi
  analyze
  src_gate || true
  grep -q '^VERDICT=PASS_SRC_LONGWAVE$' "$RUN_ROOT/audit/src_longwave_gate.txt" || { echo '[x20j] ERROR SRC gate is not PASS even with damped-fit fallback; refusing closure stage' >&2; exit 5; }
fi

if [[ "$ACTION" == --closure || "$ACTION" == --run ]]; then
  run_model_from_manifest src-q6-g-f 1
  analyze
  final_verdict
  {
    echo "runnerSha256=$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
    echo "binarySha256=$(sha256sum "$BIN" | awk '{print $1}')"
    echo "helperSha256=$(sha256sum scripts/src_mpcd_run_common_0434.sh | awk '{print $1}')"
    echo "generatorSha256=$(sha256sum scripts/generate_0493x13e_longitudinal_velocity_state.py | awk '{print $1}')"
    echo "analyzerSha256=$(sha256sum scripts/analyze_0493x20j_longitudinal_alpha175_longwave.py | awk '{print $1}')"
  } > "$RUN_ROOT/audit/campaign_provenance.txt"
  touch "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x20j"
  echo "[x20j] COMPLETE root=$RUN_ROOT"
  echo "[x20j] verdict=$RUN_ROOT/audit/final_longwave_verdict.txt"
  echo "[x20j] analysis=$RUN_ROOT/analysis/longitudinal_map_aggregated.csv"
fi
