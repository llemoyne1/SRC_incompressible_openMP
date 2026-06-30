#!/usr/bin/env bash
set -euo pipefail

# 0401 -- clean TG comparison for the resident chain
#   CUDA periodic force/stream -> CUDA SRC collision(shared 0251) -> CUDA Q6 -> CUDA thermostat.
#
# The strict regression remains CPU-Q6 vs CUDA-Q6.  A separate physical
# comparison also runs classic SRC without projection vs classic SRC+Q6; it is
# not a pass/fail equality test because Q6 deliberately changes the dynamics.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

truthy_0401() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

USER_BIN_SET=0
if [[ -n "${BIN+x}" ]]; then USER_BIN_SET=1; fi

NX=${NX:-96}
NY=${NY:-96}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-2000}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-${DUMPS_EVERY:-100}}
THREADS=${THREADS:-8}
SEED=${SEED:-1620189}
FORCE_BUILD=${FORCE_BUILD:-0}
LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-${SRC_LIVE_VIS_ENABLE:-1}}
LIVE_VIS_RUN=${LIVE_VIS_RUN:-classic_q6}

if truthy_0401 "$LIVE_VIS_ENABLE" && [[ "$USER_BIN_SET" == "0" ]]; then
  BIN=build/src_mpcd_base_cuda_q6_resident_0400_livevis
else
  BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}
fi

if truthy_0401 "$FORCE_BUILD" || [[ ! -x "$BIN" ]]; then
  if truthy_0401 "$LIVE_VIS_ENABLE"; then
    MPCD_ENABLE_LIVE_VIS=1 OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
  else
    OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
  fi
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0401-srcq6] ERROR missing binary: $BIN" >&2
  exit 127
fi
if truthy_0401 "$LIVE_VIS_ENABLE" && [[ "$USER_BIN_SET" == "1" ]]; then
  echo "[0401-srcq6] livevis requested with user BIN=$BIN; assuming it was built with MPCD_ENABLE_LIVE_VIS=1" >&2
fi

RESAMPLING_ENABLE=${RESAMPLING_ENABLE:-false}
if truthy_0401 "$RESAMPLING_ENABLE"; then
  echo "[0401-srcq6] resampling enabled: resident SRC/Q6 is used before the existing resampling stage" >&2
fi
TAG="${NX}x${NY}_${STEPS}"
RUN_ROOT_CPU=${RUN_ROOT_CPU:-runs/q6_resident_0401_srcq6_cpu_${TAG}}
RUN_ROOT_CLASSIC=${RUN_ROOT_CLASSIC:-runs/q6_resident_0401_classic_cuda_${TAG}}
RUN_ROOT_CUDA=${RUN_ROOT_CUDA:-runs/q6_resident_0401_srcq6_cuda_${TAG}}
ART_DIR=${ART_DIR:-dev_history/artifacts/q6_resident_0401_srcq6_${TAG}}
mkdir -p "$ART_DIR"

common=(
  BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST=tg_periodic_full
  NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" SUMMARY_EVERY="$SUMMARY_EVERY"
  THREADS="$THREADS" SEED="$SEED" DUMP_STATE_EVERY="$DUMP_STATE_EVERY"
  RESAMPLING_ENABLE="$RESAMPLING_ENABLE"
)

resident_classic_flags=(
  MPCD_CUDA_STREAMING_PERIODIC_0245=1
  MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
  MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=0
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
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
  MPCD_CUDA_STREAMING_PERIODIC_0245=1
  MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
  MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=0
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
  MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1
  MPCD_CUDA_Q6_RESIDENT_0400=1
  MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=${MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400:-1}
)

livevis_off_env=(SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0)
livevis_on_env=("${livevis_off_env[@]}")
if truthy_0401 "$LIVE_VIS_ENABLE"; then
  SRC_LIVE_VIS_FIELD=${SRC_LIVE_VIS_FIELD:-${LIVE_VIS_FIELD:-vorticity}}
  SRC_LIVE_VIS_EVERY=${SRC_LIVE_VIS_EVERY:-${LIVE_VIS_EVERY:-5}}
  SRC_LIVE_VIS_NX=${SRC_LIVE_VIS_NX:-${LIVE_VIS_NX:-512}}
  SRC_LIVE_VIS_NY=${SRC_LIVE_VIS_NY:-${LIVE_VIS_NY:-512}}
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

livevis_cpu_env=("${livevis_off_env[@]}")
livevis_classic_env=("${livevis_off_env[@]}")
livevis_q6_env=("${livevis_off_env[@]}")
if truthy_0401 "$LIVE_VIS_ENABLE"; then
  case "$LIVE_VIS_RUN" in
    cpu) livevis_cpu_env=("${livevis_on_env[@]}") ;;
    classic) livevis_classic_env=("${livevis_on_env[@]}") ;;
    classic_q6|q6|cuda) livevis_q6_env=("${livevis_on_env[@]}") ;;
    all) livevis_cpu_env=("${livevis_on_env[@]}"); livevis_classic_env=("${livevis_on_env[@]}"); livevis_q6_env=("${livevis_on_env[@]}") ;;
    none|off|0) ;;
    *) echo "[0401-srcq6] ERROR unknown LIVE_VIS_RUN=$LIVE_VIS_RUN (expected cpu, classic, classic_q6, all, none)" >&2; exit 2 ;;
  esac
  echo "[0401-srcq6] livevis enabled for run=$LIVE_VIS_RUN control=${SRC_LIVE_VIS_CONTROL_FILE:-none} field=${SRC_LIVE_VIS_FIELD:-unset} size=${SRC_LIVE_VIS_NX:-unset}x${SRC_LIVE_VIS_NY:-unset} scale=${SRC_LIVE_VIS_WINDOW_SCALE:-unset}"
fi

echo "[0401-srcq6] bin=$BIN steps=$STEPS summaryEvery=$SUMMARY_EVERY dumpStateEvery=$DUMP_STATE_EVERY"

env "${common[@]}" \
  RUN_ROOT="$RUN_ROOT_CPU" \
  RUN_TAG=cpu_clean_q6_ref \
  PROJECTION_BACKEND=cpu \
  "${livevis_cpu_env[@]}" \
  bash scripts/run_validation_mono_config_0162.sh

env "${common[@]}" \
  RUN_ROOT="$RUN_ROOT_CLASSIC" \
  RUN_TAG=cuda_0401_classic \
  PROJECTION_ENABLE=false \
  PROJECTION_BACKEND=cpu \
  SRC_CLASSIC_CUDA_MODE_ENABLE=true \
  "${resident_classic_flags[@]}" \
  "${livevis_classic_env[@]}" \
  bash scripts/run_validation_mono_config_0162.sh

env "${common[@]}" \
  RUN_ROOT="$RUN_ROOT_CUDA" \
  RUN_TAG=cuda_0401_classic_q6 \
  PROJECTION_BACKEND=cuda \
  "${resident_q6_flags[@]}" \
  "${livevis_q6_env[@]}" \
  bash scripts/run_validation_mono_config_0162.sh

python3 scripts/compare_validation_mono_config_0162.py \
  --origin "$RUN_ROOT_CPU" \
  --optimized "$RUN_ROOT_CUDA" \
  --out "$ART_DIR/compare.csv" \
  --summary-out "$ART_DIR/compare_summary.csv"

python3 - "$RUN_ROOT_CUDA/validation_summary_0162.csv" <<'PY2'
import csv, math, sys
path = sys.argv[1]
with open(path, newline='') as f:
    rows = list(csv.DictReader(f))
if len(rows) != 1:
    raise SystemExit(f"expected one summary row, got {len(rows)}")
r = rows[0]
if int(float(r.get('q6Applied', '0'))) != 1 or int(float(r.get('q6Converged', '0'))) != 1:
    raise SystemExit('resident Q6 did not apply+converge')
div = float(r.get('q6DivAfterProjectedFluxRms', 'nan'))
if not math.isfinite(div) or div > 1e-8:
    raise SystemExit(f'resident Q6 divergence too large: {div}')
print(f"[0401-srcq6] Q6 PASS: iterations={r.get('q6Iterations')} divAfter={div:.6e}")
PY2

set +e
python3 scripts/compare_validation_mono_config_0162.py \
  --origin "$RUN_ROOT_CLASSIC" \
  --optimized "$RUN_ROOT_CUDA" \
  --out "$ART_DIR/classic_vs_q6_compare.csv" \
  --summary-out "$ART_DIR/classic_vs_q6_compare_summary.csv"
classic_vs_q6_rc=$?
set -e

python3 - "$RUN_ROOT_CLASSIC/validation_summary_0162.csv" "$RUN_ROOT_CUDA/validation_summary_0162.csv" "$ART_DIR/classic_vs_q6_metrics.csv" <<'PY3'
import csv
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
metrics = [
    "Np",
    "minN",
    "maxN",
    "meanN",
    "stdN",
    "meanKinetic",
    "kBTEstimate",
    "q6Applied",
    "q6Converged",
    "q6Iterations",
    "q6DivBeforeRms",
    "q6DivAfterProjectedFluxRms",
    "q6CorrectionVelocityRms",
    "wallTime",
]

with open(out_path, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["metric", "classic", "classic_q6", "delta"])
    w.writeheader()
    for metric in metrics:
        a = classic.get(metric, "")
        b = q6.get(metric, "")
        delta = ""
        try:
            delta = f"{float(b) - float(a):.17g}"
        except (TypeError, ValueError):
            pass
        w.writerow({"metric": metric, "classic": a, "classic_q6": b, "delta": delta})

print(
    "[0401-srcq6] classic vs classic+Q6 metrics: "
    f"meanKinetic {classic.get('meanKinetic')} -> {q6.get('meanKinetic')}, "
    f"stdN {classic.get('stdN')} -> {q6.get('stdN')}, "
    f"q6Applied {classic.get('q6Applied')} -> {q6.get('q6Applied')}"
)
PY3

echo "[0401-srcq6] strict Q6 regression summary: $ART_DIR/compare_summary.csv"
echo "[0401-srcq6] physical classic-vs-Q6 compare summary: $ART_DIR/classic_vs_q6_compare_summary.csv (rc=$classic_vs_q6_rc, differences expected)"
echo "[0401-srcq6] physical classic-vs-Q6 selected metrics: $ART_DIR/classic_vs_q6_metrics.csv"
