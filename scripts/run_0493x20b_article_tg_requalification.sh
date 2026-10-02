#!/usr/bin/env bash
# SRC_GPU-SURF 0493x20b — long Taylor-Green requalification for JCP article campaign
# Replays TG only on the 12 x20a physical points, paired SRC/Q6-G-F.
# Larger domain + case-adapted duration + six common seeds. No solver/source change.

ROOT="${ROOT:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT" || exit 2

MODE="${1:---run}"
case "$MODE" in
  --run|--preflight|--matrix|--aggregate|--status) ;;
  -h|--help)
    cat <<'USAGE'
Usage:
  bash scripts/run_0493x20b_article_tg_requalification.sh --preflight
  bash scripts/run_0493x20b_article_tg_requalification.sh --run
  bash scripts/run_0493x20b_article_tg_requalification.sh --status
  bash scripts/run_0493x20b_article_tg_requalification.sh --aggregate
  bash scripts/run_0493x20b_article_tg_requalification.sh --matrix

Purpose:
  Long/reliable TG-only requalification after the short x20a pilot campaign.
  MSD and SRC acoustics are NOT replayed because the x20a measurements were already clean.

Defaults:
  CAMPAIGN_ROOT=runs/0493x20b_article_tg_requalification
  CALIBRATOR=scripts/calibrate_fluid_0493w1_standalone.sh
  BIN=build/src_mpcd_base_cuda_q6_resident_livevis_0486
  NX=NY=128
  TG seeds=6 common seeds/model/case (the original 3 + 3 new independent seeds)
  RESTART=1, CONTINUE_ON_ERROR=1, LIVE_PROGRESS=1
  LIVE_VIS_ENABLE=0 for this batch metrology campaign (enable explicitly if desired)

Case-adapted TG durations on the 128x128 domain:
  L036 16, L048 18, L060 20, L072 20, L090 18
  G04  12, G06  20, G12  22, G16  20
  A060 32, A090 36, A150 10
Dump count is max(48, ceil(T/0.4)), giving at least 48 modal samples while
keeping the raw-state volume bounded.

Total solver invocations: 12 cases * 2 models * 6 TG seeds = 144 TG runs.
USAGE
    exit 0
    ;;
  *) echo "[0493x20b] ERROR unknown mode: $MODE" >&2; exit 2 ;;
esac

CALIBRATOR="${CALIBRATOR:-scripts/calibrate_fluid_0493w1_standalone.sh}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x20b_article_tg_requalification}"
PILOT_ROOT="${PILOT_ROOT:-runs/0493x20a_article_fluid_campaign}"
RESTART="${RESTART:-1}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"

CELL_SIZE="${CELL_SIZE:-0.00390625}"
KBT="${KBT:-0.125}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

# Long TG metrology. 128^2 gives four times the linear-decay time scale of the
# x20a 64^2 domain and about twice the modal SNR from spatial averaging.
NX="${NX:-128}"
NY="${NY:-128}"
TG_MODE_X="${TG_MODE_X:-1}"
TG_MODE_Y="${TG_MODE_Y:-1}"
TG_DUMP_INTERVAL_PHYS="${TG_DUMP_INTERVAL_PHYS:-0.4}"
TG_MIN_DUMP_COUNT="${TG_MIN_DUMP_COUNT:-48}"
MAX_DUMP_GB="${MAX_DUMP_GB:-6.0}"
ALLOW_LARGE_DUMPS="${ALLOW_LARGE_DUMPS:-0}"

# Production Q6-G-F closure contract, unchanged from x20a.
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

# Batch calibration: LiveVis disabled by default for throughput and timing purity.
# It remains available and, if enabled, uses ./livevis_control.kv without editing it.
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
AGG_CSV="$CAMPAIGN_ROOT/summary/tg_results_aggregated.csv"
RATIO_CSV="$CAMPAIGN_ROOT/summary/tg_ratios_paired.csv"
REAL_CSV="$CAMPAIGN_ROOT/summary/tg_realizations.csv"
PILOT_COMPARE_CSV="$CAMPAIGN_ROOT/summary/tg_vs_x20a_pilot.csv"

check_prereqs(){
  local c
  for c in bash python3 awk sed grep sha256sum; do
    command -v "$c" >/dev/null 2>&1 || { echo "[0493x20b] ERROR missing command: $c" >&2; return 2; }
  done
  [[ -f "$CALIBRATOR" ]] || { echo "[0493x20b] ERROR calibrator missing: $CALIBRATOR" >&2; return 2; }
  [[ -x "$BIN" ]] || { echo "[0493x20b] ERROR solver binary not executable: $BIN" >&2; return 2; }
  return 0
}

write_matrix(){
  python3 - "$MATRIX_CSV" "$CELL_SIZE" "$KBT" "$PARTICLE_MASS" "$TG_DUMP_INTERVAL_PHYS" "$TG_MIN_DUMP_COUNT" <<'PY'
import csv, math, sys
out,h,kbt,m,dump_dt,min_dumps=sys.argv[1:]
h=float(h); kbt=float(kbt); m=float(m); dump_dt=float(dump_dt); min_dumps=int(min_dumps)
# Durations selected from the x20a pilot viscosities after increasing TG L from 0.25 to 0.5.
# The target is roughly >=3 e-folding times of the slower measured path, with margin.
rows=[
 ('L036_G08_A120','ell_sweep',8,120.0,0.36,16.0),
 ('L048_G08_A120','ell_sweep',8,120.0,0.48,18.0),
 ('L060_G08_A120','ell_sweep',8,120.0,0.60,20.0),
 ('L072_G08_A120','ell_sweep',8,120.0,0.72,20.0),
 ('L090_G08_A120','ell_sweep',8,120.0,0.90,18.0),
 ('L072_G04_A120','gamma_sweep',4,120.0,0.72,12.0),
 ('L072_G06_A120','gamma_sweep',6,120.0,0.72,20.0),
 ('L072_G12_A120','gamma_sweep',12,120.0,0.72,22.0),
 ('L072_G16_A120','gamma_sweep',16,120.0,0.72,20.0),
 ('L072_G08_A060','alpha_sweep',8,60.0,0.72,32.0),
 ('L072_G08_A090','alpha_sweep',8,90.0,0.72,36.0),
 ('L072_G08_A150','alpha_sweep',8,150.0,0.72,10.0),
]
vmean=math.sqrt(math.pi*kbt/(2*m))
with open(out,'w',newline='') as f:
    w=csv.writer(f,lineterminator='\n')
    w.writerow(['case_id','sweep','gamma','alpha_SRC_deg','lambdaMeanOverH','ell','h','dt','kBT','m','tg_time','tg_dump_count','seed1','seed2','seed3','seed4','seed5','seed6'])
    for i,(case,sweep,g,a,lam,T) in enumerate(rows):
        dt=lam*h/vmean
        ell=dt/h*math.sqrt(kbt/m)
        base=4933001+i*100
        seeds=(base,base+1,base+2,base+41,base+42,base+43)
        nd=max(min_dumps,int(math.ceil(T/dump_dt)))
        w.writerow([case,sweep,g,f'{a:.12g}',f'{lam:.12g}',f'{ell:.17g}',f'{h:.17g}',f'{dt:.17g}',f'{kbt:.17g}',f'{m:.17g}',f'{T:.12g}',nd,*seeds])
print(f'[0493x20b] matrix={out} configurations={len(rows)} pairedModels=2 tgSeeds=6 solverRuns={len(rows)*2*6}')
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
campaign=0493x20b_article_tg_requalification
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
pilotRoot=$PILOT_ROOT
cellSize=$CELL_SIZE
kBT=$KBT
particleMass=$PARTICLE_MASS
nx=$NX
ny=$NY
tgModeX=$TG_MODE_X
tgModeY=$TG_MODE_Y
tgSeedsPerModel=6
tgDumpIntervalPhysicalTarget=$TG_DUMP_INTERVAL_PHYS
tgMinDumpCount=$TG_MIN_DUMP_COUNT
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
      echo "[0493x20b] NOTE LIVE_VIS_ENABLE=1 but ./livevis_control.kv is absent; environment controls only"
    fi
  else
    export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0
    unset SRC_LIVE_VIS_CONTROL_FILE MPCD_LIVE_VIS_CONTROL_FILE
  fi
}

run_case_model(){
  local case_id="$1" gamma="$2" alpha="$3" lam="$4" tg_time="$5" tg_dumps="$6" seeds="$7" model="$8" action="$9"
  local rr="$CAMPAIGN_ROOT/configs/$case_id/$model"
  local rc start end elapsed log skip_existing
  mkdir -p "$rr" "$CAMPAIGN_ROOT/logs"
  log="$CAMPAIGN_ROOT/logs/${case_id}_${model}.log"
  skip_existing=0
  truthy "$RESTART" && skip_existing=1

  echo "[0493x20b] $action case=$case_id model=$model gamma=$gamma alpha=$alpha lambdaMean/h=$lam TG_T=$tg_time dumps=$tg_dumps seeds=$seeds"
  start="$(date +%s)"

  if [[ "$action" == "preflight" ]]; then
    env \
      ROOT="$ROOT" BIN="$BIN" CALIBRATION_PATH="$model" CALIBRATION_EXPERIMENTS=tg \
      RUN_ROOT="$rr" CLEAN_RUN_ROOT=0 SKIP_EXISTING="$skip_existing" LIVE_PROGRESS="$LIVE_PROGRESS" THREADS="$THREADS" \
      CELL_SIZE="$CELL_SIZE" KBT="$KBT" PARTICLE_MASS="$PARTICLE_MASS" GAMMA="$gamma" ROTATION_ANGLE_DEG="$alpha" LAMBDA_OVER_H="$lam" \
      RANDOM_ROTATION_SIGN="$RANDOM_ROTATION_SIGN" GRID_SHIFT_ENABLE="$GRID_SHIFT_ENABLE" \
      THERMOSTAT_ENABLE="$THERMOSTAT_ENABLE" THERMOSTAT_MODE="$THERMOSTAT_MODE" THERMOSTAT_EVERY="$THERMOSTAT_EVERY" THERMOSTAT_MIN_PARTICLES="$THERMOSTAT_MIN_PARTICLES" \
      NX="$NX" NY="$NY" TG_MODE_X="$TG_MODE_X" TG_MODE_Y="$TG_MODE_Y" TG_TIME="$tg_time" TG_DUMP_COUNT="$tg_dumps" SEEDS="$seeds" \
      MAX_DUMP_GB="$MAX_DUMP_GB" ALLOW_LARGE_DUMPS="$ALLOW_LARGE_DUMPS" \
      PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_OPERATOR="$PROJECTION_OPERATOR" PROJECTION_TOLERANCE="$PROJECTION_TOLERANCE" PROJECTION_MAX_ITERATIONS="$PROJECTION_MAX_ITERATIONS" \
      Q6_GF_DENSITY_RELAXATION_TIME="$Q6_GF_DENSITY_RELAXATION_TIME" Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="$Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE" \
      Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="$Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES" Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="$Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES" \
      Q6_GF_DENSITY_TRACTION_GAIN="$Q6_GF_DENSITY_TRACTION_GAIN" Q6_GF_MIN_FILL_FRACTION="$Q6_GF_MIN_FILL_FRACTION" MPCD_Q6_G_F_RESIDENT_CG_0493X7J="$MPCD_Q6_G_F_RESIDENT_CG_0493X7J" \
      bash "$CALIBRATOR" --preflight >"$log" 2>&1
    rc=$?
  else
    env \
      ROOT="$ROOT" BIN="$BIN" CALIBRATION_PATH="$model" CALIBRATION_EXPERIMENTS=tg \
      RUN_ROOT="$rr" CLEAN_RUN_ROOT=0 SKIP_EXISTING="$skip_existing" LIVE_PROGRESS="$LIVE_PROGRESS" THREADS="$THREADS" \
      CELL_SIZE="$CELL_SIZE" KBT="$KBT" PARTICLE_MASS="$PARTICLE_MASS" GAMMA="$gamma" ROTATION_ANGLE_DEG="$alpha" LAMBDA_OVER_H="$lam" \
      RANDOM_ROTATION_SIGN="$RANDOM_ROTATION_SIGN" GRID_SHIFT_ENABLE="$GRID_SHIFT_ENABLE" \
      THERMOSTAT_ENABLE="$THERMOSTAT_ENABLE" THERMOSTAT_MODE="$THERMOSTAT_MODE" THERMOSTAT_EVERY="$THERMOSTAT_EVERY" THERMOSTAT_MIN_PARTICLES="$THERMOSTAT_MIN_PARTICLES" \
      NX="$NX" NY="$NY" TG_MODE_X="$TG_MODE_X" TG_MODE_Y="$TG_MODE_Y" TG_TIME="$tg_time" TG_DUMP_COUNT="$tg_dumps" SEEDS="$seeds" \
      MAX_DUMP_GB="$MAX_DUMP_GB" ALLOW_LARGE_DUMPS="$ALLOW_LARGE_DUMPS" \
      PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_OPERATOR="$PROJECTION_OPERATOR" PROJECTION_TOLERANCE="$PROJECTION_TOLERANCE" PROJECTION_MAX_ITERATIONS="$PROJECTION_MAX_ITERATIONS" \
      Q6_GF_DENSITY_RELAXATION_TIME="$Q6_GF_DENSITY_RELAXATION_TIME" Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="$Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE" \
      Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="$Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES" Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="$Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES" \
      Q6_GF_DENSITY_TRACTION_GAIN="$Q6_GF_DENSITY_TRACTION_GAIN" Q6_GF_MIN_FILL_FRACTION="$Q6_GF_MIN_FILL_FRACTION" MPCD_Q6_G_F_RESIDENT_CG_0493X7J="$MPCD_Q6_G_F_RESIDENT_CG_0493X7J" \
      bash "$CALIBRATOR" >"$log" 2>&1
    rc=$?
  fi

  end="$(date +%s)"; elapsed=$((end-start))
  if [[ $rc -eq 0 ]]; then
    echo "[0493x20b] PASS case=$case_id model=$model elapsed=${elapsed}s"
  else
    echo "[0493x20b] FAIL case=$case_id model=$model rc=$rc elapsed=${elapsed}s log=$log" >&2
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -Is 2>/dev/null || date)" "$case_id" "$model" "$action" "$rc" "$elapsed" >> "$STATUS_TSV"
  return "$rc"
}

aggregate(){
  python3 - "$CAMPAIGN_ROOT" "$MATRIX_CSV" "$AGG_CSV" "$RATIO_CSV" "$REAL_CSV" "$PILOT_ROOT" "$PILOT_COMPARE_CSV" <<'PY'
import csv, json, math, statistics, sys
from pathlib import Path
root=Path(sys.argv[1]); matrix=Path(sys.argv[2]); agg=Path(sys.argv[3]); ratios=Path(sys.argv[4]); real=Path(sys.argv[5]); pilot_root=Path(sys.argv[6]); pilot_cmp=Path(sys.argv[7])
M=list(csv.DictReader(matrix.open()))
rows=[]; realiz=[]; per_case={}

def finite(x):
    try: return math.isfinite(float(x))
    except Exception: return False

def mean_sd_cv(v):
    v=[float(x) for x in v]
    if not v: return None,None,None
    mu=sum(v)/len(v)
    sd=statistics.stdev(v) if len(v)>1 else 0.0
    return mu,sd,(sd/mu if mu else None)

for c in M:
    per_case[c['case_id']]={}
    for model in ('src','src-q6-g-f'):
        jf=root/'configs'/c['case_id']/model/'analysis'/'fluid_characterization.json'
        if not jf.exists():
            r={**c,'model':model,'status':'MISSING','viscosity_status':'MISSING'}
            rows.append(r); per_case[c['case_id']][model]=r; continue
        try: d=json.loads(jf.read_text())
        except Exception as e:
            r={**c,'model':model,'status':'JSON_ERROR','viscosity_status':'JSON_ERROR','error':str(e)}
            rows.append(r); per_case[c['case_id']][model]=r; continue
        trs=d.get('tgRuns',[])
        usable=[x for x in trs if x.get('status') in ('PASS','REVIEW') and finite(x.get('nu'))]
        r2=[float(x['R2']) for x in trs if finite(x.get('R2'))]
        r={**c,'model':model,'status':d.get('status'),'viscosity_status':d.get('viscosityStatus'),
           'nu_eff':d.get('viscosityKinematic'),'nu_std':d.get('viscosityStd'),'nu_CV':d.get('viscosityCV'),
           'n_runs':len(trs),'n_usable':len(usable),'n_pass':sum(x.get('status')=='PASS' for x in trs),
           'n_review':sum(x.get('status')=='REVIEW' for x in trs),'n_invalid':sum(x.get('status')=='INVALID' for x in trs),
           'mean_fit_R2':sum(r2)/len(r2) if r2 else None,'min_fit_R2':min(r2) if r2 else None}
        h=float(c['h']); dt=float(c['dt'])
        r['nu_star']=float(r['nu_eff'])*dt/(h*h) if finite(r.get('nu_eff')) else None
        rows.append(r); per_case[c['case_id']][model]=r
        for tr in trs:
            realiz.append({'case_id':c['case_id'],'model':model,'seed':tr.get('seed'),'status':tr.get('status'),'nu_eff':tr.get('nu'),'fit_R2':tr.get('R2'),'fit_points':tr.get('fitPoints'),'window_std':tr.get('windowStd'),'window_min':tr.get('windowMin'),'window_max':tr.get('windowMax')})

def write(path, rr):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not rr: path.write_text(''); return
    keys=[]
    for r in rr:
        for k in r:
            if k not in keys: keys.append(k)
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=keys,lineterminator='\n'); w.writeheader(); w.writerows(rr)

write(agg,rows); write(real,realiz)

# Status-aware paired ratios. Invalid ensemble values are never published as article ratios.
real_index={(r['case_id'],r['model'],str(r['seed'])):r for r in realiz}
q=[]
for c in M:
    s=per_case[c['case_id']].get('src',{}); g=per_case[c['case_id']].get('src-q6-g-f',{})
    rr={k:c[k] for k in ('case_id','sweep','gamma','alpha_SRC_deg','lambdaMeanOverH','ell','h','dt','kBT','m','tg_time','tg_dump_count')}
    ss=s.get('viscosity_status'); gs=g.get('viscosity_status')
    if ss=='PASS' and gs=='PASS': ratio_status='PASS'
    elif ss in ('PASS','REVIEW') and gs in ('PASS','REVIEW'): ratio_status='REVIEW'
    else: ratio_status='INVALID'
    rr['ratio_status']=ratio_status; rr['src_viscosity_status']=ss; rr['q6gf_viscosity_status']=gs
    if ratio_status!='INVALID' and finite(s.get('nu_eff')) and finite(g.get('nu_eff')):
        rr['R_nu_ratio_of_means']=float(g['nu_eff'])/float(s['nu_eff'])
        rr['delta_nu_relative']=rr['R_nu_ratio_of_means']-1.0
    else:
        rr['R_nu_ratio_of_means']=None; rr['delta_nu_relative']=None
    paired=[]
    for key in ('seed1','seed2','seed3','seed4','seed5','seed6'):
        seed=str(c[key])
        a=real_index.get((c['case_id'],'src',seed)); b=real_index.get((c['case_id'],'src-q6-g-f',seed))
        if a and b and a.get('status') in ('PASS','REVIEW') and b.get('status') in ('PASS','REVIEW') and finite(a.get('nu_eff')) and finite(b.get('nu_eff')):
            paired.append(float(b['nu_eff'])/float(a['nu_eff']))
    mu,sd,cv=mean_sd_cv(paired)
    rr['paired_seed_count']=len(paired); rr['R_nu_paired_mean']=mu; rr['R_nu_paired_std']=sd; rr['R_nu_paired_CV']=cv
    q.append(rr)
write(ratios,q)

# Optional comparison with the short x20a pilot aggregate if present.
pc=[]
pilot_file=pilot_root/'summary'/'campaign_results_aggregated.csv'
if pilot_file.exists():
    old={(r['case_id'],r['model']):r for r in csv.DictReader(pilot_file.open())}
    for r in rows:
        o=old.get((r['case_id'],r['model']))
        if not o: continue
        z={'case_id':r['case_id'],'model':r['model'],'pilot_status':o.get('status'),'long_status':r.get('viscosity_status'),'pilot_nu':o.get('nu_eff'),'long_nu':r.get('nu_eff')}
        if finite(o.get('nu_eff')) and finite(r.get('nu_eff')):
            z['long_over_pilot_nu']=float(r['nu_eff'])/float(o['nu_eff']); z['relative_shift']=z['long_over_pilot_nu']-1.0
        pc.append(z)
write(pilot_cmp,pc)
print(f'[0493x20b] aggregate rows={len(rows)} -> {agg}')
print(f'[0493x20b] paired ratios rows={len(q)} -> {ratios}')
print(f'[0493x20b] realizations rows={len(realiz)} -> {real}')
if pc: print(f'[0493x20b] pilot comparison rows={len(pc)} -> {pilot_cmp}')
PY
}

status(){
  python3 - "$CAMPAIGN_ROOT" "$MATRIX_CSV" <<'PY'
import csv,json,sys
from pathlib import Path
root=Path(sys.argv[1]); M=list(csv.DictReader(open(sys.argv[2])))
done=0; good=0
for c in M:
    for model in ('src','src-q6-g-f'):
        p=root/'configs'/c['case_id']/model/'analysis'/'fluid_characterization.json'
        if p.exists():
            done+=1
            try:
                d=json.loads(p.read_text()); st=d.get('viscosityStatus','?')
                if st in ('PASS','REVIEW'): good+=1
                print(f"{c['case_id']:18s} {model:12s} {st:8s} nu={d.get('viscosityKinematic')} CV={d.get('viscosityCV')}")
            except Exception as e: print(f"{c['case_id']:18s} {model:12s} JSON_ERROR {e}")
        else: print(f"{c['case_id']:18s} {model:12s} PENDING")
print(f'[0493x20b] completed model-cases={done}/{len(M)*2}; PASS_or_REVIEW={good}/{done if done else 0}')
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
action=run
[[ "$MODE" == "--preflight" ]] && action=preflight
failures=0

while IFS=',' read -r case_id sweep gamma alpha lam ell h dt kbt mass tg_time tg_dumps s1 s2 s3 s4 s5 s6; do
  [[ "$case_id" == "case_id" ]] && continue
  seeds="$s1,$s2,$s3,$s4,$s5,$s6"
  for model in src src-q6-g-f; do
    run_case_model "$case_id" "$gamma" "$alpha" "$lam" "$tg_time" "$tg_dumps" "$seeds" "$model" "$action"
    rc=$?
    if [[ $rc -ne 0 ]]; then
      failures=$((failures+1))
      if ! truthy "$CONTINUE_ON_ERROR"; then
        echo "[0493x20b] stopping on first error (CONTINUE_ON_ERROR=$CONTINUE_ON_ERROR)" >&2
        exit "$rc"
      fi
    fi
    if [[ "$action" == "run" ]]; then aggregate >/dev/null 2>&1 || true; fi
  done
done < "$MATRIX_CSV"

if [[ "$action" == "run" ]]; then aggregate; status; fi
if [[ $failures -ne 0 ]]; then
  echo "[0493x20b] COMPLETE WITH FAILURES=$failures; rerun with RESTART=1 to retry incomplete seeds" >&2
  exit 4
fi
echo "[0493x20b] COMPLETE PASS mode=$MODE"
exit 0
