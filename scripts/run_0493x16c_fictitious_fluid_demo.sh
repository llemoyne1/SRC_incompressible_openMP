#!/usr/bin/env bash

# 0493x16c demonstration variant with fictitious-fluid inventory.
# Same qualified x16b coupling as run_0493x16c_fictitious_fluid_inventory.sh, but with
# a larger domain/grid and faster initial slab translation for clear LiveVis
# and recorded-field visualization. No physics branch is added here.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

export CASE_LABEL="${CASE_LABEL:-0493x16c_fictitious_fluid_demo}"
export BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x16c_fictitious_fluid_demo}"

# Preserve x16a/x16b/x16c cell size and geometric proportions while doubling each
# domain dimension: 4x cells/particles, 4x solid mass, 2x slab-cell thickness.
export Lx="${Lx:-1.0}"
export Ly="${Ly:-0.5}"
export NX="${NX:-256}"
export NY="${NY:-128}"
export SLAB_CELLS="${SLAB_CELLS:-16}"
export SOLID_MASS="${SOLID_MASS:-131072.0}"

# Faster than the qualifier (0.02) but still modest relative to the thermal
# velocity scale of the selected kBT. Intended for visible demonstration.
export SOLID_UX0="${SOLID_UX0:-0.08}"
export STEPS="${STEPS:-3000}"

# Higher-resolution live/recorded fields and denser temporal sampling for video.
export LIVE_VIS_NX="${LIVE_VIS_NX:-256}"
export LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
export LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
export LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-chi}"
export RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy,chi}"
export RECORD_EVERY="${RECORD_EVERY:-20}"
export FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-20}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"

exec bash "$ROOT/scripts/run_0493x16c_fictitious_fluid_inventory.sh"
