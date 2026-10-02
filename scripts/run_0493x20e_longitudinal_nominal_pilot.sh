#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL=longitudinal_nominal_pilot_0493x20e
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x20e_longitudinal_nominal_pilot}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
SKIP_EXISTING="${SKIP_EXISTING:-1}"
CONTINUE_ON_FAILURE="${CONTINUE_ON_FAILURE:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"

# Final nominal article fluid.
CELL_SIZE="0.00390625"
GAMMA_NOM=8
KBT="0.125"
MASS="1.0"
ROTATION_DEG=120
ROTATION_RAD="2.0943951023931953"
DT_NOM="0.0063471328149122585"
ELL_NOM="0.5744768837780632"
CS_REF="${CS_REF:-0.35512}"          # high-statistics x13h-A reference
NX_NOM="${NX_NOM:-64}"
NY_NOM="${NY_NOM:-16}"
MODE_X="${MODE_X:-1}"
MACH_LIST="${MACH_LIST:-0.05,0.10}"
SEEDS="${SEEDS:-4938501,4938502,4938503}"
ACOUSTIC_CYCLES="${ACOUSTIC_CYCLES:-3.4}"
SRC_DUMP_TARGET="${SRC_DUMP_TARGET:-120}"
CLOSURE_DUMP_EVERY="${CLOSURE_DUMP_EVERY:-2}"

usage() {
  cat <<'EOF'
0493x20e — nominal longitudinal response pilot

Usage:
  bash scripts/run_0493x20e_longitudinal_nominal_pilot.sh --preflight
  bash scripts/run_0493x20e_longitudinal_nominal_pilot.sh --smoke
  bash scripts/run_0493x20e_longitudinal_nominal_pilot.sh --run
  bash scripts/run_0493x20e_longitudinal_nominal_pilot.sh --analyze
  bash scripts/run_0493x20e_longitudinal_nominal_pilot.sh --status

Scope:
  nominal fluid only; SRC vs production SRC + particle/field closure
  Ma_ref = 0.05, 0.10 by default; 3 paired seeds; 64x16 periodic domain.
  No source modification and no rebuild.

The smoke runs only one closure case for 12 steps and validates the existing
resident Q6 divergence audit before the 12-run pilot is started.
EOF
}

ACTION="${1:---run}"
case "$ACTION" in
  --preflight|--smoke|--run|--analyze|--status) ;;
  -h|--help) usage; exit 0 ;;
  *) echo "[x20e] ERROR unknown action: $ACTION" >&2; usage >&2; exit 2 ;;
esac

for dep in \
  scripts/src_mpcd_run_common_0434.sh \
  scripts/generate_0493x13e_longitudinal_velocity_state.py \
  scripts/analyze_0493w1_src_fluid_calibrator.py \
  scripts/analyze_0493x20e_longitudinal_nominal_pilot.py; do
  [[ -f "$dep" ]] || { echo "[x20e] ERROR missing dependency: $dep" >&2; exit 2; }
done
command -v python3 >/dev/null

mkdir -p "$CAMPAIGN_ROOT"
manifest="$CAMPAIGN_ROOT/manifest_0493x20e.csv"

make_manifest() {
python3 - "$manifest" "$MACH_LIST" "$SEEDS" "$CELL_SIZE" "$GAMMA_NOM" "$KBT" "$MASS" "$ROTATION_DEG" "$ROTATION_RAD" "$DT_NOM" "$ELL_NOM" "$CS_REF" "$NX_NOM" "$NY_NOM" "$MODE_X" "$ACOUSTIC_CYCLES" "$SRC_DUMP_TARGET" "$CLOSURE_DUMP_EVERY" <<'PY'
import csv,math,sys
(out,machs,seeds,h,gamma,kbt,mass,deg,rad,dt,ell,cs,nx,ny,mode,cycles,src_target,closure_dump)=sys.argv[1:]
h=float(h);gamma=int(gamma);kbt=float(kbt);mass=float(mass);deg=float(deg);rad=float(rad);dt=float(dt);ell=float(ell);cs=float(cs);nx=int(nx);ny=int(ny);mode=int(mode);cycles=float(cycles);src_target=int(src_target);closure_dump=int(closure_dump)
seedv=[int(s) for s in seeds.split(',') if s.strip()]
Lx=nx*h;Ly=ny*h;period=Lx/(cs*mode);T=cycles*period;steps=math.ceil(T/dt)
src_dump=max(1,round(steps/src_target))
rows=[]
for model in ('src','src-q6-g-f'):
  for ma in [float(x) for x in machs.split(',') if x.strip()]:
    U=ma*cs
    dump=src_dump if model=='src' else max(1,closure_dump)
    summary=dump if model=='src' else 1
    for seed in seedv:
      mtag='SRC' if model=='src' else 'closure'
      atag=f'Ma{ma:.2f}'.replace('.','p')
      run=f'pilot/{mtag}/{atag}/seed{seed}'
      rows.append(dict(model=model,case='nominal',ell=ell,gamma=gamma,alpha_SRC_deg=deg,rotationAngleRad=rad,h=h,dt=dt,kBT=kbt,m=mass,Nx=nx,Ny=ny,Lx=Lx,Ly=Ly,modeX=mode,k=2*math.pi*mode/Lx,wavelength=Lx,mach=ma,U0=U,csReference=cs,acousticCycles=cycles,steps=steps,dumpEvery=dump,summaryEvery=summary,physicalTime=steps*dt,seed=seed,runDir=run))
with open(out,'w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
print(f'[x20e] manifest={out} runs={len(rows)} L={Lx:.9g}x{Ly:.9g} T_ac={period:.9g} T={steps*dt:.9g} steps={steps} srcDump={src_dump} closureDump={closure_dump}')
PY
}
make_manifest

if [[ "$ACTION" == --status ]]; then
  total=0;done=0;failed=0
  while IFS=, read -r model case ell gamma deg rad h dt kbt mass nx ny lx ly mode k wave mach U cs cycles steps dump summary T seed runDir; do
    [[ "$model" == model ]] && continue
    total=$((total+1))
    [[ -f "$CAMPAIGN_ROOT/$runDir/RUN_COMPLETE_0493x20e" ]] && done=$((done+1))
    [[ -f "$CAMPAIGN_ROOT/$runDir/RUN_FAILED_0493x20e" ]] && failed=$((failed+1))
  done < "$manifest"
  echo "[x20e-status] complete=$done/$total failed=$failed"
  [[ -f "$CAMPAIGN_ROOT/analysis/longitudinal_pilot_aggregated.csv" ]] && cat "$CAMPAIGN_ROOT/analysis/longitudinal_pilot_aggregated.csv"
  exit 0
fi

if [[ "$ACTION" == --analyze ]]; then
  python3 scripts/analyze_0493x20e_longitudinal_nominal_pilot.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT"
  exit 0
fi

export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS
INACTIVE_SLOTS=0
SUMMARY_ROLE_FILTER=fluid
DUMP_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=2500
PROJECTION_TOLERANCE=1e-5
PROJECTION_MOMENTUM_CORRECTION_ENABLE=false
Q6_PROJECTION_STRENGTH=1.0
Q6_GF_DENSITY_RELAXATION_TIME=0.25
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6
Q6_GF_DENSITY_TRACTION_GAIN=1.0
Q6_GF_MIN_FILL_FRACTION=0.10
Q6_GF_HAS_GAS_PHASE=0
Q6_GF_EXTERNAL_SPECIES=0
LIVE_VIS_ENABLE=0
FILTERED_RECORDING_ENABLE=0
RECORD_ENABLE=false
PARTICLE_TYPE_FILTER=-1

# Defaults populate ancillary controls expected by suite_write_common_params_0434.
NX="$NX_NOM"; NY="$NY_NOM"; GAMMA="$GAMMA_NOM"; DT="$DT_NOM"; PARTICLE_MASS="$MASS"
ROTATION_ANGLE="$ROTATION_RAD"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3; SEED=4938501
Lx="$(awk -v n="$NX_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
Ly="$(awk -v n="$NY_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
SUMMARY_EVERY=1; DUMP_STATE_EVERY=1
suite_defaults_common_0434
suite_compute_derived_0434

write_params() {
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
    cat >> "$params" <<PARAMS
speciesRegistryEnable = false
speciesQ6Enable = false
PARAMS
  fi
  GAMMA="$gamma" NX="$nx" NY="$ny" Lx="$lx" Ly="$ly" DT="$dt" KBT="$KBT" PARTICLE_MASS="$MASS" \
    ROTATION_ANGLE="$rad" RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true \
    THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 \
    THERMOSTAT_TARGET_KBT="$KBT" THERMOSTAT_MIN_PARTICLES=3 SEED="$seed" \
    SUMMARY_EVERY="$summary" DUMP_STATE_EVERY="$dump" \
    suite_write_common_params_0434 "$model" >> "$params"
}

prepare_flags_and_preflight() {
  local model=$1 params=$2 nx=$3 ny=$4 lx=$5 ly=$6 gamma=$7
  NX="$nx"; NY="$ny"; Lx="$lx"; Ly="$ly"; GAMMA="$gamma"
  suite_export_cuda_flags_0434 "$model" periodic
  if [[ "$model" == src-q6-g-f ]]; then
    export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
    export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  fi
  suite_preflight_run_ok_0492 "$params"
}

run_case() {
  local model=$1 mach=$2 seed=$3 steps=$4 dump=$5 summary=$6 runDir=$7 execute=$8
  local dir="$CAMPAIGN_ROOT/$runDir"
  local marker="$dir/RUN_COMPLETE_0493x20e" failmarker="$dir/RUN_FAILED_0493x20e"
  mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params"
  if [[ "$execute" == 1 && "$SKIP_EXISTING" == 1 && -f "$marker" ]]; then
    echo "[x20e] SKIP $runDir"
    return 0
  fi
  local lx ly U state meta params
  lx="$(awk -v n="$NX_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
  ly="$(awk -v n="$NY_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
  U="$(awk -v ma="$mach" -v c="$CS_REF" 'BEGIN{printf "%.17g",ma*c}')"
  state="$dir/init/longitudinal_0493x20e.smpcd"
  meta="$dir/init/longitudinal_0493x20e.meta.json"
  params="$dir/params/params_0493x20e.kv"
  python3 scripts/generate_0493x13e_longitudinal_velocity_state.py \
    --output "$state" --metadata "$meta" --Lx "$lx" --Ly "$ly" --Nx "$NX_NOM" --Ny "$NY_NOM" \
    --gamma "$GAMMA_NOM" --kBT "$KBT" --mass "$MASS" --seed "$seed" --mode-x "$MODE_X" \
    --amplitude "$U" --mach-requested "$mach" --sound-speed-reference "$CS_REF"
  write_params "$model" "$state" "$params" "$dir/output" "$NX_NOM" "$NY_NOM" "$lx" "$ly" "$DT_NOM" "$steps" "$GAMMA_NOM" "$ROTATION_RAD" "$seed" "$summary" "$dump"
  prepare_flags_and_preflight "$model" "$params" "$NX_NOM" "$NY_NOM" "$lx" "$ly" "$GAMMA_NOM"
  echo "[x20e] model=$model Ma=$mach U0=$U seed=$seed steps=$steps dump=$dump summary=$summary run=$runDir"
  [[ "$execute" == 1 ]] || return 0
  suite_ensure_binary_0434
  rm -f "$marker" "$failmarker"
  set +e
  /usr/bin/time -o "$dir/logs/time_0493x20e.txt" -f 'elapsed=%e user=%U sys=%S' \
    "$BIN" "$params" 2>&1 | tee "$dir/logs/run_0493x20e.log"
  rc=${PIPESTATUS[0]}
  set -e
  if [[ $rc -ne 0 ]]; then
    touch "$failmarker"
    echo "[x20e] RUN FAILED rc=$rc $runDir" >&2
    return "$rc"
  fi
  touch "$marker"
}

if [[ "$ACTION" == --smoke ]]; then
  smoke_dir="smoke/closure_Ma0p05_seed4938501"
  run_case src-q6-g-f 0.05 4938501 12 1 1 "$smoke_dir" 1
  python3 scripts/analyze_0493x20e_longitudinal_nominal_pilot.py \
    --repo-root "$ROOT" --check-audit "$CAMPAIGN_ROOT/$smoke_dir"
  echo "[x20e] SMOKE PASS — resident Q6 divergence audit is available; no solver patch required"
  exit 0
fi

if [[ "$ACTION" == --preflight ]]; then
  # Validate one seed for each model/amplitude; the other seeds change only RNG state.
  while IFS=, read -r model case ell gamma deg rad h dt kbt mass nx ny lx ly mode k wave mach U cs cycles steps dump summary T seed runDir; do
    [[ "$model" == model ]] && continue
    [[ "$seed" == 4938501 ]] || continue
    run_case "$model" "$mach" "$seed" "$steps" "$dump" "$summary" "preflight/$model/Ma${mach}/seed${seed}" 0
  done < "$manifest"
  python3 scripts/analyze_0493x20e_longitudinal_nominal_pilot.py --self-test
  echo "[x20e] PREFLIGHT PASS"
  exit 0
fi

# Full 12-run pilot.
new=0; failed=0
while IFS=, read -r model case ell gamma deg rad h dt kbt mass nx ny lx ly mode k wave mach U cs cycles steps dump summary T seed runDir; do
  [[ "$model" == model ]] && continue
  before=0; [[ -f "$CAMPAIGN_ROOT/$runDir/RUN_COMPLETE_0493x20e" ]] && before=1
  set +e
  run_case "$model" "$mach" "$seed" "$steps" "$dump" "$summary" "$runDir" 1
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    failed=$((failed+1))
    [[ "$CONTINUE_ON_FAILURE" == 1 ]] || exit "$rc"
  elif [[ $before == 0 ]]; then
    new=$((new+1))
  fi
done < "$manifest"

python3 scripts/analyze_0493x20e_longitudinal_nominal_pilot.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT"
touch "$CAMPAIGN_ROOT/CAMPAIGN_COMPLETE_0493x20e"
echo "[x20e] PILOT COMPLETE new=$new failed=$failed"
