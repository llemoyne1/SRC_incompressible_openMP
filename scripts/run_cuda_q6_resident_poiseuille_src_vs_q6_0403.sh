#!/usr/bin/env bash
set -euo pipefail

# 0403 -- autonomous Poiseuille visual comparison:
#   SRC classic CUDA-resident  vs  SRC classic CUDA-resident + Q6 CUDA-resident.
#
# This script is intentionally a physical comparison, not a strict equality
# regression: Q6 modifies the velocity field. It keeps dumps and livevis
# controls explicit so the same command can be used for inspection runs.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

truthy_0403() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

USER_BIN_SET=0
if [[ -n "${BIN+x}" ]]; then USER_BIN_SET=1; fi

NX=${NX:-128}
NY=${NY:-64}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-2000}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-${DUMPS_EVERY:-100}}
THREADS=${THREADS:-8}
SEED=${SEED:-1620189}
FORCE_BUILD=${FORCE_BUILD:-0}
BUILD_IF_STALE=${BUILD_IF_STALE:-0}
LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-${SRC_LIVE_VIS_ENABLE:-1}}
LIVE_VIS_RUN=${LIVE_VIS_RUN:-q6}
RESAMPLING_ENABLE=${RESAMPLING_ENABLE:-false}

if truthy_0403 "$RESAMPLING_ENABLE"; then
  echo "[0403-poiseuille-src-vs-q6] ERROR: this script compares SRC vs SRC/Q6 only; RESAMPLING_ENABLE must remain false." >&2
  exit 2
fi

if truthy_0403 "$LIVE_VIS_ENABLE" && [[ "$USER_BIN_SET" == "0" ]]; then
  BIN=build/src_mpcd_base_cuda_q6_resident_0400_livevis
else
  BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}
fi

needs_build=0
if truthy_0403 "$FORCE_BUILD" || [[ ! -x "$BIN" ]]; then
  needs_build=1
elif truthy_0403 "$BUILD_IF_STALE"; then
  if find src include scripts/build_src_mpcd_cuda_q6_resident_0400.sh -type f -newer "$BIN" -print -quit | grep -q .; then
    needs_build=1
  fi
fi

if [[ "$needs_build" == "1" ]]; then
  if truthy_0403 "$LIVE_VIS_ENABLE"; then
    MPCD_ENABLE_LIVE_VIS=1 OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
  else
    OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
  fi
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0403-poiseuille-src-vs-q6] ERROR missing binary: $BIN" >&2
  exit 127
fi
if truthy_0403 "$LIVE_VIS_ENABLE" && [[ "$USER_BIN_SET" == "1" ]]; then
  echo "[0403-poiseuille-src-vs-q6] livevis requested with user BIN=$BIN; assuming it was built with MPCD_ENABLE_LIVE_VIS=1" >&2
fi

TAG="${NX}x${NY}_${STEPS}"
RUN_ROOT_CLASSIC=${RUN_ROOT_CLASSIC:-runs/q6_resident_0403_poiseuille_src_${TAG}}
RUN_ROOT_Q6=${RUN_ROOT_Q6:-runs/q6_resident_0403_poiseuille_src_q6_${TAG}}
ART_DIR=${ART_DIR:-dev_history/artifacts/q6_resident_0403_poiseuille_src_vs_q6_${TAG}}
mkdir -p "$ART_DIR"

common=(
  BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST=poiseuille_wall_full
  NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" SUMMARY_EVERY="$SUMMARY_EVERY"
  THREADS="$THREADS" SEED="$SEED" DUMP_STATE_EVERY="$DUMP_STATE_EVERY"
  WALL_THERMAL_NOISE=0.0 RESAMPLING_ENABLE=false
)

resident_classic_flags=(
  MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
  MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=1
  MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
  MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
  MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1
  MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
  MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1
)

resident_q6_flags=(
  MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
  MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=1
  MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
  MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402=1
  MPCD_CUDA_Q6_RESIDENT_0400=1
  MPCD_CUDA_Q6_RESIDENT_STRICT_0400=1
  MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=${MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400:-1}
)

livevis_off_env=(SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0)
livevis_on_env=("${livevis_off_env[@]}")
if truthy_0403 "$LIVE_VIS_ENABLE"; then
  SRC_LIVE_VIS_FIELD=${SRC_LIVE_VIS_FIELD:-${LIVE_VIS_FIELD:-ux}}
  SRC_LIVE_VIS_EVERY=${SRC_LIVE_VIS_EVERY:-${LIVE_VIS_EVERY:-5}}
  SRC_LIVE_VIS_NX=${SRC_LIVE_VIS_NX:-${LIVE_VIS_NX:-768}}
  SRC_LIVE_VIS_NY=${SRC_LIVE_VIS_NY:-${LIVE_VIS_NY:-384}}
  SRC_LIVE_VIS_CLIP=${SRC_LIVE_VIS_CLIP:-${LIVE_VIS_CLIP:--1}}
  SRC_LIVE_VIS_GAIN=${SRC_LIVE_VIS_GAIN:-${LIVE_VIS_GAIN:-1.0}}
  SRC_LIVE_VIS_SMOOTH_PASSES=${SRC_LIVE_VIS_SMOOTH_PASSES:-${LIVE_VIS_SMOOTH_PASSES:-1}}
  SRC_LIVE_VIS_COLORMAP=${SRC_LIVE_VIS_COLORMAP:-${LIVE_VIS_COLORMAP:-thermal}}
  SRC_LIVE_VIS_WINDOW_SCALE=${SRC_LIVE_VIS_WINDOW_SCALE:-${LIVE_VIS_WINDOW_SCALE:-1}}
  SRC_LIVE_VIS_VSYNC=${SRC_LIVE_VIS_VSYNC:-${LIVE_VIS_VSYNC:-0}}
  SRC_LIVE_VIS_CUDA_FIELD=${SRC_LIVE_VIS_CUDA_FIELD:-${LIVE_VIS_CUDA_FIELD:-1}}
  SRC_LIVE_VIS_CUDA_SNAPSHOT=${SRC_LIVE_VIS_CUDA_SNAPSHOT:-${LIVE_VIS_CUDA_SNAPSHOT:-1}}
  SRC_LIVE_VIS_LOG_SOURCE=${SRC_LIVE_VIS_LOG_SOURCE:-${LIVE_VIS_LOG_SOURCE:-1}}
  SRC_LIVE_VIS_CONTROL_FILE=${SRC_LIVE_VIS_CONTROL_FILE:-${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}}
  SRC_LIVE_VIS_CONTROL_EVERY=${SRC_LIVE_VIS_CONTROL_EVERY:-${LIVE_VIS_CONTROL_EVERY:-1}}
  SRC_LIVE_VIS_CONTROL_LOG=${SRC_LIVE_VIS_CONTROL_LOG:-${LIVE_VIS_CONTROL_LOG:-1}}
  if [[ ! -f "$SRC_LIVE_VIS_CONTROL_FILE" ]]; then
    cat > "$SRC_LIVE_VIS_CONTROL_FILE" <<CONTROL
field = ${SRC_LIVE_VIS_FIELD}
clip = ${SRC_LIVE_VIS_CLIP}
gain = ${SRC_LIVE_VIS_GAIN}
smoothPasses = ${SRC_LIVE_VIS_SMOOTH_PASSES}
colormap = ${SRC_LIVE_VIS_COLORMAP}
quiverScale = ${SRC_LIVE_VIS_QUIVER_SCALE:--1}
CONTROL
  fi
  livevis_on_env=(
    SRC_LIVE_VIS_ENABLE=1 MPCD_LIVE_VIS_ENABLE=1
    SRC_LIVE_VIS_FIELD="$SRC_LIVE_VIS_FIELD"
    SRC_LIVE_VIS_EVERY="$SRC_LIVE_VIS_EVERY"
    SRC_LIVE_VIS_NX="$SRC_LIVE_VIS_NX"
    SRC_LIVE_VIS_NY="$SRC_LIVE_VIS_NY"
    SRC_LIVE_VIS_CLIP="$SRC_LIVE_VIS_CLIP"
    SRC_LIVE_VIS_GAIN="$SRC_LIVE_VIS_GAIN"
    SRC_LIVE_VIS_SMOOTH_PASSES="$SRC_LIVE_VIS_SMOOTH_PASSES"
    SRC_LIVE_VIS_COLORMAP="$SRC_LIVE_VIS_COLORMAP"
    SRC_LIVE_VIS_WINDOW_SCALE="$SRC_LIVE_VIS_WINDOW_SCALE"
    SRC_LIVE_VIS_VSYNC="$SRC_LIVE_VIS_VSYNC"
    SRC_LIVE_VIS_CUDA_FIELD="$SRC_LIVE_VIS_CUDA_FIELD"
    SRC_LIVE_VIS_CUDA_SNAPSHOT="$SRC_LIVE_VIS_CUDA_SNAPSHOT"
    SRC_LIVE_VIS_LOG_SOURCE="$SRC_LIVE_VIS_LOG_SOURCE"
    SRC_LIVE_VIS_CONTROL_FILE="$SRC_LIVE_VIS_CONTROL_FILE"
    SRC_LIVE_VIS_CONTROL_EVERY="$SRC_LIVE_VIS_CONTROL_EVERY"
    SRC_LIVE_VIS_CONTROL_LOG="$SRC_LIVE_VIS_CONTROL_LOG"
  )
fi

livevis_classic_env=("${livevis_off_env[@]}")
livevis_q6_env=("${livevis_off_env[@]}")
if truthy_0403 "$LIVE_VIS_ENABLE"; then
  case "$LIVE_VIS_RUN" in
    classic|src) livevis_classic_env=("${livevis_on_env[@]}") ;;
    q6|src_q6|classic_q6|cuda) livevis_q6_env=("${livevis_on_env[@]}") ;;
    all) livevis_classic_env=("${livevis_on_env[@]}"); livevis_q6_env=("${livevis_on_env[@]}") ;;
    none|off|0) ;;
    *) echo "[0403-poiseuille-src-vs-q6] ERROR unknown LIVE_VIS_RUN=$LIVE_VIS_RUN (expected src, q6, all, none)" >&2; exit 2 ;;
  esac
  echo "[0403-poiseuille-src-vs-q6] livevis run=$LIVE_VIS_RUN control=$SRC_LIVE_VIS_CONTROL_FILE field=$SRC_LIVE_VIS_FIELD size=${SRC_LIVE_VIS_NX}x${SRC_LIVE_VIS_NY} scale=${SRC_LIVE_VIS_WINDOW_SCALE}"
fi

echo "[0403-poiseuille-src-vs-q6] bin=$BIN steps=$STEPS summaryEvery=$SUMMARY_EVERY dumpStateEvery=$DUMP_STATE_EVERY"
echo "[0403-poiseuille-src-vs-q6] SRC run=$RUN_ROOT_CLASSIC"
echo "[0403-poiseuille-src-vs-q6] SRC/Q6 run=$RUN_ROOT_Q6"

env "${common[@]}" \
  RUN_ROOT="$RUN_ROOT_CLASSIC" \
  RUN_TAG=src_cuda_0403 \
  PROJECTION_ENABLE=false \
  PROJECTION_BACKEND=cpu \
  SRC_CLASSIC_CUDA_MODE_ENABLE=true \
  "${resident_classic_flags[@]}" \
  "${livevis_classic_env[@]}" \
  bash scripts/run_validation_mono_config_0162.sh

env "${common[@]}" \
  RUN_ROOT="$RUN_ROOT_Q6" \
  RUN_TAG=src_q6_cuda_0403 \
  PROJECTION_BACKEND=cuda \
  "${resident_q6_flags[@]}" \
  "${livevis_q6_env[@]}" \
  bash scripts/run_validation_mono_config_0162.sh

set +e
python3 scripts/compare_validation_mono_config_0162.py \
  --origin "$RUN_ROOT_CLASSIC" \
  --optimized "$RUN_ROOT_Q6" \
  --out "$ART_DIR/src_vs_src_q6_compare.csv" \
  --summary-out "$ART_DIR/src_vs_src_q6_compare_summary.csv"
compare_rc=$?
set -e

python3 - "$RUN_ROOT_CLASSIC/validation_summary_0162.csv" "$RUN_ROOT_Q6/validation_summary_0162.csv" "$ART_DIR/src_vs_src_q6_metrics.csv" <<'PY'
import csv
import math
import sys

classic_path, q6_path, out_path = sys.argv[1:4]

def read_one(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    if len(rows) != 1:
        raise SystemExit(f"expected one summary row in {path}, got {len(rows)}")
    return rows[0]

classic = read_one(classic_path)
q6 = read_one(q6_path)
if int(float(classic.get("q6Applied", "1"))) != 0:
    raise SystemExit("classic SRC run unexpectedly applied Q6")
if int(float(q6.get("q6Applied", "0"))) != 1 or int(float(q6.get("q6Converged", "0"))) != 1:
    raise SystemExit("SRC/Q6 run did not apply and converge Q6")
div = float(q6.get("q6DivAfterProjectedFluxRms", "nan"))
if not math.isfinite(div) or div > 1.0e-8:
    raise SystemExit(f"SRC/Q6 projected divergence too large: {div}")

metrics = [
    "Np",
    "minN",
    "maxN",
    "meanN",
    "stdN",
    "meanKinetic",
    "kBTEstimate",
    "meanVx",
    "meanVy",
    "q6Applied",
    "q6Converged",
    "q6Iterations",
    "q6DivBeforeRms",
    "q6DivAfterProjectedFluxRms",
    "q6CorrectionVelocityRms",
    "wallTime",
]

with open(out_path, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["metric", "src", "src_q6", "delta"])
    w.writeheader()
    for metric in metrics:
        a = classic.get(metric, "")
        b = q6.get(metric, "")
        delta = ""
        try:
            delta = f"{float(b) - float(a):.17g}"
        except (TypeError, ValueError):
            pass
        w.writerow({"metric": metric, "src": a, "src_q6": b, "delta": delta})

print(
    "[0403-poiseuille-src-vs-q6] metrics: "
    f"meanKinetic {classic.get('meanKinetic')} -> {q6.get('meanKinetic')}, "
    f"stdN {classic.get('stdN')} -> {q6.get('stdN')}, "
    f"q6DivAfter={div:.6e}"
)
PY

echo "[0403-poiseuille-src-vs-q6] compare summary: $ART_DIR/src_vs_src_q6_compare_summary.csv (rc=$compare_rc, differences expected)"
echo "[0403-poiseuille-src-vs-q6] selected metrics: $ART_DIR/src_vs_src_q6_metrics.csv"
echo "[0403-poiseuille-src-vs-q6] dumps: $RUN_ROOT_CLASSIC and $RUN_ROOT_Q6"
