#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build_src_mpcd_base.sh
./build/src_mpcd_base examples/params_open_channel_classic_inlet_outlet_smoke_64x32.kv
