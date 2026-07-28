#!/usr/bin/env bash
set -euo pipefail

repo="${1:-$(pwd)}"
runner="$repo/scripts/run_0493o1_tg_split_guard.sh"
[[ -f "$runner" ]] || { echo "[0493o2-fix1-check] missing $runner" >&2; exit 2; }

grep -q '0493o2-fix1: TG mono/dual species runner' "$runner"
grep -q 'TG_SPECIES_MODE="${TG_SPECIES_MODE:-mono}"' "$runner"
grep -q 'species_registry_params_0493o2' "$runner"
grep -q 'rewrite_tg_species_types_0493o2' "$runner"
grep -q 'speciesCount = 2' "$runner"
grep -q 'species1ResamplingEnable = ${SPECIES1_RESAMPLING_ENABLE}' "$runner"
grep -q 'rewrite_tg_species_types_0493o2 "$STATE"' "$runner"
grep -q 'TG_CASE_SUFFIX="_dual_t${TG_SPECIES0_TYPE}_t${TG_SPECIES1_TYPE}"' "$runner"

bash -n "$runner"

python3 - "$runner" <<'PY'
from __future__ import annotations

import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

runner = Path(sys.argv[1])
text = runner.read_text(encoding="utf-8")
assert text.count("$(species_registry_params_0493o2)") == 1
assert text.count('rewrite_tg_species_types_0493o2 "$STATE"') == 1
assert re.search(r'case "\$TG_SPECIES_MODE" in\s*\n\s*mono\|dual\)', text)

match = re.search(r"<<'PY0493O2'\n(.*?)\nPY0493O2", text, flags=re.S)
if not match:
    raise SystemExit("embedded PY0493O2 rewriter not found")
rewriter = match.group(1)

with tempfile.TemporaryDirectory(prefix="0493o2-check-") as td:
    td = Path(td)
    script = td / "rewriter.py"
    state = td / "synthetic.smpcd"
    script.write_text(rewriter, encoding="utf-8")

    nx = ny = 2
    gamma = 4
    inactive = 4
    x = []
    y = []
    vx = []
    vy = []
    typ = []
    mass = []
    role = []
    for iy in range(ny):
        for ix in range(nx):
            for local in range(gamma):
                x.append((ix + (local + 1) / (gamma + 1)) / nx)
                y.append((iy + (gamma - local) / (gamma + 1)) / ny)
                vx.append(0.01 * (1 + len(x)))
                vy.append(-0.02 * (1 + len(y)))
                typ.append(0)
                mass.append(1.0)
                role.append(1)
    for _ in range(inactive):
        x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0)
        typ.append(0); mass.append(1.0); role.append(0)

    n = len(x)
    magic = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    with state.open("wb") as f:
        f.write(magic)
        f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
        f.write(struct.pack("<8Q", *reserved))
        for arr, fmt in [
            (x, "d"), (y, "d"), (vx, "d"), (vy, "d"),
            (typ, "I"), (mass, "d"), (role, "B"),
        ]:
            f.write(struct.pack(f"<{n}{fmt}", *arr))

    before = state.read_bytes()
    subprocess.run(
        [sys.executable, str(script), str(state), "2", "2", "1", "1", "1", "2"],
        check=True,
    )
    after = state.read_bytes()

    header = 16 + struct.calcsize("<IIIIQIIII") + 8 * 8
    type_off = header + 8 * n * 4
    mass_off = type_off + 4 * n
    role_off = mass_off + 8 * n
    types = struct.unpack_from(f"<{n}I", after, type_off)

    # The rewriter may change only the type array.
    assert before[:type_off] == after[:type_off]
    assert before[mass_off:] == after[mass_off:]
    for cell in range(nx * ny):
        lo = cell * gamma
        assert types[lo:lo + gamma].count(1) == gamma // 2
        assert types[lo:lo + gamma].count(2) == gamma // 2
    assert all(t == 1 for t in types[nx * ny * gamma:])

print("[0493o2-fix1-check] embedded state rewrite: PASS")
PY

echo "[0493o2-fix1-check] static runner structure: PASS"
echo "[0493o2-fix1-check] TG mono/dual runner: PASS"
