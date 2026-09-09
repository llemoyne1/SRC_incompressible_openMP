#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'
if not SRC.exists():
    raise SystemExit(f'[0493x10e-patch] missing {SRC}')

text = SRC.read_text()

if 'r1-analytic-collective-exact-momentum-energy-reaction' not in text:
    raise SystemExit('[0493x10e-patch] x10d analytic-reaction prerequisite not found')
if 'hardFinalMirrorAttempts' in text or 'r1-final-endpoint-tangent-mirror' in text:
    raise SystemExit('[0493x10e-patch] x10e already appears applied')

def repl(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10e-patch] {label}: expected one anchor, found {n}')
    text = text.replace(old, new, 1)

# ---------------------------------------------------------------------------
# Audit: distinguish the common preInside endpoint mirror from the existing
# radius-2 local-anchor fallback.  No new device buffer is introduced: these
# are fields of the existing per-output accumulator.
# ---------------------------------------------------------------------------
repl(
'''    unsigned long long hardFinalEndpointCorrections = 0ull;\n    unsigned long long hardFinalLocalAnchorCorrections = 0ull;\n''',
'''    unsigned long long hardFinalEndpointCorrections = 0ull;\n    unsigned long long hardFinalMirrorAttempts = 0ull;\n    unsigned long long hardFinalMirrorAccepted = 0ull;\n    unsigned long long hardFinalMirrorNormalFallbacks = 0ull;\n    unsigned long long hardFinalMirrorHardFallbacks = 0ull;\n    unsigned long long hardFinalLocalAnchorCorrections = 0ull;\n''',
'audit mirror counters')

# ---------------------------------------------------------------------------
# Single physical change of x10e:
# x10c landed a preInside/endOutside particle at the last interior bisection
# point.  That is impermeable but can pin mass at alpha=0.5.  x10e instead
# preserves the residual path length and mirrors the endpoint across the local
# tangent plane of the physical alpha field.  Velocity is untouched, so x10d
# exact P/E is untouched as well.
# ---------------------------------------------------------------------------
old_branch = '''                if (preInside && endSampled) {\n                    // Current point inside, true final endpoint outside.\n                    // Locate the final crossing on the actual post-reaction\n                    // trajectory and land at the last sampled interior point.\n                    double lo = 0.0; // inside\n                    double hi = 1.0; // outside\n                    bool ok = true;\n                    for (int it = 0; it < 4; ++it) {\n                        const double mid = 0.5 * (lo + hi);\n                        const double xm = xPre + mid * (xEnd - xPre);\n                        const double ym = yPre + mid * (yEnd - yPre);\n                        double am = 0.5;\n                        if (!q6_x9t_sample_alpha(alpha, xm, ym,\n                                                 nx, ny, lx, ly,\n                                                 periodicX, periodicY, &am) ||\n                            !isfinite(am)) {\n                            ok = false;\n                            break;\n                        }\n                        if (am >= 0.5) lo = mid;\n                        else hi = mid;\n                    }\n                    if (ok) {\n                        targetX = xPre + lo * (xEnd - xPre);\n                        targetY = yPre + lo * (yEnd - yPre);\n                    } else {\n                        targetX = xPre;\n                        targetY = yPre;\n                    }\n                    corrected = true;\n                } else {\n'''

new_branch = '''                if (preInside && endSampled) {\n                    // 0493x10e: current point inside, true final endpoint\n                    // outside.  x10c used to clamp the particle at the last\n                    // sampled interior point.  Repeated use of that clamp can\n                    // pile particles directly on alpha=0.5.  Keep the same\n                    // four-sample crossing location, but mirror the remaining\n                    // endpoint displacement across the local tangent instead.\n                    if (audit) atomicAdd(&audit->hardFinalMirrorAttempts, 1ull);\n\n                    double lo = 0.0; // inside\n                    double hi = 1.0; // outside\n                    bool ok = true;\n                    for (int it = 0; it < 4; ++it) {\n                        const double mid = 0.5 * (lo + hi);\n                        const double xm = xPre + mid * (xEnd - xPre);\n                        const double ym = yPre + mid * (yEnd - yPre);\n                        double am = 0.5;\n                        if (!q6_x9t_sample_alpha(alpha, xm, ym,\n                                                 nx, ny, lx, ly,\n                                                 periodicX, periodicY, &am) ||\n                            !isfinite(am)) {\n                            ok = false;\n                            break;\n                        }\n                        if (am >= 0.5) lo = mid;\n                        else hi = mid;\n                    }\n\n                    if (ok) {\n                        // Mid-bracket is the least biased estimate of the\n                        // physical alpha=0.5 crossing.\n                        const double tg = 0.5 * (lo + hi);\n                        const double xg = xPre + tg * (xEnd - xPre);\n                        const double yg = yPre + tg * (yEnd - yPre);\n                        const double dxRem = xEnd - xg;\n                        const double dyRem = yEnd - yg;\n                        const double rem = sqrt(dxRem * dxRem + dyRem * dyRem);\n\n                        double ngx = 0.0, ngy = 0.0;\n                        const bool haveNormal = q6_x10a_sample_alpha_normal(\n                            alpha, xg, yg, nx, ny, lx, ly,\n                            periodicX, periodicY, &ngx, &ngy);\n\n                        bool mirrorAccepted = false;\n                        if (haveNormal && isfinite(rem)) {\n                            // Reflect the residual displacement about the\n                            // local tangent.  n points from liquid to vacuum.\n                            const double dn = dxRem * ngx + dyRem * ngy;\n                            if (dn > 0.0 && isfinite(dn)) {\n                                double mx = xEnd - 2.0 * dn * ngx;\n                                double my = yEnd - 2.0 * dn * ngy;\n                                double am = 0.0;\n                                if (q6_x9t_sample_alpha(alpha, mx, my,\n                                                        nx, ny, lx, ly,\n                                                        periodicX, periodicY, &am) &&\n                                    am >= 0.5) {\n                                    targetX = mx;\n                                    targetY = my;\n                                    mirrorAccepted = true;\n                                } else {\n                                    // Curvature/bilinear interpolation can put\n                                    // the tangent mirror marginally outside.\n                                    // Preserve the same residual length, now\n                                    // purely along the inward normal.\n                                    mx = xg - rem * ngx;\n                                    my = yg - rem * ngy;\n                                    if (q6_x9t_sample_alpha(alpha, mx, my,\n                                                            nx, ny, lx, ly,\n                                                            periodicX, periodicY, &am) &&\n                                        am >= 0.5) {\n                                        targetX = mx;\n                                        targetY = my;\n                                        mirrorAccepted = true;\n                                        if (audit) atomicAdd(\n                                            &audit->hardFinalMirrorNormalFallbacks, 1ull);\n                                    }\n                                }\n                            }\n                        }\n\n                        if (mirrorAccepted) {\n                            corrected = true;\n                            if (audit) atomicAdd(&audit->hardFinalMirrorAccepted, 1ull);\n                        } else {\n                            // Rare hard fallback: reverse the unresolved\n                            // residual segment about the crossing estimate.\n                            // This still lands away from the interface instead\n                            // of clamping onto it.\n                            double mx = 2.0 * xg - xEnd;\n                            double my = 2.0 * yg - yEnd;\n                            double am = 0.0;\n                            if (q6_x9t_sample_alpha(alpha, mx, my,\n                                                    nx, ny, lx, ly,\n                                                    periodicX, periodicY, &am) &&\n                                am >= 0.5) {\n                                targetX = mx;\n                                targetY = my;\n                            } else {\n                                // xPre was explicitly sampled inside; use it\n                                // only as the final safety net.\n                                targetX = xPre;\n                                targetY = yPre;\n                            }\n                            corrected = true;\n                            if (audit) atomicAdd(&audit->hardFinalMirrorHardFallbacks, 1ull);\n                        }\n                    } else {\n                        // Sampling failure: xPre was explicitly inside.\n                        targetX = xPre;\n                        targetY = yPre;\n                        corrected = true;\n                        if (audit) atomicAdd(&audit->hardFinalMirrorHardFallbacks, 1ull);\n                    }\n                } else {\n'''
repl(old_branch, new_branch, 'x10c preInside clamp -> x10e tangent mirror')

# CSV counters.
repl(
'''               "hardFinalReceiverOutsideBefore,hardFinalNeutralOutsideBefore,"\n               "hardFinalEndpointCorrections,hardFinalLocalAnchorCorrections,"\n''',
'''               "hardFinalReceiverOutsideBefore,hardFinalNeutralOutsideBefore,"\n               "hardFinalEndpointCorrections,hardFinalMirrorAttempts,"\n               "hardFinalMirrorAccepted,hardFinalMirrorNormalFallbacks,"\n               "hardFinalMirrorHardFallbacks,hardFinalLocalAnchorCorrections,"\n''',
'CSV mirror header')

repl(
'''        << a.hardFinalReceiverOutsideBefore << ',' << a.hardFinalNeutralOutsideBefore << ','\n        << a.hardFinalEndpointCorrections << ',' << a.hardFinalLocalAnchorCorrections << ','\n''',
'''        << a.hardFinalReceiverOutsideBefore << ',' << a.hardFinalNeutralOutsideBefore << ','\n        << a.hardFinalEndpointCorrections << ',' << a.hardFinalMirrorAttempts << ','\n        << a.hardFinalMirrorAccepted << ',' << a.hardFinalMirrorNormalFallbacks << ','\n        << a.hardFinalMirrorHardFallbacks << ',' << a.hardFinalLocalAnchorCorrections << ','\n''',
'CSV mirror row')

repl(
'''           "r1-final-post-velocity-endpoint-barrier-radius2-local-anchor;"\n           "no-merge-no-resampling;"\n''',
'''           "r1-final-post-velocity-endpoint-barrier-radius2-local-anchor;"\n           "r1-final-endpoint-tangent-mirror-no-interface-clamp;"\n           "no-merge-no-resampling;"\n''',
'contract tag')

SRC.write_text(text)

# ---------------------------------------------------------------------------
# Runner: same x10d physics, only final endpoint placement differs.
# ---------------------------------------------------------------------------
runner = ROOT / 'scripts/run_0493x10e_final_endpoint_mirror.sh'
runner.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export TARGET=wall
export RUN_ROOT="${RUN_ROOT:-runs/0493x10e_final_endpoint_mirror}"
export GAMMA="${GAMMA:-20}"
export DT="${DT:-0.002}"
export KBT="${KBT:-0.125}"
export LIQUID_MASS="${LIQUID_MASS:-1.0}"
export ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
export RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
export GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
export THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
export THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
export THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
export THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
export THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
export SIGMA_ACTIVE="${SIGMA_ACTIVE:-9450.0}"
export SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-3}"
export KINETIC_REFLECTION_FRACTION="${KINETIC_REFLECTION_FRACTION:-1.0}"
export EVAPORATION_TARGET_TYPE="${EVAPORATION_TARGET_TYPE:--1}"
export DROP_RADIUS_CELLS="${DROP_RADIUS_CELLS:-40}"
export DROP_CENTER_X="${DROP_CENTER_X:-1.5625}"
export DROP_CENTER_Y="${DROP_CENTER_Y:-0.78125}"
export DROP_VX="${DROP_VX:-0.0}"
export DROP_VY="${DROP_VY:-0.0}"
export GRAVITY_Y="${GRAVITY_Y:-0.0}"
export STEPS="${STEPS:-800}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-25}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
export LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-10}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
export CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

if [[ "$KINETIC_REFLECTION_FRACTION" != "1" && "$KINETIC_REFLECTION_FRACTION" != "1.0" ]]; then
  echo "[0493x10e-suite] ERROR x10e qualification is intentionally hard-r1 only" >&2
  exit 2
fi

printf '%s\n' \
  "[0493x10e-suite] SHAPE/ISOTROPY TEST: replace x10c endpoint clamp by local tangent mirror" \
  "[0493x10e-suite] x10d exact analytic P/E reaction retained unchanged" \
  "[0493x10e-suite] x10a/x10b retention and x10c final hard barrier retained" \
  "[0493x10e-suite] common preInside/endOutside path mirrors residual displacement; radius-2 fallback unchanged" \
  "[0493x10e-suite] no velocity change, no new particle pass, no merge/resampling" \
  "[0493x10e-suite] kBT=$KBT LiveVis=$LIVE_VIS_ENABLE filteredRecording=$FILTERED_RECORDING_ENABLE"

bash scripts/run_0493x9s_splash.sh
CSV="$RUN_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv"
[[ -f "$CSV" ]] || { echo "[0493x10e-suite] ERROR missing $CSV" >&2; exit 2; }
python3 scripts/analyze_0493x10e_final_endpoint_mirror.py "$CSV"
''')
runner.chmod(0o755)

# Analyzer focused on the isolation experiment.
an = ROOT / 'scripts/analyze_0493x10e_final_endpoint_mirror.py'
an.write_text(r'''#!/usr/bin/env python3
import csv, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: analyze_0493x10e_final_endpoint_mirror.py <cuda_phase_kinetic_crossing_0493x9z.csv>')
p = Path(sys.argv[1])
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10e-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def S(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def pct(a,b): return 100.0*a/b if b else 0.0

last = rows[-1]
checks = S('hardFinalEndpointChecks')
out = S('hardFinalEndpointOutsideBefore')
att = S('hardFinalMirrorAttempts')
acc = S('hardFinalMirrorAccepted')
nfb = S('hardFinalMirrorNormalFallbacks')
hfb = S('hardFinalMirrorHardFallbacks')
local = S('hardFinalLocalAnchorCorrections')
miss = S('hardFinalLocalAnchorMisses')
after = S('hardFinalEndpointOutsideAfter')
maxdeep = max(I(r,'deepOuterParticles') for r in rows)
nonin = S('analyticNonInwardPositiveCells')
invalid = S('analyticInvalidCells')
trivial = S('analyticTrivialCells')

print('===== 0493x10e FINAL ENDPOINT TANGENT MIRROR =====')
print(f'file={p} rows={len(rows)} lastStep={last.get("step","?")}')
print('--- barrier load ---')
print(f'outsideBefore={out}/{checks} ({pct(out,checks):.6f}%)')
print(f'mirrorAttempts={att} accepted={acc} ({pct(acc,att):.3f}%)')
print(f'normalFallbacks={nfb} hardFallbacks={hfb} localAnchorCorrections={local}')
print(f'outsideAfter={after}/{checks} anchorMisses={miss} maxDeepOuter={maxdeep}')
print('--- x10d conservation retained ---')
print(f'max|deltaP|={max(maxabs("deltaPx"),maxabs("deltaPy")):.12e}')
print(f'max|deltaKE|={maxabs("deltaKineticEnergy"):.12e}')
print(f'nonInwardPositiveCells={nonin} trivial={trivial} invalid={invalid}')
print(f'last meanA={F(last,"analyticDonorScaleMean"):.9g} mean|a-2|={F(last,"analyticDonorScaleAbsFromSpecularMean"):.9g}')

ret = (after == 0 and miss == 0)
cons = max(maxabs('deltaPx'), maxabs('deltaPy')) < 1e-9 and maxabs('deltaKineticEnergy') < 1e-9
print('hardRetentionContract=' + ('PASS' if ret else 'FAIL'))
print('conservationContract=' + ('PASS' if cons else 'FAIL'))
print('shapeContract=VISUAL_PENDING')
''')
an.chmod(0o755)

# Pure geometric sanity check: plane alpha=0.5, arbitrary tangent component.
chk = ROOT / 'scripts/check_0493x10e_endpoint_mirror_math.py'
chk.write_text(r'''#!/usr/bin/env python3
import math

def reflect_endpoint(xg, yg, xe, ye, nx, ny):
    dx, dy = xe-xg, ye-yg
    dn = dx*nx + dy*ny
    return xe-2*dn*nx, ye-2*dn*ny

worst_len = 0.0
worst_normal = 0.0
for ang in [i*math.pi/37.0 for i in range(74)]:
    nx, ny = math.cos(ang), math.sin(ang)
    tx, ty = -ny, nx
    for normal in (1e-6, 0.01, 0.2, 1.0):
        for tangent in (-0.7, -0.1, 0.0, 0.3, 0.9):
            xg, yg = 0.13, -0.27
            xe = xg + normal*nx + tangent*tx
            ye = yg + normal*ny + tangent*ty
            xr, yr = reflect_endpoint(xg, yg, xe, ye, nx, ny)
            li = math.hypot(xe-xg, ye-yg)
            lr = math.hypot(xr-xg, yr-yg)
            nr = (xr-xg)*nx + (yr-yg)*ny
            worst_len = max(worst_len, abs(li-lr))
            worst_normal = max(worst_normal, abs(nr + normal))
            if nr >= 1e-12:
                raise SystemExit('FAIL reflected endpoint not inward')
print(f'maxResidualLengthError={worst_len:.3e}')
print(f'maxNormalMirrorError={worst_normal:.3e}')
print('status=PASS')
''')
chk.chmod(0o755)

print('[0493x10e-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10e-patch] wrote scripts/run_0493x10e_final_endpoint_mirror.sh')
print('[0493x10e-patch] wrote scripts/analyze_0493x10e_final_endpoint_mirror.py')
print('[0493x10e-patch] wrote scripts/check_0493x10e_endpoint_mirror_math.py')
