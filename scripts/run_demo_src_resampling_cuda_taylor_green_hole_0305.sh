#!/usr/bin/env bash
set -euo pipefail

# 0305 — Taylor-Green periodic demo with an initially empty fluid hole.
# The hole is created by converting the particles initially located in a small
# rectangular patch to Inactive role.  The cell remains fluid; this tests whether
# advection and the post-SRC CUDA resampling guard refill a bulk support defect.

BIN="${BIN:-build/src_mpcd_base_cuda_0305}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_demo_common_0283.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_resampling_demo_common_0303.sh"

CASE_NAME="taylor_green_hole"
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-64}"; NY="${NY:-64}"
GAMMA="${GAMMA:-20}"; STEPS="${STEPS:-1200}"; DT="${DT:-0.001}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1628605}"; SUMMARY_EVERY="${SUMMARY_EVERY:-50}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-200}"
TG_U0="${TG_U0:-0.04}"; TG_FORCING_AMPLITUDE="${TG_FORCING_AMPLITUDE:-0.02}"
HOLE_XMIN="${HOLE_XMIN:-0.45}"; HOLE_XMAX="${HOLE_XMAX:-0.55}"
HOLE_YMIN="${HOLE_YMIN:-0.45}"; HOLE_YMAX="${HOLE_YMAX:-0.55}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/demo_src_resampling_cuda_${CASE_NAME}_0305}"
RUN_ROOT="${RUN_ROOT:-$(resampling_demo_root_0303 "$CASE_NAME" "$BASE_RUN_ROOT")}"
prepare_demo_dirs_0283 "$RUN_ROOT"
STATE_FILE="$RUN_ROOT/init/${CASE_NAME}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS_FILE="$RUN_ROOT/params/${CASE_NAME}.kv"
OUT_DIR="$RUN_ROOT/output"
LOG_FILE="$RUN_ROOT/logs/${CASE_NAME}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_NAME}.time"

# Start with a normal periodic TG state, then deactivate particles in the hole.
generate_demo_state_0283 "$STATE_FILE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" taylor_green 0.0 0.0 "$TG_U0" 0.0 -1.0 0.0 -1.0 0 none
python3 - "$STATE_FILE" "$HOLE_XMIN" "$HOLE_XMAX" "$HOLE_YMIN" "$HOLE_YMAX" <<'PY'
import struct, sys
path,x0,x1,y0,y1=sys.argv[1:]
x0=float(x0); x1=float(x1); y0=float(y0); y1=float(y1)
with open(path,'r+b') as f:
    magic=f.read(16)
    hdr=f.read(struct.calcsize('<IIIIQIIII'))
    version,endian,dim,hasMass,n,hasRole,roleBytes,typeBytes,res=struct.unpack('<IIIIQIIII',hdr)
    reserved=f.read(8*8)
    off_x=f.tell()
    xs=list(struct.unpack('<%dd'%n, f.read(8*n)))
    off_y=f.tell()
    ys=list(struct.unpack('<%dd'%n, f.read(8*n)))
    f.seek(8*n,1) # vx
    f.seek(8*n,1) # vy
    f.seek(4*n,1) # type
    f.seek(8*n,1) # mass
    off_role=f.tell()
    roles=bytearray(f.read(n))
    deactivated=0
    for i,(x,y) in enumerate(zip(xs,ys)):
        if roles[i] == 1 and x0 <= x <= x1 and y0 <= y <= y1:
            roles[i] = 0
            deactivated += 1
    f.seek(off_role)
    f.write(roles)
print(f'[0305-tg-hole] deactivated={deactivated} hole=[{x0},{x1}]x[{y0},{y1}] state={path}')
PY

mkdir -p "$OUT_DIR"
cat > "$PARAMS_FILE" <<PARAMS
inputState = ${STATE_FILE}
outputDir = ${OUT_DIR}

Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}

bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = true
taylorGreenForcingAmplitude = ${TG_FORCING_AMPLITUDE}
taylorGreenForcingModeX = 1
taylorGreenForcingModeY = 1

$(write_src_classic_common_params_0283 "$STEPS" "$DT" "$KBT" "$SEED" "$SUMMARY_EVERY" "$DUMP_STATE_EVERY" "$THREADS")
PARAMS

src_gpu_cuda_env_periodic_resident_thermostat_0283
src_gpu_resampling_env_0303
write_resampling_demo_metadata_0303 "$RUN_ROOT/logs/resampling_0303.env"
print_resampling_demo_banner_0303 "$CASE_NAME" "$RUN_ROOT"
run_demo_case_0283 "$PARAMS_FILE" "$LOG_FILE" "$TIME_FILE" "$OUT_DIR"
