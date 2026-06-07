#!/usr/bin/env bash
set -euo pipefail

# 0275 — GPU-primary launcher for the SRC_GPU branch.
#
# Default policy:
#   - BACKEND=cuda: make the validated resident CUDA classic-SRC path the
#     primary execution path when the parameter file is already classic-only.
#   - BACKEND=openmp/cpu: run the same binary with CUDA resident shortcuts
#     disabled. This is the explicit OpenMP/CPU opt-out path.
#
# Q6/resampling/thermostat/capacity preservation:
#   The wrapper does not force classic CUDA mode when any of these modules are
#   active in the parameter file. In that case the existing CPU/OpenMP
#   continuations and any explicit per-module CUDA backends remain in charge.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<USAGE
Usage: $0 [--backend cuda|openmp|cpu] [--bin path/to/src_mpcd_base] params.kv

Environment:
  MPCD_BACKEND or MPCD_RUNTIME_BACKEND   default: cuda
  BIN                                    default: build/src_mpcd_base_cuda_0275 if present, else build/src_mpcd_base_cuda_0274, else build/src_mpcd_base
  MPCD_CUDA_PRIMARY_KEEP_TEMP=1          keep generated temporary params file
  MPCD_CUDA_PRIMARY_VERBOSE=1            print selected policy
USAGE
}

BACKEND=${MPCD_BACKEND:-${MPCD_RUNTIME_BACKEND:-cuda}}
BIN_DEFAULT="build/src_mpcd_base_cuda_0275"
if [[ ! -x "$BIN_DEFAULT" && -x build/src_mpcd_base_cuda_0274 ]]; then
  BIN_DEFAULT="build/src_mpcd_base_cuda_0274"
elif [[ ! -x "$BIN_DEFAULT" && -x build/src_mpcd_base ]]; then
  BIN_DEFAULT="build/src_mpcd_base"
fi
BIN=${BIN:-$BIN_DEFAULT}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      BACKEND="$2"
      shift 2
      ;;
    --backend=*)
      BACKEND="${1#--backend=}"
      shift
      ;;
    --bin)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      BIN="$2"
      shift 2
      ;;
    --bin=*)
      BIN="${1#--bin=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -* )
      echo "[0275-cuda-primary] unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi
PARAMS=$1
if [[ ! -f "$PARAMS" ]]; then
  echo "[0275-cuda-primary] parameter file not found: $PARAMS" >&2
  exit 2
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0275-cuda-primary] binary not found/executable: $BIN" >&2
  echo "[0275-cuda-primary] build with: bash scripts/build_src_mpcd_cuda_0275.sh" >&2
  exit 127
fi

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
truthy() {
  case "$(lower "${1:-}")" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}
falsey() {
  case "$(lower "${1:-}")" in
    0|false|no|off|'') return 0 ;;
    *) return 1 ;;
  esac
}

param_value_last() {
  local key=$1
  awk -v want="$key" '
    function trim(s){ sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
    BEGIN{ IGNORECASE=0 }
    {
      line=$0
      sub(/#.*/, "", line)
      if (line !~ /=/) next
      split(line, a, "=")
      k=trim(a[1])
      if (k==want) {
        v=line
        sub(/^[^=]*=/, "", v)
        val=trim(v)
      }
    }
    END{ if (val != "") print val }
  ' "$PARAMS"
}

param_bool() {
  local key=$1 default=$2 value
  value=$(param_value_last "$key" || true)
  if [[ -z "$value" ]]; then
    value=$default
  fi
  case "$(lower "$value")" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

set_cuda_resident_off() {
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0
  export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0
  export MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=0
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
  export MPCD_CUDA_STREAMING_PERIODIC_0245=0
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247=0
  export MPCD_CUDA_STREAMING_PISTON_0247B=0
  export MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=0
  export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  export MPCD_CUDA_RESAMPLING_PERSISTENT_0240=0
}

set_cuda_resident_primary_classic() {
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=${MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260:-1}
  export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=${MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261:-1}
  export MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=${MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262:-1}
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=${MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263:-1}
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=${MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264:-1}

  export MPCD_CUDA_STREAMING_PERIODIC_0245=${MPCD_CUDA_STREAMING_PERIODIC_0245:-1}
  export MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=${MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL:-0}
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=${MPCD_CUDA_STREAMING_WALL_SIMPLE_0246:-1}
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=${MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL:-0}
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247=${MPCD_CUDA_IMMERSED_RECTANGLE_0247:-1}
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=${MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL:-0}
  export MPCD_CUDA_STREAMING_PISTON_0247B=${MPCD_CUDA_STREAMING_PISTON_0247B:-1}
  export MPCD_CUDA_STREAMING_PISTON_0247B_DOWNLOAD_ALL=${MPCD_CUDA_STREAMING_PISTON_0247B_DOWNLOAD_ALL:-0}

  export MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=${MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A:-0}
  export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=${MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B:-0}

  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE:-1}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT:-0}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT:-1}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257:-1}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251:-1}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT:-0}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253:-1}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254:-1}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_PISTON_0255=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_PISTON_0255:-1}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272:-1}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272:-1}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272:-1}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273:-1}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273:-1}
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274:-1}

  export MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM=${MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM:-1}
  export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS=${MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS:-1}

  # Keep CUDA thermostat/resampling disabled in the classic-resident primary path.
  # Their future wall/solid/piston/inlet-outlet aware reactivation must use the
  # explicit synchronization bridge, not this classic-only shortcut.
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=${MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE:-0}
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=${MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260:-0}
  export MPCD_CUDA_RESAMPLING_PERSISTENT_0240=${MPCD_CUDA_RESAMPLING_PERSISTENT_0240:-0}
}

backend_lc=$(lower "$BACKEND")
case "$backend_lc" in
  openmp|cpu|host)
    set_cuda_resident_off
    [[ "${MPCD_CUDA_PRIMARY_VERBOSE:-0}" == "1" ]] && echo "[0275-cuda-primary] backend=openmp params=$PARAMS bin=$BIN" >&2
    exec "$BIN" "$PARAMS"
    ;;
  cuda|gpu|auto)
    ;;
  *)
    echo "[0275-cuda-primary] unsupported backend '$BACKEND'" >&2
    usage
    exit 2
    ;;
esac

classic_modules_active=0
if param_bool projectionEnable false; then classic_modules_active=1; fi
if param_bool resamplingEnable false; then classic_modules_active=1; fi
if param_bool closedCapacityResponseEnable false; then classic_modules_active=1; fi
if param_bool thermostatEnable false; then classic_modules_active=1; fi

PARAMS_TO_RUN="$PARAMS"
if [[ "$classic_modules_active" == "0" ]]; then
  set_cuda_resident_primary_classic
  TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/src_gpu_0275.XXXXXX")
  TMP_PARAMS="$TMP_DIR/params_cuda_primary_0275.kv"
  cp "$PARAMS" "$TMP_PARAMS"
  {
    echo ""
    echo "# 0275 GPU-primary wrapper override for classic-only validated resident CUDA path"
    echo "srcClassicCudaModeEnable = true"
  } >> "$TMP_PARAMS"
  PARAMS_TO_RUN="$TMP_PARAMS"
  if [[ "${MPCD_CUDA_PRIMARY_KEEP_TEMP:-0}" != "1" ]]; then
    trap 'rm -rf "$TMP_DIR"' EXIT
  else
    echo "[0275-cuda-primary] keeping temporary params: $TMP_PARAMS" >&2
  fi
  [[ "${MPCD_CUDA_PRIMARY_VERBOSE:-0}" == "1" ]] && echo "[0275-cuda-primary] backend=cuda classic-resident-primary params=$PARAMS_TO_RUN bin=$BIN" >&2
else
  # Preserve Q6/resampling/thermostat/capacity semantics. Do not force classic
  # CUDA mode and do not activate resident shortcuts that would keep the host
  # state stale across CPU continuation stages.
  [[ "${MPCD_CUDA_PRIMARY_VERBOSE:-0}" == "1" ]] && echo "[0275-cuda-primary] backend=cuda mixed CPU/GPU continuation; Q6/resampling/thermostat/capacity requested, no classic-resident override params=$PARAMS bin=$BIN" >&2
fi

exec "$BIN" "$PARAMS_TO_RUN"
