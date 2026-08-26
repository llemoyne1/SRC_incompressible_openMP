#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0493x9q: qualitative dripping-jet potential test for the existing x9/Q6-G-F
# capillary path.  This is deliberately NOT a calibrated dripping-faucet test.
CASE_LABEL="dripping_vk_0493x10o_q6_thermal_interface"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"
TOPOLOGY=segmented
RESTART="${RESTART:-}"
TARGET_STEP="${TARGET_STEP:-}"
if [[ -n "$RESTART" ]]; then
  RESTART_TAG="$(basename "$RESTART" .smpcd)"
  RUN_ROOT="${RUN_ROOT:-runs/0493x10o_q6_thermal_interface_dripping_restart_${RESTART_TAG}}"
else
  RUN_ROOT="${RUN_ROOT:-runs/0493x10o_q6_thermal_interface_dripping_s4500_g01_v2}"
fi
CASES="${CASES:-capillary}"

# Square cells: h=0.005 by default.
Lx="${Lx:-1.0}"; Ly="${Ly:-1.5}"; NX="${NX:-200}"; NY="${NY:-300}"
GAMMA="${GAMMA:-20}"; DT="${DT:-0.002}"; KBT="${KBT:-0.125}"; STEPS="${STEPS:-30000}"
SEED="${SEED:-493940}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
GAS_MASS="${GAS_MASS:-1.0}"; LIQUID_MASS="${LIQUID_MASS:-1.0}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"; GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"
SIGMA_ACTIVE="${SIGMA_ACTIVE:-4500.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-3}"
GRAVITY_Y="${GRAVITY_Y:--0.1}"
UIN="${UIN:-0.1}"
INLET_WIDTH_CELLS="${INLET_WIDTH_CELLS:-6}"
INLET_CENTER_X="${INLET_CENTER_X:-0.5}"
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-2}"
# x9q-fix2: 0142 allows segmented openings on only one Cartesian axis.
# Keep all openings on the TOP face: centered liquid inlet + two symmetric gas vents.
VENT_LEFT_SMIN="${VENT_LEFT_SMIN:-0.05}"
VENT_LEFT_SMAX="${VENT_LEFT_SMAX:-0.35}"
VENT_RIGHT_SMIN="${VENT_RIGHT_SMIN:-0.65}"
VENT_RIGHT_SMAX="${VENT_RIGHT_SMAX:-0.95}"
CONTACT_ANGLE_DEG="${CONTACT_ANGLE_DEG:-90.0}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-$((GAMMA*NX*NY/2))}"

VACUUM_BACKGROUND="${VACUUM_BACKGROUND:-1}"
KINETIC_REFLECTION_FRACTION="${KINETIC_REFLECTION_FRACTION:-1.0}"
EVAPORATION_TARGET_TYPE="${EVAPORATION_TARGET_TYPE:--1}"

if [[ "$KINETIC_REFLECTION_FRACTION" != "1" && "$KINETIC_REFLECTION_FRACTION" != "1.0" ]]; then
  echo "[0493x10g-drip] ERROR this validation is intentionally hard-r1 only" >&2
  exit 2
fi
if ! suite_truthy_0434 "$VACUUM_BACKGROUND"; then
  echo "[0493x10g-drip] ERROR kinetic retention currently requires vacuum background" >&2
  exit 2
fi

python3 - "$KBT" "$LIQUID_MASS" "$DT" "$GAMMA" "$SIGMA_ACTIVE" "$GRAVITY_Y" <<'PY'
import math, sys
kbt=float(sys.argv[1]); m=float(sys.argv[2]); dt=float(sys.argv[3]); gamma=float(sys.argv[4]); sigma=float(sys.argv[5]); g=float(sys.argv[6])
legacy_kbt=1.25e-6; legacy_m=10.0
vth=math.sqrt(kbt/m); legacy_vth=math.sqrt(legacy_kbt/legacy_m)
print('[0493x10g-drip] VK-fluid validation against historical cold x9q/x9r dripping')
print(f'[0493x10g-drip] gamma={gamma:g} dt={dt:g} kBT={kbt:g} liquidMass={m:g} vthProxy=sqrt(kBT/m)={vth:.8g}')
print(f'[0493x10g-drip] historicalCold kBT={legacy_kbt:g} liquidMass={legacy_m:g} vthProxy={legacy_vth:.8g} thermalSpeedRatio={vth/legacy_vth:.6g}')
print(f'[0493x10g-drip] capillary/gravity kept from x9r qualitative case: sigma={sigma:g} gravityY={g:g}')
print('[0493x10g-drip] NOTE capability test only: changing particle mass means this is not nondimensionally matched to the cold historical run')
PY

if suite_truthy_0434 "$VACUUM_BACKGROUND"; then
  PHASE_B_SELECTOR="vacuum"
  Q6_GF_HAS_GAS_PHASE=0
else
  PHASE_B_SELECTOR="type:$GAS_TYPE"
  Q6_GF_HAS_GAS_PHASE=1
fi

SUMMARY_EVERY="${SUMMARY_EVERY:-25}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-2000}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

# Restart semantics:
# - RESTART points to a v2 .smpcd state dump.
# - The solver step/time counters restart from zero; STEPS is therefore the
#   number of additional steps unless TARGET_STEP is supplied.
# - TARGET_STEP is an optional nominal global target, parsed against
#   state_step_XXXXXXXX.smpcd when possible.
# - The RNG stream is re-seeded from SEED; this is a physical continuation,
#   not a bitwise continuation of the stochastic trajectory.
RESTART_STEP=0
if [[ -n "$RESTART" ]]; then
  [[ -f "$RESTART" ]] || {
    echo "[0493x10o-restart] ERROR restart dump not found: $RESTART" >&2
    exit 2
  }
  RESTART="$(python3 - "$RESTART" <<'PY'
import os, sys
print(os.path.abspath(sys.argv[1]))
PY
)"
  RESTART_BASE="$(basename "$RESTART")"
  if [[ "$RESTART_BASE" =~ ^state_step_([0-9]+)\.smpcd$ ]]; then
    RESTART_STEP=$((10#${BASH_REMATCH[1]}))
  fi
  if [[ -n "$TARGET_STEP" ]]; then
    [[ "$TARGET_STEP" =~ ^[0-9]+$ ]] || {
      echo "[0493x10o-restart] ERROR TARGET_STEP must be an integer >= 0" >&2
      exit 2
    }
    (( TARGET_STEP > RESTART_STEP )) || {
      echo "[0493x10o-restart] ERROR TARGET_STEP=$TARGET_STEP must exceed restartStep=$RESTART_STEP" >&2
      exit 2
    }
    STEPS=$((TARGET_STEP - RESTART_STEP))
  fi
fi

if [[ -n "$RESTART" ]]; then
  # A restarted faucet is already past its startup ramp.  Since the state dump
  # does not carry the absolute simulation clock, keep the nominal inlet active
  # immediately rather than replaying the 0..0.25 startup transient.
  INLET_RAMP_ENABLE="${INLET_RAMP_ENABLE:-false}"
  INLET_RAMP_START_TIME="${INLET_RAMP_START_TIME:-0.0}"
  INLET_RAMP_END_TIME="${INLET_RAMP_END_TIME:-0.25}"
  INLET_RAMP_INITIAL_FACTOR="${INLET_RAMP_INITIAL_FACTOR:-1.0}"
  INLET_RAMP_FINAL_FACTOR="${INLET_RAMP_FINAL_FACTOR:-1.0}"
else
  INLET_RAMP_ENABLE="${INLET_RAMP_ENABLE:-true}"
  INLET_RAMP_START_TIME="${INLET_RAMP_START_TIME:-0.0}"
  INLET_RAMP_END_TIME="${INLET_RAMP_END_TIME:-0.25}"
  INLET_RAMP_INITIAL_FACTOR="${INLET_RAMP_INITIAL_FACTOR:-0.2}"
  INLET_RAMP_FINAL_FACTOR="${INLET_RAMP_FINAL_FACTOR:-1.0}"
fi

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
PARTICLE_TYPE_FILTER="$LIQUID_TYPE"

MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0
MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0
MPCD_X10M_MOVING_INTERFACE_WALL=0
MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
MPCD_X10O_THERMAL_PARTICLE_MASS="${MPCD_X10O_THERMAL_PARTICLE_MASS:-$LIQUID_MASS}"
MPCD_X10O_THERMAL_SIGMAS="${MPCD_X10O_THERMAL_SIGMAS:-3.0}"
MPCD_X10O_THERMAL_MAX_CELLS="${MPCD_X10O_THERMAL_MAX_CELLS:-0.75}"
MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS=1
export MPCD_X10J_SIMPLE_SPECULAR_ABLATION MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION MPCD_X10M_MOVING_INTERFACE_WALL MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL MPCD_X10O_Q6_THERMAL_INTERFACE_WALL MPCD_X10O_THERMAL_PARTICLE_MASS MPCD_X10O_THERMAL_SIGMAS MPCD_X10O_THERMAL_MAX_CELLS MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS
LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}"
LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}"
LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
OVERWRITE_LIVEVIS_CONTROL="${OVERWRITE_LIVEVIS_CONTROL:-1}"
if [[ "$LIVE_VIS_RECORD_ENABLE" == 1 || "$LIVE_VIS_RECORD_ENABLE" == true ]]; then RECORD_ENABLE=true; else RECORD_ENABLE=false; fi
RECORD_EVERY="$LIVE_VIS_RECORD_EVERY"
RECORD_FIELDS="$LIVE_VIS_RECORD_FIELDS"
export LIVE_VIS_RECORD_ENABLE LIVE_VIS_RECORD_EVERY LIVE_VIS_RECORD_FIELDS FILTER_SAMPLE_EVERY OVERWRITE_LIVEVIS_CONTROL RECORD_ENABLE RECORD_EVERY RECORD_FIELDS

THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"; THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
PROJECTION_BACKEND=cuda; PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"; PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-5}"
Q6_PROJECTION_STRENGTH=1.0; Q6_STRICT="${Q6_STRICT:-1}"

Q6_GF_EXTERNAL_SPECIES=1

Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1; Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3.0
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6.0; Q6_GF_DENSITY_TRACTION_GAIN=1.0
SPECIES_RESAMPLING_ENABLE=false; LIQUID_RESAMPLING_ENABLE=false; GAS_RESAMPLING_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero; PARTICLE_MASS="$GAS_MASS"; BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$LIQUID_TYPE"; TG_HOLE_ENABLE=false
suite_defaults_common_0434
suite_compute_derived_0434

python3 - "$Lx" "$Ly" "$NX" "$NY" "$INLET_WIDTH_CELLS" "$INLET_CENTER_X" "$LIQUID_MASS" "$GAS_MASS" "$VENT_LEFT_SMIN" "$VENT_LEFT_SMAX" "$VENT_RIGHT_SMIN" "$VENT_RIGHT_SMAX" <<'PY'
import sys
Lx,Ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
w=float(sys.argv[5]); cx=float(sys.argv[6]); ml,mg=float(sys.argv[7]),float(sys.argv[8]); vl0,vl1,vr0,vr1=map(float,sys.argv[9:13])
dx=Lx/nx; dy=Ly/ny
if abs(dx-dy)>1e-12: raise SystemExit('[0493x9q] square cells required')
if not (4 <= w <= 0.25*nx): raise SystemExit('[0493x9q] inlet width must be >=4 cells and <=25% of Nx')
if not (0.0 < cx < 1.0): raise SystemExit('[0493x9q] inlet center must be a relative x coordinate in (0,1)')
if not (ml>0 and mg>0): raise SystemExit('[0493x9q] masses must be positive')
if not (0.0 <= vl0 < vl1 <= 1.0 and 0.0 <= vr0 < vr1 <= 1.0):
    raise SystemExit('[0493x9q] top vent intervals must lie in [0,1] with min<max')
in0=max(0.0,cx-0.5*w/nx); in1=min(1.0,cx+0.5*w/nx)
if not (vl1 < in0 and in1 < vr0):
    raise SystemExit('[0493x9q] top vents must remain disjoint from centered inlet')
print(f'[0493x9q] geometry h={dx:.8g} inletWidth={w*dx:.8g} massRatio={ml/mg:.6g} '
      f'topVents=[{vl0:.3f},{vl1:.3f}]+[{vr0:.3f},{vr1:.3f}]')
PY

INLET_SMIN="$(awk -v cx="$INLET_CENTER_X" -v w="$INLET_WIDTH_CELLS" -v nx="$NX" 'BEGIN{s=cx-0.5*w/nx;if(s<0)s=0;printf "%.17g",s}')"
INLET_SMAX="$(awk -v cx="$INLET_CENTER_X" -v w="$INLET_WIDTH_CELLS" -v nx="$NX" 'BEGIN{s=cx+0.5*w/nx;if(s>1)s=1;printf "%.17g",s}')"
LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GAS_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"

if [[ -n "$RESTART" ]] && suite_truthy_0434 "$CLEAN_RUN_ROOT"; then
  RUN_ROOT_ABS="$(python3 - "$RUN_ROOT" <<'PY'
import os, sys
print(os.path.abspath(sys.argv[1]))
PY
)"
  case "$RESTART" in
    "$RUN_ROOT_ABS"|"$RUN_ROOT_ABS"/*)
      echo "[0493x10o-restart] ERROR RESTART is inside RUN_ROOT while CLEAN_RUN_ROOT=1" >&2
      echo "[0493x10o-restart] use a new RUN_ROOT (recommended) or CLEAN_RUN_ROOT=0" >&2
      exit 2
      ;;
  esac
fi

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/logs"

if [[ -n "$RESTART" ]]; then
  # Production dumps normally use dumpRoleFilter=fluid, so the inactive liquid
  # tail used by hard-cell inlet injection is absent from a restart dump.
  # Rebuild only the missing inactive capacity in a private copy; never mutate
  # the source dump.
  STATE="$RUN_ROOT/init/restart_with_liquid_slots_0493x10o.smpcd"
  python3 - "$RESTART" "$STATE" "$INACTIVE_SLOTS" "$LIQUID_TYPE" "$LIQUID_MASS" <<'PY'
from array import array
import os
import struct
import sys

src, out = sys.argv[1], sys.argv[2]
target_inactive = int(sys.argv[3])
liquid_type = int(sys.argv[4])
liquid_mass = float(sys.argv[5])

hdr_fmt = "<IIIIQIIII"
hdr_size = struct.calcsize(hdr_fmt)

with open(src, "rb") as f:
    magic = f.read(16)
    if not magic.startswith(b"SRCMPCD_STATE"):
        raise SystemExit(f"[0493x10o-restart] ERROR bad state magic in {src}")
    raw = f.read(hdr_size)
    if len(raw) != hdr_size:
        raise SystemExit(f"[0493x10o-restart] ERROR truncated header in {src}")
    version, endian, dim, ns, n, a, b, rsv_n, word = struct.unpack(hdr_fmt, raw)
    if version != 2 or endian != 0x01020304 or dim != 2:
        raise SystemExit(
            f"[0493x10o-restart] ERROR unsupported state header "
            f"version={version} endian={endian:#x} dim={dim}"
        )
    reserved_raw = f.read(8 * 8)
    if len(reserved_raw) != 8 * 8:
        raise SystemExit(f"[0493x10o-restart] ERROR truncated reserved header in {src}")

    def read_array(code, count):
        arr = array(code)
        need = arr.itemsize * count
        data = f.read(need)
        if len(data) != need:
            raise SystemExit(
                f"[0493x10o-restart] ERROR truncated array {code}: "
                f"need={need} got={len(data)}"
            )
        arr.frombytes(data)
        if sys.byteorder == "big":
            arr.byteswap()
        return arr

    x = read_array("d", n)
    y = read_array("d", n)
    vx = read_array("d", n)
    vy = read_array("d", n)
    typ = read_array("I", n)
    mass = read_array("d", n)
    role = read_array("B", n)

    trailing = f.read()
    if trailing:
        raise SystemExit(
            f"[0493x10o-restart] ERROR unexpected trailing bytes={len(trailing)} in {src}"
        )

existing_inactive = sum(1 for r in role if r == 0)
add = max(0, target_inactive - existing_inactive)

if add:
    x.extend([0.0] * add)
    y.extend([0.0] * add)
    vx.extend([0.0] * add)
    vy.extend([0.0] * add)
    typ.extend([liquid_type] * add)
    mass.extend([liquid_mass] * add)
    role.extend([0] * add)

new_n = n + add
os.makedirs(os.path.dirname(out) or ".", exist_ok=True)

with open(out, "wb") as f:
    f.write(magic)
    f.write(struct.pack(
        hdr_fmt, version, endian, dim, ns, new_n, a, b, rsv_n, word
    ))
    f.write(reserved_raw)
    for arr in (x, y, vx, vy, typ, mass, role):
        if sys.byteorder == "big":
            arr.byteswap()
            f.write(arr.tobytes())
            arr.byteswap()
        else:
            f.write(arr.tobytes())

print(
    f"[0493x10o-restart] source={src} sourceParticles={n} "
    f"existingInactive={existing_inactive} addedInactive={add} "
    f"state={out} totalParticles={new_n}"
)
PY

  NOMINAL_FINAL_STEP=$((RESTART_STEP + STEPS))
  echo "[0493x10o-restart] restartStep=$RESTART_STEP additionalSteps=$STEPS nominalFinalStep=$NOMINAL_FINAL_STEP"
  echo "[0493x10o-restart] inletRamp=$INLET_RAMP_ENABLE initialFactor=$INLET_RAMP_INITIAL_FACTOR finalFactor=$INLET_RAMP_FINAL_FACTOR"
  echo "[0493x10o-restart] NOTE solver time/step counters and RNG sequence restart locally from zero"
else
  if suite_truthy_0434 "$VACUUM_BACKGROUND"; then

    STATE="$RUN_ROOT/init/vacuum_with_liquid_slots_0493x9q.smpcd"

    python3 - "$STATE" "$INACTIVE_SLOTS" "$LIQUID_TYPE" "$LIQUID_MASS" <<'PY'
import os
import struct
import sys

out = sys.argv[1]
n = int(sys.argv[2])
typ0 = int(sys.argv[3])
mass0 = float(sys.argv[4])

x = [0.0] * n
y = [0.0] * n
vx = [0.0] * n
vy = [0.0] * n
typ = [typ0] * n
mass = [mass0] * n
role = [0] * n

os.makedirs(os.path.dirname(out) or ".", exist_ok=True)

magic = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
reserved = [0] * 8
reserved[0] = 1
reserved[1] = 1

with open(out, "wb") as f:
    f.write(magic)
    f.write(struct.pack("<IIIIQIIII",
                        2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
    f.write(struct.pack("<8Q", *reserved))

    for arr, fmt in (
        (x, "d"), (y, "d"),
        (vx, "d"), (vy, "d"),
        (typ, "I"), (mass, "d"), (role, "B")
    ):
        f.write(struct.pack("<%d%s" % (n, fmt), *arr))

print(
    f"[0493x9q-generate-vacuum] state={out} "
    f"fluid=0 inactiveLiquid={n} total={n}"
)
PY

  else

    STATE="$RUN_ROOT/init/gas_box_with_liquid_slots_0493x9q.smpcd"

    python3 scripts/generate_0493x9q_gas_box_state.py \
      --output "$STATE" --Lx "$Lx" --Ly "$Ly" \
      --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
      --kBT "$KBT" --gas-mass "$GAS_MASS" --gas-type "$GAS_TYPE" \
      --liquid-mass "$LIQUID_MASS" --liquid-type "$LIQUID_TYPE" \
      --inactive-slots "$INACTIVE_SLOTS" --seed "$SEED"

  fi
fi

sha256sum "$STATE" | sed 's/^/[0493x9q-init] sha256=/'




run_one(){
  local name="$1" sigma contact
  case "$name" in
    capillary) sigma="$SIGMA_ACTIVE"; contact="$CONTACT_ANGLE_DEG" ;;
    sigma0) sigma=0.0; contact=-1.0 ;;
    capillary_contactoff) sigma="$SIGMA_ACTIVE"; contact=-1.0 ;;
    *) echo "[0493x9q] ERROR unknown case=$name (use capillary, sigma0, capillary_contactoff)" >&2; return 2 ;;
  esac
  local dir="$RUN_ROOT/$name"; mkdir -p "$dir/params" "$dir/output" "$dir/logs"
  local params="$dir/params/${CASE_LABEL}.kv" log="$dir/logs/${CASE_LABEL}.log" tf="$dir/logs/${CASE_LABEL}.time"
  cat > "$params" <<PARAMS
inputState = $STATE
outputDir = $dir/output
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = wall
bcY = wall
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 3
openBoundarySegment0 = top inlet $INLET_SMIN $INLET_SMAX 0.0 -$UIN $LIQUID_TYPE $LIQUID_MASS
# Symmetric top gas vents. Particle streaming can remove gas through these
# outlets; the liquid-only Q6 projection sees zero prescribed liquid flux there.
openBoundarySegment1 = top outlet $VENT_LEFT_SMIN $VENT_LEFT_SMAX 0.0 0.0 0 $GAS_MASS
openBoundarySegment2 = top outlet $VENT_RIGHT_SMIN $VENT_RIGHT_SMAX 0.0 0.0 0 $GAS_MASS
inletVelocityRampEnable = $INLET_RAMP_ENABLE
inletVelocityRampStartTime = $INLET_RAMP_START_TIME
inletVelocityRampEndTime = $INLET_RAMP_END_TIME
inletVelocityRampInitialFactor = $INLET_RAMP_INITIAL_FACTOR
inletVelocityRampFinalFactor = $INLET_RAMP_FINAL_FACTOR
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
inletKBT = -1.0
inletThermalNoise = 0.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $INLET_RESERVOIR_CELLS
inletTargetOccupancy = $GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = false
inletReinjectBackflow = true
openBoundaryOutletMode = hybrid
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0
bodyAccelerationX = 0.0
bodyAccelerationY = $GRAVITY_Y
wallVpEnable = false
wallAccommodation = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
surfaceTensionSigma = $sigma
surfaceTensionMinRadiusCells = $SURFACE_TENSION_MIN_RADIUS_CELLS
phaseInterfaceASelector = type:$LIQUID_TYPE
phaseInterfaceBSelector = $PHASE_B_SELECTOR
phaseInterfaceKineticReflectionFraction = $KINETIC_REFLECTION_FRACTION
phaseInterfaceEvaporationTargetType = $EVAPORATION_TARGET_TYPE
phaseInterfaceContactAngleDegrees = $contact
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GAS_REFERENCE_CELL_MASS
species1ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x9q.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_FILL_FRACTION
PARAMS
  suite_write_common_params_0434 "$RUN_MODE" >> "$params"

  suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
  export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
  export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=1
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
  export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
  export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
  if awk -v s="$sigma" 'BEGIN{exit !(s>0)}'; then
    if awk -v a="$contact" 'BEGIN{exit !(a>0 && a<180)}'; then
      export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
      export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
      export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=1
    else
      export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=1
      export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=1
      export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=0
    fi
  else
    export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=1
    export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=1
    export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=0
  fi

  BASE_RUN_ROOT="$dir"
  LIVE_VIS_CONTROL_FILE="$dir/livevis_control_0493x9q.kv"
  suite_prepare_livevis_control_0434 "$dir" "$RUN_MODE"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$dir/logs/environment_0493x9q.env" "$RUN_MODE"
  printf '%s\n' \
    "[0493x9q-suite] case=$name sigma=$sigma minRadiusCells=$SURFACE_TENSION_MIN_RADIUS_CELLS contactAngle=$contact gravityY=$GRAVITY_Y inlet=top[$INLET_SMIN,$INLET_SMAX] Uin=-$UIN vents=top[$VENT_LEFT_SMIN,$VENT_LEFT_SMAX]+[$VENT_RIGHT_SMIN,$VENT_RIGHT_SMAX] mode=hybrid-zero" \
    "[0493x9q-suite] grid=${NX}x${NY} h=$(awk -v l="$Lx" -v n="$NX" 'BEGIN{printf "%.7g",l/n}') gamma=$GAMMA massRatio=$(awk -v a="$LIQUID_MASS" -v b="$GAS_MASS" 'BEGIN{printf "%.6g",a/b}') steps=$STEPS dt=$DT restart=${RESTART:-none} restartStep=$RESTART_STEP" \
    "[0493x10o-drip] objective=Q6-hydrodynamic normal motion + finite thermal envelope around continuous alpha=.5; no B8/global reaction"
  suite_run_binary_0434 "$params" "$log" "$tf" "$dir/output"
}

ran=()
for name in $CASES; do
  run_one "$name"
  ran+=("$name")
done
if suite_truthy_0434 "${PREFLIGHT_ONLY:-0}"; then
  echo "[0493x9q-suite] PREFLIGHT_ONLY complete; analysis skipped"
  exit 0
fi
python3 scripts/analyze_0493x9q_dripping_jet.py --root "$RUN_ROOT" --cases "${ran[@]}"

KINCSV="$RUN_ROOT/capillary/output/cuda_phase_kinetic_crossing_0493x9z.csv"
if [[ -f "$KINCSV" ]]; then
  python3 scripts/analyze_0493x10o_q6_thermal_interface.py "$KINCSV" --mode dripping
else
  echo "[0493x10g-drip] WARNING kinetic audit CSV not found: $KINCSV" >&2
fi
