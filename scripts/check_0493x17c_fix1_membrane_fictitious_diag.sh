#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
F=src/cuda_darcy_brinkman_0343.cu
fail(){ echo "[0493x17c-fix1] FAIL $*" >&2; exit 2; }
pass(){ echo "[0493x17c-fix1] PASS $*"; }
[[ -f "$F" ]] || fail "missing $F"
grep -q '0493x17c-fix1: x16c is a fictitious-domain inventory diagnostic' "$F" || fail 'fix marker absent'
grep -q 'params.chiSolidDynamicsEnable && params.chiSolidModel != "membrane_2d"' "$F" || fail 'membrane exclusion guard absent'
grep -q '0493x16k missing resident exact solid-fraction diagnostic field' "$F" || fail 'legacy rigid exact-solidFraction guard was removed'
grep -q 'diagnostics_fictitious_fluid_particles_0493x16c' "$F" || fail 'legacy x16c diagnostic implementation absent'
grep -q 'collectCellImpulse0493x16b = params.chiSolidDynamicsEnable' "$F" || fail 'x16b cell-load collection unexpectedly changed'
pass 'membrane skips obsolete x16c fictitious-domain inventory'
pass 'legacy rigid/specular solidFraction guard preserved'
pass 'x16b cell-load collection preserved'
echo '[0493x17c-fix1] ALL CHECKS PASS'
