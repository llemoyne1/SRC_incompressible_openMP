#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'
if not SRC.exists():
    raise SystemExit(f'[0493x10a-patch] missing {SRC}')
text = SRC.read_text()


def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10a-patch] {label}: expected 1 anchor, found {n}')
    text = text.replace(old, new, 1)

# 1) Minimal audit extension: keep the existing x9z CSV and append x10a geometry fields.
replace_once(
'''    unsigned long long appliedStillOutwardRelative = 0ull;\n    unsigned long long appliedInteriorPredictedOutside = 0ull;\n    unsigned long long convertedParticles = 0ull;\n''',
'''    unsigned long long appliedStillOutwardRelative = 0ull;\n    unsigned long long appliedInteriorPredictedOutside = 0ull;\n    unsigned long long crossingPointNormalFallbacks = 0ull;\n    unsigned long long endpointSealCorrections = 0ull;\n    unsigned long long endpointSealSampleFallbacks = 0ull;\n    unsigned long long appliedInteriorFinalOutside = 0ull;\n    unsigned long long convertedParticles = 0ull;\n''',
'audit counters')
replace_once(
'''    double deltaKineticEnergy = 0.0;\n    double positionCorrectionAbsSum = 0.0;\n    double reactionEnergyResidualAbsSum = 0.0;\n''',
'''    double deltaKineticEnergy = 0.0;\n    double positionCorrectionAbsSum = 0.0;\n    double endpointSealCorrectionAbsSum = 0.0;\n    double reactionEnergyResidualAbsSum = 0.0;\n''',
'audit doubles')

# 2) Pointwise normal from the same bilinear physical alpha used by x9y point sampling.
anchor = '''struct KineticCrossingDecision0493x9t {\n'''
helper = r'''
// 0493x10a: value-consistent pointwise normal of the *physical* x6c alpha.
// The interpolation is exactly the bilinear cell-centre interpolation used by
// q6_x9t_sample_alpha.  n_AB points from alpha-high A toward alpha-low B.
__device__ __forceinline__ bool q6_x10a_sample_alpha_normal(
    const double* alpha,
    double x,
    double y,
    int nx,
    int ny,
    double lx,
    double ly,
    int periodicX,
    int periodicY,
    double* nxOut,
    double* nyOut) {
    if (!alpha || !nxOut || !nyOut || nx < 1 || ny < 1 || !(lx > 0.0) || !(ly > 0.0))
        return false;
    if (periodicX) {
        x -= floor(x / lx) * lx;
        if (x >= lx) x = 0.0;
    } else if (x < 0.0 || x > lx) {
        return false;
    }
    if (periodicY) {
        y -= floor(y / ly) * ly;
        if (y >= ly) y = 0.0;
    } else if (y < 0.0 || y > ly) {
        return false;
    }

    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);
    const double gx = x / dx - 0.5;
    const double gy = y / dy - 0.5;
    int i0 = static_cast<int>(floor(gx));
    int j0 = static_cast<int>(floor(gy));
    double fx = gx - floor(gx);
    double fy = gy - floor(gy);
    int i1 = i0 + 1;
    int j1 = j0 + 1;

    if (periodicX) {
        i0 = q6_x9t_wrap_index(i0, nx);
        i1 = q6_x9t_wrap_index(i1, nx);
    } else {
        if (i0 < 0) { i0 = 0; i1 = 0; fx = 0.0; }
        if (i1 >= nx) { i0 = nx - 1; i1 = nx - 1; fx = 0.0; }
    }
    if (periodicY) {
        j0 = q6_x9t_wrap_index(j0, ny);
        j1 = q6_x9t_wrap_index(j1, ny);
    } else {
        if (j0 < 0) { j0 = 0; j1 = 0; fy = 0.0; }
        if (j1 >= ny) { j0 = ny - 1; j1 = ny - 1; fy = 0.0; }
    }

    const double a00 = alpha[j0 * nx + i0];
    const double a10 = alpha[j0 * nx + i1];
    const double a01 = alpha[j1 * nx + i0];
    const double a11 = alpha[j1 * nx + i1];
    const double dadx = ((1.0 - fy) * (a10 - a00) + fy * (a11 - a01)) / dx;
    const double dady = ((1.0 - fx) * (a01 - a00) + fx * (a11 - a10)) / dy;
    double nxv = -dadx;
    double nyv = -dady;
    const double ng = sqrt(nxv * nxv + nyv * nyv);
    if (!(ng > 1.0e-14) || !isfinite(ng)) return false;
    nxv /= ng;
    nyv /= ng;
    *nxOut = nxv;
    *nyOut = nyv;
    return true;
}

'''
replace_once(anchor, helper + anchor, 'pointwise-normal insertion')

# 3) Extend crossing decision with a diagnostic fallback bit.
replace_once(
'''    bool pointwiseInteriorOuterCell = false;\n    bool bisectionFallback = false;\n    int bathCell = -1;\n''',
'''    bool pointwiseInteriorOuterCell = false;\n    bool bisectionFallback = false;\n    bool crossingPointNormalFallback = false;\n    int bathCell = -1;\n''',
'decision fallback flag')

# 4) Replace x9y decision function as one semantic unit.  This preserves its
# pointwise alpha classification and shell policy, but resolves the alpha=0.5
# bracket in both particle passes so pass-2 reaction and pass-3 donor kick use
# exactly the same per-donor crossing normal.
start = text.index('__device__ __forceinline__ KineticCrossingDecision0493x9x q6_x9y_decide_crossing(')
end = text.index('\n__global__ void q6_x9z_classify_individual_reflections(', start)
new_func = r'''__device__ __forceinline__ KineticCrossingDecision0493x9x q6_x9y_decide_crossing(
    std::uint64_t i,
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    std::uint32_t phaseAType,
    int nx, int ny, double lx, double ly, double dt,
    int periodicX, int periodicY,
    double reflectionFraction,
    unsigned long long step,
    unsigned long long seed,
    bool resolveCrossingFraction) {
    KineticCrossingDecision0493x9x d{};
    (void)resolveCrossingFraction; // x10a always resolves true interior crossings.
    if (particles.role && particles.role[i] != kParticleRoleFluid) return d;
    if (!particles.type || particles.type[i] != phaseAType) return d;
    const int c = cells.cellId[i];
    if (c < 0 || c >= cells.numCells || !alpha || !totalM || !totalPx || !totalPy) return d;
    const double mc = totalM[c];
    if (!(mc > 0.0) || !isfinite(mc)) return d;

    const double x0 = particles.x[i];
    const double y0 = particles.y[i];
    const double x1 = x0 + particles.vx[i] * dt;
    const double y1 = y0 + particles.vy[i] * dt;
    const bool centerBulk = alpha[c] >= 0.5;

    double a0 = alpha[c];
    double a1 = 1.0;
    bool pointInside = false;
    bool shellSide = false;

    if (centerBulk) {
        if (!q6_x9t_sample_alpha(alpha, x1, y1,
                                 nx, ny, lx, ly, periodicX, periodicY, &a1))
            return d;
        if (!(a1 < 0.5)) return d;
        if (!q6_x9t_sample_alpha(alpha, x0, y0,
                                 nx, ny, lx, ly, periodicX, periodicY, &a0))
            return d;
        if (a0 >= 0.5) pointInside = true;
        else shellSide = true;
    } else {
        if (!q6_x9t_sample_alpha(alpha, x0, y0,
                                 nx, ny, lx, ly, periodicX, periodicY, &a0))
            return d;
        if (a0 >= 0.5) {
            d.pointwiseInteriorOuterCell = true;
            if (!q6_x9t_sample_alpha(alpha, x1, y1,
                                     nx, ny, lx, ly, periodicX, periodicY, &a1))
                return d;
            if (!(a1 < 0.5)) return d;
            pointInside = true;
        } else {
            shellSide = true;
        }
    }

    int bath = c;

    if (pointInside) {
        if (!(a0 >= 0.5) || !(a1 < 0.5)) {
            d.startBelowHalf = true;
            return d;
        }

        // Bracket the physical alpha=0.5 crossing.  lo is always a sampled
        // inside point.  sGamma is a sub-bracket interpolation used only for
        // the pointwise normal; sInside=lo remains the safe reflection anchor.
        double lo = 0.0;
        double hi = 1.0;
        double aLo = a0;
        double aHi = a1;
        bool fallback = false;
        for (int it = 0; it < 4; ++it) {
            const double mid = 0.5 * (lo + hi);
            double am = 0.5;
            if (!q6_x9t_sample_alpha(
                    alpha,
                    x0 + mid * particles.vx[i] * dt,
                    y0 + mid * particles.vy[i] * dt,
                    nx, ny, lx, ly, periodicX, periodicY, &am) ||
                !isfinite(am)) {
                fallback = true;
                break;
            }
            if (am >= 0.5) { lo = mid; aLo = am; }
            else { hi = mid; aHi = am; }
        }

        double sInside = lo;
        double sGamma = 0.5 * (lo + hi);
        if (fallback) {
            d.bisectionFallback = true;
            // x0 was explicitly sampled inside.  Keep the safe anchor there;
            // use the old endpoint interpolation only to estimate the normal.
            sInside = 0.0;
            const double den = a0 - a1;
            if (den > 1.0e-14 && isfinite(den))
                sGamma = fmin(fmax((a0 - 0.5) / den, 0.0), 1.0);
            else
                sGamma = 0.0;
        } else {
            const double den = aLo - aHi;
            if (den > 1.0e-14 && isfinite(den)) {
                const double f = fmin(fmax((aLo - 0.5) / den, 0.0), 1.0);
                sGamma = lo + f * (hi - lo);
            }
        }

        const double xGamma = x0 + sGamma * particles.vx[i] * dt;
        const double yGamma = y0 + sGamma * particles.vy[i] * dt;
        if (!q6_x10a_sample_alpha_normal(alpha, xGamma, yGamma,
                                         nx, ny, lx, ly, periodicX, periodicY,
                                         &d.nx, &d.ny)) {
            d.crossingPointNormalFallback = true;
            if (!q6_x9t_cell_normal(alpha, c, nx, ny, lx / nx, ly / ny,
                                    periodicX, periodicY, &d.nx, &d.ny))
                return d;
        }

        if (!centerBulk) {
            if (!q6_x9x_choose_direct_bulk_bath(
                    alpha, totalM, c, d.nx, d.ny,
                    nx, ny, periodicX, periodicY, &bath))
                return d;
        }

        const double mb = totalM[bath];
        if (!(mb > 0.0) || !isfinite(mb)) return d;
        const double ux = totalPx[bath] / mb;
        const double uy = totalPy[bath] / mb;
        const double crx = particles.vx[i] - ux;
        const double cry = particles.vy[i] - uy;
        const double gn = crx * d.nx + cry * d.ny;
        if (!(gn > 0.0) || !isfinite(gn)) return d;

        d.crossing = true;
        d.interiorCrossing = true;
        d.bathCell = bath;
        d.crossingFraction = sInside;
        d.outwardRelativeNormalSpeed = gn;
    } else if (shellSide) {
        d.shellParticle = true;
        d.pointwiseOuterRoutedToShell = true;

        // There is no current-step interior bracket for an already escaped
        // shell particle.  Use its own pointwise alpha normal at x0, with the
        // historical cell-gradient fallback only when the bilinear gradient is
        // degenerate.
        if (!q6_x10a_sample_alpha_normal(alpha, x0, y0,
                                         nx, ny, lx, ly, periodicX, periodicY,
                                         &d.nx, &d.ny)) {
            d.crossingPointNormalFallback = true;
            if (!q6_x9t_cell_normal(alpha, c, nx, ny, lx / nx, ly / ny,
                                    periodicX, periodicY, &d.nx, &d.ny)) {
                d.deepOuterParticle = true;
                return d;
            }
        }

        if (centerBulk) {
            bath = c;
        } else if (!q6_x9x_choose_direct_bulk_bath(
                       alpha, totalM, c, d.nx, d.ny,
                       nx, ny, periodicX, periodicY, &bath)) {
            d.deepOuterParticle = true;
            return d;
        }

        const double mb = totalM[bath];
        if (!(mb > 0.0) || !isfinite(mb)) {
            d.deepOuterParticle = true;
            return d;
        }
        const double ux = totalPx[bath] / mb;
        const double uy = totalPy[bath] / mb;
        const double crx = particles.vx[i] - ux;
        const double cry = particles.vy[i] - uy;
        const double gn = crx * d.nx + cry * d.ny;
        if (!(gn > 0.0) || !isfinite(gn)) {
            d.bathCell = bath;
            return d;
        }

        d.crossing = true;
        d.shellGuard = true;
        d.bathCell = bath;
        d.crossingFraction = 0.0;
        d.outwardRelativeNormalSpeed = gn;
    } else {
        return d;
    }

    if (reflectionFraction >= 1.0) d.reflect = true;
    else if (reflectionFraction > 0.0)
        d.reflect = q6_x9t_uniform01(i, step, seed) < reflectionFraction;
    return d;
}
'''
text = text[:start] + new_func + text[end:]

# 5) Audit the pointwise-normal fallback in pass 2 (summary cadence only).
replace_once(
'''            if (d.startBelowHalf) atomicAdd(&audit->startBelowHalf, 1ull);\n            if (d.pointwiseOuterRoutedToShell)\n''',
'''            if (d.startBelowHalf) atomicAdd(&audit->startBelowHalf, 1ull);\n            if (d.crossingPointNormalFallback)\n                atomicAdd(&audit->crossingPointNormalFallbacks, 1ull);\n            if (d.pointwiseOuterRoutedToShell)\n''',
'pass2 normal fallback audit')

# 6) Replace only the x9z donor reflection/positioning core.  Momentum/energy
# reaction is intentionally unchanged in x10a.
old_core = r'''            // Core x9z change: each donor uses its own normal. This guarantees
            // (v_new-u_bulk).n_i = -(v_old-u_bulk).n_i < 0 individually.
            newVx = oldVx - 2.0 * gn * d.nx;
            newVy = oldVy - 2.0 * gn * d.ny;

            // Same crossing-time trajectory placement as qualified x9y.
            if (d.interiorCrossing && d.crossingFraction > 0.0) {
                const double corrX = d.crossingFraction * dt * (oldVx - newVx);
                const double corrY = d.crossingFraction * dt * (oldVy - newVy);
                particles.x[i] += corrX;
                particles.y[i] += corrY;
                if (audit)
                    atomic_add_double_0400(&audit->positionCorrectionAbsSum,
                        sqrt(corrX * corrX + corrY * corrY));
            }

            if (audit) {
                atomicAdd(&audit->appliedReflections, 1ull);
                atomicAdd(&audit->individualDonorReflections, 1ull);
                const double postGn =
                    (newVx - ubx) * d.nx + (newVy - uby) * d.ny;
                const double tol = 1.0e-12 * fmax(1.0, fabs(gn));
                if (postGn > tol)
                    atomicAdd(&audit->appliedStillOutwardRelative, 1ull);

                if (d.interiorCrossing) {
                    double afinal = 1.0;
                    if (q6_x9t_sample_alpha(alpha,
                            particles.x[i] + newVx * dt,
                            particles.y[i] + newVy * dt,
                            nx, ny, lx, ly, periodicX, periodicY, &afinal) &&
                        afinal < 0.5)
                        atomicAdd(&audit->appliedInteriorPredictedOutside, 1ull);
                }
            }
'''
new_core = r'''            // x10a keeps the x9z individual specular velocity law, but the
            // normal now comes from the donor's own physical alpha=0.5 crossing.
            // Relative to the same pre-reaction bath reference this preserves
            // the strict x9z invariant (v_new-u_bulk).n_i = -gn < 0.
            newVx = oldVx - 2.0 * gn * d.nx;
            newVy = oldVy - 2.0 * gn * d.ny;

            // Geometry seal for true interior crossings, still inside pass 3.
            // First build the physically reflected endpoint from the last
            // sampled inside point on the incoming segment.  If that endpoint
            // is outside alpha<0.5, bisect the *reflected* segment and clamp the
            // final streamed position to its last sampled inside point.  This
            // changes position only: donor momentum and kinetic energy are not
            // touched by the seal.  Transmitted crossings never enter this path.
            if (d.interiorCrossing) {
                const double x0p = particles.x[i];
                const double y0p = particles.y[i];
                const double s = fmin(fmax(d.crossingFraction, 0.0), 1.0);
                const double xInside = x0p + s * oldVx * dt;
                const double yInside = y0p + s * oldVy * dt;
                const double xCandidate = xInside + (1.0 - s) * newVx * dt;
                const double yCandidate = yInside + (1.0 - s) * newVy * dt;

                double targetX = xCandidate;
                double targetY = yCandidate;
                double aCandidate = 1.0;
                const bool candidateSampled = q6_x9t_sample_alpha(
                    alpha, xCandidate, yCandidate,
                    nx, ny, lx, ly, periodicX, periodicY, &aCandidate);
                const bool candidateOutside = !candidateSampled || !(aCandidate >= 0.5);

                if (audit && candidateSampled && aCandidate < 0.5)
                    atomicAdd(&audit->appliedInteriorPredictedOutside, 1ull);

                if (candidateOutside) {
                    bool sealFallback = !candidateSampled;
                    double aInside = 0.0;
                    if (!q6_x9t_sample_alpha(alpha, xInside, yInside,
                                             nx, ny, lx, ly, periodicX, periodicY,
                                             &aInside) || !(aInside >= 0.5)) {
                        // x0 was pointwise sampled inside by q6_x9y_decide_crossing.
                        targetX = x0p;
                        targetY = y0p;
                        sealFallback = true;
                    } else if (candidateSampled) {
                        double lo = 0.0;
                        double hi = 1.0;
                        for (int it = 0; it < 4; ++it) {
                            const double mid = 0.5 * (lo + hi);
                            const double xm = xInside + mid * (xCandidate - xInside);
                            const double ym = yInside + mid * (yCandidate - yInside);
                            double am = 0.5;
                            if (!q6_x9t_sample_alpha(alpha, xm, ym,
                                                     nx, ny, lx, ly,
                                                     periodicX, periodicY, &am) ||
                                !isfinite(am)) {
                                sealFallback = true;
                                break;
                            }
                            if (am >= 0.5) lo = mid;
                            else hi = mid;
                        }
                        if (sealFallback) {
                            targetX = xInside;
                            targetY = yInside;
                        } else {
                            targetX = xInside + lo * (xCandidate - xInside);
                            targetY = yInside + lo * (yCandidate - yInside);
                        }
                    } else {
                        targetX = xInside;
                        targetY = yInside;
                    }

                    // Final hard verification.  If any interpolation anomaly
                    // remains, fall back to x0, which was explicitly sampled
                    // inside before this particle was classified as interior.
                    double aTarget = 0.0;
                    if (!q6_x9t_sample_alpha(alpha, targetX, targetY,
                                             nx, ny, lx, ly, periodicX, periodicY,
                                             &aTarget) || !(aTarget >= 0.5)) {
                        targetX = x0p;
                        targetY = y0p;
                        sealFallback = true;
                    }

                    if (audit) {
                        atomicAdd(&audit->endpointSealCorrections, 1ull);
                        if (sealFallback)
                            atomicAdd(&audit->endpointSealSampleFallbacks, 1ull);
                    }
                }

                // Store the pre-stream position whose subsequent ordinary
                // streaming by newV lands exactly at targetX,targetY.
                const double corrX = targetX - newVx * dt - x0p;
                const double corrY = targetY - newVy * dt - y0p;
                particles.x[i] = x0p + corrX;
                particles.y[i] = y0p + corrY;
                if (audit) {
                    const double corrAbs = sqrt(corrX * corrX + corrY * corrY);
                    atomic_add_double_0400(&audit->positionCorrectionAbsSum, corrAbs);
                    if (candidateOutside)
                        atomic_add_double_0400(&audit->endpointSealCorrectionAbsSum, corrAbs);

                    double afinal = 0.0;
                    if (!q6_x9t_sample_alpha(alpha,
                            particles.x[i] + newVx * dt,
                            particles.y[i] + newVy * dt,
                            nx, ny, lx, ly, periodicX, periodicY, &afinal) ||
                        !(afinal >= 0.5))
                        atomicAdd(&audit->appliedInteriorFinalOutside, 1ull);
                }
            }

            if (audit) {
                atomicAdd(&audit->appliedReflections, 1ull);
                atomicAdd(&audit->individualDonorReflections, 1ull);
                const double postGn =
                    (newVx - ubx) * d.nx + (newVy - uby) * d.ny;
                const double tol = 1.0e-12 * fmax(1.0, fabs(gn));
                if (postGn > tol)
                    atomicAdd(&audit->appliedStillOutwardRelative, 1ull);
            }
'''
replace_once(old_core, new_core, 'x9z donor geometry core')

# 7) CSV: append x10a geometry diagnostics without disturbing existing column names.
replace_once(
'''               "unsupportedNormalCancellation,unsupportedGroupNotOutward,"\n               "appliedStillOutwardRelative,appliedInteriorPredictedOutside,"\n               "convertedParticles,individualDonorReflections,receiverCorrectedParticles,"\n''',
'''               "unsupportedNormalCancellation,unsupportedGroupNotOutward,"\n               "appliedStillOutwardRelative,appliedInteriorPredictedOutside,"\n               "crossingPointNormalFallbacks,endpointSealCorrections,"\n               "endpointSealSampleFallbacks,appliedInteriorFinalOutside,"\n               "convertedParticles,individualDonorReflections,receiverCorrectedParticles,"\n''',
'CSV header counters')
replace_once(
'''               "deltaPx,deltaPy,deltaKineticEnergy,positionCorrectionAbsMean,"\n               "reactionEnergyResidualAbs,reactionDeltaUMagnitudeMean,"\n''',
'''               "deltaPx,deltaPy,deltaKineticEnergy,positionCorrectionAbsMean,"\n               "endpointSealCorrectionAbsMean,reactionEnergyResidualAbs,reactionDeltaUMagnitudeMean,"\n''',
'CSV header doubles')
replace_once(
'''    const double meanReactionDU = a.reactionActiveCells > 0ull ?\n        a.reactionDeltaUMagnitudeSum / static_cast<double>(a.reactionActiveCells) : 0.0;\n''',
'''    const double meanSealCorr = a.endpointSealCorrections > 0ull ?\n        a.endpointSealCorrectionAbsSum / static_cast<double>(a.endpointSealCorrections) : 0.0;\n    const double meanReactionDU = a.reactionActiveCells > 0ull ?\n        a.reactionDeltaUMagnitudeSum / static_cast<double>(a.reactionActiveCells) : 0.0;\n''',
'CSV mean seal correction')
replace_once(
'''        << a.unsupportedNormalCancellation << ',' << a.unsupportedGroupNotOutward << ','\n        << a.appliedStillOutwardRelative << ',' << a.appliedInteriorPredictedOutside << ','\n        << a.convertedParticles << ','\n''',
'''        << a.unsupportedNormalCancellation << ',' << a.unsupportedGroupNotOutward << ','\n        << a.appliedStillOutwardRelative << ',' << a.appliedInteriorPredictedOutside << ','\n        << a.crossingPointNormalFallbacks << ',' << a.endpointSealCorrections << ','\n        << a.endpointSealSampleFallbacks << ',' << a.appliedInteriorFinalOutside << ','\n        << a.convertedParticles << ','\n''',
'CSV row counters')
replace_once(
'''        << a.deltaPx << ',' << a.deltaPy << ',' << a.deltaKineticEnergy << ',' << meanCorr << ','\n        << a.reactionEnergyResidualAbsSum << ',' << meanReactionDU << ',' << meanLambdaDev << ','\n''',
'''        << a.deltaPx << ',' << a.deltaPy << ',' << a.deltaKineticEnergy << ',' << meanCorr << ','\n        << meanSealCorr << ',' << a.reactionEnergyResidualAbsSum << ',' << meanReactionDU << ',' << meanLambdaDev << ','\n''',
'CSV row doubles')
replace_once(
'''           "individual-donor-own-normal-reflection;per-cell-impulse-energy-reaction;"\n           "receiver-affine-translation-plus-thermal-rescale;"\n           "donor-crossing-time-position-correction;no-merge-no-resampling;"\n''',
'''           "individual-donor-crossing-point-normal-reflection;per-cell-impulse-energy-reaction;"\n           "receiver-affine-translation-plus-thermal-rescale;"\n           "interior-reflected-endpoint-alpha-ge-half-seal;no-merge-no-resampling;"\n''',
'CSV contract')

SRC.write_text(text)

# 8) New validation scripts.  They deliberately reuse the existing x9z CSV
# so the source-side audit plumbing stays minimal.
run = ROOT / 'scripts/run_0493x10a_vacuum_drop_geometry_seal.sh'
run.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export TARGET=wall
export RUN_ROOT="${RUN_ROOT:-runs/0493x10a_vacuum_drop_geometry_seal}"
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

printf '%s\n' \
  "[0493x10a-suite] geometry only: pointwise normal at physical alpha=0.5 crossing" \
  "[0493x10a-suite] reflected endpoint seal for true interior crossings" \
  "[0493x10a-suite] x9z velocity/reaction law intentionally unchanged" \
  "[0493x10a-suite] 3 x9 particle passes + existing O(Ncell) reaction kernel; no new full pass" \
  "[0493x10a-suite] kBT=$KBT r=$KINETIC_REFLECTION_FRACTION LiveVis=$LIVE_VIS_ENABLE filteredRecording=$FILTERED_RECORDING_ENABLE"

bash scripts/run_0493x9s_splash.sh
CSV="$RUN_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv"
[[ -f "$CSV" ]] || { echo "[0493x10a-suite] ERROR missing $CSV" >&2; exit 2; }
python3 scripts/analyze_0493x10a_geometry_seal.py "$CSV"
''')
run.chmod(0o755)

an = ROOT / 'scripts/analyze_0493x10a_geometry_seal.py'
an.write_text(r'''#!/usr/bin/env python3
import csv, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: analyze_0493x10a_geometry_seal.py <cuda_phase_kinetic_crossing_0493x9z.csv>")
path=Path(sys.argv[1])
with path.open(newline='') as f: rows=list(csv.DictReader(f))
if not rows: raise SystemExit('[0493x10a-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def ratio(a,b): return a/b if b else 0.0

last=rows[-1]
interior=isum('interiorCrossings')
applied=isum('appliedReflections')
still=isum('appliedStillOutwardRelative')
preout=isum('appliedInteriorPredictedOutside')
finalout=isum('appliedInteriorFinalOutside')
seals=isum('endpointSealCorrections')
sealFallback=isum('endpointSealSampleFallbacks')
normalFallback=isum('crossingPointNormalFallbacks')
unsupported=isum('unsupportedReflections')
outer0=I(rows[0],'phaseAOuterCellParticles'); outer1=I(last,'phaseAOuterCellParticles')
deep0=I(rows[0],'deepOuterParticles'); deep1=I(last,'deepOuterParticles')
maxdp=max(maxabs('deltaPx'),maxabs('deltaPy'))
maxde=maxabs('deltaKineticEnergy')

print('===== 0493x10a CROSSING-NORMAL + ENDPOINT SEAL =====')
print(f'file={path} rows={len(rows)} lastStep={last.get("step","?")}')
print('--- geometry ---')
print(f'interiorCrossings={interior} preSealPredictedOutside={preout}/{interior} ({ratio(preout,interior):.3%})')
print(f'endpointSealCorrections={seals} sampleFallbacks={sealFallback}')
print(f'appliedInteriorFinalOutside={finalout}/{interior} ({ratio(finalout,interior):.6%})')
print(f'crossingPointNormalFallbacks={normalFallback}')
print('--- individual velocity invariant ---')
print(f'applied={applied} stillOutwardRelative={still} unsupported={unsupported}')
print('--- halo proxies ---')
print(f'outer first={outer0} last={outer1} growth={outer1-outer0:+d}')
print(f'deepOuter first={deep0} last={deep1} growth={deep1-deep0:+d}')
print('--- unchanged x9z reaction audit ---')
print(f'max|deltaP|={maxdp:.6e} max|deltaKE|={maxde:.6e} '
      f'lastMeanLambdaDev={F(last,"reactionLambdaDeviationAbsMean"):.6e}')

geometry_ok = finalout == 0 and still == 0 and applied > 0
print(f'geometryContract={"PASS" if geometry_ok else "FAIL"}')
if not geometry_ok:
    raise SystemExit(3)
''')
an.chmod(0o755)

check = ROOT / 'scripts/check_0493x10a_geometry_math.py'
check.write_text(r'''#!/usr/bin/env python3
# Pure geometry identity used by the pre-stream position correction.
# x_pre' = x_target - v_new*dt  => ordinary streaming lands at x_target.
import random, math
rng=random.Random(493100)
worst=0.0
for _ in range(20000):
    x0=rng.uniform(-2,2); y0=rng.uniform(-2,2)
    ovx=rng.uniform(-3,3); ovy=rng.uniform(-3,3)
    nvx=rng.uniform(-3,3); nvy=rng.uniform(-3,3)
    dt=10**rng.uniform(-4,-1); s=rng.random()
    xi=x0+s*ovx*dt; yi=y0+s*ovy*dt
    # emulate an arbitrary last-inside fraction t on reflected segment
    t=rng.random()
    xc=xi+(1-s)*nvx*dt; yc=yi+(1-s)*nvy*dt
    xt=xi+t*(xc-xi); yt=yi+t*(yc-yi)
    xpre=xt-nvx*dt; ypre=yt-nvy*dt
    xf=xpre+nvx*dt; yf=ypre+nvy*dt
    worst=max(worst,abs(xf-xt),abs(yf-yt))
print(f'maxEndpointIdentityError={worst:.3e}')
print('status=' + ('PASS' if worst < 1e-14 else 'FAIL'))
''')
check.chmod(0o755)

print('[0493x10a-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10a-patch] wrote scripts/run_0493x10a_vacuum_drop_geometry_seal.sh')
print('[0493x10a-patch] wrote scripts/analyze_0493x10a_geometry_seal.py')
print('[0493x10a-patch] wrote scripts/check_0493x10a_geometry_math.py')
