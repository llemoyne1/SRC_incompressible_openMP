#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'
if not SRC.exists():
    raise SystemExit(f'[0493x10f-patch] missing {SRC}')

text = SRC.read_text()

if 'r1-final-endpoint-tangent-mirror-no-interface-clamp' not in text:
    raise SystemExit('[0493x10f-patch] x10e prerequisite not found')
if 'r1-global-single-component-reservoir-ablation' in text:
    raise SystemExit('[0493x10f-patch] x10f already appears applied')

def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10f-patch] {label}: expected 1 anchor, found {n}')
    text = text.replace(old, new, 1)

# ---------------------------------------------------------------------------
# Global hard-r1 reaction state: O(1), not a new particle field.
# ---------------------------------------------------------------------------
replace_once(
'''    double analyticDonorScaleSum = 0.0;
    double analyticDonorScaleAbsFromSpecularSum = 0.0;
};

struct ResidentWorkspace0400 {
''',
'''    double analyticDonorScaleSum = 0.0;
    double analyticDonorScaleAbsFromSpecularSum = 0.0;

    // 0493x10f single-component/global-reservoir ablation diagnostics.
    // This is deliberately NOT yet the production multi-liquid-domain model.
    unsigned long long globalReactionActive = 0ull;
    unsigned long long globalReactionTrivial = 0ull;
    unsigned long long globalReactionInvalid = 0ull;
    unsigned long long globalReactionDonorCells = 0ull;
    unsigned long long globalReactionReceiverCells = 0ull;
    double globalReactionA = 0.0;
    double globalReactionH = 0.0;
    double globalReactionSNorm = 0.0;
    double globalReactionCellSNormSum = 0.0;
    double globalReactionCancellationRatio = 0.0;
    double globalReactionReceiverMass = 0.0;
    double globalReactionScale = 0.0;
    double globalReactionDeltaUMagnitude = 0.0;
    double globalReactionFormulaResidual = 0.0;
};

struct KineticGlobalReaction0493x10f {
    double A = 0.0;
    double Sx = 0.0;
    double Sy = 0.0;
    double H = 0.0;
    double receiverM = 0.0;
    double receiverPx = 0.0;
    double receiverPy = 0.0;
    double cellSNormSum = 0.0;
    unsigned long long donorCells = 0ull;
    unsigned long long receiverCells = 0ull;

    double a = 0.0;
    double dux = 0.0;
    double duy = 0.0;
    int active = 0;
    int trivial = 0;
    int invalid = 0;
};

struct ResidentWorkspace0400 {
''',
'audit/global struct')

replace_once(
'''    DeviceBuffer0400<KineticInterfaceAccumulator0493x9u> kineticAccum0493x9u;
    DeviceBuffer0400<KineticCrossingAccumulator0493x9x> kineticAccum0493x9x;
''',
'''    DeviceBuffer0400<KineticInterfaceAccumulator0493x9u> kineticAccum0493x9u;
    DeviceBuffer0400<KineticCrossingAccumulator0493x9x> kineticAccum0493x9x;
    DeviceBuffer0400<KineticGlobalReaction0493x10f> kineticGlobalReaction0493x10f;
''',
'workspace global buffer')

replace_once(
'''    void ensure_kinetic_interface_0493x9x(int numCells) {
        ensure_kinetic_interface_0493x9u(numCells);
        kineticAccum0493x9x.ensure(1u);
    }
''',
'''    void ensure_kinetic_interface_0493x9x(int numCells) {
        ensure_kinetic_interface_0493x9u(numCells);
        kineticAccum0493x9x.ensure(1u);
        kineticGlobalReaction0493x10f.ensure(1u);
    }
''',
'workspace ensure global buffer')

# ---------------------------------------------------------------------------
# Classification pass: hard-r1 stores H in the old recvK scratch.
# ---------------------------------------------------------------------------
replace_once(
'''                atomic_add_double_0400(&recvM[c], m);
                atomic_add_double_0400(&recvPx[c], m * vx);
                atomic_add_double_0400(&recvPy[c], m * vy);
                atomic_add_double_0400(&recvK[c], 0.5 * m * (vx * vx + vy * vy));
''',
'''                atomic_add_double_0400(&recvM[c], m);
                atomic_add_double_0400(&recvPx[c], m * vx);
                atomic_add_double_0400(&recvPy[c], m * vy);
                // Hard r=1 x10f reuses recvK as donor-H scratch below.
                // The global exact energy root does not need receiver K.
                // Preserve the historical receiver thermal accumulator only
                // for r<1 evaporation semantics.
                if (reflectionFraction < 1.0)
                    atomic_add_double_0400(&recvK[c], 0.5 * m * (vx * vx + vy * vy));
''',
'classification receiver K split')

replace_once(
'''                            atomic_add_double_0400(&donorDeltaE[b], m * gn * gn);
                            atomic_add_double_0400(&reactionJx[b], m * gn * d.nx);
                            atomic_add_double_0400(&reactionJy[b], m * gn * d.ny);
''',
'''                            atomic_add_double_0400(&donorDeltaE[b], m * gn * gn);
                            atomic_add_double_0400(&reactionJx[b], m * gn * d.nx);
                            atomic_add_double_0400(&reactionJy[b], m * gn * d.ny);
                            // x10f additionally accumulates
                            //   H = sum m g_i (v_i . n_i).
                            // recvK is unused by hard-r1 and gives this statistic
                            // without adding another O(Ncell) buffer.
                            atomic_add_double_0400(
                                &recvK[b],
                                m * gn * (vx * d.nx + vy * d.ny));
''',
'classification donor H')

# ---------------------------------------------------------------------------
# New O(Ncell) reduction + O(1) finalizer.
# ---------------------------------------------------------------------------
marker = '''// 0493x10d: O(Ncell) preparation between particle passes 2 and 3.\n'''
kernels = r'''
// 0493x10f: hard-r1 GLOBAL-RESERVOIR ABLATION.
//
// This tests whether the cardinal accumulation of x10d is caused by forcing
// the counter-impulse into receivers from the same interface cell.  Every
// donor keeps its own pointwise normal and local bath-relative g_i, while the
// exact momentum/energy reaction is aggregated over the whole phase-A set of
// this kinetic-interface call.
//
// IMPORTANT: this is a single-liquid-component ablation only.  A production
// multi-drop/pool implementation must run the same reduction independently
// per connected alpha>=0.5 liquid component.
//
// A = sum m g^2, S = sum m g n, H = sum m g (v.n)
// receivers: M_R, P_R, u_R=P_R/M_R
// donor dv=-a g n, receiver du=+a S/M_R
// dE = a(u_R.S-H)+0.5 a^2(A+|S|^2/M_R)
// a* = 2(H-u_R.S)/(A+|S|^2/M_R)
__global__ void q6_x10f_reduce_global_reaction(
    int numCells,
    const double* donorA,
    const double* donorSx,
    const double* donorSy,
    const double* donorH,
    const double* recvM,
    const double* recvPx,
    const double* recvPy,
    KineticGlobalReaction0493x10f* global) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;

    for (int c = idx; c < numCells; c += stride) {
        const double A = donorA[c];
        const double Sx = donorSx[c];
        const double Sy = donorSy[c];
        const double H = donorH[c];
        const double donorRequest = fabs(A) + fabs(Sx) + fabs(Sy) + fabs(H);
        if (donorRequest > 1.0e-30 &&
            isfinite(A) && isfinite(Sx) && isfinite(Sy) && isfinite(H)) {
            atomic_add_double_0400(&global->A, A);
            atomic_add_double_0400(&global->Sx, Sx);
            atomic_add_double_0400(&global->Sy, Sy);
            atomic_add_double_0400(&global->H, H);
            atomic_add_double_0400(
                &global->cellSNormSum, sqrt(Sx * Sx + Sy * Sy));
            atomicAdd(&global->donorCells, 1ull);
        }

        const double mr = recvM[c];
        if (mr > 1.0e-14 && isfinite(mr) &&
            isfinite(recvPx[c]) && isfinite(recvPy[c])) {
            atomic_add_double_0400(&global->receiverM, mr);
            atomic_add_double_0400(&global->receiverPx, recvPx[c]);
            atomic_add_double_0400(&global->receiverPy, recvPy[c]);
            atomicAdd(&global->receiverCells, 1ull);
        }
    }
}

__global__ void q6_x10f_finalize_global_reaction(
    KineticGlobalReaction0493x10f* global,
    KineticCrossingAccumulator0493x9x* audit) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;

    const double A = global->A;
    const double Sx = global->Sx;
    const double Sy = global->Sy;
    const double H = global->H;
    const double mr = global->receiverM;

    global->a = 0.0;
    global->dux = 0.0;
    global->duy = 0.0;
    global->active = 0;
    global->trivial = 0;
    global->invalid = 0;

    const double request = fabs(A) + fabs(Sx) + fabs(Sy) + fabs(H);
    if (!(request > 1.0e-30) || !isfinite(request)) {
        if (audit) {
            audit->globalReactionDonorCells = global->donorCells;
            audit->globalReactionReceiverCells = global->receiverCells;
        }
        return;
    }

    global->active = 1;
    double B = 0.0;
    double uRx = 0.0;
    double uRy = 0.0;
    double numer = 0.0;
    double denom = 0.0;
    double a = 0.0;
    bool valid = true;

    if (!(mr > 1.0e-14) || !isfinite(mr) ||
        !isfinite(global->receiverPx) || !isfinite(global->receiverPy)) {
        valid = false;
    } else {
        uRx = global->receiverPx / mr;
        uRy = global->receiverPy / mr;
        B = (Sx * Sx + Sy * Sy) / mr;
        denom = A + B;
        numer = 2.0 * (H - (uRx * Sx + uRy * Sy));
        valid = isfinite(A) && A >= 0.0 &&
                isfinite(B) && B >= 0.0 &&
                isfinite(H) && isfinite(denom) && denom > 1.0e-30 &&
                isfinite(numer);
        if (valid) a = numer / denom;
    }

    if (!(a > 0.0) || !isfinite(a)) {
        a = 0.0;
        global->trivial = 1;
        if (!valid) global->invalid = 1;
    } else {
        global->dux = a * Sx / mr;
        global->duy = a * Sy / mr;
        if (!isfinite(global->dux) || !isfinite(global->duy)) {
            global->dux = 0.0;
            global->duy = 0.0;
            a = 0.0;
            global->trivial = 1;
            global->invalid = 1;
        }
    }
    global->a = a;

    const double residual =
        a * ((uRx * Sx + uRy * Sy) - H) +
        0.5 * a * a * (A + B);
    const double sNorm = sqrt(Sx * Sx + Sy * Sy);
    const double cancellation =
        global->cellSNormSum > 0.0 ? sNorm / global->cellSNormSum : 0.0;

    if (audit) {
        // Keep generic x10d diagnostics meaningful: one reaction object per
        // audited step instead of one reaction object per active interface cell.
        atomicAdd(&audit->reactionActiveCells, 1ull);
        atomicAdd(&audit->analyticConservativeReactionCells, 1ull);
        if (!(mr > 1.0e-14) || !isfinite(mr))
            atomicAdd(&audit->reactionNoReceiverCells, 1ull);

        if (a > 0.0) {
            atomicAdd(&audit->reactionFeasibleCells, 1ull);
            atomicAdd(&audit->analyticPositiveScaleCells, 1ull);
            if (a > 1.0)
                atomicAdd(&audit->analyticInwardCells, 1ull);
            else
                atomicAdd(&audit->analyticNonInwardPositiveCells, 1ull);
            atomic_add_double_0400(&audit->analyticDonorScaleSum, a);
            atomic_add_double_0400(
                &audit->analyticDonorScaleAbsFromSpecularSum, fabs(a - 2.0));
        } else {
            atomicAdd(&audit->analyticTrivialCells, 1ull);
            if (global->invalid)
                atomicAdd(&audit->analyticInvalidCells, 1ull);
        }

        atomic_add_double_0400(
            &audit->reactionEnergyResidualAbsSum, fabs(residual));
        atomic_add_double_0400(
            &audit->reactionDeltaUMagnitudeSum,
            sqrt(global->dux * global->dux + global->duy * global->duy));

        audit->globalReactionActive = 1ull;
        audit->globalReactionTrivial = global->trivial ? 1ull : 0ull;
        audit->globalReactionInvalid = global->invalid ? 1ull : 0ull;
        audit->globalReactionDonorCells = global->donorCells;
        audit->globalReactionReceiverCells = global->receiverCells;
        audit->globalReactionA = A;
        audit->globalReactionH = H;
        audit->globalReactionSNorm = sNorm;
        audit->globalReactionCellSNormSum = global->cellSNormSum;
        audit->globalReactionCancellationRatio = cancellation;
        audit->globalReactionReceiverMass = mr;
        audit->globalReactionScale = a;
        audit->globalReactionDeltaUMagnitude =
            sqrt(global->dux * global->dux + global->duy * global->duy);
        audit->globalReactionFormulaResidual = residual;
    }
}

'''
replace_once(marker, kernels + marker, 'insert x10f kernels')

# ---------------------------------------------------------------------------
# Pass 3 consumes the global object in hard-r1.
# ---------------------------------------------------------------------------
replace_once(
'''    const double* reactionLambda,
    std::uint32_t phaseAType,
''',
'''    const double* reactionLambda,
    const KineticGlobalReaction0493x10f* globalReaction,
    std::uint32_t phaseAType,
''',
'apply signature global pointer')

replace_once(
'''        const bool hardR1Containment = reflectionFraction >= 1.0;
        const bool hardShellCapture = hardR1Containment && d.shellRecoverable;
        const bool donor = d.crossing && d.reflect;
        const bool receiver = !d.crossing && !hardShellCapture && reactionActive[c] > 0.5;
''',
'''        const bool hardR1Containment = reflectionFraction >= 1.0;
        const bool hardShellCapture = hardR1Containment && d.shellRecoverable;
        const bool donor = d.crossing && d.reflect;
        const bool globalReactionActive =
            hardR1Containment && globalReaction && globalReaction->active != 0;
        const bool receiver =
            !d.crossing && !hardShellCapture &&
            (hardR1Containment ? globalReactionActive
                               : (reactionActive[c] > 0.5));
''',
'apply receiver global selection')

replace_once(
'''            if (hardR1Containment) {
                donorScale = reactionLambda[b]; // x10d: this buffer stores a*, not lambda
                if (!(donorScale >= 0.0) || !isfinite(donorScale)) donorScale = 0.0;
            }
''',
'''            if (hardR1Containment) {
                // x10f: one exact global scale for the whole current phase-A
                // reservoir.  Donors still keep their own local g_i and n_i.
                donorScale =
                    (globalReaction && globalReaction->active != 0)
                        ? globalReaction->a : 0.0;
                if (!(donorScale >= 0.0) || !isfinite(donorScale))
                    donorScale = 0.0;
            }
''',
'apply donor global scale')

replace_once(
'''            if (hardR1Containment) {
                // x10d: exact collective reaction.  The receiver only takes
                // the uniform impulse +a*S; its internal/thermal velocities
                // are untouched.  Exact energy closure is obtained by solving
                // the donor amplitude a jointly, not by a thermal lambda.
                newVx = oldVx + reactionDeltaUx[c];
                newVy = oldVy + reactionDeltaUy[c];
            } else {
''',
'''            if (hardR1Containment) {
                // x10f global-reservoir ablation: every non-donor receiver in
                // this current phase-A set gets the same tiny +a*S/M_R shift.
                // This removes the cell-local outward counter-kick suspected
                // of generating the cardinal mass accumulation.
                const double dux = globalReaction ? globalReaction->dux : 0.0;
                const double duy = globalReaction ? globalReaction->duy : 0.0;
                newVx = oldVx + dux;
                newVy = oldVy + duy;
            } else {
''',
'apply receiver global du')

# ---------------------------------------------------------------------------
# CSV diagnostics.
# ---------------------------------------------------------------------------
replace_once(
'''               "analyticTrivialCells,analyticInvalidCells,"
               "analyticDonorScaleMean,analyticDonorScaleAbsFromSpecularMean,contract\\n";
''',
'''               "analyticTrivialCells,analyticInvalidCells,"
               "analyticDonorScaleMean,analyticDonorScaleAbsFromSpecularMean,"
               "globalReactionActive,globalReactionTrivial,globalReactionInvalid,"
               "globalReactionDonorCells,globalReactionReceiverCells,"
               "globalReactionA,globalReactionH,globalReactionSNorm,"
               "globalReactionCellSNormSum,globalReactionCancellationRatio,"
               "globalReactionReceiverMass,globalReactionScale,"
               "globalReactionDeltaUMagnitude,globalReactionFormulaResidual,"
               "contract\\n";
''',
'CSV global header')

replace_once(
'''        << meanAnalyticScale << ',' << meanAnalyticScaleAbsFrom2 << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'''        << meanAnalyticScale << ',' << meanAnalyticScaleAbsFrom2 << ','
        << a.globalReactionActive << ',' << a.globalReactionTrivial << ','
        << a.globalReactionInvalid << ',' << a.globalReactionDonorCells << ','
        << a.globalReactionReceiverCells << ',' << a.globalReactionA << ','
        << a.globalReactionH << ',' << a.globalReactionSNorm << ','
        << a.globalReactionCellSNormSum << ','
        << a.globalReactionCancellationRatio << ','
        << a.globalReactionReceiverMass << ',' << a.globalReactionScale << ','
        << a.globalReactionDeltaUMagnitude << ','
        << a.globalReactionFormulaResidual << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'CSV global row')

replace_once(
'''           "r1-final-endpoint-tangent-mirror-no-interface-clamp;"
           "no-merge-no-resampling;"
''',
'''           "r1-final-endpoint-tangent-mirror-no-interface-clamp;"
           "r1-global-single-component-reservoir-ablation;"
           "multi-component-not-production;"
           "no-merge-no-resampling;"
''',
'CSV global contract tag')

# ---------------------------------------------------------------------------
# Orchestration: r=1 uses reduce+finalize; r<1 stays exact legacy path.
# ---------------------------------------------------------------------------
old_prepare = '''    q6_x9z_prepare_receiver_reaction<<<cellBlocks, threads>>>(
        grid.numCells,
        ws.kineticRefM0493x9t.data(),
        ws.kineticRefPx0493x9t.data(),
        ws.kineticRefPy0493x9t.data(),
        ws.kineticTxM0493x9t.data(),
        ws.kineticTxPx0493x9t.data(),
        ws.kineticTxPy0493x9t.data(),
        ws.kineticRefNx0493x9u.data(),
        ws.kineticRefNy0493x9u.data(),
        ws.kineticTotalM0493x9t.data(),
        ws.kineticTotalPx0493x9t.data(),
        ws.kineticTotalPy0493x9t.data(),
        r,
        auditDev);
    check_cuda_0400(cudaGetLastError(), "0493x9z receiver reaction prepare launch");
'''
new_prepare = '''    if (r >= 1.0) {
        check_cuda_0400(
            cudaMemset(ws.kineticGlobalReaction0493x10f.data(), 0,
                       sizeof(KineticGlobalReaction0493x10f)),
            "0493x10f global reaction zero");

        q6_x10f_reduce_global_reaction<<<cellBlocks, threads>>>(
            grid.numCells,
            ws.kineticRefM0493x9t.data(),
            ws.kineticRefPx0493x9t.data(),
            ws.kineticRefPy0493x9t.data(),
            ws.kineticRefNx0493x9u.data(),
            ws.kineticTxM0493x9t.data(),
            ws.kineticTxPx0493x9t.data(),
            ws.kineticTxPy0493x9t.data(),
            ws.kineticGlobalReaction0493x10f.data());
        check_cuda_0400(
            cudaGetLastError(), "0493x10f global reaction reduce launch");

        q6_x10f_finalize_global_reaction<<<1, 1>>>(
            ws.kineticGlobalReaction0493x10f.data(), auditDev);
        check_cuda_0400(
            cudaGetLastError(), "0493x10f global reaction finalize launch");
    } else {
        q6_x9z_prepare_receiver_reaction<<<cellBlocks, threads>>>(
            grid.numCells,
            ws.kineticRefM0493x9t.data(),
            ws.kineticRefPx0493x9t.data(),
            ws.kineticRefPy0493x9t.data(),
            ws.kineticTxM0493x9t.data(),
            ws.kineticTxPx0493x9t.data(),
            ws.kineticTxPy0493x9t.data(),
            ws.kineticRefNx0493x9u.data(),
            ws.kineticRefNy0493x9u.data(),
            ws.kineticTotalM0493x9t.data(),
            ws.kineticTotalPx0493x9t.data(),
            ws.kineticTotalPy0493x9t.data(),
            r,
            auditDev);
        check_cuda_0400(
            cudaGetLastError(), "0493x9z receiver reaction prepare launch");
    }
'''
replace_once(old_prepare, new_prepare, 'orchestration prepare branch')

replace_once(
'''        ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(), ws.kineticTxPy0493x9t.data(),
        ws.kineticRefNy0493x9u.data(), phaseAType,
''',
'''        ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(), ws.kineticTxPy0493x9t.data(),
        ws.kineticRefNy0493x9u.data(),
        ws.kineticGlobalReaction0493x10f.data(),
        phaseAType,
''',
'orchestration apply global arg')

SRC.write_text(text)

# ---------------------------------------------------------------------------
# Analyzer.
# ---------------------------------------------------------------------------
an = ROOT / 'scripts/analyze_0493x10f_global_reservoir_ablation.py'
an.write_text(r'''#!/usr/bin/env python3
import csv
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(
        'usage: analyze_0493x10f_global_reservoir_ablation.py '
        '<cuda_phase_kinetic_crossing_0493x9z.csv>')

p = Path(sys.argv[1])
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10f-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def S(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def pct(a,b): return 100.0*a/b if b else 0.0

last = rows[-1]
checks = S('hardFinalEndpointChecks')
outside = S('hardFinalEndpointOutsideBefore')
after = S('hardFinalEndpointOutsideAfter')
miss = S('hardFinalLocalAnchorMisses')
maxdeep = max(I(r,'deepOuterParticles') for r in rows)

active = S('globalReactionActive')
trivial = S('globalReactionTrivial')
invalid = S('globalReactionInvalid')
scales = [F(r,'globalReactionScale') for r in rows if I(r,'globalReactionActive')]
cancel = [F(r,'globalReactionCancellationRatio') for r in rows if I(r,'globalReactionActive')]
dus = [F(r,'globalReactionDeltaUMagnitude') for r in rows if I(r,'globalReactionActive')]

print('===== 0493x10f GLOBAL RESERVOIR ABLATION =====')
print(f'file={p} rows={len(rows)} lastStep={last.get("step","?")}')
print('--- global exact reaction ---')
print(f'active={active} trivial={trivial} invalid={invalid}')
if scales:
    print(f'scale a: last={scales[-1]:.9g} min={min(scales):.9g} max={max(scales):.9g} mean={sum(scales)/len(scales):.9g}')
if cancel:
    print('S cancellation |sum S|/sum|S_cell|: '
          f'last={cancel[-1]:.6e} max={max(cancel):.6e} mean={sum(cancel)/len(cancel):.6e}')
if dus:
    print(f'global receiver |du|: last={dus[-1]:.6e} max={max(dus):.6e}')
print(f'last donorCells={I(last,"globalReactionDonorCells")} '
      f'receiverCells={I(last,"globalReactionReceiverCells")} '
      f'receiverMass={F(last,"globalReactionReceiverMass"):.9g}')

print('--- actual pass-3 conservation ---')
dp = max(maxabs('deltaPx'), maxabs('deltaPy'))
de = maxabs('deltaKineticEnergy')
formula = maxabs('globalReactionFormulaResidual')
print(f'max|deltaP|={dp:.12e}')
print(f'max|deltaKE|={de:.12e}')
print(f'max|analyticResidual|={formula:.12e}')

print('--- hard barrier / shape context ---')
print(f'outsideBefore={outside}/{checks} ({pct(outside,checks):.6f}%)')
print(f'outsideAfter={after}/{checks} anchorMisses={miss} maxDeepOuter={maxdeep}')
print(f'last hardFinalReceiverOutsideBefore={I(last,"hardFinalReceiverOutsideBefore")}')

cons = dp < 1e-9 and de < 1e-9 and formula < 1e-9
ret = after == 0 and miss == 0
glob = active > 0 and invalid == 0
print('conservationContract=' + ('PASS' if cons else 'FAIL'))
print('hardRetentionContract=' + ('PASS' if ret else 'FAIL'))
print('globalReservoirContract=' + ('PASS' if glob else 'FAIL'))
print('multiComponentContract=NOT_APPLICABLE_ABLATION_ONLY')
print('shapeContract=VISUAL_PENDING')
''')
an.chmod(0o755)

# ---------------------------------------------------------------------------
# Pure algebra check.
# ---------------------------------------------------------------------------
chk = ROOT / 'scripts/check_0493x10f_global_reaction_math.py'
chk.write_text(r'''#!/usr/bin/env python3
import math
import random

rng = random.Random(49310)
max_p = 0.0
max_e = 0.0

for _ in range(2000):
    nd = rng.randint(1, 40)
    nr = rng.randint(2, 80)
    donors = []
    A = Sx = Sy = H = 0.0
    for _ in range(nd):
        m = 0.2 + 2.0*rng.random()
        ang = 2.0*math.pi*rng.random()
        nx, ny = math.cos(ang), math.sin(ang)
        ubx = -0.4 + 0.8*rng.random()
        uby = -0.4 + 0.8*rng.random()
        g = 0.02 + 1.5*rng.random()
        tang = -1.0 + 2.0*rng.random()
        tx, ty = -ny, nx
        vx = ubx + g*nx + tang*tx
        vy = uby + g*ny + tang*ty
        donors.append((m,vx,vy,g,nx,ny))
        A += m*g*g
        Sx += m*g*nx
        Sy += m*g*ny
        H += m*g*(vx*nx + vy*ny)

    receivers = []
    mr = prx = pry = 0.0
    for _ in range(nr):
        m = 0.2 + 2.0*rng.random()
        vx = -0.8 + 1.6*rng.random()
        vy = -0.8 + 1.6*rng.random()
        receivers.append((m,vx,vy))
        mr += m
        prx += m*vx
        pry += m*vy

    urx, ury = prx/mr, pry/mr
    B = (Sx*Sx + Sy*Sy)/mr
    denom = A+B
    numer = 2.0*(H - (urx*Sx + ury*Sy))
    a = numer/denom if denom > 0.0 else 0.0
    if not (a > 0.0 and math.isfinite(a)):
        a = 0.0
    dux, duy = a*Sx/mr, a*Sy/mr

    p0x = p0y = e0 = 0.0
    p1x = p1y = e1 = 0.0
    for m,vx,vy,g,nx,ny in donors:
        nvx = vx-a*g*nx
        nvy = vy-a*g*ny
        p0x += m*vx; p0y += m*vy
        p1x += m*nvx; p1y += m*nvy
        e0 += 0.5*m*(vx*vx+vy*vy)
        e1 += 0.5*m*(nvx*nvx+nvy*nvy)
    for m,vx,vy in receivers:
        nvx = vx+dux
        nvy = vy+duy
        p0x += m*vx; p0y += m*vy
        p1x += m*nvx; p1y += m*nvy
        e0 += 0.5*m*(vx*vx+vy*vy)
        e1 += 0.5*m*(nvx*nvx+nvy*nvy)

    max_p = max(max_p, abs(p1x-p0x), abs(p1y-p0y))
    max_e = max(max_e, abs(e1-e0))

print(f'maxMomentumResidual={max_p:.3e}')
print(f'maxEnergyResidual={max_e:.3e}')
if max_p > 1e-10 or max_e > 1e-10:
    raise SystemExit('status=FAIL')
print('status=PASS')
''')
chk.chmod(0o755)

# ---------------------------------------------------------------------------
# Qualification runner.  x10e geometry is intentionally retained unchanged.
# ---------------------------------------------------------------------------
run = ROOT / 'scripts/run_0493x10f_global_reservoir_ablation.sh'
run.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export TARGET=wall
export RUN_ROOT="${RUN_ROOT:-runs/0493x10f_global_reservoir_ablation}"
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
  echo "[0493x10f-suite] ERROR x10f ablation is intentionally hard-r1 only" >&2
  exit 2
fi

printf '%s\n' \
  "[0493x10f-suite] GLOBAL RESERVOIR ABLATION: remove cell-local receiver counter-kick" \
  "[0493x10f-suite] donors retain individual pointwise normals/local bath g; one exact global a and du" \
  "[0493x10f-suite] x10e endpoint mirror/barrier retained unchanged for one-modification comparison" \
  "[0493x10f-suite] exact P/E root, no lambda/floor, no new particle pass" \
  "[0493x10f-suite] IMPORTANT: single liquid component only; disconnected liquid domains are NOT production-qualified" \
  "[0493x10f-suite] kBT=$KBT LiveVis=$LIVE_VIS_ENABLE filteredRecording=$FILTERED_RECORDING_ENABLE"

bash scripts/run_0493x9s_splash.sh
CSV="$RUN_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv"
[[ -f "$CSV" ]] || { echo "[0493x10f-suite] ERROR missing $CSV" >&2; exit 2; }
python3 scripts/analyze_0493x10f_global_reservoir_ablation.py "$CSV"
''')
run.chmod(0o755)

print('[0493x10f-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10f-patch] wrote scripts/run_0493x10f_global_reservoir_ablation.sh')
print('[0493x10f-patch] wrote scripts/analyze_0493x10f_global_reservoir_ablation.py')
print('[0493x10f-patch] wrote scripts/check_0493x10f_global_reaction_math.py')
