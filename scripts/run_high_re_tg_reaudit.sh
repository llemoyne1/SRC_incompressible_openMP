#!/usr/bin/env bash
# Re-audit the decisive SRC high-Re fluid points using the standalone historical 0493w1 TG calibrator.
# No solver/source modification.
set -euo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"
usage(){ cat <<'USAGE'
High-Re SRC viscosity re-audit with direct standalone historical Taylor-Green calibrator

Usage:
  bash run_high_re_tg_reaudit.sh
  bash run_high_re_tg_reaudit.sh --preflight
  bash run_high_re_tg_reaudit.sh --analyze-only
  bash run_high_re_tg_reaudit.sh --check

Default matrix:
  A0        gamma=20 alpha= 90 deg lambda/h=0.22687409291590604
  A1        gamma=20 alpha=120 deg lambda/h=0.48
  G08_L048  gamma= 8 alpha=120 deg lambda/h=0.48
  G08_L072  gamma= 8 alpha=120 deg lambda/h=0.72

These are the four decision points needed to re-audit x13:
  - A0/A1 reproduce the original x13a 0493w1/TG baseline;
  - G08_L048/G08_L072 test the later gamma=8 and lambda/h=0.72 choice.

Overrides:
  CALIBRATOR=scripts/calibrate_src_fluid_0493w1_standalone.sh   # direct standalone, no run_common
  CASES=A0,A1,G08_L048,G08_L072
  SEEDS=4931301,4931302,4931303
  CAMPAIGN_ROOT=runs/0493x13_high_re_tg_reaudit
  BIN=build/src_mpcd_base_cuda_q6_resident_livevis_0486
  TG_TIME=4.0 TG_DUMP_COUNT=80
  CLEAN_CAMPAIGN_ROOT=1

The calibrator is direct standalone: no run_common/suite helper is used.

The historical seed 4931301 is deliberately retained. The campaign report shows
both its direct delta versus the published x13a value and the new multi-seed mean.
USAGE
}
MODE=run
case "${1:-}" in
  '') ;;
  --preflight) MODE=preflight; shift ;;
  --analyze-only) MODE=analyze; shift ;;
  --check) MODE=check; shift ;;
  -h|--help) usage; exit 0 ;;
  *) echo "[high-re-tg] ERROR unknown argument $1" >&2; usage >&2; exit 2 ;;
esac
[[ $# -eq 0 ]] || { echo "[high-re-tg] ERROR unexpected args: $*" >&2; exit 2; }

resolve_root(){
  if [[ -n "${ROOT:-}" ]]; then (cd "$ROOT" && pwd); return; fi
  if [[ -d "$PWD/src" && -d "$PWD/scripts" ]]; then pwd; return; fi
  if [[ -d "$SELF_DIR/../src" && -d "$SELF_DIR/../scripts" ]]; then (cd "$SELF_DIR/.." && pwd); return; fi
  echo '[high-re-tg] ERROR cannot locate SRC_GPU-SURF; export ROOT=/path/to/repo' >&2; return 2
}
ROOT="$(resolve_root)"; cd "$ROOT"
CALIBRATOR="${CALIBRATOR:-scripts/calibrate_src_fluid_0493w1_standalone.sh}"
if [[ ! -f "$CALIBRATOR" && -f "$SELF_DIR/calibrate_src_fluid_0493w1_standalone.sh" ]]; then CALIBRATOR="$SELF_DIR/calibrate_src_fluid_0493w1_standalone.sh"; fi
[[ -f "$CALIBRATOR" ]] || { echo "[high-re-tg] ERROR calibrator not found: $CALIBRATOR" >&2; exit 2; }

CASES="${CASES:-A0,A1,G08_L048,G08_L072}"
SEEDS="${SEEDS:-4931301,4931302,4931303}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x13_high_re_tg_reaudit}"
CELL_SIZE="${CELL_SIZE:-0.00390625}"; KBT="${KBT:-0.125}"; PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
NX="${NX:-64}"; NY="${NY:-64}"; TG_TIME="${TG_TIME:-4.0}"; TG_DUMP_COUNT="${TG_DUMP_COUNT:-80}"
CLEAN_CAMPAIGN_ROOT="${CLEAN_CAMPAIGN_ROOT:-0}"
SKIP_EXISTING="${SKIP_EXISTING:-1}"

case_spec(){
  case "$1" in
    A0)       echo '20|90|0.22687409291590604|0.00073747|historical_x13a_A0' ;;
    A1)       echo '20|120|0.48|0.00055699|historical_x13a_A1' ;;
    G08_L048) echo '8|120|0.48||gamma8_reference_at_048' ;;
    G08_L072) echo '8|120|0.72||gamma8_final_candidate_072' ;;
    *) return 1 ;;
  esac
}
IFS=',' read -r -a CASE_ARRAY <<< "$CASES"
for c in "${CASE_ARRAY[@]}"; do case_spec "$c" >/dev/null || { echo "[high-re-tg] ERROR bad case $c" >&2; exit 2; }; done

if [[ "$MODE" == run && "$CLEAN_CAMPAIGN_ROOT" == 1 ]]; then rm -rf "$CAMPAIGN_ROOT"; fi
mkdir -p "$CAMPAIGN_ROOT"

invoke_case(){
  local c="$1" action="$2" spec gamma deg lam hist role
  spec="$(case_spec "$c")"; IFS='|' read -r gamma deg lam hist role <<< "$spec"
  local case_root="$CAMPAIGN_ROOT/$c"
  echo
  echo "================================================================"
  echo "[high-re-tg] case=$c gamma=$gamma alpha=${deg}deg lambda/h=$lam role=$role"
  echo "================================================================"
  local -a cmd=(bash "$CALIBRATOR")
  case "$action" in preflight) cmd+=(--preflight);; analyze) cmd+=(--analyze-only);; check) cmd+=(--preflight);; esac
  env ROOT="$ROOT" ${BIN:+BIN="$BIN"} \
    CALIBRATION_EXPERIMENTS=tg \
    GAMMA="$gamma" ROTATION_ANGLE_DEG="$deg" LAMBDA_OVER_H="$lam" DT_OVERRIDE='' DT='' \
    KBT="$KBT" PARTICLE_MASS="$PARTICLE_MASS" CELL_SIZE="$CELL_SIZE" NX="$NX" NY="$NY" \
    TG_TIME="$TG_TIME" TG_DUMP_COUNT="$TG_DUMP_COUNT" SEEDS="$SEEDS" \
    RUN_ROOT="$case_root" SKIP_EXISTING="$SKIP_EXISTING" CLEAN_RUN_ROOT=0 \
    CHARACTERISTIC_U=-1 CHARACTERISTIC_L=-1 LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
    "${cmd[@]}"
}

if [[ "$MODE" == check ]]; then
  env ROOT="$ROOT" ${BIN:+BIN="$BIN"} bash "$CALIBRATOR" --check
  for c in "${CASE_ARRAY[@]}"; do invoke_case "$c" preflight; done
  echo '[high-re-tg] CHECK PASS: calibrator + four-case matrix'
  exit 0
fi
if [[ "$MODE" == preflight ]]; then
  for c in "${CASE_ARRAY[@]}"; do invoke_case "$c" preflight; done
  echo '[high-re-tg] PREFLIGHT PASS; no simulations launched'
  exit 0
fi
for c in "${CASE_ARRAY[@]}"; do invoke_case "$c" "$MODE"; done

python3 - "$CAMPAIGN_ROOT" "$CASES" <<'PY'
import csv,json,math,sys
from pathlib import Path
root=Path(sys.argv[1]); cases=[x for x in sys.argv[2].split(',') if x]
hist={'A0':0.00073747,'A1':0.00055699}
rows=[]
for c in cases:
    p=root/c/'analysis'/'summary.json'
    if not p.exists(): raise SystemExit(f'[high-re-tg] missing {p}')
    d=json.loads(p.read_text()); per=d.get('perSeed',[]); seed0=next((r for r in per if int(r.get('seed',-1))==4931301),None)
    mean=float(d['nuMean']) if d.get('nuMean') is not None else math.nan
    ref=hist.get(c,math.nan); seednu=float(seed0['nu']) if seed0 else math.nan
    rows.append({'case':c,'status':d.get('status',''),'nuMean':mean,'nuStd':d.get('nuStd'),'nuCV':d.get('nuCV'),'nuMin':d.get('nuMin'),'nuMax':d.get('nuMax'),'historicalNu':ref if math.isfinite(ref) else '', 'seed4931301Nu':seednu if math.isfinite(seednu) else '', 'seed4931301DeltaPct':100*(seednu/ref-1) if math.isfinite(ref) and math.isfinite(seednu) else '', 'ensembleDeltaVsHistoricalPct':100*(mean/ref-1) if math.isfinite(ref) and math.isfinite(mean) else ''})
by={r['case']:r for r in rows}
base=by.get('A0',{}).get('nuMean',math.nan)
for r in rows:
    n=r['nuMean']; r['viscosityReductionVsA0Pct']=100*(1-n/base) if isinstance(n,(int,float)) and math.isfinite(n) and isinstance(base,(int,float)) and math.isfinite(base) else ''
comparison={}
if 'G08_L048' in by and 'G08_L072' in by:
    a=float(by['G08_L048']['nuMean']); b=float(by['G08_L072']['nuMean']); rel=(b/a-1) if a>0 else math.nan
    comparison={'nuG08L048':a,'nuG08L072':b,'relativeChange072Vs048':rel,'relativeChange072Vs048Pct':100*rel}
    if math.isfinite(rel):
        comparison['screeningInterpretation']='L072_LOWER_VISCOSITY' if rel < -.05 else ('L048_LOWER_VISCOSITY' if rel > .05 else 'WITHIN_5_PERCENT')
# Baseline reproduction is descriptive, not a hard physics gate.
baseline=[]
for c in ('A0','A1'):
    if c in by and by[c]['seed4931301DeltaPct']!='':
        x=abs(float(by[c]['seed4931301DeltaPct'])); baseline.append((c,x,'CLOSE' if x<=10 else ('REVIEW' if x<=20 else 'DIVERGENT')))
summary={'schema':'0493x13-high-re-tg-reaudit-v1','method':'historical_0493w1_TG','cases':rows,'baselineReproduction':[{'case':c,'absDeltaPct':x,'classification':g} for c,x,g in baseline],'G08comparison':comparison}
(root/'summary.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n')
keys=[]
for r in rows:
    for k in r:
        if k not in keys: keys.append(k)
with (root/'summary.csv').open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=keys); w.writeheader(); w.writerows(rows)
md=['# High-Re SRC re-audit — historical 0493w1 Taylor–Green','', 'This campaign rechecks viscosity only. Acoustic and MSD results are not rerun.','', '| case | QC | nu mean | std | historical 0493w1 nu | seed 4931301 delta | reduction vs A0 |','|---|---|---:|---:|---:|---:|---:|']
for r in rows:
    def f(x,fmt='.8g'):
        return '—' if x=='' or x is None else format(float(x),fmt)
    md.append(f"| {r['case']} | {r['status']} | {f(r['nuMean'])} | {f(r['nuStd'],'.4g')} | {f(r['historicalNu'])} | {f(r['seed4931301DeltaPct'],'.2f')}% | {f(r['viscosityReductionVsA0Pct'],'.2f')}% |")
md += ['','## Historical-seed reproduction','']
for c,x,g in baseline: md.append(f'- {c}: {g}, |delta| = {x:.2f}% versus the x13a 0493w1 value.')
if comparison:
    md += ['','## Gamma=8 0.48 vs 0.72','',f"- nu(0.48) = {comparison['nuG08L048']:.10g}",f"- nu(0.72) = {comparison['nuG08L072']:.10g}",f"- relative change 0.72 vs 0.48 = {comparison['relativeChange072Vs048Pct']:.2f}%",f"- screening interpretation: **{comparison.get('screeningInterpretation','')}**"]
md += ['','No obstacle/application length enters these viscosity measurements. Reynolds numbers should be recomputed only after this constitutive re-audit is accepted.','']
(root/'README_RESULTS.md').write_text('\n'.join(md)+'\n')
print(f'[high-re-tg] summary={root/"README_RESULTS.md"}')
for r in rows: print(f"[high-re-tg] {r['case']}: status={r['status']} nu={float(r['nuMean']):.10g}")
if comparison: print(f"[high-re-tg] G08 0.72 vs 0.48: {comparison['relativeChange072Vs048Pct']:.2f}% ({comparison['screeningInterpretation']})")
PY

echo
cat "$CAMPAIGN_ROOT/README_RESULTS.md"
