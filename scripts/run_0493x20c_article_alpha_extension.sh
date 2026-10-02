#!/usr/bin/env bash
# SRC_GPU-SURF 0493x20c — extension du balayage alpha pour la campagne article.
# Points additionnels: 30,45,165,175 deg; gamma=8; lambdaMean/h=0.72.
# SRC et Q6-G-F apparies; 6 seeds; TG 128^2 + MSD 64^2. Aucun son, aucun changement solveur.

ROOT="${ROOT:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)" || exit 2
cd "$ROOT" || exit 2

MODE="${1:---run}"
case "$MODE" in
  --run|--preflight|--status|--matrix) ;;
  -h|--help)
    cat <<'USAGE'
Usage:
  bash scripts/run_0493x20c_article_alpha_extension.sh --preflight
  bash scripts/run_0493x20c_article_alpha_extension.sh --run
  bash scripts/run_0493x20c_article_alpha_extension.sh --status
  bash scripts/run_0493x20c_article_alpha_extension.sh --matrix

Campagne:
  alpha_SRC = 30, 45, 165, 175 deg
  gamma = 8 ; lambdaMean/h = 0.72 ; kBT = 0.125 ; m = 1 ; h = 1/256
  models = src, src-q6-g-f
  6 seeds communes SRC/Q6-G-F par angle
  TG: 128x128, mode (1,1), temps adapte par angle
  MSD: 64x64, temps adapte par angle
  acoustique: non rejouee

Runs solveur: 4 angles * 2 modeles * (6 TG + 6 MSD) = 96.
RESTART=1 / SKIP_EXISTING=1 par defaut.
USAGE
    exit 0
    ;;
  *) echo "[0493x20c] ERROR unknown mode: $MODE" >&2; exit 2 ;;
esac

CALIBRATOR="${CALIBRATOR:-scripts/calibrate_fluid_0493w1_standalone.sh}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x20c_article_alpha_extension}"
RESTART="${RESTART:-1}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"

CELL_SIZE="${CELL_SIZE:-0.00390625}"
KBT="${KBT:-0.125}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
GAMMA="${GAMMA:-8}"
LAMBDA_OVER_H="${LAMBDA_OVER_H:-0.72}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

# TG: meme longueur d'onde hydrodynamique que x20b, avec echantillonnage plus dense
# aux grands angles ou la relaxation peut etre rapide.
TG_NX="${TG_NX:-128}"
TG_NY="${TG_NY:-128}"
TG_MODE_X="${TG_MODE_X:-1}"
TG_MODE_Y="${TG_MODE_Y:-1}"

# MSD: la campagne x20a a montre des fits tres propres en 64^2; inutile de payer 128^2.
MSD_NX="${MSD_NX:-64}"
MSD_NY="${MSD_NY:-64}"
MSD_SAMPLE_PARTICLES="${MSD_SAMPLE_PARTICLES:-20000}"

MAX_DUMP_GB="${MAX_DUMP_GB:-8.0}"
ALLOW_LARGE_DUMPS="${ALLOW_LARGE_DUMPS:-0}"

# Contrat Q6-G-F de production, identique x20a/x20b.
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

# Batch de petites grilles: LiveVis OFF par defaut, mais utilisable sans toucher au fichier de controle.
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
MATRIX="$CAMPAIGN_ROOT/campaign_matrix.csv"
STATUS="$CAMPAIGN_ROOT/summary/campaign_status.tsv"

write_matrix(){
  cat > "$MATRIX" <<'CSV'
case_id,alpha_SRC_deg,tg_time,tg_dumps,msd_time,msd_dumps,seed1,seed2,seed3,seed4,seed5,seed6
L072_G08_A030,30,16,96,4,80,4934201,4934202,4934203,4934242,4934243,4934244
L072_G08_A045,45,24,96,5,80,4934301,4934302,4934303,4934342,4934343,4934344
L072_G08_A165,165,10,120,8,96,4934401,4934402,4934403,4934442,4934443,4934444
L072_G08_A175,175,8,120,10,120,4934501,4934502,4934503,4934542,4934543,4934544
CSV
  echo "[0493x20c] matrix=$MATRIX configurations=4 pairedModels=2 seeds=6 experiments=tg+msd solverRuns=96"
}

check_prereqs(){
  command -v bash >/dev/null 2>&1 || { echo "[0493x20c] ERROR bash missing" >&2; return 2; }
  command -v python3 >/dev/null 2>&1 || { echo "[0493x20c] ERROR python3 missing" >&2; return 2; }
  [[ -f "$CALIBRATOR" ]] || { echo "[0493x20c] ERROR calibrator missing: $CALIBRATOR" >&2; return 2; }
  [[ -x "$BIN" ]] || { echo "[0493x20c] ERROR binary missing/not executable: $BIN" >&2; return 2; }
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
    fi
  else
    export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0
    unset SRC_LIVE_VIS_CONTROL_FILE MPCD_LIVE_VIS_CONTROL_FILE
  fi
}

run_one(){
  local case_id="$1" alpha="$2" tg_time="$3" tg_dumps="$4" msd_time="$5" msd_dumps="$6" seeds="$7" model="$8" action="$9"
  local rr="$CAMPAIGN_ROOT/configs/$case_id/$model"
  local log="$CAMPAIGN_ROOT/logs/${case_id}_${model}.log"
  local skip=0 rc t0 t1
  truthy "$RESTART" && skip=1
  mkdir -p "$rr"

  echo "[0493x20c] $action case=$case_id model=$model alpha=$alpha TG=${tg_time}/${tg_dumps} MSD=${msd_time}/${msd_dumps} seeds=$seeds"
  t0="$(date +%s)"

  env \
    ROOT="$ROOT" BIN="$BIN" \
    CALIBRATION_PATH="$model" CALIBRATION_EXPERIMENTS="tg msd" \
    RUN_ROOT="$rr" CLEAN_RUN_ROOT=0 SKIP_EXISTING="$skip" \
    LIVE_PROGRESS="$LIVE_PROGRESS" THREADS="$THREADS" \
    CELL_SIZE="$CELL_SIZE" KBT="$KBT" PARTICLE_MASS="$PARTICLE_MASS" \
    GAMMA="$GAMMA" ROTATION_ANGLE_DEG="$alpha" LAMBDA_OVER_H="$LAMBDA_OVER_H" \
    RANDOM_ROTATION_SIGN="$RANDOM_ROTATION_SIGN" GRID_SHIFT_ENABLE="$GRID_SHIFT_ENABLE" \
    THERMOSTAT_ENABLE="$THERMOSTAT_ENABLE" THERMOSTAT_MODE="$THERMOSTAT_MODE" \
    THERMOSTAT_EVERY="$THERMOSTAT_EVERY" THERMOSTAT_MIN_PARTICLES="$THERMOSTAT_MIN_PARTICLES" \
    NX="$TG_NX" NY="$TG_NY" TG_MODE_X="$TG_MODE_X" TG_MODE_Y="$TG_MODE_Y" \
    TG_TIME="$tg_time" TG_DUMP_COUNT="$tg_dumps" SEEDS="$seeds" \
    MSD_NX="$MSD_NX" MSD_NY="$MSD_NY" MSD_TIME="$msd_time" MSD_DUMP_COUNT="$msd_dumps" \
    MSD_SAMPLE_PARTICLES="$MSD_SAMPLE_PARTICLES" MSD_SEEDS="$seeds" \
    MAX_DUMP_GB="$MAX_DUMP_GB" ALLOW_LARGE_DUMPS="$ALLOW_LARGE_DUMPS" \
    PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_OPERATOR="$PROJECTION_OPERATOR" \
    PROJECTION_TOLERANCE="$PROJECTION_TOLERANCE" PROJECTION_MAX_ITERATIONS="$PROJECTION_MAX_ITERATIONS" \
    Q6_GF_DENSITY_RELAXATION_TIME="$Q6_GF_DENSITY_RELAXATION_TIME" \
    Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="$Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE" \
    Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="$Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES" \
    Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="$Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES" \
    Q6_GF_DENSITY_TRACTION_GAIN="$Q6_GF_DENSITY_TRACTION_GAIN" Q6_GF_MIN_FILL_FRACTION="$Q6_GF_MIN_FILL_FRACTION" \
    MPCD_Q6_G_F_RESIDENT_CG_0493X7J="$MPCD_Q6_G_F_RESIDENT_CG_0493X7J" \
    bash "$CALIBRATOR" $([[ "$action" == "preflight" ]] && printf '%s' '--preflight') >"$log" 2>&1
  rc=$?

  t1="$(date +%s)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -Is 2>/dev/null || date)" "$case_id" "$model" "$action" "$rc" "$((t1-t0))" >> "$STATUS"
  if [[ $rc -eq 0 ]]; then
    echo "[0493x20c] PASS case=$case_id model=$model elapsed=$((t1-t0))s"
  else
    echo "[0493x20c] FAIL case=$case_id model=$model rc=$rc log=$log" >&2
  fi
  return "$rc"
}

show_status(){
  python3 - "$CAMPAIGN_ROOT" "$MATRIX" <<'PY'
import csv,json,sys
from pathlib import Path
root=Path(sys.argv[1]); rows=list(csv.DictReader(open(sys.argv[2])))
done=0
for c in rows:
    for model in ('src','src-q6-g-f'):
        p=root/'configs'/c['case_id']/model/'analysis'/'fluid_characterization.json'
        if not p.exists():
            print(f"{c['case_id']:18s} {model:12s} PENDING")
            continue
        done += 1
        try:
            d=json.loads(p.read_text())
            print(f"{c['case_id']:18s} {model:12s} {str(d.get('status','?')):8s} nu={d.get('viscosityKinematic')} D={d.get('selfDiffusion')} Sc={d.get('Schmidt')}")
        except Exception as e:
            print(f"{c['case_id']:18s} {model:12s} JSON_ERROR {e}")
print(f"[0493x20c] completed model-cases={done}/{len(rows)*2}")
PY
}

write_matrix
if [[ "$MODE" == "--matrix" ]]; then cat "$MATRIX"; exit 0; fi
check_prereqs || exit $?
export_livevis
if [[ "$MODE" == "--status" ]]; then show_status; exit 0; fi

if [[ ! -f "$STATUS" ]]; then
  printf 'timestamp\tcase_id\tmodel\taction\trc\telapsed_s\n' > "$STATUS"
fi

action=run
[[ "$MODE" == "--preflight" ]] && action=preflight
failures=0
while IFS=',' read -r case_id alpha tg_time tg_dumps msd_time msd_dumps s1 s2 s3 s4 s5 s6; do
  [[ "$case_id" == "case_id" ]] && continue
  seeds="$s1,$s2,$s3,$s4,$s5,$s6"
  for model in src src-q6-g-f; do
    run_one "$case_id" "$alpha" "$tg_time" "$tg_dumps" "$msd_time" "$msd_dumps" "$seeds" "$model" "$action"
    rc=$?
    if [[ $rc -ne 0 ]]; then
      failures=$((failures+1))
      if ! truthy "$CONTINUE_ON_ERROR"; then exit "$rc"; fi
    fi
  done
done < "$MATRIX"

if [[ "$action" == "run" ]]; then show_status; fi
if [[ $failures -ne 0 ]]; then
  echo "[0493x20c] COMPLETE WITH FAILURES=$failures; rerun with RESTART=1" >&2
  exit 4
fi
echo "[0493x20c] COMPLETE PASS mode=$MODE"
