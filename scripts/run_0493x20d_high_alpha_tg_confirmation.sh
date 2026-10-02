#!/usr/bin/env bash
# SRC_GPU-SURF 0493x20d — confirmation TG grands angles pour la campagne article.
# Deux points seulement: alpha=165,175 deg; gamma=8; lambdaMean/h=0.72.
# SRC et Q6-G-F apparies; memes 6 seeds que x20c; TG 256^2 mode (1,1).
# Aucun MSD, aucun son, aucune modification solveur/calibrateur, aucune maintenance /Info.

ROOT="${ROOT:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)" || exit 2
cd "$ROOT" || exit 2

MODE="${1:---run}"
case "$MODE" in
  --run|--preflight|--status|--matrix|--summary) ;;
  -h|--help)
    cat <<'USAGE'
Usage:
  bash scripts/run_0493x20d_high_alpha_tg_confirmation.sh --preflight
  bash scripts/run_0493x20d_high_alpha_tg_confirmation.sh --run
  bash scripts/run_0493x20d_high_alpha_tg_confirmation.sh --status
  bash scripts/run_0493x20d_high_alpha_tg_confirmation.sh --summary
  bash scripts/run_0493x20d_high_alpha_tg_confirmation.sh --matrix

Campagne:
  alpha_SRC = 165, 175 deg
  gamma = 8 ; lambdaMean/h = 0.72 ; kBT = 0.125 ; m = 1 ; h = 1/256
  models = src, src-q6-g-f
  6 seeds communes SRC/Q6-G-F par angle, identiques a x20c
  TG = 256x256, mode (1,1)
  alpha=165: T=10, 48 dumps cibles
  alpha=175: T=8, 56 dumps cibles
  MSD/sound = non lances

Runs solveur: 2 angles * 2 modeles * 6 TG = 24.
Le domaine 256^2 double la longueur d'onde par rapport a x20c (128^2), donc
la decroissance visqueuse TG est environ 4 fois plus lente a nu identique.
RESTART=1 / SKIP_EXISTING=1 par defaut.
USAGE
    exit 0
    ;;
  *) echo "[0493x20d] ERROR unknown mode: $MODE" >&2; exit 2 ;;
esac

CALIBRATOR="${CALIBRATOR:-scripts/calibrate_fluid_0493w1_standalone.sh}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
SUMMARIZER="${SUMMARIZER:-scripts/summarize_0493x20d_high_alpha_tg_confirmation.py}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x20d_high_alpha_tg_confirmation}"
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

TG_NX="${TG_NX:-256}"
TG_NY="${TG_NY:-256}"
TG_MODE_X="${TG_MODE_X:-1}"
TG_MODE_Y="${TG_MODE_Y:-1}"

# 6 seeds x 256^2: volumes preflight attendus ~6.94 GB (165) et ~7.93 GB (175)
# avec les cadences ci-dessous. La limite est donc volontairement 9 GB sans bypass.
MAX_DUMP_GB="${MAX_DUMP_GB:-9.0}"
ALLOW_LARGE_DUMPS="${ALLOW_LARGE_DUMPS:-0}"

# Contrat Q6-G-F de production, identique x20a/x20b/x20c.
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

# Run court de calibration: LiveVis OFF par defaut; le fichier livevis_control.kv n'est jamais modifie.
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
case_id,alpha_SRC_deg,tg_time,tg_dumps,seed1,seed2,seed3,seed4,seed5,seed6
L072_G08_A165_256,165,10,48,4934401,4934402,4934403,4934442,4934443,4934444
L072_G08_A175_256,175,8,56,4934501,4934502,4934503,4934542,4934543,4934544
CSV
  echo "[0493x20d] matrix=$MATRIX configurations=2 pairedModels=2 seeds=6 experiment=tg solverRuns=24"
}

check_prereqs(){
  command -v bash >/dev/null 2>&1 || { echo "[0493x20d] ERROR bash missing" >&2; return 2; }
  command -v python3 >/dev/null 2>&1 || { echo "[0493x20d] ERROR python3 missing" >&2; return 2; }
  [[ -f "$CALIBRATOR" ]] || { echo "[0493x20d] ERROR calibrator missing: $CALIBRATOR" >&2; return 2; }
  [[ -x "$BIN" ]] || { echo "[0493x20d] ERROR binary missing/not executable: $BIN" >&2; return 2; }
  [[ -f "$SUMMARIZER" ]] || { echo "[0493x20d] ERROR summarizer missing: $SUMMARIZER" >&2; return 2; }
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
  local case_id="$1" alpha="$2" tg_time="$3" tg_dumps="$4" seeds="$5" model="$6" action="$7"
  local rr="$CAMPAIGN_ROOT/configs/$case_id/$model"
  local log="$CAMPAIGN_ROOT/logs/${case_id}_${model}.log"
  local skip=0 rc t0 t1
  truthy "$RESTART" && skip=1
  mkdir -p "$rr"

  echo "[0493x20d] $action case=$case_id model=$model alpha=$alpha grid=${TG_NX}x${TG_NY} TG=${tg_time}/${tg_dumps} seeds=$seeds"
  t0="$(date +%s)"

  env \
    ROOT="$ROOT" BIN="$BIN" \
    CALIBRATION_PATH="$model" CALIBRATION_EXPERIMENTS="tg" \
    RUN_ROOT="$rr" CLEAN_RUN_ROOT=0 SKIP_EXISTING="$skip" \
    LIVE_PROGRESS="$LIVE_PROGRESS" THREADS="$THREADS" \
    CELL_SIZE="$CELL_SIZE" KBT="$KBT" PARTICLE_MASS="$PARTICLE_MASS" \
    GAMMA="$GAMMA" ROTATION_ANGLE_DEG="$alpha" LAMBDA_OVER_H="$LAMBDA_OVER_H" \
    RANDOM_ROTATION_SIGN="$RANDOM_ROTATION_SIGN" GRID_SHIFT_ENABLE="$GRID_SHIFT_ENABLE" \
    THERMOSTAT_ENABLE="$THERMOSTAT_ENABLE" THERMOSTAT_MODE="$THERMOSTAT_MODE" \
    THERMOSTAT_EVERY="$THERMOSTAT_EVERY" THERMOSTAT_MIN_PARTICLES="$THERMOSTAT_MIN_PARTICLES" \
    NX="$TG_NX" NY="$TG_NY" TG_MODE_X="$TG_MODE_X" TG_MODE_Y="$TG_MODE_Y" \
    TG_TIME="$tg_time" TG_DUMP_COUNT="$tg_dumps" SEEDS="$seeds" \
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
    echo "[0493x20d] PASS case=$case_id model=$model elapsed=$((t1-t0))s"
  else
    echo "[0493x20d] FAIL case=$case_id model=$model rc=$rc log=$log" >&2
  fi
  return "$rc"
}

show_status(){
  python3 - "$CAMPAIGN_ROOT" "$MATRIX" <<'PY'
import csv,json,sys
from pathlib import Path
root=Path(sys.argv[1]); rows=list(csv.DictReader(open(sys.argv[2], newline='', encoding='utf-8')))
done=0
for c in rows:
    for model in ('src','src-q6-g-f'):
        p=root/'configs'/c['case_id']/model/'analysis'/'fluid_characterization.json'
        if not p.exists():
            print(f"{c['case_id']:22s} {model:12s} PENDING")
            continue
        done += 1
        try:
            d=json.loads(p.read_text(encoding='utf-8'))
            print(f"{c['case_id']:22s} {model:12s} {str(d.get('status','?')):8s} nu={d.get('viscosityKinematic')} CV={d.get('viscosityCV')} R2min={min([r.get('R2',1.0) for r in (d.get('tgRuns') or [])] or [float('nan')])}")
        except Exception as e:
            print(f"{c['case_id']:22s} {model:12s} JSON_ERROR {e}")
print(f"[0493x20d] completed model-cases={done}/{len(rows)*2}")
PY
}

write_matrix
if [[ "$MODE" == "--matrix" ]]; then cat "$MATRIX"; exit 0; fi
check_prereqs || exit $?
export_livevis
if [[ "$MODE" == "--status" ]]; then show_status; exit 0; fi
if [[ "$MODE" == "--summary" ]]; then python3 "$SUMMARIZER" "$CAMPAIGN_ROOT"; exit $?; fi

if [[ ! -f "$STATUS" ]]; then
  printf 'timestamp\tcase_id\tmodel\taction\trc\telapsed_s\n' > "$STATUS"
fi

action=run
[[ "$MODE" == "--preflight" ]] && action=preflight
failures=0
while IFS=',' read -r case_id alpha tg_time tg_dumps s1 s2 s3 s4 s5 s6; do
  [[ "$case_id" == "case_id" ]] && continue
  seeds="$s1,$s2,$s3,$s4,$s5,$s6"
  for model in src src-q6-g-f; do
    run_one "$case_id" "$alpha" "$tg_time" "$tg_dumps" "$seeds" "$model" "$action"
    rc=$?
    if [[ $rc -ne 0 ]]; then
      failures=$((failures+1))
      if ! truthy "$CONTINUE_ON_ERROR"; then exit "$rc"; fi
    fi
  done
done < "$MATRIX"

if [[ "$action" == "run" ]]; then
  show_status
  python3 "$SUMMARIZER" "$CAMPAIGN_ROOT" || failures=$((failures+1))
fi
if [[ $failures -ne 0 ]]; then
  echo "[0493x20d] COMPLETE WITH FAILURES=$failures; rerun with RESTART=1" >&2
  exit 4
fi
echo "[0493x20d] COMPLETE PASS mode=$MODE"
