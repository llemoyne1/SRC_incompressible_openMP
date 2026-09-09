#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'
if not SRC.exists():
    raise SystemExit(f'[0493x10b-patch] missing {SRC}')
text = SRC.read_text()

if '0493x10a: value-consistent pointwise normal' not in text:
    raise SystemExit('[0493x10b-patch] x10a prerequisite not found; apply x10a first')
if 'analyticReactionCandidate' in text or '0493x10b analytic' in text.lower():
    raise SystemExit('[0493x10b-patch] obsolete analytic x10b appears to be present; do not stack this patch on it')
if 'shellHardRetentionCandidates' in text:
    raise SystemExit('[0493x10b-patch] hard-retention x10b already appears applied')


def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10b-patch] {label}: expected 1 anchor, found {n}')
    text = text.replace(old, new, 1)

# Audit: keep x10a fields and add only the shell-hard-retention observables.
replace_once(
'''    unsigned long long appliedInteriorFinalOutside = 0ull;\n    unsigned long long convertedParticles = 0ull;\n''',
'''    unsigned long long appliedInteriorFinalOutside = 0ull;\n    unsigned long long shellRecoverableParticles = 0ull;\n    unsigned long long shellHardRetentionCandidates = 0ull;\n    unsigned long long shellHardRetentionAlreadyInside = 0ull;\n    unsigned long long shellHardRetentionCorrections = 0ull;\n    unsigned long long shellHardRetentionFallbacks = 0ull;\n    unsigned long long shellHardRetentionFinalOutside = 0ull;\n    unsigned long long convertedParticles = 0ull;\n''',
'audit shell counters')
replace_once(
'''    double endpointSealCorrectionAbsSum = 0.0;\n    double reactionEnergyResidualAbsSum = 0.0;\n''',
'''    double endpointSealCorrectionAbsSum = 0.0;\n    double shellHardRetentionCorrectionAbsSum = 0.0;\n    double reactionEnergyResidualAbsSum = 0.0;\n''',
'audit shell correction sum')

# Decision state: shellRecoverable means pointwise alpha<0.5 but a direct bulk
# bath exists. It is deliberately distinct from shellGuard (which additionally
# requires outward relative velocity and therefore triggers velocity reflection).
replace_once(
'''    bool shellParticle = false;\n    bool deepOuterParticle = false;\n''',
'''    bool shellParticle = false;\n    bool shellRecoverable = false;\n    bool deepOuterParticle = false;\n''',
'decision shell recoverable')

# Once a direct bulk bath has been found, retain it even when gn<=0.  This is
# what lets pass 3 repair position without forcing an unnecessary velocity kick.
replace_once(
'''        const double mb = totalM[bath];\n        if (!(mb > 0.0) || !isfinite(mb)) {\n            d.deepOuterParticle = true;\n            return d;\n        }\n        const double ux = totalPx[bath] / mb;\n''',
'''        d.shellRecoverable = true;\n        d.bathCell = bath;\n\n        const double mb = totalM[bath];\n        if (!(mb > 0.0) || !isfinite(mb)) {\n            d.shellRecoverable = false;\n            d.deepOuterParticle = true;\n            return d;\n        }\n        const double ux = totalPx[bath] / mb;\n''',
'shell bath persistence')
replace_once(
'''        if (!(gn > 0.0) || !isfinite(gn)) {\n            d.bathCell = bath;\n            return d;\n        }\n''',
'''        if (!(gn > 0.0) || !isfinite(gn)) {\n            // Already outside but naturally moving back toward the bulk.  In\n            // hard-retention r=1 mode, pass 3 may still repair its endpoint if\n            // it would remain outside; no velocity reflection is requested.\n            return d;\n        }\n''',
'shell nonoutward path')

# Audit recoverable shell population at classification cadence.
replace_once(
'''            if (d.shellParticle) atomicAdd(&audit->shellParticles, 1ull);\n            if (d.deepOuterParticle) atomicAdd(&audit->deepOuterParticles, 1ull);\n''',
'''            if (d.shellParticle) atomicAdd(&audit->shellParticles, 1ull);\n            if (d.shellRecoverable) atomicAdd(&audit->shellRecoverableParticles, 1ull);\n            if (d.deepOuterParticle) atomicAdd(&audit->deepOuterParticles, 1ull);\n''',
'classify shell recoverable audit')

# A recoverable shell particle in r=1 hard-retention mode is not part of the
# receiver reservoir.  It is handled kinematically in pass 3.  For r<1 the old
# behavior is untouched so transmitted/evaporating particles are not recaptured.
replace_once(
'''        if (!d.crossing) {\n            // Receiver statistics for the affine bulk reaction used in pass 3.\n            // One additional atomic (K) versus x9y; no new particle pass.\n            atomic_add_double_0400(&recvM[c], m);\n            atomic_add_double_0400(&recvPx[c], m * vx);\n            atomic_add_double_0400(&recvPy[c], m * vy);\n            atomic_add_double_0400(&recvK[c], 0.5 * m * (vx * vx + vy * vy));\n            continue;\n        }\n''',
'''        if (!d.crossing) {\n            // x10b: r=1 means an impermeable kinetic interface.  A particle\n            // already on the pointwise outer side but still connected to a\n            // direct bulk bath is reserved for hard positional recovery in\n            // pass 3 and must not contaminate the reaction receiver pool.\n            const bool hardShellCapture = reflectionFraction >= 1.0 && d.shellRecoverable;\n            if (!hardShellCapture) {\n                atomic_add_double_0400(&recvM[c], m);\n                atomic_add_double_0400(&recvPx[c], m * vx);\n                atomic_add_double_0400(&recvPy[c], m * vy);\n                atomic_add_double_0400(&recvK[c], 0.5 * m * (vx * vx + vy * vy));\n            }\n            continue;\n        }\n''',
'classify receiver exclusion')

# Ensure shell capture is serviced by the existing third particle pass.  It is
# active only for r=1; partial reflection keeps x10a semantics for evaporation.
replace_once(
'''        const bool donor = d.crossing && d.reflect;\n        const bool receiver = !d.crossing && reactionActive[c] > 0.5;\n        if (!donor && !receiver) continue;\n''',
'''        const bool hardShellCapture = reflectionFraction >= 1.0 && d.shellRecoverable;\n        const bool donor = d.crossing && d.reflect;\n        const bool receiver = !d.crossing && !hardShellCapture && reactionActive[c] > 0.5;\n        if (!donor && !receiver && !hardShellCapture) continue;\n''',
'apply hard shell selection')

replace_once(
'''        } else {\n            // Conservative reaction to non-crossing receiver particles in the\n            // bath cell. Coefficients were prepared by the O(Ncell) kernel.\n''',
'''        } else if (receiver) {\n            // Conservative reaction to non-crossing receiver particles in the\n            // bath cell. Coefficients were prepared by the O(Ncell) kernel.\n''',
'receiver else-if')

# Insert positional hard retention after donor/receiver velocity choice and
# before writing the final velocity.  Cost is O(N_shell), four bilinear samples
# only when the natural/reflected endpoint is still outside; no extra kernel.
anchor = '''        particles.vx[i] = newVx;\n        particles.vy[i] = newVy;\n'''
insert = r'''        // 0493x10b hard bulk retention for r=1 only.
        //
        // A shell particle is pointwise alpha(x0)<0.5 but has a direct bulk
        // bath.  After any donor velocity reflection above, first let it return
        // naturally if its ordinary streamed endpoint is already inside.  If
        // not, bracket alpha=0.5 on the short segment from that endpoint to the
        // direct bulk-cell centre, then mirror the endpoint to the interior
        // side.  This changes position only and intentionally leaves the x9z
        // impulse/energy reaction untouched for later work.
        if (hardShellCapture) {
            if (audit) atomicAdd(&audit->shellHardRetentionCandidates, 1ull);

            const double x0p = particles.x[i];
            const double y0p = particles.y[i];
            const double xCandidate = x0p + newVx * dt;
            const double yCandidate = y0p + newVy * dt;
            double aCandidate = 0.0;
            const bool candidateSampled = q6_x9t_sample_alpha(
                alpha, xCandidate, yCandidate,
                nx, ny, lx, ly, periodicX, periodicY, &aCandidate);

            if (candidateSampled && aCandidate >= 0.5) {
                if (audit) atomicAdd(&audit->shellHardRetentionAlreadyInside, 1ull);
            } else {
                bool fallback = !candidateSampled;
                double targetX = xCandidate;
                double targetY = yCandidate;
                const int b = d.bathCell;

                if (b >= 0 && b < cells.numCells) {
                    const int bi = b % nx;
                    const int bj = b / nx;
                    const double dx = lx / static_cast<double>(nx);
                    const double dy = ly / static_cast<double>(ny);
                    double anchorX = (static_cast<double>(bi) + 0.5) * dx;
                    double anchorY = (static_cast<double>(bj) + 0.5) * dy;

                    // Use the nearest periodic image so the recovery segment is
                    // local even when an interface crosses a periodic seam.
                    if (periodicX) {
                        double dd = anchorX - xCandidate;
                        if (dd >  0.5 * lx) anchorX -= lx;
                        if (dd < -0.5 * lx) anchorX += lx;
                    }
                    if (periodicY) {
                        double dd = anchorY - yCandidate;
                        if (dd >  0.5 * ly) anchorY -= ly;
                        if (dd < -0.5 * ly) anchorY += ly;
                    }

                    double aAnchor = 0.0;
                    const bool anchorInside = q6_x9t_sample_alpha(
                        alpha, anchorX, anchorY,
                        nx, ny, lx, ly, periodicX, periodicY, &aAnchor) &&
                        aAnchor >= 0.5;

                    if (candidateSampled && aCandidate < 0.5 && anchorInside) {
                        // lo=outside, hi=inside.  Four iterations match x10a
                        // and are enough because the anchor is one direct bulk
                        // cell away.  Mirror the candidate by approximately the
                        // same normal distance across the located crossing;
                        // clamp at the bath centre if that mirror would overshoot.
                        double lo = 0.0;
                        double hi = 1.0;
                        for (int it = 0; it < 4; ++it) {
                            const double mid = 0.5 * (lo + hi);
                            const double xm = xCandidate + mid * (anchorX - xCandidate);
                            const double ym = yCandidate + mid * (anchorY - yCandidate);
                            double am = 0.5;
                            if (!q6_x9t_sample_alpha(alpha, xm, ym,
                                                     nx, ny, lx, ly,
                                                     periodicX, periodicY, &am) ||
                                !isfinite(am)) {
                                fallback = true;
                                break;
                            }
                            if (am >= 0.5) hi = mid;
                            else lo = mid;
                        }

                        if (!fallback) {
                            const double tMirror = fmin(1.0, 2.0 * hi);
                            targetX = xCandidate + tMirror * (anchorX - xCandidate);
                            targetY = yCandidate + tMirror * (anchorY - yCandidate);
                            double aTarget = 0.0;
                            if (!q6_x9t_sample_alpha(alpha, targetX, targetY,
                                                     nx, ny, lx, ly,
                                                     periodicX, periodicY, &aTarget) ||
                                !(aTarget >= 0.5)) {
                                // The alpha profile need not be monotone along
                                // a curved-cell diagonal.  The bulk centre is a
                                // guaranteed local fallback by construction.
                                targetX = anchorX;
                                targetY = anchorY;
                                fallback = true;
                            }
                        } else {
                            targetX = anchorX;
                            targetY = anchorY;
                        }
                    } else if (anchorInside) {
                        targetX = anchorX;
                        targetY = anchorY;
                        fallback = true;
                    } else {
                        // Should be unreachable for shellRecoverable; leave the
                        // state untouched and make the contract failure visible.
                        fallback = true;
                    }
                } else {
                    fallback = true;
                }

                double aFinal = 0.0;
                const bool finalInside = q6_x9t_sample_alpha(
                    alpha, targetX, targetY,
                    nx, ny, lx, ly, periodicX, periodicY, &aFinal) &&
                    aFinal >= 0.5;

                if (finalInside) {
                    // Store the pre-stream location that makes the ordinary
                    // downstream streaming land exactly at the recovered target.
                    const double corrX = targetX - xCandidate;
                    const double corrY = targetY - yCandidate;
                    particles.x[i] = x0p + corrX;
                    particles.y[i] = y0p + corrY;
                    if (audit) {
                        atomicAdd(&audit->shellHardRetentionCorrections, 1ull);
                        if (fallback)
                            atomicAdd(&audit->shellHardRetentionFallbacks, 1ull);
                        atomic_add_double_0400(&audit->shellHardRetentionCorrectionAbsSum,
                                              sqrt(corrX * corrX + corrY * corrY));
                    }
                } else if (audit && fallback) {
                    atomicAdd(&audit->shellHardRetentionFallbacks, 1ull);
                }
            }

            if (audit) {
                double aVerify = 0.0;
                if (!q6_x9t_sample_alpha(alpha,
                        particles.x[i] + newVx * dt,
                        particles.y[i] + newVy * dt,
                        nx, ny, lx, ly, periodicX, periodicY, &aVerify) ||
                    !(aVerify >= 0.5))
                    atomicAdd(&audit->shellHardRetentionFinalOutside, 1ull);
            }
        }

        particles.vx[i] = newVx;
        particles.vy[i] = newVy;
'''
replace_once(anchor, insert, 'apply shell retention insertion')

# CSV plumbing.
replace_once(
'''               "crossingPointNormalFallbacks,endpointSealCorrections,"\n               "endpointSealSampleFallbacks,appliedInteriorFinalOutside,"\n               "convertedParticles,individualDonorReflections,receiverCorrectedParticles,"\n''',
'''               "crossingPointNormalFallbacks,endpointSealCorrections,"\n               "endpointSealSampleFallbacks,appliedInteriorFinalOutside,"\n               "shellRecoverableParticles,shellHardRetentionCandidates,"\n               "shellHardRetentionAlreadyInside,shellHardRetentionCorrections,"\n               "shellHardRetentionFallbacks,shellHardRetentionFinalOutside,"\n               "convertedParticles,individualDonorReflections,receiverCorrectedParticles,"\n''',
'CSV shell counter header')
replace_once(
'''               "endpointSealCorrectionAbsMean,reactionEnergyResidualAbs,reactionDeltaUMagnitudeMean,"\n''',
'''               "endpointSealCorrectionAbsMean,shellHardRetentionCorrectionAbsMean,"\n               "reactionEnergyResidualAbs,reactionDeltaUMagnitudeMean,"\n''',
'CSV shell correction header')
replace_once(
'''    const double meanReactionDU = a.reactionActiveCells > 0ull ?\n''',
'''    const double meanShellRetentionCorr = a.shellHardRetentionCorrections > 0ull ?\n        a.shellHardRetentionCorrectionAbsSum / static_cast<double>(a.shellHardRetentionCorrections) : 0.0;\n    const double meanReactionDU = a.reactionActiveCells > 0ull ?\n''',
'CSV mean shell correction')
replace_once(
'''        << a.endpointSealSampleFallbacks << ',' << a.appliedInteriorFinalOutside << ','\n        << a.convertedParticles << ','\n''',
'''        << a.endpointSealSampleFallbacks << ',' << a.appliedInteriorFinalOutside << ','\n        << a.shellRecoverableParticles << ',' << a.shellHardRetentionCandidates << ','\n        << a.shellHardRetentionAlreadyInside << ',' << a.shellHardRetentionCorrections << ','\n        << a.shellHardRetentionFallbacks << ',' << a.shellHardRetentionFinalOutside << ','\n        << a.convertedParticles << ','\n''',
'CSV shell counter row')
replace_once(
'''        << meanSealCorr << ',' << a.reactionEnergyResidualAbsSum << ',' << meanReactionDU << ',' << meanLambdaDev << ','\n''',
'''        << meanSealCorr << ',' << meanShellRetentionCorr << ','\n        << a.reactionEnergyResidualAbsSum << ',' << meanReactionDU << ',' << meanLambdaDev << ','\n''',
'CSV shell correction row')
replace_once(
'''           "interior-reflected-endpoint-alpha-ge-half-seal;no-merge-no-resampling;"\n           "same-three-x9-particle-passes-plus-one-cell-kernel;deterministic-hash" << '\\n';\n''',
'''           "interior-reflected-endpoint-alpha-ge-half-seal;"\n           "r1-shell-hard-retention-direct-bulk-mirror;no-merge-no-resampling;"\n           "same-three-x9-particle-passes-plus-one-cell-kernel;deterministic-hash" << '\\n';\n''',
'CSV contract tag')

SRC.write_text(text)

# Runner: same high-temperature static vacuum drop as x10a, r=1 only.
run = ROOT / 'scripts/run_0493x10b_hard_bulk_retention.sh'
run.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export TARGET=wall
export RUN_ROOT="${RUN_ROOT:-runs/0493x10b_hard_bulk_retention}"
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
  echo "[0493x10b-suite] ERROR this qualification is intentionally r=1 hard retention" >&2
  exit 2
fi

printf '%s\n' \
  "[0493x10b-suite] HARD RETENTION ONLY: prevent phase-A particles from remaining outside bulk" \
  "[0493x10b-suite] x10a true interior endpoint seal retained" \
  "[0493x10b-suite] r=1 recoverable shell endpoint -> direct bulk bracket/mirror in existing pass 3" \
  "[0493x10b-suite] no new particle pass; no halo search; no merge/resampling" \
  "[0493x10b-suite] x9z velocity/reaction law intentionally unchanged for later conservation work" \
  "[0493x10b-suite] kBT=$KBT LiveVis=$LIVE_VIS_ENABLE filteredRecording=$FILTERED_RECORDING_ENABLE"

bash scripts/run_0493x9s_splash.sh
CSV="$RUN_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv"
[[ -f "$CSV" ]] || { echo "[0493x10b-suite] ERROR missing $CSV" >&2; exit 2; }
python3 scripts/analyze_0493x10b_hard_bulk_retention.py "$CSV"
''')
run.chmod(0o755)

an = ROOT / 'scripts/analyze_0493x10b_hard_bulk_retention.py'
an.write_text(r'''#!/usr/bin/env python3
import csv, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: analyze_0493x10b_hard_bulk_retention.py <cuda_phase_kinetic_crossing_0493x9z.csv>')
path = Path(sys.argv[1])
with path.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10b-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def rat(a,b): return a/b if b else 0.0

last = rows[-1]
interior = isum('interiorCrossings')
final_interior_out = isum('appliedInteriorFinalOutside')
recoverable = isum('shellRecoverableParticles')
candidates = isum('shellHardRetentionCandidates')
already = isum('shellHardRetentionAlreadyInside')
corrected = isum('shellHardRetentionCorrections')
fallbacks = isum('shellHardRetentionFallbacks')
final_shell_out = isum('shellHardRetentionFinalOutside')
outer0, outer1 = I(rows[0],'phaseAOuterCellParticles'), I(last,'phaseAOuterCellParticles')
shell0, shell1 = I(rows[0],'shellParticles'), I(last,'shellParticles')
deep0, deep1 = I(rows[0],'deepOuterParticles'), I(last,'deepOuterParticles')
maxdp = max(maxabs('deltaPx'), maxabs('deltaPy'))
maxde = maxabs('deltaKineticEnergy')

print('===== 0493x10b HARD BULK RETENTION =====')
print(f'file={path} rows={len(rows)} lastStep={last.get("step","?")}')
print('--- x10a interior contract ---')
print(f'interiorCrossings={interior} finalOutside={final_interior_out}/{interior} ({rat(final_interior_out,interior):.6%})')
print('--- recoverable shell hard retention (r=1) ---')
print(f'shellRecoverable={recoverable} candidates={candidates}')
print(f'alreadyNaturallyInside={already} corrected={corrected} fallbacks={fallbacks}')
print(f'shellHardRetentionFinalOutside={final_shell_out}/{candidates} ({rat(final_shell_out,candidates):.6%})')
print('--- halo outcome ---')
print(f'outer first={outer0} last={outer1} growth={outer1-outer0:+d}')
print(f'shell first={shell0} last={shell1} growth={shell1-shell0:+d}')
print(f'deepOuter first={deep0} last={deep1} growth={deep1-deep0:+d}')
print('--- unchanged reaction audit (not a pass criterion) ---')
print(f'max|deltaP|={maxdp:.6e} max|deltaKE|={maxde:.6e} lastMeanLambdaDev={F(last,"reactionLambdaDeviationAbsMean"):.6e}')
geometry_ok = final_interior_out == 0 and final_shell_out == 0
retention_ok = deep1 == deep0 == 0
print('hardGeometryContract=' + ('PASS' if geometry_ok else 'FAIL'))
print('bulkRetentionOutcome=' + ('PASS' if retention_ok else 'FAIL'))
''')
an.chmod(0o755)

chk = ROOT / 'scripts/check_0493x10b_hard_retention_math.py'
chk.write_text(r'''#!/usr/bin/env python3
import math

def alpha(x):
    # synthetic 1-D interface: alpha>=0.5 for x<=0.5
    return 1.0-x

def recover(candidate, anchor, niter=4):
    assert alpha(candidate) < 0.5 and alpha(anchor) >= 0.5
    lo, hi = 0.0, 1.0
    for _ in range(niter):
        mid = 0.5*(lo+hi)
        x = candidate + mid*(anchor-candidate)
        if alpha(x) >= 0.5: hi = mid
        else: lo = mid
    t = min(1.0, 2.0*hi)
    x = candidate + t*(anchor-candidate)
    if alpha(x) < 0.5: x = anchor
    return x

worst = 0.0
for candidate in (0.5001,0.52,0.60,0.74,0.90):
    for anchor in (0.49,0.40,0.25,0.0):
        if not (candidate > 0.5 and anchor <= 0.5):
            continue
        x = recover(candidate, anchor)
        worst = max(worst, max(0.0, 0.5-alpha(x)))
        if alpha(x) < 0.5:
            raise SystemExit('FAIL recovered endpoint outside')

# Same pre-stream placement identity used by x10a/x10b.
maxerr = 0.0
for x0 in (-1.2,0.0,3.4):
    for v in (-2.1,0.0,4.7):
        for target in (-0.7,0.3,2.2):
            dt=0.002
            corr=target-(x0+v*dt)
            landed=(x0+corr)+v*dt
            maxerr=max(maxerr,abs(landed-target))
print(f'maxRecoveryOutsideDefect={worst:.3e}')
print(f'maxEndpointIdentityError={maxerr:.3e}')
print('status=PASS')
''')
chk.chmod(0o755)

print('[0493x10b-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10b-patch] wrote scripts/run_0493x10b_hard_bulk_retention.sh')
print('[0493x10b-patch] wrote scripts/analyze_0493x10b_hard_bulk_retention.py')
print('[0493x10b-patch] wrote scripts/check_0493x10b_hard_retention_math.py')
