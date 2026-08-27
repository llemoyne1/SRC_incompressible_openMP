#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL=src_gamma_transport_qualification_0493x13c
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x13c_transport_qualification}"
RUN_ROOT="$CAMPAIGN_ROOT/H_gamma"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"

PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
CLEAN_ROOT="${CLEAN_ROOT:-0}"
SKIP_EXISTING="${SKIP_EXISTING:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"

GAMMAS="${GAMMAS:-6,8,10,14,20}"
H_SEEDS="${H_SEEDS:-4931411,4931412,4931413,4931414}"
SHEAR_NY_LIST="${SHEAR_NY_LIST:-64,128}"
SHEAR_NX="${SHEAR_NX:-32}"
SHEAR_AMPLITUDE="${SHEAR_AMPLITUDE:-0.05}"
SHEAR_DUMP_COUNT="${SHEAR_DUMP_COUNT:-96}"
PREFLIGHT_FIRST_SEED_ONLY="${PREFLIGHT_FIRST_SEED_ONLY:-1}"

CELL_SIZE="0.00390625"
KBT="0.125"
MASS="1.0"
ROTATION_DEG="120"
ROTATION_RAD="2.0943951023931953"
TARGET_LAMBDA_OVER_H="0.48"
MODE_Y=1

# Canonical globals required by the shared 0434 helper. Per-run values override these.
NX="$SHEAR_NX"; NY=64; GAMMA=20; DT=.004231421876608172; PARTICLE_MASS="$MASS"
ROTATION_ANGLE="$ROTATION_RAD"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3; SEED=4931411

for dep in \
  scripts/generate_0493x13b_shear_state.py \
  scripts/analyze_0493x13b_constitutive_transport.py \
  scripts/analyze_0493w1_src_fluid_calibrator.py \
  scripts/analyze_0493x13c_H_gamma_multiseed.py; do
  [[ -f "$dep" ]] || { echo "[0493x13c-Hgamma] missing dependency: $dep" >&2; exit 2; }
done
command -v python3 >/dev/null

if [[ "$ANALYZE_ONLY" == 1 ]]; then
  python3 scripts/analyze_0493x13c_H_gamma_multiseed.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT"
  exit 0
fi

if [[ "$CLEAN_ROOT" == 1 ]]; then
  rm -rf "$RUN_ROOT"
fi
mkdir -p "$RUN_ROOT"
rm -f "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13c_Hgamma"

manifest="$RUN_ROOT/manifest_0493x13c_Hgamma.csv"
python3 - "$manifest" "$GAMMAS" "$H_SEEDS" "$SHEAR_NY_LIST" "$SHEAR_NX" "$CELL_SIZE" "$KBT" "$MASS" "$ROTATION_DEG" "$TARGET_LAMBDA_OVER_H" "$SHEAR_AMPLITUDE" "$SHEAR_DUMP_COUNT" <<'PY'
import csv, math, sys
(
    out, gammas, seeds, nys, nx, h, kbt, mass, angle_deg,
    lam_over_h, amplitude, dump_count
) = sys.argv[1:]
nx=int(nx); h=float(h); kbt=float(kbt); mass=float(mass)
angle_deg=float(angle_deg); lam=float(lam_over_h); amp=float(amplitude); dump_count=int(dump_count)
seed_list=[int(x) for x in seeds.split(',') if x.strip()]
gamma_list=[int(x) for x in gammas.split(',') if x.strip()]
ny_list=[int(x) for x in nys.split(',') if x.strip()]
if not seed_list or not gamma_list or not ny_list: raise SystemExit('empty x13c-Hgamma design axis')
vmean=math.sqrt(math.pi*kbt/(2*mass)); dt=lam*h/vmean
rows=[]
for gamma in gamma_list:
    fg=(gamma-1.0+math.exp(-gamma))/gamma
    q=fg*(1.0-math.cos(math.radians(angle_deg)))
    nu_kin=kbt*dt/mass*(1.0/q-0.5)
    nu_col=h*h*q/(12.0*dt)
    nu_srd=nu_kin+nu_col
    for ny in ny_list:
        Lx=nx*h; Ly=ny*h; k=2*math.pi/Ly
        # Same logic as x13b-H: about 1.4 SRD e-folds, capped for cost.
        T=max(4.0,min(28.0,1.4/(nu_srd*k*k)))
        steps=math.ceil(T/dt); dump=max(1,math.ceil(steps/dump_count))
        for seed_index,seed in enumerate(seed_list):
            fluid=f'G{gamma:02d}'
            run=f'{fluid}/Ny{ny}/seed{seed}'
            rows.append(dict(
                fluid=fluid, role='gamma_A1_transport_scan', gamma=gamma,
                rotationAngleDeg=angle_deg, rotationAngleRad=math.radians(angle_deg),
                targetLambdaMeanOverCell=lam, dt=dt, cellSize=h,
                lambdaPhysical=lam*h, viscositySRDKinematic=nu_srd,
                Nx=nx, Ny=ny, Lx=Lx, Ly=Ly, wavelengthCells=ny, modeY=1,
                amplitude=amp, seedIndex=seed_index, seed=seed,
                steps=steps, dumpEvery=dump, physicalTime=steps*dt,
                kLambda=k*lam*h, runDir=run,
                estimatedParticleSteps=nx*ny*gamma*steps,
            ))
with open(out,'w',newline='') as fp:
    w=csv.DictWriter(fp,fieldnames=list(rows[0]),lineterminator='\n')
    w.writeheader(); w.writerows(rows)
print(f'[0493x13c-Hgamma] manifest={out} runs={len(rows)} gammas={gamma_list} seeds={seed_list} Ny={ny_list}')
PY

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

runs_done=0; runs_skipped=0; preflight_done=0
while IFS=, read -r fluid role gamma deg rad lam dt h lamphys nuSrd nx ny lx ly wc mode amp seedIndex seed steps dump T klambda runDir particleSteps; do
  [[ "$fluid" == fluid ]] && continue
  if [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_SEED_ONLY" == 1 && "$seedIndex" != 0 ]]; then
    continue
  fi
  dir="$RUN_ROOT/$runDir"
  marker="$dir/RUN_COMPLETE_0493x13c_Hgamma"
  if [[ "$PREFLIGHT_ONLY" != 1 && "$SKIP_EXISTING" == 1 && -f "$marker" ]]; then
    echo "[0493x13c-Hgamma] SKIP complete fluid=$fluid Ny=$ny seed=$seed"
    runs_skipped=$((runs_skipped+1)); continue
  fi
  mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params"
  state="$dir/init/shear_0493x13c.smpcd"
  python3 scripts/generate_0493x13b_shear_state.py \
    --output "$state" --Lx "$lx" --Ly "$ly" --Nx "$nx" --Ny "$ny" \
    --gamma "$gamma" --kBT "$KBT" --mass "$MASS" --seed "$seed" \
    --mode-y "$mode" --amplitude "$amp"
  SUMMARY_EVERY="$dump"; DUMP_STATE_EVERY="$dump"
  cat > "$dir/params/params_0493x13c_Hgamma.kv" <<PARAMS
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
    suite_write_common_params_0434 src >> "$dir/params/params_0493x13c_Hgamma.kv"
  suite_export_cuda_flags_0434 src periodic
  suite_preflight_run_ok_0492 "$dir/params/params_0493x13c_Hgamma.kv"
  echo "[0493x13c-Hgamma] fluid=$fluid gamma=$gamma Ny=$ny seed=$seed amp=$amp steps=$steps T=$T"
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    preflight_done=$((preflight_done+1)); continue
  fi
  rm -f "$marker"
  set +e
  /usr/bin/time -o "$dir/logs/time_0493x13c.txt" -f 'elapsed=%e user=%U sys=%S' \
    "$BIN" "$dir/params/params_0493x13c_Hgamma.kv" 2>&1 | tee "$dir/logs/run_0493x13c.log"
  rc=${PIPESTATUS[0]}
  set -e
  [[ $rc -eq 0 ]] || exit "$rc"
  touch "$marker"
  runs_done=$((runs_done+1))
done < "$manifest"

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  echo "[0493x13c-Hgamma] PREFLIGHT PASS checked=$preflight_done (first seed per gamma,wavelength by default)"
  exit 0
fi

python3 scripts/analyze_0493x13c_H_gamma_multiseed.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT"
touch "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13c_Hgamma"
echo "[0493x13c-Hgamma] CAMPAIGN COMPLETE new=$runs_done skipped=$runs_skipped marker=$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13c_Hgamma"
