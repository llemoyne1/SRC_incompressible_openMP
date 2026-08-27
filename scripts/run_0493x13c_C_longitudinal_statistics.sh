#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL=src_longitudinal_statistics_0493x13c
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x13c_transport_qualification}"
RUN_ROOT="$CAMPAIGN_ROOT/C_statistics"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"

PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
CLEAN_ROOT="${CLEAN_ROOT:-0}"
SKIP_EXISTING="${SKIP_EXISTING:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"

FLUIDS="${FLUIDS:-A1,G08,G10}"
SOUND_AMPLITUDES="${SOUND_AMPLITUDES:-0.04,0.08}"
SOUND_NX_LIST="${SOUND_NX_LIST:-64}"
SOUND_NY="${SOUND_NY:-16}"
SOUND_DUMP_COUNT="${SOUND_DUMP_COUNT:-120}"
SOUND_PHYSICAL_TIME_BASE="${SOUND_PHYSICAL_TIME_BASE:-2.4}"
CSTAT_EQUIVALENT_GAMMA_REPS="${CSTAT_EQUIVALENT_GAMMA_REPS:-240}"
CSTAT_MIN_REPS="${CSTAT_MIN_REPS:-12}"
SEED_BASE="${SEED_BASE:-4931511}"
PREFLIGHT_FIRST_REP_ONLY="${PREFLIGHT_FIRST_REP_ONLY:-1}"

CELL_SIZE="0.00390625"; KBT="0.125"; MASS="1.0"; MODE_X=1
ROTATION_DEG=120; ROTATION_RAD="2.0943951023931953"; TARGET_LAMBDA_OVER_H="0.48"

# Canonical globals for the shared helper.
NX=64; NY="$SOUND_NY"; GAMMA=20; DT=.004231421876608172; PARTICLE_MASS="$MASS"
ROTATION_ANGLE="$ROTATION_RAD"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3; SEED="$SEED_BASE"

for dep in \
  scripts/generate_0493x13b_sound_state_fractional.py \
  scripts/analyze_0493w1_src_fluid_calibrator.py \
  scripts/analyze_0493x13c_C_longitudinal_statistics.py; do
  [[ -f "$dep" ]] || { echo "[0493x13c-Cstat] missing dependency: $dep" >&2; exit 2; }
done
command -v python3 >/dev/null

fluid_spec(){
  case "$1" in
    A1) echo '20|A1_gamma20_reference';;
    G08) echo '8|low_gamma_A1';;
    G10) echo '10|low_gamma_A1';;
    *) return 1;;
  esac
}
IFS=',' read -ra FARR <<< "$FLUIDS"
for f in "${FARR[@]}"; do fluid_spec "$f" >/dev/null || { echo "bad fluid $f" >&2; exit 2; }; done

if [[ "$ANALYZE_ONLY" == 1 ]]; then
  python3 scripts/analyze_0493x13c_C_longitudinal_statistics.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT"
  exit 0
fi

if [[ "$CLEAN_ROOT" == 1 ]]; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT"
rm -f "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13c_Cstat"
manifest="$RUN_ROOT/manifest_0493x13c_Cstat.csv"

python3 - "$manifest" "$FLUIDS" "$SOUND_AMPLITUDES" "$SOUND_NX_LIST" "$SOUND_NY" "$CELL_SIZE" "$KBT" "$MASS" "$ROTATION_DEG" "$TARGET_LAMBDA_OVER_H" "$SOUND_DUMP_COUNT" "$SOUND_PHYSICAL_TIME_BASE" "$CSTAT_EQUIVALENT_GAMMA_REPS" "$CSTAT_MIN_REPS" <<'PY'
import csv,math,sys
(out,fluids,amps,nxs,ny,h,kbt,mass,angle_deg,lam_over_h,dump_count,Tbase,equiv,min_reps)=sys.argv[1:]
ny=int(ny);h=float(h);kbt=float(kbt);mass=float(mass);angle_deg=float(angle_deg);lam=float(lam_over_h)
dump_count=int(dump_count);Tbase=float(Tbase);equiv=float(equiv);min_reps=int(min_reps)
spec={'A1':(20,'A1_gamma20_reference'),'G08':(8,'low_gamma_A1'),'G10':(10,'low_gamma_A1')}
vmean=math.sqrt(math.pi*kbt/(2*mass));dt=lam*h/vmean; rows=[]
for fluid in fluids.split(','):
    gamma,role=spec[fluid]; reps=max(min_reps,math.ceil(equiv/gamma))
    for nx in map(int,nxs.split(',')):
        Lx=nx*h;Ly=ny*h;T=Tbase*(nx/64);steps=math.ceil(T/dt);dump=max(1,math.ceil(steps/dump_count));k=2*math.pi/Lx
        for amp in map(float,amps.split(',')):
            tag=f'E{amp:.4f}'.replace('.','p');run=f'{fluid}/Nx{nx}/{tag}'
            rows.append(dict(fluid=fluid,role=role,gamma=gamma,rotationAngleDeg=angle_deg,rotationAngleRad=math.radians(angle_deg),
                targetLambdaMeanOverCell=lam,dt=dt,cellSize=h,lambdaPhysical=lam*h,Nx=nx,Ny=ny,Lx=Lx,Ly=Ly,
                wavelengthCells=nx,modeX=1,amplitude=amp,replicates=reps,steps=steps,dumpEvery=dump,physicalTime=steps*dt,
                kLambda=k*lam*h,runDir=run,equivalentGammaRepBudget=gamma*reps,
                estimatedParticleStepsPerRep=nx*ny*gamma*steps,estimatedParticleStepsGroup=nx*ny*gamma*steps*reps))
with open(out,'w',newline='') as fp:
    w=csv.DictWriter(fp,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
print(f'[0493x13c-Cstat] manifest={out} groups={len(rows)}')
for r in rows: print(f"[0493x13c-Cstat] design fluid={r['fluid']} eps={r['amplitude']} reps={r['replicates']} gamma*reps={r['equivalentGammaRepBudget']}")
PY

export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS
INACTIVE_SLOTS=0; SUMMARY_ROLE_FILTER=fluid; DUMP_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false; RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false; PROJECTION_BACKEND=cuda; PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=100; PROJECTION_TOLERANCE=1e-12
PROJECTION_MOMENTUM_CORRECTION_ENABLE=true; Q6_PROJECTION_STRENGTH=1.0
LIVE_VIS_ENABLE=0; FILTERED_RECORDING_ENABLE=0; RECORD_ENABLE=false; PARTICLE_TYPE_FILTER=-1
suite_defaults_common_0434; suite_compute_derived_0434
[[ "$PREFLIGHT_ONLY" == 1 ]] || suite_ensure_binary_0434

groups_done=0; subruns_done=0; subruns_skipped=0; preflight_done=0
while IFS=, read -r fluid role gamma deg rad lam dt h lamphys nx ny lx ly wc mode amp reps steps dump T klambda runDir eqBudget psRep psGroup; do
  [[ "$fluid" == fluid ]] && continue
  group="$RUN_ROOT/$runDir"; mkdir -p "$group"
  for ((rep=0; rep<reps; ++rep)); do
    if [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_REP_ONLY" == 1 && "$rep" != 0 ]]; then continue; fi
    repTag=$(printf 'rep%02d' "$rep"); dir="$group/$repTag"; marker="$dir/RUN_COMPLETE_0493x13c_Cstat"
    if [[ "$PREFLIGHT_ONLY" != 1 && "$SKIP_EXISTING" == 1 && -f "$marker" ]]; then
      subruns_skipped=$((subruns_skipped+1)); continue
    fi
    mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params"
    state="$dir/init/sound_0493x13c.smpcd"; meta="$dir/init/sound_0493x13c.meta.json"
    # Paired design: same rep seed across amplitudes of a given fluid/Nx.
    seed=$((SEED_BASE + rep*1009 + gamma*100003 + nx*101))
    python3 scripts/generate_0493x13b_sound_state_fractional.py \
      --output "$state" --metadata "$meta" --Lx "$lx" --Ly "$ly" --Nx "$nx" --Ny "$ny" \
      --gamma "$gamma" --dt "$dt" --kBT "$KBT" --mass "$MASS" --seed "$seed" \
      --sound-mode-x "$mode" --sound-density-amplitude "$amp"
    SUMMARY_EVERY="$dump"; DUMP_STATE_EVERY="$dump"
    cat > "$dir/params/params_0493x13c_Cstat.kv" <<PARAMS
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
    GAMMA="$gamma" DT="$dt" KBT="$KBT" PARTICLE_MASS="$MASS" ROTATION_ANGLE="$rad" \
    RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true THERMOSTAT_ENABLE=true \
    THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT="$KBT" \
    THERMOSTAT_MIN_PARTICLES=3 SEED="$seed" \
      suite_write_common_params_0434 src >> "$dir/params/params_0493x13c_Cstat.kv"
    suite_export_cuda_flags_0434 src periodic
    suite_preflight_run_ok_0492 "$dir/params/params_0493x13c_Cstat.kv"
    echo "[0493x13c-Cstat] fluid=$fluid gamma=$gamma eps=$amp rep=$rep/$reps seed=$seed steps=$steps"
    if [[ "$PREFLIGHT_ONLY" == 1 ]]; then preflight_done=$((preflight_done+1)); continue; fi
    rm -f "$marker"
    set +e
    /usr/bin/time -o "$dir/logs/time_0493x13c.txt" -f 'elapsed=%e user=%U sys=%S' \
      "$BIN" "$dir/params/params_0493x13c_Cstat.kv" 2>&1 | tee "$dir/logs/run_0493x13c.log"
    rc=${PIPESTATUS[0]}; set -e; [[ $rc -eq 0 ]] || exit "$rc"
    touch "$marker"; subruns_done=$((subruns_done+1))
  done
  groups_done=$((groups_done+1))
done < "$manifest"

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  echo "[0493x13c-Cstat] PREFLIGHT PASS checked=$preflight_done (first replicate per group by default)"
  exit 0
fi

python3 scripts/analyze_0493x13c_C_longitudinal_statistics.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT"
touch "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13c_Cstat"
echo "[0493x13c-Cstat] CAMPAIGN COMPLETE groups=$groups_done new=$subruns_done skipped=$subruns_skipped marker=$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13c_Cstat"
