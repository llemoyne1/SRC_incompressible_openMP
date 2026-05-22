#!/usr/bin/env bash
set -euo pipefail

CXX=${CXX:-g++}
CXXFLAGS=${CXXFLAGS:--std=c++17 -O2 -Wall -Wextra -fopenmp}

mkdir -p build

$CXX $CXXFLAGS -Iinclude \
  src/main_src_mpcd_base.cpp \
  src/params_io_base.cpp \
  src/cell_grid.cpp \
  src/boundary_base.cpp \
  src/fluid_domain.cpp \
  src/immersed_circle.cpp \
  src/src_collision.cpp \
  src/thermostat.cpp \
  src/elliptic_projection.cpp \
  src/src_mpcd_base.cpp \
  src/runtime_summary.cpp \
  src/particle_state.cpp \
  src/state_smpcd_io.cpp \
  -o build/src_mpcd_base


echo "Built build/src_mpcd_base"

$CXX $CXXFLAGS -Iinclude \
  src/main_validate_elliptic_projection.cpp \
  src/elliptic_projection.cpp \
  -o build/validate_elliptic_projection

echo "Built build/validate_elliptic_projection"
