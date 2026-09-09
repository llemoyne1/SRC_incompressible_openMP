#!/usr/bin/env python3
# 0493x7n - build a path-selectable fluid calibrator from the existing 0493w1
# runner.  The source runner is left untouched.  This patcher is fail-fast and
# writes nothing unless common params and CUDA flags are demonstrably routed
# through the selected calibration path.

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "scripts" / "run_0493w1_src_fluid_calibrator.sh"
DST = ROOT / "scripts" / "run_0493x7n_path_fluid_calibrator.sh"
README = ROOT / "README_0493X7N_PATH_SELECTABLE_FLUID_CALIBRATOR.md"

if not SRC.exists():
    raise SystemExit(f"[0493x7n] ERROR missing {SRC}")

text = SRC.read_text()
if "0493w1" not in text:
    raise SystemExit("[0493x7n] ERROR source does not look like the 0493w1 calibrator")
if "suite_write_common_params_0434" not in text:
    raise SystemExit("[0493x7n] ERROR source does not use suite_write_common_params_0434")
if "suite_export_cuda_flags_0434" not in text:
    raise SystemExit("[0493x7n] ERROR source does not use suite_export_cuda_flags_0434")
if "0493x7n: calibrate the numerical path" in text:
    raise SystemExit("[0493x7n] ERROR source already appears to contain x7n changes")

selector = r'''
# -----------------------------------------------------------------------------
# 0493x7n: calibrate the numerical path that will actually be used in production.
#
# Examples:
#   CALIBRATION_PATH=src
#   CALIBRATION_PATH=src-q6
#   CALIBRATION_PATH=src-q6-g-f
#
# Any path accepted by suite_validate_path_0434 is accepted here. src remains
# the default, preserving historical 0493w1 behavior.
# -----------------------------------------------------------------------------
CALIBRATION_PATH="${CALIBRATION_PATH:-${INTEG_PATH:-src}}"
suite_validate_path_0434 "$CALIBRATION_PATH"
export CALIBRATION_PATH

echo "[0493x7n] calibrationPath=$CALIBRATION_PATH"
'''

anchor_patterns = [
    r'(source\s+["\']?\$ROOT/scripts/src_mpcd_run_common_0434\.sh["\']?[^\n]*\n\s*suite_root_cd_0434[^\n]*\n)',
    r'(source\s+["\']?\$ROOT/scripts/src_mpcd_run_common_0434\.sh["\']?[^\n]*\n)',
    r'(set\s+-[^\n]*\n)',
]
inserted = False
for pat in anchor_patterns:
    m = re.search(pat, text)
    if m:
        text = text[:m.end()] + selector + text[m.end():]
        inserted = True
        break
if not inserted:
    raise SystemExit("[0493x7n] ERROR could not locate safe selector insertion point")

known_calls = (
    "suite_validate_path_0434",
    "suite_write_common_params_0434",
    "suite_export_cuda_flags_0434",
    "suite_prepare_livevis_control_0434",
    "suite_write_env_file_0434",
    "suite_preflight_run_ok_0492",
)

lines = text.splitlines(True)
out_lines = []
changed_lines = []

for lineno, line in enumerate(lines, 1):
    original = line

    line = re.sub(
        r'^(\s*(?:RUN_MODE|INTEG_PATH|SRC_INTEG_PATH|CALIBRATION_MODE)\s*=\s*)'
        r'(?:"src"|\'src\'|src)(\s*(?:#.*)?\n?)$',
        r'\1"$CALIBRATION_PATH"\2',
        line,
    )

    line = re.sub(
        r'^(\s*local\s+mode\s*=\s*)(?:"src"|\'src\'|src)(\s*(?:#.*)?\n?)$',
        r'\1"$CALIBRATION_PATH"\2',
        line,
    )

    if any(name in line for name in known_calls):
        line = re.sub(r'(?<![\w-])["\']src["\'](?![\w-])', '"$CALIBRATION_PATH"', line)
        line = re.sub(r'(?<![\w$-])src(?![\w-])', '"$CALIBRATION_PATH"', line)

    line = re.sub(
        r'\bSUITE_ACTIVE_MODE_0434=(?:"src"|\'src\'|src)\b',
        'SUITE_ACTIVE_MODE_0434="$CALIBRATION_PATH"',
        line,
    )

    if line != original:
        changed_lines.append((lineno, original.rstrip(), line.rstrip()))
    out_lines.append(line)

text = "".join(out_lines)

mass_insert = r'''
# 0493x7n: single-phase Q6-g-f registry must represent this calibrated fluid.
Q6_GF_SINGLE_PHASE_PARTICLE_MASS="${Q6_GF_SINGLE_PHASE_PARTICLE_MASS:-$PARTICLE_MASS}"
Q6_GF_SINGLE_PHASE_TYPE="${Q6_GF_SINGLE_PHASE_TYPE:-0}"
export Q6_GF_SINGLE_PHASE_PARTICLE_MASS Q6_GF_SINGLE_PHASE_TYPE
'''

if "Q6_GF_SINGLE_PHASE_PARTICLE_MASS=" not in text:
    mass_patterns = [
        r'(^[ \t]*PARTICLE_MASS\s*=\s*["\']?\$\{PARTICLE_MASS:-[^}\n]+\}["\']?[^\n]*\n)',
        r'(^[ \t]*PARTICLE_MASS\s*=\s*[^\n]+\n)',
    ]
    mass_done = False
    for pat in mass_patterns:
        m = re.search(pat, text, flags=re.M)
        if m:
            text = text[:m.end()] + mass_insert + text[m.end():]
            mass_done = True
            break
    if not mass_done:
        raise SystemExit(
            "[0493x7n] ERROR could not locate PARTICLE_MASS assignment; "
            "refusing to guess the q6-g-f registry mass"
        )

manifest_block = r'''

# -----------------------------------------------------------------------------
# 0493x7n path/applicability manifest.
# The historical analyzer stays unchanged for compatibility.
# For Q6 paths, acoustic regression is a longitudinal-response diagnostic and
# must not be interpreted as an ordinary sound-speed calibration.
# -----------------------------------------------------------------------------
if [[ -d "${RUN_ROOT}/analysis" ]]; then
  q6_enabled=0
  q6_g_f_enabled=0
  resampling_enabled=0
  if suite_path_has_q6_0434 "$CALIBRATION_PATH"; then q6_enabled=1; fi
  if suite_path_has_q6_g_f_0493x7h "$CALIBRATION_PATH"; then q6_g_f_enabled=1; fi
  if suite_path_has_resampling_0434 "$CALIBRATION_PATH"; then resampling_enabled=1; fi

  python3 - \
    "${RUN_ROOT}/analysis/calibration_path_0493x7n.json" \
    "$CALIBRATION_PATH" \
    "$q6_enabled" \
    "$q6_g_f_enabled" \
    "$resampling_enabled" \
    "${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}" \
    "${PROJECTION_TOLERANCE:-}" \
    "${PROJECTION_MAX_ITERATIONS:-}" <<'PY_X7N_MANIFEST'
import json
import sys
from pathlib import Path

(out, path, q6, q6gf, resampling, tau, projection_tol, projection_maxit) = sys.argv[1:]
q6 = bool(int(q6))
q6gf = bool(int(q6gf))
resampling = bool(int(resampling))

data = {
    "schema": "0493x7n-path-fluid-calibration-v1",
    "calibrationPath": path,
    "q6Enabled": q6,
    "q6GFEnabled": q6gf,
    "resamplingEnabled": resampling,
    "q6DensityRelaxationTime": float(tau) if q6gf else None,
    "projectionTolerance": float(projection_tol) if projection_tol else None,
    "projectionMaxIterations": int(projection_maxit) if projection_maxit else None,
    "observableApplicability": {
        "transverseViscosityTG": {
            "status": "applicable",
            "meaning": "transverse momentum transport of the selected numerical path",
        },
        "selfDiffusionMSD": {
            "status": "applicable",
            "meaning": "Lagrangian self-diffusion of the selected numerical path",
        },
        "schmidtNumber": {
            "status": "applicable",
            "meaning": "nu/Dself for the selected numerical path",
        },
        "soundSpeed": {
            "status": "not_applicable" if q6 else "applicable",
            "meaning": (
                "Q6 suppresses/modifies longitudinal compressive modes; "
                "retain the acoustic experiment only as a longitudinal-response diagnostic"
                if q6 else
                "ordinary acoustic response of the unprojected SRC path"
            ),
        },
        "acousticRegression": {
            "status": "diagnostic" if q6 else "applicable",
            "meaning": (
                "residual longitudinal-mode response under projection"
                if q6 else
                "sound-speed and longitudinal attenuation measurement"
            ),
        },
    },
}

p = Path(out)
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
print(f"[0493x7n] path manifest={p}")
PY_X7N_MANIFEST
fi
'''

text = text.rstrip() + "\n" + manifest_block.lstrip("\n")

def routed(call):
    for line in text.splitlines():
        if call in line and (
            "$CALIBRATION_PATH" in line
            or "$RUN_MODE" in line
            or "${RUN_MODE}" in line
            or "$CALIBRATION_MODE" in line
        ):
            return True
    return False

if not routed("suite_write_common_params_0434"):
    raise SystemExit("[0493x7n] ERROR common params are not demonstrably path-selectable")
if not routed("suite_export_cuda_flags_0434"):
    raise SystemExit("[0493x7n] ERROR CUDA flags are not demonstrably path-selectable")

for i, line in enumerate(text.splitlines(), 1):
    if any(name in line for name in known_calls):
        if re.search(r'(?<![\w-])["\']?src["\']?(?![\w-])', line):
            raise SystemExit(
                f"[0493x7n] ERROR hard-coded src remains at critical line {i}: {line}"
            )

readme = r'''# 0493x7n — path-selectable fluid calibrator

## Purpose

0493w1 characterizes the underlying SRC fluid with Q6 and resampling disabled.
That remains a useful baseline, but it is not sufficient when a production
simulation uses a projected or otherwise modified numerical path.

0493x7n keeps the 0493w1 experiments, state generation, sampling and analyzer,
while making the integration path explicit:

    CALIBRATION_PATH=src
    CALIBRATION_PATH=src-q6
    CALIBRATION_PATH=src-q6-g-f

Any path accepted by `suite_validate_path_0434` is accepted by the runner.
`src` remains the default. The original
`scripts/run_0493w1_src_fluid_calibrator.sh` is not modified.

## Path authority

The selected path is passed through the existing 0434/x7h common helpers:

- `suite_write_common_params_0434`
- `suite_export_cuda_flags_0434`

Therefore projection enablement, resampling enablement, resident CUDA flags and
the Q6-g-f parameter block come from the same path-selection code as run_ok
simulations.

For single-phase Q6-g-f calibration, the autogenerated liquid registry inherits
`PARTICLE_MASS` through `Q6_GF_SINGLE_PHASE_PARTICLE_MASS`.

Q6-g-f controls remain ordinary environment overrides, e.g.

    Q6_GF_DENSITY_RELAXATION_TIME=0.25
    PROJECTION_TOLERANCE=1e-5
    PROJECTION_MAX_ITERATIONS=800

This permits controlled ablations such as `tau_rho=0` without another
calibrator.

## Observable interpretation

### Taylor–Green transverse viscosity

Applicable to every path. It measures transverse momentum transport under the
complete selected numerical path.

### Periodic MSD / self diffusion

Applicable to every path. Together with TG viscosity it defines the effective
Schmidt number of the selected path.

### Acoustic experiment

For an unprojected SRC path it retains the 0493w1 interpretation as a
sound-speed and longitudinal-attenuation calibration.

For a Q6 path, ordinary sound speed is not applicable: projection deliberately
suppresses or modifies longitudinal compressive modes. The acoustic experiment
is retained only as a diagnostic of residual longitudinal response.

The historical 0493w1 analysis outputs are preserved for compatibility.
0493x7n additionally writes

    analysis/calibration_path_0493x7n.json

which records the path and observable applicability so a projected-path run
cannot silently be mistaken for an ordinary SRC acoustic calibration.

## Recommended comparison for the current Poiseuille investigation

Use the production local signature:

    gamma = 20
    dt = 0.001
    kBT = 0.001
    particle mass = 1
    rotation angle = 1.5
    random rotation sign = true
    grid shift = true
    thermostat = cell_relative_rescale, every step

Compare at least:

1. `CALIBRATION_PATH=src`
2. `CALIBRATION_PATH=src-q6`
3. `CALIBRATION_PATH=src-q6-g-f`, `Q6_GF_DENSITY_RELAXATION_TIME=0.25`
4. `CALIBRATION_PATH=src-q6-g-f`, `Q6_GF_DENSITY_RELAXATION_TIME=0`

The first decisive observable is TG viscosity. If Q6-g-f preserves TG
viscosity while Poiseuille changes strongly, the defect is associated with
forcing/wall coupling rather than intrinsic transverse momentum transport.
'''

DST.write_text(text)
DST.chmod(0o755)
README.write_text(readme)

print(f"[0493x7n] source={SRC}")
print(f"[0493x7n] wrote={DST}")
print(f"[0493x7n] wrote={README}")
print(f"[0493x7n] transformed critical lines={len(changed_lines)}")
for lineno, old, new in changed_lines:
    print(f"[0493x7n] line {lineno}:")
    print(f"  - {old}")
    print(f"  + {new}")
