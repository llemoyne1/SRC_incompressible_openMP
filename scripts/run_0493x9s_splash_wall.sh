#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export TARGET=wall
exec bash "$ROOT/scripts/run_0493x9s_splash.sh"
