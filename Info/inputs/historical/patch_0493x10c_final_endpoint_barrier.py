#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'
if not SRC.exists():
    raise SystemExit(f'[0493x10c-patch] missing {SRC}')

text = SRC.read_text()

if 'shellHardRetentionCandidates' not in text:
    raise SystemExit('[0493x10c-patch] x10b hard-retention prerequisite not found')
if 'hardFinalEndpointChecks' in text:
    raise SystemExit('[0493x10c-patch] x10c already appears applied')


def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10c-patch] {label}: expected 1 anchor, found {n}')
    text = text.replace(old, new, 1)

replace_once(
"""    unsigned long long shellHardRetentionFinalOutside = 0ull;
    unsigned long long convertedParticles = 0ull;
""",
"""    unsigned long long shellHardRetentionFinalOutside = 0ull;
    unsigned long long hardFinalEndpointChecks = 0ull;
    unsigned long long hardFinalEndpointOutsideBefore = 0ull;
    unsigned long long hardFinalReceiverOutsideBefore = 0ull;
    unsigned long long hardFinalNeutralOutsideBefore = 0ull;
    unsigned long long hardFinalEndpointCorrections = 0ull;
    unsigned long long hardFinalLocalAnchorCorrections = 0ull;
    unsigned long long hardFinalLocalAnchorMisses = 0ull;
    unsigned long long hardFinalEndpointOutsideAfter = 0ull;
    unsigned long long convertedParticles = 0ull;
""",
'audit hard-final counters')

replace_once(
"""    double shellHardRetentionCorrectionAbsSum = 0.0;
    double reactionEnergyResidualAbsSum = 0.0;
""",
"""    double shellHardRetentionCorrectionAbsSum = 0.0;
    double hardFinalEndpointCorrectionAbsSum = 0.0;
    double reactionEnergyResidualAbsSum = 0.0;
""",
'audit hard-final correction sum')

replace_once(
"""        const bool hardShellCapture = reflectionFraction >= 1.0 && d.shellRecoverable;
        const bool donor = d.crossing && d.reflect;
        const bool receiver = !d.crossing && !hardShellCapture && reactionActive[c] > 0.5;
        if (!donor && !receiver && !hardShellCapture) continue;
""",
"""        const bool hardR1Containment = reflectionFraction >= 1.0;
        const bool hardShellCapture = hardR1Containment && d.shellRecoverable;
        const bool donor = d.crossing && d.reflect;
        const bool receiver = !d.crossing && !hardShellCapture && reactionActive[c] > 0.5;
        // x10c: in r=1 mode every phase-A particle reaches the final endpoint
        // barrier below, even if it was not a donor/receiver/shell candidate.
        // This closes two residual escape paths:
        //   (1) an endpoint-outside trajectory rejected by the old gn>0 gate;
        //   (2) a receiver whose velocity becomes outward only after the x9z
        //       affine reaction has been applied in this same pass.
        if (!donor && !receiver && !hardShellCapture && !hardR1Containment) continue;
""",
'pass3 hard-r1 reachability')

anchor = """        particles.vx[i] = newVx;
        particles.vy[i] = newVy;
"""

insert = r'''        // -----------------------------------------------------------------
        // 0493x10c — final r=1 endpoint barrier.
        //
        // This is the last geometric operation in pass 3, after donor
        // reflection, receiver affine reaction, and x10b shell recovery.
        // Therefore it tests the endpoint that will really be streamed with
        // final velocity newV.
        //
        // Cost: one bilinear alpha sample per phase-A particle in r=1 mode;
        // bisection only for endpoints still outside; a bounded 5x5 cell-centre
        // search only when the current pre-stream position itself is outside.
        // No velocity is modified here.
        if (hardR1Containment) {
            if (audit) atomicAdd(&audit->hardFinalEndpointChecks, 1ull);

            const double xPre = particles.x[i];
            const double yPre = particles.y[i];
            const double xEnd = xPre + newVx * dt;
            const double yEnd = yPre + newVy * dt;

            double aEnd = 0.0;
            const bool endSampled = q6_x9t_sample_alpha(
                alpha, xEnd, yEnd,
                nx, ny, lx, ly, periodicX, periodicY, &aEnd);
            const bool endOutside = !endSampled || !(aEnd >= 0.5);

            if (endOutside) {
                if (audit) {
                    atomicAdd(&audit->hardFinalEndpointOutsideBefore, 1ull);
                    if (receiver)
                        atomicAdd(&audit->hardFinalReceiverOutsideBefore, 1ull);
                    else if (!donor && !hardShellCapture)
                        atomicAdd(&audit->hardFinalNeutralOutsideBefore, 1ull);
                }

                double targetX = xEnd;
                double targetY = yEnd;
                bool corrected = false;
                bool usedLocalAnchor = false;

                double aPre = 0.0;
                const bool preInside = q6_x9t_sample_alpha(
                    alpha, xPre, yPre,
                    nx, ny, lx, ly, periodicX, periodicY, &aPre) &&
                    aPre >= 0.5;

                if (preInside && endSampled) {
                    // Current point inside, true final endpoint outside.
                    // Locate the final crossing on the actual post-reaction
                    // trajectory and land at the last sampled interior point.
                    double lo = 0.0; // inside
                    double hi = 1.0; // outside
                    bool ok = true;
                    for (int it = 0; it < 4; ++it) {
                        const double mid = 0.5 * (lo + hi);
                        const double xm = xPre + mid * (xEnd - xPre);
                        const double ym = yPre + mid * (yEnd - yPre);
                        double am = 0.5;
                        if (!q6_x9t_sample_alpha(alpha, xm, ym,
                                                 nx, ny, lx, ly,
                                                 periodicX, periodicY, &am) ||
                            !isfinite(am)) {
                            ok = false;
                            break;
                        }
                        if (am >= 0.5) lo = mid;
                        else hi = mid;
                    }
                    if (ok) {
                        targetX = xPre + lo * (xEnd - xPre);
                        targetY = yPre + lo * (yEnd - yPre);
                    } else {
                        targetX = xPre;
                        targetY = yPre;
                    }
                    corrected = true;
                } else {
                    // Already pointwise outside at this final check. x10b
                    // handles the direct-bulk shell; x10c adds a bounded local
                    // fallback for residual deep/reclassified particles.
                    const double dxCell = lx / static_cast<double>(nx);
                    const double dyCell = ly / static_cast<double>(ny);
                    int bestCell = -1;
                    double bestX = 0.0;
                    double bestY = 0.0;
                    double bestD2 = 0.0;

                    for (int oy = -2; oy <= 2; ++oy) {
                        for (int ox = -2; ox <= 2; ++ox) {
                            int k = -1;
                            if (!q6_x9u_offset_cell(c, ox, oy,
                                                    nx, ny,
                                                    periodicX, periodicY, &k))
                                continue;
                            if (!(alpha[k] >= 0.5)) continue;
                            if (!(totalM[k] > 0.0) || !isfinite(totalM[k])) continue;

                            const int ki = k % nx;
                            const int kj = k / nx;
                            double ax = (static_cast<double>(ki) + 0.5) * dxCell;
                            double ay = (static_cast<double>(kj) + 0.5) * dyCell;

                            if (periodicX) {
                                double dd = ax - xEnd;
                                if (dd >  0.5 * lx) ax -= lx;
                                if (dd < -0.5 * lx) ax += lx;
                            }
                            if (periodicY) {
                                double dd = ay - yEnd;
                                if (dd >  0.5 * ly) ay -= ly;
                                if (dd < -0.5 * ly) ay += ly;
                            }

                            double aa = 0.0;
                            if (!q6_x9t_sample_alpha(alpha, ax, ay,
                                                     nx, ny, lx, ly,
                                                     periodicX, periodicY, &aa) ||
                                !(aa >= 0.5))
                                continue;

                            const double ddx = ax - xEnd;
                            const double ddy = ay - yEnd;
                            const double d2 = ddx * ddx + ddy * ddy;
                            if (bestCell < 0 || d2 < bestD2) {
                                bestCell = k;
                                bestX = ax;
                                bestY = ay;
                                bestD2 = d2;
                            }
                        }
                    }

                    if (bestCell >= 0) {
                        usedLocalAnchor = true;
                        if (endSampled && aEnd < 0.5) {
                            double lo = 0.0; // outside
                            double hi = 1.0; // inside
                            bool ok = true;
                            for (int it = 0; it < 4; ++it) {
                                const double mid = 0.5 * (lo + hi);
                                const double xm = xEnd + mid * (bestX - xEnd);
                                const double ym = yEnd + mid * (bestY - yEnd);
                                double am = 0.5;
                                if (!q6_x9t_sample_alpha(alpha, xm, ym,
                                                         nx, ny, lx, ly,
                                                         periodicX, periodicY, &am) ||
                                    !isfinite(am)) {
                                    ok = false;
                                    break;
                                }
                                if (am >= 0.5) hi = mid;
                                else lo = mid;
                            }
                            if (ok) {
                                const double tMirror = fmin(1.0, 2.0 * hi);
                                targetX = xEnd + tMirror * (bestX - xEnd);
                                targetY = yEnd + tMirror * (bestY - yEnd);
                            } else {
                                targetX = bestX;
                                targetY = bestY;
                            }
                        } else {
                            targetX = bestX;
                            targetY = bestY;
                        }
                        corrected = true;
                    } else if (audit) {
                        atomicAdd(&audit->hardFinalLocalAnchorMisses, 1ull);
                    }
                }

                if (corrected) {
                    double aTarget = 0.0;
                    if (!q6_x9t_sample_alpha(alpha, targetX, targetY,
                                             nx, ny, lx, ly,
                                             periodicX, periodicY, &aTarget) ||
                        !(aTarget >= 0.5)) {
                        corrected = false;
                    }
                }

                if (corrected) {
                    const double corrX = targetX - xEnd;
                    const double corrY = targetY - yEnd;
                    particles.x[i] = xPre + corrX;
                    particles.y[i] = yPre + corrY;
                    if (audit) {
                        atomicAdd(&audit->hardFinalEndpointCorrections, 1ull);
                        if (usedLocalAnchor)
                            atomicAdd(&audit->hardFinalLocalAnchorCorrections, 1ull);
                        atomic_add_double_0400(
                            &audit->hardFinalEndpointCorrectionAbsSum,
                            sqrt(corrX * corrX + corrY * corrY));
                    }
                }
            }

            if (audit) {
                double aVerify = 0.0;
                if (!q6_x9t_sample_alpha(
                        alpha,
                        particles.x[i] + newVx * dt,
                        particles.y[i] + newVy * dt,
                        nx, ny, lx, ly, periodicX, periodicY, &aVerify) ||
                    !(aVerify >= 0.5))
                    atomicAdd(&audit->hardFinalEndpointOutsideAfter, 1ull);
            }
        }

        particles.vx[i] = newVx;
        particles.vy[i] = newVy;
'''
replace_once(anchor, insert, 'universal final endpoint barrier')

replace_once(
"""               "shellHardRetentionFallbacks,shellHardRetentionFinalOutside,"
               "convertedParticles,individualDonorReflections,receiverCorrectedParticles,"
""",
"""               "shellHardRetentionFallbacks,shellHardRetentionFinalOutside,"
               "hardFinalEndpointChecks,hardFinalEndpointOutsideBefore,"
               "hardFinalReceiverOutsideBefore,hardFinalNeutralOutsideBefore,"
               "hardFinalEndpointCorrections,hardFinalLocalAnchorCorrections,"
               "hardFinalLocalAnchorMisses,hardFinalEndpointOutsideAfter,"
               "convertedParticles,individualDonorReflections,receiverCorrectedParticles,"
""",
'CSV hard-final counter header')

replace_once(
"""               "endpointSealCorrectionAbsMean,shellHardRetentionCorrectionAbsMean,"
               "reactionEnergyResidualAbs,reactionDeltaUMagnitudeMean,"
""",
"""               "endpointSealCorrectionAbsMean,shellHardRetentionCorrectionAbsMean,"
               "hardFinalEndpointCorrectionAbsMean,"
               "reactionEnergyResidualAbs,reactionDeltaUMagnitudeMean,"
""",
'CSV hard-final correction header')

replace_once(
"""    const double meanReactionDU = a.reactionActiveCells > 0ull ?
""",
"""    const double meanHardFinalCorr = a.hardFinalEndpointCorrections > 0ull ?
        a.hardFinalEndpointCorrectionAbsSum /
            static_cast<double>(a.hardFinalEndpointCorrections) : 0.0;
    const double meanReactionDU = a.reactionActiveCells > 0ull ?
""",
'CSV hard-final mean')

replace_once(
"""        << a.shellHardRetentionFallbacks << ',' << a.shellHardRetentionFinalOutside << ','
        << a.convertedParticles << ','
""",
"""        << a.shellHardRetentionFallbacks << ',' << a.shellHardRetentionFinalOutside << ','
        << a.hardFinalEndpointChecks << ',' << a.hardFinalEndpointOutsideBefore << ','
        << a.hardFinalReceiverOutsideBefore << ',' << a.hardFinalNeutralOutsideBefore << ','
        << a.hardFinalEndpointCorrections << ',' << a.hardFinalLocalAnchorCorrections << ','
        << a.hardFinalLocalAnchorMisses << ',' << a.hardFinalEndpointOutsideAfter << ','
        << a.convertedParticles << ','
""",
'CSV hard-final counter row')

replace_once(
"""        << meanSealCorr << ',' << meanShellRetentionCorr << ','
        << a.reactionEnergyResidualAbsSum << ',' << meanReactionDU << ',' << meanLambdaDev << ','
""",
"""        << meanSealCorr << ',' << meanShellRetentionCorr << ',' << meanHardFinalCorr << ','
        << a.reactionEnergyResidualAbsSum << ',' << meanReactionDU << ',' << meanLambdaDev << ','
""",
'CSV hard-final correction row')

replace_once(
"""           "r1-shell-hard-retention-direct-bulk-mirror;no-merge-no-resampling;"
           "same-three-x9-particle-passes-plus-one-cell-kernel;deterministic-hash" << '\\n';
""",
"""           "r1-shell-hard-retention-direct-bulk-mirror;"
           "r1-final-post-velocity-endpoint-barrier-radius2-local-anchor;"
           "no-merge-no-resampling;"
           "same-three-x9-particle-passes-plus-one-cell-kernel;deterministic-hash" << '\\n';
""",
'CSV x10c contract tag')

SRC.write_text(text)

run = ROOT / 'scripts/run_0493x10c_final_endpoint_barrier.sh'
run.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export TARGET=wall
export RUN_ROOT="${RUN_ROOT:-runs/0493x10c_final_endpoint_barrier}"
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
export STEPS="${STEPS:-150}"
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
  echo "[0493x10c-suite] ERROR qualification intentionally restricted to r=1" >&2
  exit 2
fi

printf '%s\n' \
  "[0493x10c-suite] FINAL ENDPOINT BARRIER: containment after every pass-3 velocity change" \
  "[0493x10c-suite] catches receiver-reaction exits and old relative-gn-gate misses" \
  "[0493x10c-suite] bounded radius-2 local anchor only for particles already pointwise outside" \
  "[0493x10c-suite] no new particle pass; no merge/resampling; velocity/reaction law unchanged" \
  "[0493x10c-suite] kBT=$KBT LiveVis=$LIVE_VIS_ENABLE filteredRecording=$FILTERED_RECORDING_ENABLE"

bash scripts/run_0493x9s_splash.sh
CSV="$RUN_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv"
[[ -f "$CSV" ]] || { echo "[0493x10c-suite] ERROR missing $CSV" >&2; exit 2; }
python3 scripts/analyze_0493x10c_final_endpoint_barrier.py "$CSV"
''')
run.chmod(0o755)

an = ROOT / 'scripts/analyze_0493x10c_final_endpoint_barrier.py'
an.write_text(r'''#!/usr/bin/env python3
import csv, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: analyze_0493x10c_final_endpoint_barrier.py <cuda_phase_kinetic_crossing_0493x9z.csv>')
path = Path(sys.argv[1])
with path.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10c-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def rat(a,b): return a/b if b else 0.0
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)

last = rows[-1]
checks = isum('hardFinalEndpointChecks')
outside_before = isum('hardFinalEndpointOutsideBefore')
receiver_out = isum('hardFinalReceiverOutsideBefore')
neutral_out = isum('hardFinalNeutralOutsideBefore')
corr = isum('hardFinalEndpointCorrections')
local = isum('hardFinalLocalAnchorCorrections')
miss = isum('hardFinalLocalAnchorMisses')
outside_after = isum('hardFinalEndpointOutsideAfter')

deep0 = I(rows[0], 'deepOuterParticles')
deep1 = I(last, 'deepOuterParticles')
shell0 = I(rows[0], 'shellParticles')
shell1 = I(last, 'shellParticles')
outer0 = I(rows[0], 'phaseAOuterCellParticles')
outer1 = I(last, 'phaseAOuterCellParticles')

print('===== 0493x10c FINAL POST-VELOCITY ENDPOINT BARRIER =====')
print(f'file={path} rows={len(rows)} lastStep={last.get("step","?")}')
print('--- final barrier ---')
print(f'checks={checks}')
print(f'outsideBefore={outside_before} ({rat(outside_before,checks):.6%} of checked)')
print(f'  receiverReactionCreated/Remaining={receiver_out} ({rat(receiver_out,outside_before):.3%} of outside)')
print(f'  neutralOrOldGate={neutral_out} ({rat(neutral_out,outside_before):.3%} of outside)')
print(f'corrections={corr} localAnchorCorrections={local} anchorMisses={miss}')
print(f'outsideAfter={outside_after}/{checks} ({rat(outside_after,checks):.9%})')
print('--- classification halo before same-pass recovery ---')
print(f'outer first={outer0} last={outer1} growth={outer1-outer0:+d}')
print(f'shell first={shell0} last={shell1} growth={shell1-shell0:+d}')
print(f'deepOuter first={deep0} last={deep1} growth={deep1-deep0:+d}')
print('--- reaction audit retained only as context ---')
print(f'max|deltaP|={max(maxabs("deltaPx"),maxabs("deltaPy")):.6e}')
print(f'max|deltaKE|={maxabs("deltaKineticEnergy"):.6e}')
print(f'lastMeanLambdaDev={F(last,"reactionLambdaDeviationAbsMean"):.6e}')

contract = (outside_after == 0 and miss == 0)
print('finalEndpointContract=' + ('PASS' if contract else 'FAIL'))
if contract and deep1 > 0:
    print('interpretation=all corrected-pass endpoints are inside current alpha; residual deepOuter is pre-correction/reclassification history')
elif contract:
    print('interpretation=hard r=1 geometric retention closed on current alpha')
else:
    print('interpretation=hard barrier still has an uncovered local geometry path')
''')
an.chmod(0o755)

chk = ROOT / 'scripts/check_0493x10c_final_endpoint_math.py'
chk.write_text(r'''#!/usr/bin/env python3

def alpha(x):
    return 1.0 - x

def inside_to_outside(x0, x1, n=4):
    assert alpha(x0) >= 0.5 and alpha(x1) < 0.5
    lo, hi = 0.0, 1.0
    for _ in range(n):
        mid = 0.5*(lo+hi)
        x = x0 + mid*(x1-x0)
        if alpha(x) >= 0.5: lo = mid
        else: hi = mid
    return x0 + lo*(x1-x0)

def outside_to_anchor(x1, anchor, n=4):
    assert alpha(x1) < 0.5 and alpha(anchor) >= 0.5
    lo, hi = 0.0, 1.0
    for _ in range(n):
        mid = 0.5*(lo+hi)
        x = x1 + mid*(anchor-x1)
        if alpha(x) >= 0.5: hi = mid
        else: lo = mid
    t = min(1.0, 2.0*hi)
    x = x1 + t*(anchor-x1)
    return x if alpha(x) >= 0.5 else anchor

worst = 0.0
for x0 in (0.0, 0.2, 0.49, 0.4999):
    for x1 in (0.5001, 0.55, 0.8, 1.2):
        x = inside_to_outside(x0, x1)
        worst = max(worst, max(0.0, 0.5-alpha(x)))
        if alpha(x) < 0.5:
            raise SystemExit('FAIL inside->outside barrier')
for x1 in (0.5001, 0.55, 0.8, 1.2):
    for anchor in (0.49, 0.4, 0.2, 0.0):
        x = outside_to_anchor(x1, anchor)
        worst = max(worst, max(0.0, 0.5-alpha(x)))
        if alpha(x) < 0.5:
            raise SystemExit('FAIL outside->anchor barrier')

maxerr = 0.0
dt = 0.002
for x0 in (-1.2, 0.0, 3.4):
    for v in (-2.1, 0.0, 4.7):
        for target in (-0.7, 0.3, 2.2):
            corr = target - (x0 + v*dt)
            landed = (x0+corr) + v*dt
            maxerr = max(maxerr, abs(landed-target))
print(f'maxOutsideDefect={worst:.3e}')
print(f'maxEndpointIdentityError={maxerr:.3e}')
print('status=PASS')
''')
chk.chmod(0o755)

print('[0493x10c-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10c-patch] wrote scripts/run_0493x10c_final_endpoint_barrier.sh')
print('[0493x10c-patch] wrote scripts/analyze_0493x10c_final_endpoint_barrier.py')
print('[0493x10c-patch] wrote scripts/check_0493x10c_final_endpoint_math.py')
