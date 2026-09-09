#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"
cd "$ROOT"

CASE_RUNNER="${CASE_RUNNER:-$ROOT/scripts/run_0493x12d_jfm524_measurement_case.sh}"
[[ -x "$CASE_RUNNER" ]] || { echo "[0493x12d-jfm] ERROR missing executable case runner: $CASE_RUNNER" >&2; exit 2; }

CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x12d_jfm524_overnight_Re649_We514}"
MATRIX_ONLY="${MATRIX_ONLY:-0}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CONTINUE_ON_FAIL="${CONTINUE_ON_FAIL:-1}"

# Qualified current SRC/Q6-G-F fluid.  Keep this block unchanged in the reference campaign.
NX="${NX:-3200}"
NY="${NY:-1024}"
Lx="${Lx:-12.5}"
Ly="${Ly:-4.0}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"

# JFM 524 target mapped to the qualified lattice fluid.
# Experiment: D=3.7 mm, U=3.3 m/s, Re=12200, We=514, gD/U^2=0.0037.
# Current SRC: D=320h, Uimpact=0.35, nu=6.7432658123431854e-4 -> Re ~=648.8.
DROP_RADIUS_CELLS="${DROP_RADIUS_CELLS:-160}"
DROP_CENTER_X="${DROP_CENTER_X:-6.25}"
DROP_CENTER_Y="${DROP_CENTER_Y:-0.703125}"
DROP_VX="${DROP_VX:-0.0}"
DROP_VY="${DROP_VY:--0.3499190531394368}"
GRAVITY_Y="${GRAVITY_Y:--0.0003626}"
SIGMA_ACTIVE="${SIGMA_ACTIVE:-392.1491851919759}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
CONTACT_ANGLE_DEG="${CONTACT_ANGLE_DEG:-90.0}"

# Quantitative-domain choice: NY=1024 (Ly=4) rather than the minimal NY=512.
# The 3200x1600 reference shows the ejected sheet/filament arc rising well above
# y=2 by steps 1500-2000.  Ly=2 is adequate for the near-wall footprint but would
# truncate precisely the sheet length/angle observable measured in the article.
# Ly=4 still removes 36% of the old vertical grid while retaining the useful arc.
# Output cadence selected for quantitative reconstruction of angle/length/thickness histories.
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-500}"
RECORD_EVERY="${RECORD_EVERY:-50}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-50}"
LIVE_VIS_NX="${LIVE_VIS_NX:-800}"
LIVE_VIS_NY="${LIVE_VIS_NY:-256}"

# Cost estimate anchored to the user's current observation (2300x1600 at 1.5 s/step).
BASELINE_SEC_PER_STEP="${BASELINE_SEC_PER_STEP:-1.5}"
BASELINE_NX="${BASELINE_NX:-2300}"
BASELINE_NY="${BASELINE_NY:-1600}"

# Fields:
# label | family | replicate | e_mm | e_cells | dobs_mm | dobs_cells | steps | seed
#
# The d_obs=2.0 mm trio targets figure 4(a) (angle vs t*) and figure 5
# (sheet length/speed and thickness), reaching t* ~=1.4; the current SRC event
# is already fully developed by ~2000 steps, so 2500 retains a post-event margin.
# The e=0.07 mm distance sweep targets figure 4(b), including the near-onset
# d_obs=1.9 mm point and the experimental upper range d_obs=4.5 mm.
# Two additional central replicas quantify stochastic repeatability.
SPECS=(
  "time_e035_d200_r0|height_time|0|0.035|3|2.0|173|2500|493960"
  "time_e070_d200_r0|height_time+distance|0|0.070|6|2.0|173|2500|493970"
  "time_e200_d200_r0|height_time|0|0.200|17|2.0|173|2500|493980"

  "dist_e070_d190_r0|distance|0|0.070|6|1.9|164|2000|493971"
  "dist_e070_d250_r0|distance|0|0.070|6|2.5|216|2000|493972"
  "dist_e070_d300_r0|distance|0|0.070|6|3.0|259|2000|493973"
  "dist_e070_d350_r0|distance|0|0.070|6|3.5|303|2000|493974"
  "dist_e070_d400_r0|distance|0|0.070|6|4.0|346|2000|493975"
  "dist_e070_d450_r0|distance|0|0.070|6|4.5|389|2000|493976"

  "repeat_e070_d200_r1|repeatability|1|0.070|6|2.0|173|2000|494979"
  "repeat_e070_d200_r2|repeatability|2|0.070|6|2.0|173|2000|495988"
)

mkdir -p "$CAMPAIGN_ROOT"
MANIFEST="$CAMPAIGN_ROOT/jfm524_campaign_manifest.tsv"
STATUS="$CAMPAIGN_ROOT/jfm524_campaign_status.tsv"
LOG="$CAMPAIGN_ROOT/jfm524_campaign.log"

printf "label\tfamily\treplicate\tseed\te_target_mm\te_cells\te_over_D_actual\te_equiv_mm\tdobs_target_mm\tdobs_cells\tdobs_over_D_actual\tdobs_equiv_mm\tsteps\ttstar_end\tWe_SRC\tRe_SRC\tWe_JFM\tRe_JFM\n" > "$MANIFEST"

total_steps=0
for spec in "${SPECS[@]}"; do
  IFS='|' read -r label family rep e_mm e_cells d_mm d_cells steps seed <<<"$spec"
  total_steps=$((total_steps + steps))
  python3 - "$MANIFEST" "$label" "$family" "$rep" "$seed" "$e_mm" "$e_cells" "$d_mm" "$d_cells" "$steps" <<'PY'
import sys
p,label,family,rep,seed,e_mm,e_cells,d_mm,d_cells,steps=sys.argv[1:]
e_mm=float(e_mm); e_cells=int(e_cells); d_mm=float(d_mm); d_cells=int(d_cells); steps=int(steps)
D_cells=320.0; D_mm=3.7; dt=0.002; U=0.35; D_lattice=1.25
with open(p,"a",encoding="utf-8") as f:
    f.write("\t".join([
        label,family,rep,seed,
        f"{e_mm:.6g}",str(e_cells),f"{e_cells/D_cells:.9g}",f"{D_mm*e_cells/D_cells:.9g}",
        f"{d_mm:.6g}",str(d_cells),f"{d_cells/D_cells:.9g}",f"{D_mm*d_cells/D_cells:.9g}",
        str(steps),f"{steps*dt*U/D_lattice:.9g}","514","648.8","514","12200"
    ])+"\n")
PY
done

estimate="$(python3 - "$BASELINE_SEC_PER_STEP" "$BASELINE_NX" "$BASELINE_NY" "$NX" "$NY" "$total_steps" <<'PY'
import sys
s,bx,by,nx,ny,steps=map(float,sys.argv[1:])
new=s*(nx*ny)/(bx*by)
hours=new*steps/3600
print(f"{new:.3f} {hours:.2f}")
PY
)"
read -r est_sec est_hours <<<"$estimate"

echo "===== 0493x12d JFM 524 OVERNIGHT CAMPAIGN ====="
echo "grid=${NX}x${NY} L=(${Lx},${Ly}) h=$(python3 - <<PY
print($Lx/$NX)
PY
) dt=$DT gamma=$GAMMA kBT=$KBT"
echo "drop D/h=320 Uimpact=0.35 sigmaDeclared=$SIGMA_ACTIVE gravityY=$GRAVITY_Y"
echo "targets: We_SRC=514 Re_SRC~648.8 | JFM experiment We=514 Re=12200 gD/U^2=0.0037"
echo "article obstacle heights: 0.035,0.070,0.200 mm -> cells 3,6,17"
echo "article distance sweep: 0..4.5 mm; sampled splash-relevant range 1.9..4.5 mm"
echo "cadence: recordEvery=$RECORD_EVERY fields=mass,ux,uy dumpsEvery=$DUMP_STATE_EVERY"
echo "LiveVis=${LIVE_VIS_NX}x${LIVE_VIS_NY} every=1"
echo "cases=${#SPECS[@]} totalSteps=$total_steps"
echo "naive cost scaling from ${BASELINE_NX}x${BASELINE_NY}@${BASELINE_SEC_PER_STEP}s: ~${est_sec}s/step, ~${est_hours}h total"
echo "manifest=$MANIFEST"
echo
column -t -s $'\t' "$MANIFEST" 2>/dev/null || cat "$MANIFEST"

if [[ "$MATRIX_ONLY" == "1" ]]; then
  echo "[0493x12d-jfm] MATRIX_ONLY=1; no case launched"
  exit 0
fi

printf "label\tstatus\trc\tstart\tend\n" > "$STATUS"
failures=0
exec > >(tee -a "$LOG") 2>&1

for spec in "${SPECS[@]}"; do
  IFS='|' read -r label family rep e_mm e_cells d_mm d_cells steps seed <<<"$spec"
  case_root="$CAMPAIGN_ROOT/$label"
  start="$(date -Is)"
  echo
  echo "================================================================"
  echo "START $label family=$family rep=$rep seed=$seed"
  echo "target e=${e_mm}mm -> ${e_cells}h ; d_obs=${d_mm}mm -> ${d_cells}h ; steps=$steps"
  echo "================================================================"

  if RUN_MODE=src-q6-g-f \
     CAMPAIGN_ROOT="$case_root" CASES=rmin4 \
     NX="$NX" NY="$NY" Lx="$Lx" Ly="$Ly" \
     GAMMA="$GAMMA" DT="$DT" KBT="$KBT" LIQUID_MASS="$LIQUID_MASS" \
     ROTATION_ANGLE="$ROTATION_ANGLE" \
     DROP_RADIUS_CELLS="$DROP_RADIUS_CELLS" DROP_CENTER_X="$DROP_CENTER_X" DROP_CENTER_Y="$DROP_CENTER_Y" \
     DROP_VX="$DROP_VX" DROP_VY="$DROP_VY" GRAVITY_Y="$GRAVITY_Y" \
     SIGMA_ACTIVE="$SIGMA_ACTIVE" SURFACE_TENSION_MIN_RADIUS_CELLS="$SURFACE_TENSION_MIN_RADIUS_CELLS" \
     CONTACT_ANGLE_DEG="$CONTACT_ANGLE_DEG" \
     OBSTACLE_HEIGHT_CELLS="$e_cells" OBSTACLE_DISTANCE_CELLS="$d_cells" \
     STEPS="$steps" SEED="$seed" SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
     RECORD_EVERY="$RECORD_EVERY" FILTER_SAMPLE_EVERY="$FILTER_SAMPLE_EVERY" \
     LIVE_VIS_NX="$LIVE_VIS_NX" LIVE_VIS_NY="$LIVE_VIS_NY" \
     CLEAN_RUN_ROOT=1 PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
     bash "$CASE_RUNNER"; then
    rc=0; st=PASS
  else
    rc=$?; st=FAIL; failures=$((failures+1))
  fi
  end="$(date -Is)"
  printf "%s\t%s\t%s\t%s\t%s\n" "$label" "$st" "$rc" "$start" "$end" >> "$STATUS"
  echo "END $label status=$st rc=$rc"
  if (( rc != 0 )) && [[ "$CONTINUE_ON_FAIL" != "1" ]]; then
    break
  fi
done

echo
echo "===== 0493x12d JFM 524 CAMPAIGN COMPLETE ====="
cat "$STATUS"
echo "manifest=$MANIFEST"
echo "status=$STATUS"
echo "log=$LOG"
(( failures == 0 )) || exit 1
