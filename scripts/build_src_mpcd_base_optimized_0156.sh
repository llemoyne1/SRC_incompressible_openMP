#!/usr/bin/env bash
set -euo pipefail

# 0156 — build profiles for performance work without changing the solver code.
# Usage examples:
#   BUILD_PROFILE=safe   ./scripts/build_src_mpcd_base_optimized_0156.sh
#   BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
#   BUILD_PROFILE=lto-native OUT_DIR=build_native_lto ./scripts/build_src_mpcd_base_optimized_0156.sh

CXX=${CXX:-g++}
BUILD_PROFILE=${BUILD_PROFILE:-native}
OUT_DIR=${OUT_DIR:-build}
mkdir -p "$OUT_DIR"

COMMON_FLAGS="-std=c++17 -Wall -Wextra -fopenmp"
case "$BUILD_PROFILE" in
  safe)
    OPT_FLAGS="-O2"
    ;;
  release)
    OPT_FLAGS="-O3 -DNDEBUG"
    ;;
  native)
    OPT_FLAGS="-O3 -DNDEBUG -march=native -mtune=native"
    ;;
  lto-native)
    OPT_FLAGS="-O3 -DNDEBUG -march=native -mtune=native -flto"
    ;;
  *)
    echo "Unknown BUILD_PROFILE='$BUILD_PROFILE'. Expected: safe, release, native, lto-native" >&2
    exit 2
    ;;
esac

CXXFLAGS=${CXXFLAGS:-$COMMON_FLAGS $OPT_FLAGS}

echo "[0156-build] CXX=$CXX"
echo "[0156-build] BUILD_PROFILE=$BUILD_PROFILE"
echo "[0156-build] OUT_DIR=$OUT_DIR"
echo "[0156-build] CXXFLAGS=$CXXFLAGS"

$CXX $CXXFLAGS -Iinclude \
  src/main_src_mpcd_base.cpp \
  src/params_io_base.cpp \
  src/cell_grid.cpp \
  src/boundary_base.cpp \
  src/fluid_domain.cpp \
  src/immersed_solid.cpp \
  src/src_collision.cpp \
  src/thermostat.cpp \
  src/elliptic_projection.cpp \
  src/q6_projection_adapter.cpp \
  src/closed_capacity_response.cpp \
  src/src_mpcd_base.cpp \
  src/runtime_summary.cpp \
  src/particle_state.cpp \
  src/state_smpcd_io.cpp \
  src/weighted_resampling.cpp \
  -o "$OUT_DIR/src_mpcd_base"

echo "[0156-build] Built $OUT_DIR/src_mpcd_base"

$CXX $CXXFLAGS -Iinclude \
  src/main_validate_elliptic_projection.cpp \
  src/elliptic_projection.cpp \
  -o "$OUT_DIR/validate_elliptic_projection"

echo "[0156-build] Built $OUT_DIR/validate_elliptic_projection"
