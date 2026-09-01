#!/usr/bin/env bash
set -euo pipefail

# 0493x14f — quick qualification of the per-type thermostat on the actual
# liquid/gas src-q6-g-f production path. Reuses the maintained type1->type2
# runner with x6g gas pressure active, x10/x12 kinetic retention OFF, and a
# deliberately zero sigma for this thermostat/Q6-g-f coupling check.
# This wrapper never writes ./livevis_control.kv.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

CASE_LABEL="${CASE_LABEL:-0493x14f_species_thermostat_q6gf_quick}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/$CASE_LABEL}"
NX="${NX:-128}"; NY="${NY:-64}"; Lx="${Lx:-2.0}"; Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-8}"; STEPS="${STEPS:-200}"; DT="${DT:-0.002}"
KBT_GAS="${KBT_GAS:-0.08}"; KBT_LIQUID="${KBT_LIQUID:-0.02}"
LIQUID_PARTICLE_MASS="${LIQUID_PARTICLE_MASS:-1.0}"; GAS_PARTICLE_MASS="${GAS_PARTICLE_MASS:-0.1}"
UIN="${UIN:-0.10}"; INLET_HEIGHT_CELLS="${INLET_HEIGHT_CELLS:-16}"
SUMMARY_EVERY="${SUMMARY_EVERY:-20}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-$STEPS}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

export CASE_LABEL BASE_RUN_ROOT NX NY Lx Ly GAMMA STEPS DT
# x6g EOS still consumes the global KBT in the current code: choose the gas
# target here so the quick q6-g-f test is internally consistent on the gas side.
export KBT="$KBT_GAS" THERMOSTAT_TARGET_KBT="$KBT_GAS"
export LIQUID_PARTICLE_MASS GAS_PARTICLE_MASS UIN INLET_HEIGHT_CELLS SUMMARY_EVERY DUMP_STATE_EVERY
export SPECIES_THERMOSTAT_ENABLE=true
export INJECT_THERMOSTAT_TARGET_KBT="$KBT_LIQUID"
export BACKGROUND_THERMOSTAT_TARGET_KBT="$KBT_GAS"
export RUN_MODES=src-q6-g-f
export RUN_OK_LIQUID_SURFACE_ENABLE=1
export SURFACE_TENSION_SIGMA=0.0
export PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION=0.0
export SPECIES_RESAMPLING_ENABLE=false
export LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 FILTERED_RECORDING_ENABLE=0 RECORD_ENABLE=false
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export PREFLIGHT_ONLY

printf '===== 0493x14f src-q6-g-f per-type thermostat =====\n'
printf 'PATHS: runner=%s backend=%s outputRoot=%s\n' \
  "$ROOT/scripts/run_ok_0493x14f_species_thermostat_q6gf_quick.sh" \
  "$ROOT/scripts/run_ok_injection_type1_into_type2.sh" "$BASE_RUN_ROOT"
printf 'GRID: L=%sx%s N=%sx%s gamma=%s dt=%s steps=%s gridShift=true\n' "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$DT" "$STEPS"
printf 'PATH: src-q6-g-f free_surface_masked + x6g ; sigma=0 ; x10/x12=OFF\n'
printf 'THERMO: liquid(type1,m=%s,kBT=%s) gas(type2,m=%s,kBT=%s) ; globalKBT=%s for x6g EOS\n' \
  "$LIQUID_PARTICLE_MASS" "$KBT_LIQUID" "$GAS_PARTICLE_MASS" "$KBT_GAS" "$KBT"
printf 'NOTE: ./livevis_control.kv is read-only and is not modified\n'

bash "$ROOT/scripts/run_ok_injection_type1_into_type2.sh"
[[ "$PREFLIGHT_ONLY" == 1 ]] && exit 0

RUN_DIR="$BASE_RUN_ROOT/src-q6-g-f"
STATE="$RUN_DIR/init/injection_type1_into_type2_${NX}x${NY}_g${GAMMA}.smpcd"
FINAL="$RUN_DIR/output/state_step_$(printf '%08d' "$STEPS").smpcd"
CSV="$RUN_DIR/output/species_runtime_injection_0493w4.csv"
PARAMS="$RUN_DIR/params/injection_type1_into_type2.kv"
[[ -s "$FINAL" ]] || { echo "[0493x14f] FAIL missing final dump $FINAL" >&2; exit 3; }
[[ -s "$CSV" ]] || { echo "[0493x14f] FAIL missing species diagnostics $CSV" >&2; exit 3; }
grep -Eq '^speciesThermostatEnable[[:space:]]*=[[:space:]]*true' "$PARAMS" || { echo "[0493x14f] FAIL species thermostat missing from params" >&2; exit 3; }
grep -Eq '^speciesQ6Mode[[:space:]]*=[[:space:]]*free_surface_masked' "$PARAMS" || { echo "[0493x14f] FAIL q6-g-f free_surface_masked missing" >&2; exit 3; }

python3 - "$CSV" "$KBT_LIQUID" "$KBT_GAS" <<'PY'
import csv,math,sys
p,t1,t2=sys.argv[1],float(sys.argv[2]),float(sys.argv[3])
# Species runtime carries total KE and barycentric velocity. Compute an apparent
# global temperature from the final rows; this is not an exact cell-local target
# under grid shift/Q6, so use a deliberately loose 20% coupling sanity bound.
rows=list(csv.DictReader(open(p,newline='')))
last=max(int(r['step']) for r in rows)
by={int(r['type']):r for r in rows if int(r['step'])==last}
for typ,target in ((1,t1),(2,t2)):
    r=by.get(typ)
    if r is None: raise SystemExit(f'[0493x14f] FAIL missing type {typ} at final step')
    n=int(r['nFluid']); M=float(r['totalMass']); ke=float(r['kineticEnergy']); ux=float(r['meanVx']); uy=float(r['meanVy'])
    internal=ke-0.5*M*(ux*ux+uy*uy)
    app=internal/max(1,n-1)
    rel=abs(app-target)/target
    print(f'[0493x14f] type={typ} finalGlobalApparentKBT={app:.12g} target={target:.12g} rel={rel:.3e} N={n}')
    if not math.isfinite(app) or rel>0.20:
        raise SystemExit(f'[0493x14f] FAIL type {typ} apparent kBT outside 20% coupling sanity band')
print('[0493x14f] temperature coupling sanity PASS')
PY

echo "[0493x14f] PASS src-q6-g-f production-path species thermostat quick probe"
