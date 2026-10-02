#!/usr/bin/env bash
# SRC_GPU-SURF 0493x20a — JCP fluid characterization master campaign
# One master runner, reusing calibrate_fluid_0493w1_standalone.sh.
# 12 physical configurations, paired SRC / production Q6-G-F, 180 solver runs.
# No solver/source modification. No pandas. Campaign-level restart by completion markers.

ROOT="${ROOT:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT" || exit 2

MODE="${1:---run}"
case "$MODE" in
  --run|--preflight|--matrix|--aggregate|--status) ;;
  -h|--help)
    cat <<'USAGE'
Usage:
  bash scripts/run_0493x20a_article_fluid_campaign.sh --preflight
  bash scripts/run_0493x20a_article_fluid_campaign.sh --run
  bash scripts/run_0493x20a_article_fluid_campaign.sh --status
  bash scripts/run_0493x20a_article_fluid_campaign.sh --aggregate
  bash scripts/run_0493x20a_article_fluid_campaign.sh --matrix

Main defaults:
  CAMPAIGN_ROOT=runs/0493x20a_article_fluid_campaign
  BIN=build/src_mpcd_base_cuda_q6_resident_livevis_0486
  RESTART=1                  # campaign-level resume: completed realizations are skipped
  CONTINUE_ON_ERROR=1       # do not lose the whole night because one point fails
  LIVE_PROGRESS=1

Short 64x64/64x16 calibrations deliberately default to LIVE_VIS_ENABLE=0 for speed.
Set LIVE_VIS_ENABLE=1 to inspect them interactively. If enabled, the runner points
at ./livevis_control.kv when that file exists and never modifies it.

The campaign contains 12 unique physical points:
  lambdaMean/h sweep: 0.36 0.48 0.60 0.72 0.90  (gamma=8, alpha=120 deg)
  gamma sweep:        4 6 8 12 16               (lambdaMean/h=0.72, alpha=120 deg)
  alpha sweep:        60 90 120 150 deg          (lambdaMean/h=0.72, gamma=8)
The shared nominal point is lambdaMean/h=0.72, gamma=8, alpha=120 deg.

Per physical point:
  SRC      : 3 Taylor-Green + 3 sound + 3 MSD = 9 solver runs
  Q6-G-F   : 3 Taylor-Green + 3 MSD           = 6 solver runs
Total      : 12 * 15 = 180 solver runs.
USAGE
    exit 0
    ;;
  *) echo "[0493x20a] ERROR unknown mode: $MODE" >&2; exit 2 ;;
esac

CALIBRATOR="${CALIBRATOR:-scripts/calibrate_fluid_0493w1_standalone.sh}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x20a_article_fluid_campaign}"
RESTART="${RESTART:-1}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"

# Article nominal fluid definition.
CELL_SIZE="${CELL_SIZE:-0.00390625}"
KBT="${KBT:-0.125}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

# Measurement protocol: canonical TG + MSD on both paths; sound only on SRC.
NX="${NX:-64}"
NY="${NY:-64}"
TG_TIME="${TG_TIME:-4.0}"
TG_DUMP_COUNT="${TG_DUMP_COUNT:-80}"
SOUND_NX="${SOUND_NX:-64}"
SOUND_NY="${SOUND_NY:-16}"
SOUND_CYCLES="${SOUND_CYCLES:-3.4}"
SOUND_DUMP_COUNT="${SOUND_DUMP_COUNT:-120}"
SOUND_REPLICATES="${SOUND_REPLICATES:-3}"
MSD_NX="${MSD_NX:-64}"
MSD_NY="${MSD_NY:-64}"
MSD_TIME="${MSD_TIME:-5.0}"
MSD_DUMP_COUNT="${MSD_DUMP_COUNT:-60}"
MSD_SAMPLE_PARTICLES="${MSD_SAMPLE_PARTICLES:-20000}"
MAX_DUMP_GB="${MAX_DUMP_GB:-5.0}"

# Production Q6-G-F closure contract.
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-2500}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-0.10}"
MPCD_Q6_G_F_RESIDENT_CG_0493X7J="${MPCD_Q6_G_F_RESIDENT_CG_0493X7J:-1}"

# These calibrations are deliberately short and small-grid. LiveVis is therefore
# OFF by default to avoid perturbing throughput; it remains available on demand.
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-64}"
LIVE_VIS_NY="${LIVE_VIS_NY:-64}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"

truthy(){
  case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON) return 0 ;; *) return 1 ;; esac
}

mkdir -p "$CAMPAIGN_ROOT" "$CAMPAIGN_ROOT/logs" "$CAMPAIGN_ROOT/configs" "$CAMPAIGN_ROOT/summary"
MATRIX_CSV="$CAMPAIGN_ROOT/campaign_matrix.csv"
STATUS_TSV="$CAMPAIGN_ROOT/summary/campaign_status.tsv"
AGG_CSV="$CAMPAIGN_ROOT/summary/campaign_results_aggregated.csv"
RATIO_CSV="$CAMPAIGN_ROOT/summary/campaign_ratios.csv"
REAL_CSV="$CAMPAIGN_ROOT/summary/campaign_realizations.csv"

check_prereqs(){
  for c in bash python3 awk sed grep sha256sum; do
    command -v "$c" >/dev/null 2>&1 || { echo "[0493x20a] ERROR missing command: $c" >&2; return 2; }
  done
  [[ -f "$CALIBRATOR" ]] || { echo "[0493x20a] ERROR calibrator missing: $CALIBRATOR" >&2; return 2; }
  [[ -x "$BIN" ]] || { echo "[0493x20a] ERROR solver binary not executable: $BIN" >&2; return 2; }
  return 0
}

write_matrix(){
  python3 - "$MATRIX_CSV" "$CELL_SIZE" "$KBT" "$PARTICLE_MASS" <<'PY'
import csv, math, sys
out,h,kbt,m=sys.argv[1:]
h=float(h); kbt=float(kbt); m=float(m)
# Unique points only. Cross/collapse points are intentionally deferred until trends are examined.
rows=[]
for lam in (0.36,0.48,0.60,0.72,0.90):
    rows.append((f"L{int(round(100*lam)):03d}_G08_A120",8,120.0,lam,"ell_sweep"))
for gamma in (4,6,12,16):
    rows.append((f"L072_G{gamma:02d}_A120",gamma,120.0,0.72,"gamma_sweep"))
for alpha in (60,90,150):
    rows.append((f"L072_G08_A{alpha:03d}",8,float(alpha),0.72,"alpha_sweep"))
vmean=math.sqrt(math.pi*kbt/(2*m))
with open(out,'w',newline='') as f:
    w=csv.writer(f, lineterminator='\n')
    w.writerow(['case_id','sweep','gamma','alpha_SRC_deg','lambdaMeanOverH','ell','h','dt','kBT','m','seed1','seed2','seed3','soundSeedBase'])
    for i,(case,g,a,lam,sweep) in enumerate(rows):
        dt=lam*h/vmean
        ell=dt/h*math.sqrt(kbt/m)
        base=4933001+i*100
        seeds=(base,base+1,base+2)
        sound=4937001+i*100
        w.writerow([case,sweep,g,f'{a:.12g}',f'{lam:.12g}',f'{ell:.17g}',f'{h:.17g}',f'{dt:.17g}',f'{kbt:.17g}',f'{m:.17g}',*seeds,sound])
print(f'[0493x20a] matrix={out} configurations={len(rows)} pairedModels=2 solverRuns={len(rows)*15}')
PY
}

write_manifest(){
  local now git_head git_branch bin_sha cal_sha runner_sha
  now="$(date -Is 2>/dev/null || date)"
  git_head="$(git rev-parse HEAD 2>/dev/null || echo UNAVAILABLE)"
  git_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo UNAVAILABLE)"
  bin_sha="$(sha256sum "$BIN" 2>/dev/null | awk '{print $1}')"
  cal_sha="$(sha256sum "$CALIBRATOR" 2>/dev/null | awk '{print $1}')"
  runner_sha="$(sha256sum "${BASH_SOURCE[0]}" 2>/dev/null | awk '{print $1}')"
  cat > "$CAMPAIGN_ROOT/campaign_manifest.txt" <<META
campaign=0493x20a_article_fluid_campaign
created=$now
root=$ROOT
binary=$BIN
binarySha256=$bin_sha
calibrator=$CALIBRATOR
calibratorSha256=$cal_sha
runner=${BASH_SOURCE[0]}
runnerSha256=$runner_sha
gitHead=$git_head
gitBranch=$git_branch
cellSize=$CELL_SIZE
kBT=$KBT
particleMass=$PARTICLE_MASS
nx=$NX
ny=$NY
soundNx=$SOUND_NX
soundNy=$SOUND_NY
soundReplicates=$SOUND_REPLICATES
restart=$RESTART
continueOnError=$CONTINUE_ON_ERROR
liveProgress=$LIVE_PROGRESS
liveVisEnable=$LIVE_VIS_ENABLE
projectionOperator=$PROJECTION_OPERATOR
projectionTolerance=$PROJECTION_TOLERANCE
q6DensityRelaxationTime=$Q6_GF_DENSITY_RELAXATION_TIME
q6CompressionThresholdParticles=$Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES
q6TractionThresholdParticles=$Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES
q6TractionGain=$Q6_GF_DENSITY_TRACTION_GAIN
q6MinFillFraction=$Q6_GF_MIN_FILL_FRACTION
META
}

export_livevis(){
  if truthy "$LIVE_VIS_ENABLE"; then
    export SRC_LIVE_VIS_ENABLE=1 MPCD_LIVE_VIS_ENABLE=1
    export SRC_LIVE_VIS_EVERY="$LIVE_VIS_EVERY" MPCD_LIVE_VIS_EVERY="$LIVE_VIS_EVERY"
    export SRC_LIVE_VIS_NX="$LIVE_VIS_NX" SRC_LIVE_VIS_NY="$LIVE_VIS_NY"
    export SRC_LIVE_VIS_FIELD="$LIVE_VIS_FIELD" SRC_LIVE_VIS_HOLD_ON_EXIT="$LIVE_VIS_HOLD_ON_EXIT"
    if [[ -f "$ROOT/livevis_control.kv" ]]; then
      export SRC_LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
      export MPCD_LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
    else
      unset SRC_LIVE_VIS_CONTROL_FILE MPCD_LIVE_VIS_CONTROL_FILE
      echo "[0493x20a] NOTE LIVE_VIS_ENABLE=1 but ./livevis_control.kv is absent; using environment controls only"
    fi
  else
    export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0
    unset SRC_LIVE_VIS_CONTROL_FILE MPCD_LIVE_VIS_CONTROL_FILE
  fi
}

run_case_model(){
  local case_id="$1" gamma="$2" alpha="$3" lam="$4" s1="$5" s2="$6" s3="$7" sound_base="$8" model="$9" action="${10}"
  local rr="$CAMPAIGN_ROOT/configs/$case_id/$model"
  local exps seeds rc start end elapsed log
  seeds="$s1,$s2,$s3"
  if [[ "$model" == "src" ]]; then exps="tg sound msd"; else exps="tg msd"; fi
  mkdir -p "$rr" "$CAMPAIGN_ROOT/logs"
  log="$CAMPAIGN_ROOT/logs/${case_id}_${model}.log"

  echo "[0493x20a] $action case=$case_id model=$model gamma=$gamma alpha=$alpha lambdaMean/h=$lam seeds=$seeds"
  start="$(date +%s)"

  if [[ "$action" == "preflight" ]]; then
    env \
      ROOT="$ROOT" BIN="$BIN" CALIBRATION_PATH="$model" CALIBRATION_EXPERIMENTS="$exps" \
      RUN_ROOT="$rr" CLEAN_RUN_ROOT=0 SKIP_EXISTING=1 LIVE_PROGRESS="$LIVE_PROGRESS" THREADS="$THREADS" \
      CELL_SIZE="$CELL_SIZE" KBT="$KBT" PARTICLE_MASS="$PARTICLE_MASS" GAMMA="$gamma" ROTATION_ANGLE_DEG="$alpha" LAMBDA_OVER_H="$lam" \
      RANDOM_ROTATION_SIGN="$RANDOM_ROTATION_SIGN" GRID_SHIFT_ENABLE="$GRID_SHIFT_ENABLE" \
      THERMOSTAT_ENABLE="$THERMOSTAT_ENABLE" THERMOSTAT_MODE="$THERMOSTAT_MODE" THERMOSTAT_EVERY="$THERMOSTAT_EVERY" THERMOSTAT_MIN_PARTICLES="$THERMOSTAT_MIN_PARTICLES" \
      NX="$NX" NY="$NY" TG_TIME="$TG_TIME" TG_DUMP_COUNT="$TG_DUMP_COUNT" SEEDS="$seeds" \
      SOUND_NX="$SOUND_NX" SOUND_NY="$SOUND_NY" SOUND_CYCLES="$SOUND_CYCLES" SOUND_DUMP_COUNT="$SOUND_DUMP_COUNT" SOUND_REPLICATES="$SOUND_REPLICATES" SOUND_SEED_BASE="$sound_base" \
      MSD_NX="$MSD_NX" MSD_NY="$MSD_NY" MSD_TIME="$MSD_TIME" MSD_DUMP_COUNT="$MSD_DUMP_COUNT" MSD_SAMPLE_PARTICLES="$MSD_SAMPLE_PARTICLES" MSD_SEEDS="$seeds" \
      MAX_DUMP_GB="$MAX_DUMP_GB" \
      PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_OPERATOR="$PROJECTION_OPERATOR" PROJECTION_TOLERANCE="$PROJECTION_TOLERANCE" PROJECTION_MAX_ITERATIONS="$PROJECTION_MAX_ITERATIONS" \
      Q6_GF_DENSITY_RELAXATION_TIME="$Q6_GF_DENSITY_RELAXATION_TIME" Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="$Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE" \
      Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="$Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES" Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="$Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES" \
      Q6_GF_DENSITY_TRACTION_GAIN="$Q6_GF_DENSITY_TRACTION_GAIN" Q6_GF_MIN_FILL_FRACTION="$Q6_GF_MIN_FILL_FRACTION" MPCD_Q6_G_F_RESIDENT_CG_0493X7J="$MPCD_Q6_G_F_RESIDENT_CG_0493X7J" \
      bash "$CALIBRATOR" --preflight >"$log" 2>&1
    rc=$?
  else
    env \
      ROOT="$ROOT" BIN="$BIN" CALIBRATION_PATH="$model" CALIBRATION_EXPERIMENTS="$exps" \
      RUN_ROOT="$rr" CLEAN_RUN_ROOT=0 SKIP_EXISTING=1 LIVE_PROGRESS="$LIVE_PROGRESS" THREADS="$THREADS" \
      CELL_SIZE="$CELL_SIZE" KBT="$KBT" PARTICLE_MASS="$PARTICLE_MASS" GAMMA="$gamma" ROTATION_ANGLE_DEG="$alpha" LAMBDA_OVER_H="$lam" \
      RANDOM_ROTATION_SIGN="$RANDOM_ROTATION_SIGN" GRID_SHIFT_ENABLE="$GRID_SHIFT_ENABLE" \
      THERMOSTAT_ENABLE="$THERMOSTAT_ENABLE" THERMOSTAT_MODE="$THERMOSTAT_MODE" THERMOSTAT_EVERY="$THERMOSTAT_EVERY" THERMOSTAT_MIN_PARTICLES="$THERMOSTAT_MIN_PARTICLES" \
      NX="$NX" NY="$NY" TG_TIME="$TG_TIME" TG_DUMP_COUNT="$TG_DUMP_COUNT" SEEDS="$seeds" \
      SOUND_NX="$SOUND_NX" SOUND_NY="$SOUND_NY" SOUND_CYCLES="$SOUND_CYCLES" SOUND_DUMP_COUNT="$SOUND_DUMP_COUNT" SOUND_REPLICATES="$SOUND_REPLICATES" SOUND_SEED_BASE="$sound_base" \
      MSD_NX="$MSD_NX" MSD_NY="$MSD_NY" MSD_TIME="$MSD_TIME" MSD_DUMP_COUNT="$MSD_DUMP_COUNT" MSD_SAMPLE_PARTICLES="$MSD_SAMPLE_PARTICLES" MSD_SEEDS="$seeds" \
      MAX_DUMP_GB="$MAX_DUMP_GB" \
      PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_OPERATOR="$PROJECTION_OPERATOR" PROJECTION_TOLERANCE="$PROJECTION_TOLERANCE" PROJECTION_MAX_ITERATIONS="$PROJECTION_MAX_ITERATIONS" \
      Q6_GF_DENSITY_RELAXATION_TIME="$Q6_GF_DENSITY_RELAXATION_TIME" Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="$Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE" \
      Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="$Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES" Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="$Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES" \
      Q6_GF_DENSITY_TRACTION_GAIN="$Q6_GF_DENSITY_TRACTION_GAIN" Q6_GF_MIN_FILL_FRACTION="$Q6_GF_MIN_FILL_FRACTION" MPCD_Q6_G_F_RESIDENT_CG_0493X7J="$MPCD_Q6_G_F_RESIDENT_CG_0493X7J" \
      bash "$CALIBRATOR" >"$log" 2>&1
    rc=$?
  fi

  end="$(date +%s)"; elapsed=$((end-start))
  if [[ $rc -eq 0 ]]; then
    echo "[0493x20a] PASS case=$case_id model=$model elapsed=${elapsed}s"
  else
    echo "[0493x20a] FAIL case=$case_id model=$model rc=$rc elapsed=${elapsed}s log=$log" >&2
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -Is 2>/dev/null || date)" "$case_id" "$model" "$action" "$rc" "$elapsed" >> "$STATUS_TSV"
  return "$rc"
}

aggregate(){
  python3 - "$CAMPAIGN_ROOT" "$MATRIX_CSV" "$AGG_CSV" "$RATIO_CSV" "$REAL_CSV" <<'PY'
import csv,json,math,sys
from pathlib import Path
root=Path(sys.argv[1]); matrix=Path(sys.argv[2]); agg=Path(sys.argv[3]); ratios=Path(sys.argv[4]); real=Path(sys.argv[5])
M=list(csv.DictReader(matrix.open()))
rows=[]; realiz=[]
for c in M:
    for model in ('src','src-q6-g-f'):
        ar=root/'configs'/c['case_id']/model/'analysis'
        jf=ar/'fluid_characterization.json'
        if not jf.exists():
            rows.append({**c,'model':model,'status':'MISSING'})
            continue
        try: d=json.loads(jf.read_text())
        except Exception as e:
            rows.append({**c,'model':model,'status':'JSON_ERROR','error':str(e)}); continue
        h=float(c['h']); dt=float(c['dt'])
        nu=d.get('viscosityKinematic'); D=d.get('selfDiffusion')
        row={**c,'model':model,'status':d.get('status'),'nu_eff':nu,'nu_std':d.get('viscosityStd'),'nu_CV':d.get('viscosityCV'),
             'D_self':D,'D_std':d.get('selfDiffusionStd'),'D_CV':d.get('selfDiffusionCV'),'Sc':d.get('Schmidt'),
             'sound_status':d.get('soundStatus'),'c':d.get('soundSpeed'),'longitudinal_response_status':d.get('longitudinalResponseDiagnosticStatus')}
        row['nu_star']=None if nu is None else float(nu)*dt/(h*h)
        row['D_star']=None if D is None else float(D)*dt/(h*h)
        if model=='src' and d.get('soundSpeed') is not None:
            row['c_star']=float(d['soundSpeed'])*dt/h
            row['c_over_thermal']=float(d['soundSpeed'])/math.sqrt(float(c['kBT'])/float(c['m']))
        else:
            row['c_star']=None; row['c_over_thermal']=None
        rows.append(row)
        for tr in d.get('tgRuns',[]):
            realiz.append({'case_id':c['case_id'],'model':model,'experiment':'tg','replicate':tr.get('seed'),'status':tr.get('status'),'value':tr.get('nu'),'fit_R2':tr.get('R2')})
        for mr in d.get('msdRuns',[]):
            realiz.append({'case_id':c['case_id'],'model':model,'experiment':'msd','replicate':mr.get('seed'),'status':mr.get('status'),'value':mr.get('Dself'),'fit_R2':mr.get('R2')})
        if d.get('sound') is not None:
            sr=d['sound']
            realiz.append({'case_id':c['case_id'],'model':model,'experiment':'sound_pooled','replicate':sr.get('replicates'),'status':sr.get('status'),'value':sr.get('soundSpeed'),'fit_R2':''})

def write(path, rr):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not rr: path.write_text(''); return
    keys=[]
    for r in rr:
        for k in r:
            if k not in keys: keys.append(k)
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=keys); w.writeheader(); w.writerows(rr)
write(agg,rows); write(real,realiz)
by={}
for r in rows: by.setdefault(r['case_id'],{})[r['model']]=r
q=[]
for c in M:
    p=by.get(c['case_id'],{}); s=p.get('src'); g=p.get('src-q6-g-f')
    rr={k:c[k] for k in ('case_id','sweep','gamma','alpha_SRC_deg','lambdaMeanOverH','ell','h','dt','kBT','m')}
    if s and g and s.get('nu_eff') not in (None,'') and g.get('nu_eff') not in (None,''):
        rr['R_nu']=float(g['nu_eff'])/float(s['nu_eff'])
        rr['delta_nu_relative']=rr['R_nu']-1.0
    else: rr['R_nu']=rr['delta_nu_relative']=None
    if s and g and s.get('D_self') not in (None,'') and g.get('D_self') not in (None,''):
        rr['R_D']=float(g['D_self'])/float(s['D_self'])
        rr['delta_D_relative']=rr['R_D']-1.0
    else: rr['R_D']=rr['delta_D_relative']=None
    q.append(rr)
write(ratios,q)
print(f'[0493x20a] aggregate rows={len(rows)} -> {agg}')
print(f'[0493x20a] ratios rows={len(q)} -> {ratios}')
print(f'[0493x20a] realizations rows={len(realiz)} -> {real}')
PY
}

status(){
  python3 - "$CAMPAIGN_ROOT" "$MATRIX_CSV" <<'PY'
import csv,json,sys
from pathlib import Path
root=Path(sys.argv[1]); M=list(csv.DictReader(open(sys.argv[2])))
expected=len(M)*2; done=0; good=0
for c in M:
    for model in ('src','src-q6-g-f'):
        p=root/'configs'/c['case_id']/model/'analysis'/'fluid_characterization.json'
        if p.exists():
            done+=1
            try:
                d=json.loads(p.read_text())
                if d.get('status') in ('PASS','REVIEW'): good+=1
                print(f"{c['case_id']:18s} {model:12s} {d.get('status','?'):8s} nu={d.get('viscosityKinematic')} D={d.get('selfDiffusion')} Sc={d.get('Schmidt')}")
            except Exception as e: print(f"{c['case_id']:18s} {model:12s} JSON_ERROR {e}")
        else:
            print(f"{c['case_id']:18s} {model:12s} PENDING")
print(f'[0493x20a] completed configurations={done}/{expected}; PASS_or_REVIEW={good}/{done if done else 0}')
PY
}

write_matrix
if [[ "$MODE" == "--matrix" ]]; then cat "$MATRIX_CSV"; exit 0; fi
check_prereqs || exit $?
write_manifest
export_livevis

if [[ "$MODE" == "--aggregate" ]]; then aggregate; status; exit 0; fi
if [[ "$MODE" == "--status" ]]; then status; exit 0; fi

if [[ ! -f "$STATUS_TSV" ]]; then printf 'timestamp\tcase_id\tmodel\taction\trc\telapsed_s\n' > "$STATUS_TSV"; fi

action="run"
[[ "$MODE" == "--preflight" ]] && action="preflight"

failures=0
while IFS=',' read -r case_id sweep gamma alpha lam ell h dt kbt mass s1 s2 s3 sound_base; do
  [[ "$case_id" == "case_id" ]] && continue
  for model in src src-q6-g-f; do
    run_case_model "$case_id" "$gamma" "$alpha" "$lam" "$s1" "$s2" "$s3" "$sound_base" "$model" "$action"
    rc=$?
    if [[ $rc -ne 0 ]]; then
      failures=$((failures+1))
      if ! truthy "$CONTINUE_ON_ERROR"; then
        echo "[0493x20a] stopping on first error (CONTINUE_ON_ERROR=$CONTINUE_ON_ERROR)" >&2
        exit "$rc"
      fi
    fi
    if [[ "$action" == "run" ]]; then aggregate >/dev/null 2>&1 || true; fi
  done
done < "$MATRIX_CSV"

if [[ "$action" == "run" ]]; then
  aggregate
  status
fi
if [[ $failures -ne 0 ]]; then
  echo "[0493x20a] COMPLETE WITH FAILURES=$failures; rerun with RESTART=1 to retry incomplete realizations" >&2
  exit 4
fi
echo "[0493x20a] COMPLETE PASS mode=$MODE"
exit 0
