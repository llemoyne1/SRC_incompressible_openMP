#!/usr/bin/env bash
# 0493x22c — JCP Section 3.6 liquid-gas computational-cost benchmark.
# Runner/tooling only. No solver/source modification.
# B0: two-species kinetic reference (common SRC + phase thermostats; no particle/field closure).
# B1: full qualified liquid-gas particle/field chain.

ROOT="${ROOT:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)" || exit 2
cd "$ROOT" || exit 2

COMMON="$ROOT/scripts/src_mpcd_run_ok_common.sh"
[[ -f "$COMMON" ]] || { echo "[0493x22c] ERROR missing $COMMON" >&2; exit 2; }
# shellcheck source=/dev/null
source "$COMMON"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
EXPECTED_BIN_SHA="${EXPECTED_BIN_SHA:-422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc}"
GEN="${GEN:-scripts/generate_0493x14x_oscillating_drop_two_phase.py}"
ANALYZER="${ANALYZER:-scripts/analyze_0493x22c_twophase_cost.py}"
ROOTOUT="${ROOTOUT:-runs/0493x22c_article_twophase_cost}"
# Required by suite_defaults_common_0434 when RECORD_SESSION_PREFIX is defaulted.
# Define it before suite_defaults_common_0434 so the wrapper is safe under set -u.
CASE_LABEL="${CASE_LABEL:-0493x22c_article_twophase_cost}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
SMOKE_ONLY="${SMOKE_ONLY:-0}"
RESTART="${RESTART:-1}"

Lx=1.5625; Ly=1.5625; NX=400; NY=400; GAMMA=20
DT=0.002; SEED=493180; THREADS="${THREADS:-8}"
ROTATION_ANGLE=1.5707963267948966; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
RADIUS_CELLS=40; MODE=2; EPSILON=0.04; PHASE=0.0; CENTER_X=0.78125; CENTER_Y=0.78125
LIQUID_TYPE=1; GAS_TYPE=2; LIQUID_MASS=1.0; GAS_MASS=0.1; LIQUID_KBT=0.02; GAS_KBT=0.08
SURFACE_TENSION_SIGMA=2560.0; SURFACE_TENSION_MIN_RADIUS_CELLS=4
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION=1.0; PHASE_INTERFACE_EVAPORATION_TARGET_TYPE=-1; PHASE_INTERFACE_CONTACT_ANGLE_DEG=-1
X12A_LOCAL_THERMAL_RADIUS_CELLS=25.298221281347036
WARMUP_STEPS="${WARMUP_STEPS:-100}"; TIMING_STEPS="${TIMING_STEPS:-400}"; TIMING_REPS="${TIMING_REPS:-5}"; SMOKE_STEPS="${SMOKE_STEPS:-400}"

fail(){ echo "[0493x22c] ERROR: $*" >&2; exit 2; }
truthy(){ case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON) return 0;; *) return 1;; esac; }

[[ -x "$BIN" ]] || fail "binary not executable: $BIN"
[[ -f "$GEN" ]] || fail "missing generator: $GEN"
[[ -f "$ANALYZER" ]] || fail "missing analyzer: $ANALYZER"
for c in python3 sha256sum awk sed grep; do command -v "$c" >/dev/null 2>&1 || fail "missing command: $c"; done
ACTUAL_SHA="$(sha256sum "$BIN" | awk '{print $1}')"
[[ "$ACTUAL_SHA" == "$EXPECTED_BIN_SHA" ]] || fail "binary SHA mismatch actual=$ACTUAL_SHA expected=$EXPECTED_BIN_SHA"
[[ "$TIMING_REPS" == 5 ]] || fail "article benchmark requires 5 measured pairs"

mkdir -p "$ROOTOUT"/{init,params,logs,outputs,analysis}
STATE="$ROOTOUT/init/two_phase_modal_drop_seed${SEED}.smpcd"
TIMING_CSV="$ROOTOUT/timing_twophase_raw.csv"
GPU_CSV="$ROOTOUT/gpu_state_twophase.csv"

if [[ ! -s "$STATE" ]]; then
  python3 "$GEN" --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --center-x "$CENTER_X" --center-y "$CENTER_Y" --radius-cells "$RADIUS_CELLS" --mode "$MODE" --epsilon "$EPSILON" --phase "$PHASE" \
    --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
    --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --seed "$SEED" >/dev/null || fail "state generation failed"
fi

# Common physical/numerical variables consumed by the qualified runner library.
KBT="$GAS_KBT"; THERMOSTAT_TARGET_KBT="$GAS_KBT"; THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1; THERMOSTAT_MIN_PARTICLES=3
PARTICLE_MASS="$GAS_MASS"; U0=0.0; UIN=0.0; INACTIVE_SLOTS=0; SUMMARY_ROLE_FILTER=fluid; DUMP_ROLE_FILTER=fluid
PROJECTION_BACKEND=cuda; PROJECTION_OPERATOR=auto_fv_cg; PROJECTION_MAX_ITERATIONS=800; PROJECTION_TOLERANCE=1.0e-5; PROJECTION_MOMENTUM_CORRECTION_ENABLE=false; Q6_PROJECTION_STRENGTH=1.0; Q6_STRICT=1
SPECIES_RESAMPLING_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false; RESAMPLING_MASS_GUARD_ENABLE=false; CUDA_RESAMPLING_CHI_FILTER_ENABLE=false; CUDA_RESAMPLING_CHI_MIN=0.05
GUARD_NMIN=16; GUARD_NTARGET=20; GUARD_NMAX=24
Q6_GF_EXTERNAL_SPECIES=1; Q6_GF_HAS_GAS_PHASE=1; Q6_GF_MIN_FILL_FRACTION=0.10
Q6_GF_DENSITY_RELAXATION_TIME=0.25; Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1; Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3.0
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6.0; Q6_GF_DENSITY_TRACTION_GAIN=1.0
PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"; PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"
LIVE_VIS_ENABLE=0; FILTERED_RECORDING_ENABLE=0; RECORD_ENABLE=false; PARTICLE_TYPE_FILTER=-1
export OMP_NUM_THREADS="$THREADS" OMP_DYNAMIC=false OMP_PLACES=cores OMP_PROC_BIND=close
export LIVE_PROGRESS=0 SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 SRC_LIVE_VIS_HOLD_ON_EXIT=0 MPCD_LIVE_VIS_HOLD_ON_EXIT=0 MPCD_FILTERED_FIELD_RECORDING_0432=0

suite_defaults_common_0434
suite_compute_derived_0434

sample_gpu(){
  stage="$1"
  command -v nvidia-smi >/dev/null 2>&1 || return 0
  if [[ ! -s "$GPU_CSV" ]]; then
    echo 'stage,timestamp,name,driver_version,pstate,temperature_gpu,power_draw_w,clocks_sm_mhz,utilization_gpu_pct,memory_used_mib' > "$GPU_CSV"
  fi
  line="$(nvidia-smi --query-gpu=timestamp,name,driver_version,pstate,temperature.gpu,power.draw,clocks.sm,utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null | head -n1)"
  [[ -n "$line" ]] && printf '%s,%s\n' "$stage" "$line" >> "$GPU_CSV"
}

set_variant_env(){
  v="$1"
  if [[ "$v" == B0 ]]; then
    suite_export_cuda_flags_0434 src periodic || return $?
    run_ok_surface_export_off_flags_0493x13zi
    export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0
    export MPCD_X14L_GAS_SPECULAR_REFLECTION=0
    export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=0 MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=0
    export MPCD_X14V_X6G_FACE_THERMO_TRACTION=0 MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0 MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0 MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=0
    export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0 MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=0 MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0 MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=0
  else
    suite_export_cuda_flags_0434 src-q6-g-f periodic || return $?
    run_ok_surface_export_off_flags_0493x13zi
    # Exact x14ai-fix1 production liquid-gas chain.
    cell_area="$(awk -v lx="$Lx" -v nx="$NX" 'BEGIN{h=lx/nx;printf "%.17g",h*h}')"
    p_ref="$(awk -v g="$GAMMA" -v t="$GAS_KBT" -v a="$cell_area" 'BEGIN{printf "%.17g",g*t/a}')"
    export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1 MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$p_ref" MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1
    export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1 MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS" MPCD_X10O_THERMAL_SIGMAS=3.0 MPCD_X10O_THERMAL_MAX_CELLS=0.75
    export MPCD_X10_KINETIC_INTERFACE_CIC=1 MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1 MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
    export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1 MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1 MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0 MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
    export MPCD_X12A_LOCAL_THERMAL_COOLING=1 MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="$X12A_LOCAL_THERMAL_RADIUS_CELLS"
    export MPCD_X14L_GAS_SPECULAR_REFLECTION=1
    export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1 MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1
    export MPCD_X14V_X6G_FACE_THERMO_TRACTION=0 MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0 MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0 MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
    export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0 MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=0 MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0 MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=1
    export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1 MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
  fi
  # Timing purity: all article-only audits off in both variants.
  export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0 MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=0 MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0 MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0 MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
}

deduplicate_identical_params(){
  p="$1"
  python3 - "$p" <<'PY_DEDUP'
from pathlib import Path
import sys
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
seen={}
out=[]
removed=[]
for lineno,raw in enumerate(lines,1):
    s=raw.strip()
    if not s or s.startswith('#') or '=' not in s:
        out.append(raw); continue
    k,val=map(str.strip,s.split('=',1))
    if k not in seen:
        seen[k]=(val,lineno)
        out.append(raw)
        continue
    old,oldline=seen[k]
    if val != old:
        raise SystemExit(
            f'[0493x22c] ERROR conflicting duplicate parameter {k}: '
            f'line {oldline}={old!r}, line {lineno}={val!r}')
    removed.append((k,lineno))
# Preserve exact semantics while making the parameter file parser-clean.
p.write_text('\n'.join(out)+'\n')
for k,lineno in removed:
    print(f'[0493x22c] canonicalized identical duplicate key={k} removedLine={lineno}')
PY_DEDUP
}

write_params(){
  v="$1"; steps="$2"; p="$3"; outdir="$4"; diag="${5:-0}"
  mkdir -p "$outdir"
  SUMMARY_EVERY="$steps"; DUMP_STATE_EVERY=0
  cat > "$p" <<EOF
inputState = $STATE
outputDir = $outdir
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $steps
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
wallVpEnable = false
wallAccommodation = 1.0
wallThermalNoise = 0.0
speciesRegistryEnable = true
speciesCount = 2
EOF
  if [[ "$v" == B0 ]]; then
    cat >> "$p" <<EOF
species0 = $LIQUID_TYPE kinetic_liquid liquid 0.0 1.0 20
species1 = $GAS_TYPE kinetic_gas gas 0.0 0.0 2
EOF
  else
    cat >> "$p" <<EOF
species0 = $LIQUID_TYPE incompressible_liquid liquid 1.0 1.0 20
species1 = $GAS_TYPE compressible_gas gas 0.0 0.0 2
EOF
  fi
  cat >> "$p" <<EOF
species0ResamplingEnable = false
species1ResamplingEnable = false
species0ThermostatTargetKBT = $LIQUID_KBT
species1ThermostatTargetKBT = $GAS_KBT
speciesRequireRegisteredTypes = true
speciesThermostatEnable = true
speciesDiagnosticsEnable = $( [[ "$diag" == 1 ]] && echo true || echo false )
speciesDiagnosticsFilename = species_runtime_0493x22c.csv
speciesCellDiagnosticsEnable = false
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
EOF
  if [[ "$v" == B0 ]]; then
    species_q6_external_saved="$Q6_GF_EXTERNAL_SPECIES"; Q6_GF_EXTERNAL_SPECIES=0
    suite_write_common_params_0434 src >> "$p" || return $?
    Q6_GF_EXTERNAL_SPECIES="$species_q6_external_saved"
    cat >> "$p" <<EOF
speciesQ6Enable = false
EOF
  else
    Q6_GF_EXTERNAL_SPECIES=1
    suite_write_common_params_0434 src-q6-g-f >> "$p" || return $?
    run_ok_surface_append_params_0493x13zi "$p" "$PHASE_INTERFACE_A_SELECTOR" "$PHASE_INTERFACE_B_SELECTOR" || return $?
    cat >> "$p" <<EOF
phaseInterfaceKineticBilateralRelocation = true
EOF
  fi
  # The qualified src-q6-g-f common writer emits projectionMomentumCorrectionEnable
  # once in its mode-specific block and once in the generic projection block.
  # They are expected to be identical here (false). Canonicalize only identical
  # duplicates; abort on any conflicting value so benchmark physics cannot change
  # silently.
  deduplicate_identical_params "$p" || return $?
}

validate_params(){
  p="$1" v="$2" steps="$3"
  python3 - "$p" "$v" "$steps" <<'PY'
import sys
p,v,steps=sys.argv[1:]; d={}
for raw in open(p):
 s=raw.strip()
 if not s or s.startswith('#') or '=' not in s: continue
 k,val=map(str.strip,s.split('=',1))
 if k in d: raise SystemExit(f'duplicate key {k}')
 d[k]=val
req={'Nx':'400','Ny':'400','dt':'0.002','nSteps':steps,'bcX':'periodic','bcY':'periodic','speciesRegistryEnable':'true','speciesCount':'2','species0ThermostatTargetKBT':'0.02','species1ThermostatTargetKBT':'0.08','resamplingEnable':'false','dumpStateEvery':'0'}
for k,x in req.items():
 if d.get(k)!=x: raise SystemExit(f'bad {k}={d.get(k)} expected {x}')
if v=='B0':
 exp={'srcClassicCudaModeEnable':'true','projectionEnable':'false','speciesQ6Enable':'false'}
 forbidden=['surfaceTensionSigma','phaseInterfaceASelector']
 for k in forbidden:
  if k in d: raise SystemExit(f'B0 unexpectedly has {k}')
else:
 exp={'srcClassicCudaModeEnable':'false','projectionEnable':'true','speciesQ6Enable':'true','speciesQ6Mode':'free_surface_masked','surfaceTensionSigma':'2560.0','phaseInterfaceASelector':'type:1','phaseInterfaceBSelector':'type:2','projectionMomentumCorrectionEnable':'false'}
for k,x in exp.items():
 if d.get(k)!=x: raise SystemExit(f'bad {k}={d.get(k)} expected {x}')
print(f'[0493x22c] params audit PASS variant={v} steps={steps}')
PY
}

# Preflight both measured paths.
for v in B0 B1; do
  set_variant_env "$v" || exit $?
  p="$ROOTOUT/params/${v}_template.kv"
  write_params "$v" "$TIMING_STEPS" "$p" "$ROOTOUT/outputs/template_${v}" 0 || exit $?
  validate_params "$p" "$v" "$TIMING_STEPS" || exit $?
done

cat > "$ROOTOUT/benchmark_contract.txt" <<EOF
campaign=0493x22c_article_twophase_cost
binary=$BIN
binarySha256=$ACTUAL_SHA
state=$STATE
grid=${NX}x${NY}
gamma=$GAMMA
rotationAngleDeg=90
dt=$DT
liquidMass=$LIQUID_MASS
gasMass=$GAS_MASS
liquidKBT=$LIQUID_KBT
gasKBT=$GAS_KBT
seed=$SEED
RoverH=$RADIUS_CELLS
sigma=$SURFACE_TENSION_SIGMA
B0=kinetic two-species reference; common SRC + species thermostats; no projection/free-surface/capillary/interface closure
B1=full qualified liquid-gas particle/field chain x14ai-fix1
sameInitialState=true
sameParticleCount=true
liveVis=OFF
recording=OFF
dumps=OFF
smokeSteps=$SMOKE_STEPS
warmupSteps=$WARMUP_STEPS
measuredSteps=$TIMING_STEPS
pairs=$TIMING_REPS
EOF

if truthy "$PREFLIGHT_ONLY"; then
  echo "[0493x22c] PREFLIGHT PASS"
  cat "$ROOTOUT/benchmark_contract.txt"
  exit 0
fi

run_solver(){
  v="$1" rep="$2" order="$3" steps="$4" kind="$5" diag="${6:-0}"
  set_variant_env "$v" || return $?
  tag="${kind}_${v,,}_r${rep}"; p="$ROOTOUT/params/${tag}.kv"; outdir="$ROOTOUT/outputs/${tag}"; log="$ROOTOUT/logs/${tag}.log"; tf="$ROOTOUT/logs/${tag}.time"
  rm -rf "$outdir"; mkdir -p "$outdir"
  write_params "$v" "$steps" "$p" "$outdir" "$diag" || return $?
  validate_params "$p" "$v" "$steps" || return $?
  sample_gpu "pre_${v,,}_r${rep}"
  echo "[0493x22c] START kind=$kind variant=$v rep=$rep order=$order steps=$steps"
  /usr/bin/time -o "$tf" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$p" >"$log" 2>&1
  rc=$?; [[ $rc -eq 0 ]] || { echo "[0493x22c] solver failed rc=$rc log=$log" >&2; return $rc; }
  sample_gpu "post_${v,,}_r${rep}"
  if [[ "$kind" == measured ]]; then
    line="$(cat "$tf")"; elapsed="$(printf '%s\n' "$line" | sed -n 's/.*elapsed=\([^ ]*\).*/\1/p')"; user="$(printf '%s\n' "$line" | sed -n 's/.*user=\([^ ]*\).*/\1/p')"; sysv="$(printf '%s\n' "$line" | sed -n 's/.*sys=\([^ ]*\).*/\1/p')"
    [[ -n "$elapsed" ]] || return 2
    sps="$(awk -v e="$elapsed" -v n="$steps" 'BEGIN{printf "%.17g",e/n}')"
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$v" "$rep" "$order" "$steps" "$elapsed" "$user" "$sysv" "$sps" "$tf" >> "$TIMING_CSV"
    echo "[0493x22c] DONE variant=$v rep=$rep s/step=$sps"
  fi
  return 0
}

# Step 10: non-timed B0 smoke. It may be physically incoherent; the gate only
# requires finite execution, fixed populations and no workload-changing loss.
if truthy "$SMOKE_ONLY"; then
  rm -f "$GPU_CSV"
  run_solver B0 0 0 "$SMOKE_STEPS" smoke 1 || exit $?
  csv="$ROOTOUT/outputs/smoke_b0_r0/species_runtime_0493x22c.csv"
  [[ -s "$csv" ]] || fail "B0 smoke missing species runtime CSV"
  python3 - "$csv" "$ROOTOUT/analysis/twophase_B0_smoke.txt" <<'PY'
import csv,math,sys
p,out=sys.argv[1:]
rows=list(csv.DictReader(open(p,newline='')))
if not rows: raise SystemExit('[0493x22c-smoke] empty species CSV')
# Support both explicit totalMass and nFluid columns; require species 1 and 2.
by={}
for r in rows: by.setdefault(int(r['type']),[]).append(r)
if set(by)!={1,2}: raise SystemExit(f'[0493x22c-smoke] unexpected species {sorted(by)}')
lines=['===== 0493x22c B0 SMOKE =====']
for typ in (1,2):
 rr=by[typ]
 n=[int(float(x['nFluid'])) for x in rr]
 m=[float(x['totalMass']) for x in rr]
 finite=all(math.isfinite(float(x[k])) for x in rr for k in ('totalMass','Px','Py','kineticEnergy'))
 ok=(min(n)==max(n) and max(m)-min(m)<=1e-10*max(1.0,abs(m[0])) and finite)
 lines.append(f'type={typ} n0={n[0]} nRange={min(n)}..{max(n)} mass0={m[0]:.17g} massRange={min(m):.17g}..{max(m):.17g} finite={int(finite)} status={"PASS" if ok else "FAIL"}')
 if not ok: raise SystemExit('\n'.join(lines))
lines.append('B0_SMOKE=PASS')
open(out,'w').write('\n'.join(lines)+'\n'); print('\n'.join(lines))
PY
  exit $?
fi

if truthy "$RESTART" && [[ -s "$ROOTOUT/analysis/timing_twophase_summary.json" ]]; then
  echo "[0493x22c] complete analysis already exists; RESTART=1 -> no rerun"
  cat "$ROOTOUT/analysis/timing_twophase_summary.txt"
  exit 0
fi
rm -f "$TIMING_CSV" "$GPU_CSV"
echo 'variant,rep,order,steps,elapsed,user,sys,seconds_per_step,time_file' > "$TIMING_CSV"

# Identical excluded warm-up for each computational path.
run_solver B0 0 0 "$WARMUP_STEPS" warmup 0 || exit $?
run_solver B1 0 0 "$WARMUP_STEPS" warmup 0 || exit $?
rep=1
while [[ $rep -le $TIMING_REPS ]]; do
  if (( rep % 2 == 1 )); then
    run_solver B0 "$rep" 1 "$TIMING_STEPS" measured 0 || exit $?
    run_solver B1 "$rep" 2 "$TIMING_STEPS" measured 0 || exit $?
  else
    run_solver B1 "$rep" 1 "$TIMING_STEPS" measured 0 || exit $?
    run_solver B0 "$rep" 2 "$TIMING_STEPS" measured 0 || exit $?
  fi
  rep=$((rep+1))
done
python3 "$ANALYZER" "$TIMING_CSV" "$GPU_CSV" "$ROOTOUT/analysis" || exit $?
