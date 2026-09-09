#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'
if not SRC.exists():
    raise SystemExit(f'[0493x10d-patch] missing {SRC}')

text = SRC.read_text()

required = [
    'hardFinalEndpointChecks',
    'r1-final-post-velocity-endpoint-barrier-radius2-local-anchor',
    'q6_x9z_prepare_receiver_reaction',
    'receiver-affine-translation-plus-thermal-rescale',
]
for token in required:
    if token not in text:
        raise SystemExit(f'[0493x10d-patch] x10c prerequisite missing token: {token}')
if 'analyticConservativeReactionCells' in text:
    raise SystemExit('[0493x10d-patch] x10d already appears applied')


def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10d-patch] {label}: expected one anchor, found {n}')
    text = text.replace(old, new, 1)


def replace_function(start_marker: str, end_marker: str, new_body: str, label: str):
    global text
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'[0493x10d-patch] {label}: start marker not found')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'[0493x10d-patch] {label}: end marker not found')
    if text.find(start_marker, start + 1) >= 0 and text.find(start_marker, start + 1) < end:
        raise SystemExit(f'[0493x10d-patch] {label}: ambiguous start marker')
    text = text[:start] + new_body.rstrip() + '\n\n' + text[end:]

# ---------------------------------------------------------------------------
# Audit additions.  Keep the old columns/counters for backward-readable CSVs;
# x10d appends explicit analytic-reaction diagnostics.
# ---------------------------------------------------------------------------
replace_once(
'''    unsigned long long reactionEnergyFloorCells = 0ull;
    unsigned long long reactionThermalDegenerateCells = 0ull;
''',
'''    unsigned long long reactionEnergyFloorCells = 0ull;
    unsigned long long reactionThermalDegenerateCells = 0ull;
    unsigned long long analyticConservativeReactionCells = 0ull;
    unsigned long long analyticPositiveScaleCells = 0ull;
    unsigned long long analyticInwardCells = 0ull;
    unsigned long long analyticNonInwardPositiveCells = 0ull;
    unsigned long long analyticTrivialCells = 0ull;
    unsigned long long analyticInvalidCells = 0ull;
''',
'audit analytic counters')

replace_once(
'''    double reactionLambdaDeviationAbsSum = 0.0;
};
''',
'''    double reactionLambdaDeviationAbsSum = 0.0;
    double analyticDonorScaleSum = 0.0;
    double analyticDonorScaleAbsFromSpecularSum = 0.0;
};
''',
'audit analytic sums')

# ---------------------------------------------------------------------------
# Pass 2: in hard r=1 mode accumulate A=sum(m g^2) and S=sum(m g n).
# For r<1 retain the old specular-request accumulation unchanged so future
# evaporation experiments are not silently altered by x10d.
# ---------------------------------------------------------------------------
replace_once(
'''                        // Reaction requested from the non-crossing bulk:
                        // J = -sum(delta p donor), DeltaE_receiver = -sum(dE donor).
                        atomic_add_double_0400(&reactionJx[b], -dpx);
                        atomic_add_double_0400(&reactionJy[b], -dpy);
                        atomic_add_double_0400(&donorDeltaE[b], dE);
''',
'''                        if (reflectionFraction >= 1.0) {
                            // 0493x10d hard-r1 analytic conservative mode.
                            // Store the sufficient statistics
                            //   A = sum m g_i^2,
                            //   S = sum m g_i n_i.
                            // They define, together with the receiver barycentre,
                            // the exact non-trivial P/E-conserving reflection root.
                            atomic_add_double_0400(&donorDeltaE[b], m * gn * gn);
                            atomic_add_double_0400(&reactionJx[b], m * gn * d.nx);
                            atomic_add_double_0400(&reactionJy[b], m * gn * d.ny);
                        } else {
                            // Historical r<1 path retained for future evaporation:
                            // J = -sum(delta p donor),
                            // DeltaE_receiver = -sum(dE donor).
                            atomic_add_double_0400(&reactionJx[b], -dpx);
                            atomic_add_double_0400(&reactionJy[b], -dpy);
                            atomic_add_double_0400(&donorDeltaE[b], dE);
                        }
''',
'pass2 analytic sufficient statistics')

# ---------------------------------------------------------------------------
# Replace the O(Ncell) preparation kernel.  r=1 uses the exact analytic family
# with no thermal rescale and no energy floor.  r<1 is kept byte-for-byte in
# physical intent (old delta-u + lambda path).
# ---------------------------------------------------------------------------
new_prepare = r'''// 0493x10d: O(Ncell) preparation between particle passes 2 and 3.
//
// Hard r=1 mode replaces the x9z receiver affine-translation + thermal-rescale
// reaction by one exact collective elastic mode.  For donor i, with its own
// interface normal n_i and the pre-reaction bath mean u_b,
//
//   g_i = (v_i-u_b).n_i > 0,
//   A   = sum m_i g_i^2,
//   S   = sum m_i g_i n_i.
//
// Receivers in the bath cell have mass M_r and mean u_r.  The family
//
//   donor:   dv_i = -a g_i n_i
//   receiver:du_r =  a S / M_r
//
// conserves momentum for every a.  Its total kinetic-energy change is
//
//   dE(a) = a(C-A) + 0.5 a^2 (A+B),
//   B = |S|^2/M_r,  C = (u_r-u_b).S.
//
// Therefore the non-trivial exact root is
//
//   a* = 2(A-C)/(A+B).
//
// No lambda, no thermal-energy floor and no fourth particle pass are needed.
// If the non-trivial root is unavailable/non-positive, x10d deliberately uses
// the trivial exact root a=0; x10c still enforces r=1 positional containment.
// Such cells are audited and are not hidden by a clamp.
__global__ void q6_x9z_prepare_receiver_reaction(
    int numCells,
    double* donorDeltaE,
    double* reactionJx,
    double* reactionJy,
    const double* recvM,
    const double* recvPx,
    const double* recvPy,
    const double* recvK,
    double* reactionLambda,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    double reflectionFraction,
    KineticCrossingAccumulator0493x9x* audit) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= numCells) return;

    // ---------------------------------------------------------------------
    // Historical r<1 branch, retained so x10d does not redefine evaporation.
    // ---------------------------------------------------------------------
    if (reflectionFraction < 1.0) {
        const double dED = donorDeltaE[c];
        const double Jx = reactionJx[c];
        const double Jy = reactionJy[c];
        const double request = fabs(dED) + fabs(Jx) + fabs(Jy);

        donorDeltaE[c] = 0.0;
        reactionJx[c] = 0.0;
        reactionJy[c] = 0.0;
        reactionLambda[c] = 1.0;
        if (!(request > 1.0e-30) || !isfinite(request)) return;

        if (audit) atomicAdd(&audit->reactionActiveCells, 1ull);

        const double mr = recvM[c];
        if (!(mr > 1.0e-14) || !isfinite(mr)) {
            if (audit) atomicAdd(&audit->reactionNoReceiverCells, 1ull);
            return;
        }

        const double urx = recvPx[c] / mr;
        const double ury = recvPy[c] / mr;
        const double kr = recvK[c];
        const double meanK = 0.5 * mr * (urx * urx + ury * ury);
        double krel = kr - meanK;
        const double scale = fmax(1.0, fmax(fabs(kr), fabs(meanK)));
        const double tol = 1.0e-12 * scale;
        if (krel < 0.0 && krel > -tol) krel = 0.0;

        const double dux = Jx / mr;
        const double duy = Jy / mr;
        const double meanDeltaE = urx * Jx + ury * Jy +
            0.5 * (Jx * Jx + Jy * Jy) / mr;

        double target = krel - dED - meanDeltaE;
        double lambda = 1.0;
        double residual = 0.0;
        bool feasible = false;
        if (target < 0.0 && target > -tol) target = 0.0;

        if (krel > tol && target >= 0.0 && isfinite(target)) {
            lambda = sqrt(target / krel);
            feasible = isfinite(lambda);
        } else if (krel <= tol) {
            lambda = 1.0;
            residual = krel - target;
            if (fabs(residual) <= tol) {
                residual = 0.0;
                feasible = true;
            } else if (audit) {
                atomicAdd(&audit->reactionThermalDegenerateCells, 1ull);
            }
        } else {
            lambda = 0.0;
            residual = -target;
            if (audit) atomicAdd(&audit->reactionEnergyFloorCells, 1ull);
        }

        if (!isfinite(lambda)) {
            lambda = 1.0;
            residual = krel - target;
            feasible = false;
            if (audit) atomicAdd(&audit->reactionThermalDegenerateCells, 1ull);
        }

        donorDeltaE[c] = 1.0; // active flag
        reactionJx[c] = dux;
        reactionJy[c] = duy;
        reactionLambda[c] = lambda;

        if (audit) {
            if (feasible) atomicAdd(&audit->reactionFeasibleCells, 1ull);
            atomic_add_double_0400(&audit->reactionEnergyResidualAbsSum, fabs(residual));
            atomic_add_double_0400(&audit->reactionDeltaUMagnitudeSum,
                                   sqrt(dux * dux + duy * duy));
            atomic_add_double_0400(&audit->reactionLambdaDeviationAbsSum,
                                   fabs(lambda - 1.0));
        }
        return;
    }

    // ---------------------------------------------------------------------
    // x10d hard-r1 exact analytic collective reaction.
    // Inputs currently hold A and S; outputs reuse the same buffers as
    // activeFlag, receiver delta-u and donor scale a.
    // ---------------------------------------------------------------------
    const double A = donorDeltaE[c];
    const double Sx = reactionJx[c];
    const double Sy = reactionJy[c];
    const double request = fabs(A) + fabs(Sx) + fabs(Sy);

    donorDeltaE[c] = 0.0;   // inactive by default
    reactionJx[c] = 0.0;    // receiver du_x
    reactionJy[c] = 0.0;    // receiver du_y
    reactionLambda[c] = 0.0; // x10d donor scale a (NOT lambda) in hard r=1
    if (!(request > 1.0e-30) || !isfinite(request)) return;

    // Mark the reaction cell active even when the exact trivial root a=0 is
    // selected.  Donor and receiver pass-3 decisions remain deterministic.
    donorDeltaE[c] = 1.0;
    if (audit) {
        atomicAdd(&audit->reactionActiveCells, 1ull);
        atomicAdd(&audit->analyticConservativeReactionCells, 1ull);
    }

    const double mr = recvM[c];
    const double mb = totalM[c];
    if (!(mr > 1.0e-14) || !isfinite(mr)) {
        if (audit) {
            atomicAdd(&audit->reactionNoReceiverCells, 1ull);
            atomicAdd(&audit->analyticTrivialCells, 1ull);
        }
        return; // a=0: exact no-op root
    }
    if (!(mb > 1.0e-14) || !isfinite(mb) ||
        !isfinite(totalPx[c]) || !isfinite(totalPy[c])) {
        if (audit) {
            atomicAdd(&audit->analyticTrivialCells, 1ull);
            atomicAdd(&audit->analyticInvalidCells, 1ull);
            atomicAdd(&audit->reactionThermalDegenerateCells, 1ull);
        }
        return;
    }

    const double urx = recvPx[c] / mr;
    const double ury = recvPy[c] / mr;
    const double ubx = totalPx[c] / mb;
    const double uby = totalPy[c] / mb;

    const double B = (Sx * Sx + Sy * Sy) / mr;
    const double C = (urx - ubx) * Sx + (ury - uby) * Sy;
    const double denom = A + B;
    const double numer = 2.0 * (A - C);

    bool valid = isfinite(A) && A >= 0.0 &&
                 isfinite(B) && B >= 0.0 &&
                 isfinite(C) && isfinite(denom) && denom > 1.0e-30 &&
                 isfinite(numer);
    double a = valid ? numer / denom : 0.0;

    // Do not clamp a: a clamp would destroy exact energy conservation.
    // A non-positive/non-finite non-trivial root is replaced by the other
    // exact root, a=0, and exposed explicitly in diagnostics.
    if (!(a > 0.0) || !isfinite(a)) {
        a = 0.0;
        if (audit) {
            atomicAdd(&audit->analyticTrivialCells, 1ull);
            if (!valid || !isfinite(numer / denom))
                atomicAdd(&audit->analyticInvalidCells, 1ull);
        }
        return;
    }

    const double dux = a * Sx / mr;
    const double duy = a * Sy / mr;
    if (!isfinite(dux) || !isfinite(duy)) {
        reactionLambda[c] = 0.0;
        if (audit) {
            atomicAdd(&audit->analyticTrivialCells, 1ull);
            atomicAdd(&audit->analyticInvalidCells, 1ull);
        }
        return;
    }

    reactionJx[c] = dux;
    reactionJy[c] = duy;
    reactionLambda[c] = a;

    // Algebraic residual of the exact kinetic-energy identity.  This is not a
    // substitute for the actual pass-3 deltaKineticEnergy audit; both are kept.
    const double residual = a * (C - A) + 0.5 * a * a * (A + B);

    if (audit) {
        atomicAdd(&audit->reactionFeasibleCells, 1ull);
        atomicAdd(&audit->analyticPositiveScaleCells, 1ull);
        if (a > 1.0)
            atomicAdd(&audit->analyticInwardCells, 1ull);
        else
            atomicAdd(&audit->analyticNonInwardPositiveCells, 1ull);
        atomic_add_double_0400(&audit->analyticDonorScaleSum, a);
        atomic_add_double_0400(&audit->analyticDonorScaleAbsFromSpecularSum,
                               fabs(a - 2.0));
        atomic_add_double_0400(&audit->reactionEnergyResidualAbsSum,
                               fabs(residual));
        atomic_add_double_0400(&audit->reactionDeltaUMagnitudeSum,
                               sqrt(dux * dux + duy * duy));
        // reactionLambdaDeviationAbsSum intentionally remains zero in r=1:
        // there is no receiver thermal lambda in x10d.
    }
}
'''

replace_function(
    '// 0493x9z: O(Ncell) preparation between particle passes 2 and 3.',
    '__global__ void q6_x9z_apply_individual_reflections(',
    new_prepare,
    'prepare reaction kernel')

# ---------------------------------------------------------------------------
# Pass 3 donor velocity: hard r=1 uses analytic a from the bath cell. r<1
# retains specular factor 2 exactly.
# ---------------------------------------------------------------------------
replace_once(
'''            // x10a keeps the x9z individual specular velocity law, but the
            // normal now comes from the donor's own physical alpha=0.5 crossing.
            // Relative to the same pre-reaction bath reference this preserves
            // the strict x9z invariant (v_new-u_bulk).n_i = -gn < 0.
            newVx = oldVx - 2.0 * gn * d.nx;
            newVy = oldVy - 2.0 * gn * d.ny;
''',
'''            // x10d hard-r1 mode replaces fixed specular factor 2 by the
            // exact cellwise conservative scale a*.  r<1 keeps the historical
            // specular factor so evaporation semantics are unchanged.
            double donorScale = 2.0;
            if (hardR1Containment) {
                donorScale = reactionLambda[b]; // x10d: this buffer stores a*, not lambda
                if (!(donorScale >= 0.0) || !isfinite(donorScale)) donorScale = 0.0;
            }
            newVx = oldVx - donorScale * gn * d.nx;
            newVy = oldVy - donorScale * gn * d.ny;
''',
'donor analytic scale')

# ---------------------------------------------------------------------------
# Receiver velocity: hard r=1 is a uniform translation only.  No lambda and
# therefore no local thermal rescale/floor.  r<1 old path remains untouched.
# ---------------------------------------------------------------------------
replace_once(
'''        } else if (receiver) {
            // Conservative reaction to non-crossing receiver particles in the
            // bath cell. Coefficients were prepared by the O(Ncell) kernel.
            const double mr = recvM[c];
            if (!(mr > 0.0) || !isfinite(mr)) continue;
            const double urx = recvPx[c] / mr;
            const double ury = recvPy[c] / mr;
            const double lambda = reactionLambda[c];
            newVx = urx + reactionDeltaUx[c] + lambda * (oldVx - urx);
            newVy = ury + reactionDeltaUy[c] + lambda * (oldVy - ury);
            if (audit) atomicAdd(&audit->receiverCorrectedParticles, 1ull);
        }
''',
'''        } else if (receiver) {
            const double mr = recvM[c];
            if (!(mr > 0.0) || !isfinite(mr)) continue;
            if (hardR1Containment) {
                // x10d: exact collective reaction.  The receiver only takes
                // the uniform impulse +a*S; its internal/thermal velocities
                // are untouched.  Exact energy closure is obtained by solving
                // the donor amplitude a jointly, not by a thermal lambda.
                newVx = oldVx + reactionDeltaUx[c];
                newVy = oldVy + reactionDeltaUy[c];
            } else {
                // Historical r<1 reaction retained for evaporation studies.
                const double urx = recvPx[c] / mr;
                const double ury = recvPy[c] / mr;
                const double lambda = reactionLambda[c];
                newVx = urx + reactionDeltaUx[c] + lambda * (oldVx - urx);
                newVy = ury + reactionDeltaUy[c] + lambda * (oldVy - ury);
            }
            if (audit) atomicAdd(&audit->receiverCorrectedParticles, 1ull);
        }
''',
'receiver no-lambda hard-r1')

# ---------------------------------------------------------------------------
# Prepare launch gets total bath moments and r.
# ---------------------------------------------------------------------------
replace_once(
'''        ws.kineticRefNx0493x9u.data(),
        ws.kineticRefNy0493x9u.data(),
        auditDev);
''',
'''        ws.kineticRefNx0493x9u.data(),
        ws.kineticRefNy0493x9u.data(),
        ws.kineticTotalM0493x9t.data(),
        ws.kineticTotalPx0493x9t.data(),
        ws.kineticTotalPy0493x9t.data(),
        r,
        auditDev);
''',
'prepare launch total moments and r')

# ---------------------------------------------------------------------------
# CSV diagnostics: append explicit analytic columns without changing earlier
# column names, so x10c tools remain readable.
# ---------------------------------------------------------------------------
replace_once(
'''               "reactionEnergyResidualAbs,reactionDeltaUMagnitudeMean,"
               "reactionLambdaDeviationAbsMean,contract\\n";
''',
'''               "reactionEnergyResidualAbs,reactionDeltaUMagnitudeMean,"
               "reactionLambdaDeviationAbsMean,"
               "analyticConservativeReactionCells,analyticPositiveScaleCells,"
               "analyticInwardCells,analyticNonInwardPositiveCells,"
               "analyticTrivialCells,analyticInvalidCells,"
               "analyticDonorScaleMean,analyticDonorScaleAbsFromSpecularMean,contract\\n";
''',
'CSV analytic header')

replace_once(
'''    const double meanLambdaDev = a.reactionActiveCells > 0ull ?
        a.reactionLambdaDeviationAbsSum / static_cast<double>(a.reactionActiveCells) : 0.0;
''',
'''    const double meanLambdaDev = a.reactionActiveCells > 0ull ?
        a.reactionLambdaDeviationAbsSum / static_cast<double>(a.reactionActiveCells) : 0.0;
    const double meanAnalyticScale = a.analyticPositiveScaleCells > 0ull ?
        a.analyticDonorScaleSum / static_cast<double>(a.analyticPositiveScaleCells) : 0.0;
    const double meanAnalyticScaleAbsFrom2 = a.analyticPositiveScaleCells > 0ull ?
        a.analyticDonorScaleAbsFromSpecularSum /
            static_cast<double>(a.analyticPositiveScaleCells) : 0.0;
''',
'CSV analytic means')

replace_once(
'''        << a.reactionEnergyResidualAbsSum << ',' << meanReactionDU << ',' << meanLambdaDev << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'''        << a.reactionEnergyResidualAbsSum << ',' << meanReactionDU << ',' << meanLambdaDev << ','
        << a.analyticConservativeReactionCells << ',' << a.analyticPositiveScaleCells << ','
        << a.analyticInwardCells << ',' << a.analyticNonInwardPositiveCells << ','
        << a.analyticTrivialCells << ',' << a.analyticInvalidCells << ','
        << meanAnalyticScale << ',' << meanAnalyticScaleAbsFrom2 << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'CSV analytic row')

replace_once(
'''           "individual-donor-crossing-point-normal-reflection;per-cell-impulse-energy-reaction;"
           "receiver-affine-translation-plus-thermal-rescale;"
''',
'''           "individual-donor-crossing-point-normal-reflection;"
           "r1-analytic-collective-exact-momentum-energy-reaction;"
           "r1-no-receiver-thermal-lambda-no-energy-floor;rlt1-legacy-reaction-retained;"
''',
'CSV x10d contract tag')

SRC.write_text(text)

# ---------------------------------------------------------------------------
# Mathematical self-check.
# ---------------------------------------------------------------------------
chk = ROOT / 'scripts/check_0493x10d_analytic_reaction_math.py'
chk.write_text(r'''#!/usr/bin/env python3
import math, random

rng = random.Random(493104)
max_dp = 0.0
max_de = 0.0
max_formula_res = 0.0
min_a = float('inf')
max_a = 0.0
non_inward = 0
positive = 0

for _ in range(20000):
    # Independent bath reference and receiver set: this is deliberately more
    # general than the same-cell partition special case.
    ub = (rng.uniform(-1,1), rng.uniform(-1,1))
    ur = (ub[0] + rng.uniform(-0.5,0.5), ub[1] + rng.uniform(-0.5,0.5))
    mr = rng.uniform(0.2, 50.0)

    donors = []
    A = 0.0
    Sx = Sy = 0.0
    for _j in range(rng.randint(1,8)):
        th = rng.uniform(-math.pi, math.pi)
        n = (math.cos(th), math.sin(th))
        g = rng.uniform(1e-4, 2.0)
        tang = rng.uniform(-2.0,2.0)
        t = (-n[1], n[0])
        v = (ub[0] + g*n[0] + tang*t[0],
             ub[1] + g*n[1] + tang*t[1])
        m = rng.uniform(0.1, 3.0)
        donors.append((m,v,n,g))
        A += m*g*g
        Sx += m*g*n[0]
        Sy += m*g*n[1]

    B = (Sx*Sx+Sy*Sy)/mr
    C = (ur[0]-ub[0])*Sx + (ur[1]-ub[1])*Sy
    a = 2.0*(A-C)/(A+B)
    if not (a > 0.0 and math.isfinite(a)):
        # production fallback is the exact trivial root a=0
        a = 0.0
    else:
        positive += 1
        min_a = min(min_a,a)
        max_a = max(max_a,a)
        if a <= 1.0:
            non_inward += 1

    du = (a*Sx/mr, a*Sy/mr)

    dp_x = dp_y = 0.0
    de = 0.0
    for m,v,n,g in donors:
        vp = (v[0]-a*g*n[0], v[1]-a*g*n[1])
        dp_x += m*(vp[0]-v[0])
        dp_y += m*(vp[1]-v[1])
        de += 0.5*m*((vp[0]*vp[0]+vp[1]*vp[1])-(v[0]*v[0]+v[1]*v[1]))

    # Represent receiver pool only through its COM change. Internal energy is
    # unchanged by the x10d uniform receiver translation.
    dp_x += mr*du[0]
    dp_y += mr*du[1]
    de += mr*(ur[0]*du[0] + ur[1]*du[1]) + 0.5*mr*(du[0]*du[0]+du[1]*du[1])

    formula_res = a*(C-A) + 0.5*a*a*(A+B)
    max_dp = max(max_dp, abs(dp_x), abs(dp_y))
    max_de = max(max_de, abs(de))
    max_formula_res = max(max_formula_res, abs(formula_res))

print(f'maxMomentumResidual={max_dp:.3e}')
print(f'maxEnergyResidual={max_de:.3e}')
print(f'maxFormulaResidual={max_formula_res:.3e}')
print(f'positiveRootCases={positive}')
print(f'nonInwardPositiveRootCases={non_inward}')
if positive:
    print(f'positiveScaleRange=[{min_a:.6g},{max_a:.6g}]')
if max_dp > 5e-12 or max_de > 5e-11 or max_formula_res > 5e-12:
    raise SystemExit('status=FAIL')
print('status=PASS')
''')
chk.chmod(0o755)

# ---------------------------------------------------------------------------
# Qualification analyzer.
# ---------------------------------------------------------------------------
an = ROOT / 'scripts/analyze_0493x10d_analytic_reaction.py'
an.write_text(r'''#!/usr/bin/env python3
import csv, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: analyze_0493x10d_analytic_reaction.py <cuda_phase_kinetic_crossing_0493x9z.csv>')
p = Path(sys.argv[1])
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10d-check] ERROR empty CSV')

required = [
    'analyticConservativeReactionCells','analyticPositiveScaleCells',
    'analyticInwardCells','analyticNonInwardPositiveCells',
    'analyticTrivialCells','analyticInvalidCells',
    'analyticDonorScaleMean','analyticDonorScaleAbsFromSpecularMean',
    'hardFinalEndpointOutsideAfter','hardFinalLocalAnchorMisses',
]
missing = [k for k in required if k not in rows[0]]
if missing:
    raise SystemExit('[0493x10d-check] ERROR missing columns: ' + ','.join(missing))

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def wmean(mean_key, count_key):
    n = sum(I(r,count_key) for r in rows)
    return (sum(F(r,mean_key)*I(r,count_key) for r in rows)/n) if n else 0.0

a_cells = isum('analyticConservativeReactionCells')
pos = isum('analyticPositiveScaleCells')
inward = isum('analyticInwardCells')
nonin = isum('analyticNonInwardPositiveCells')
triv = isum('analyticTrivialCells')
invalid = isum('analyticInvalidCells')
no_recv = isum('reactionNoReceiverCells')
floors = isum('reactionEnergyFloorCells')
degen = isum('reactionThermalDegenerateCells')
still_out = isum('appliedStillOutwardRelative')
applied = isum('appliedReflections')
out_after = isum('hardFinalEndpointOutsideAfter')
anchor_miss = isum('hardFinalLocalAnchorMisses')
deep_max = max(I(r,'deepOuterParticles') for r in rows)
max_dp = max(maxabs('deltaPx'), maxabs('deltaPy'))
max_de = maxabs('deltaKineticEnergy')
formula_res = maxabs('reactionEnergyResidualAbs')
mean_a = wmean('analyticDonorScaleMean','analyticPositiveScaleCells')
mean_da2 = wmean('analyticDonorScaleAbsFromSpecularMean','analyticPositiveScaleCells')
last = rows[-1]

print('===== 0493x10d ANALYTIC CONSERVATIVE HARD-r1 REACTION =====')
print(f'file={p} rows={len(rows)} lastStep={last.get("step","?")}')
print('--- analytic cell reaction ---')
print(f'cells={a_cells} positiveScale={pos} trivialExactRoot={triv} invalid={invalid} noReceiver={no_recv}')
print(f'inward(a>1)={inward} nonInwardPositive(0<a<=1)={nonin}')
print(f'meanA={mean_a:.9g} mean|a-2|={mean_da2:.9g}')
print(f'legacyEnergyFloorCells={floors} legacyThermalDegenerateCells={degen}')
print('--- actual pass-3 conservation ---')
print(f'max|deltaP|={max_dp:.12e}')
print(f'max|deltaKE|={max_de:.12e}')
print(f'maxAnalyticFormulaResidualAbsSum={formula_res:.12e}')
print('--- kinetic interface / hard barrier ---')
print(f'appliedStillOutwardRelative={still_out}/{applied}')
print(f'hardFinalOutsideAfter={out_after} anchorMisses={anchor_miss} maxDeepOuter={deep_max}')

# These are absolute reduced-unit tolerances.  Prior x9/x10 roundoff audits are
# around 1e-13; 1e-8 leaves ample room for atomic reduction ordering while
# still sharply separating the old O(1..100) reaction defects.
cons = max_dp <= 1e-8 and max_de <= 1e-8
geom = out_after == 0 and anchor_miss == 0
analytic = invalid == 0 and floors == 0
inw = nonin == 0 and triv == 0 and still_out == 0
print('conservationContract=' + ('PASS' if cons else 'FAIL'))
print('hardRetentionContract=' + ('PASS' if geom else 'FAIL'))
print('analyticNoFloorContract=' + ('PASS' if analytic else 'FAIL'))
print('inwardnessContract=' + ('PASS' if inw else 'FAIL'))
if cons and geom and analytic and inw:
    print('qualification=PASS')
elif cons and geom and analytic:
    print('qualification=PASS_P_E_RETENTION__INWARDNESS_NEEDS_REVIEW')
else:
    print('qualification=FAIL')
''')
an.chmod(0o755)

# ---------------------------------------------------------------------------
# Runner: same physical drop, r=1 only.  Start short; if it passes, the same
# runner can be extended without changing physics.
# ---------------------------------------------------------------------------
run = ROOT / 'scripts/run_0493x10d_analytic_conservative_reaction.sh'
run.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export TARGET=wall
export RUN_ROOT="${RUN_ROOT:-runs/0493x10d_analytic_conservative_reaction}"
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
  echo "[0493x10d-suite] ERROR x10d analytic qualification is intentionally hard-r1 only" >&2
  exit 2
fi

printf '%s\n' \
  "[0493x10d-suite] HARD-r1 analytic collective reaction: exact cellwise momentum+kinetic-energy root" \
  "[0493x10d-suite] donor dv=-a*g*n; receiver uniform du=a*S/Mr; no receiver thermal lambda" \
  "[0493x10d-suite] no energy floor; non-positive analytic root -> exact trivial a=0 (audited, not clamped)" \
  "[0493x10d-suite] x10a/x10b/x10c retention retained; no new particle pass; r<1 legacy path retained" \
  "[0493x10d-suite] kBT=$KBT LiveVis=$LIVE_VIS_ENABLE filteredRecording=$FILTERED_RECORDING_ENABLE"

bash scripts/run_0493x9s_splash.sh
CSV="$RUN_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv"
[[ -f "$CSV" ]] || { echo "[0493x10d-suite] ERROR missing $CSV" >&2; exit 2; }
python3 scripts/analyze_0493x10d_analytic_reaction.py "$CSV"
''')
run.chmod(0o755)

print('[0493x10d-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10d-patch] wrote scripts/check_0493x10d_analytic_reaction_math.py')
print('[0493x10d-patch] wrote scripts/analyze_0493x10d_analytic_reaction.py')
print('[0493x10d-patch] wrote scripts/run_0493x10d_analytic_conservative_reaction.sh')
