#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'
if not SRC.exists():
    raise SystemExit(f'[0493x10i-patch] missing {SRC}')

text = SRC.read_text()

if '0493x10h-mobile-interface-relative-thermal-retention' not in text:
    raise SystemExit('[0493x10i-patch] x10h prerequisite not found')
if '0493x10g-hierarchical-global-reduction-performance-only' not in text:
    raise SystemExit('[0493x10i-patch] x10g prerequisite not found')
if '0493x10i-shifted-mesoscopic-reservoirs' in text:
    raise SystemExit('[0493x10i-patch] x10i already appears applied')

def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10i-patch] {label}: expected 1 anchor, found {n}')
    text = text.replace(old, new, 1)

# Audit fields.
replace_once(
'''    double globalReactionDeltaUMagnitude = 0.0;
    double globalReactionFormulaResidual = 0.0;
};
''',
'''    double globalReactionDeltaUMagnitude = 0.0;
    double globalReactionFormulaResidual = 0.0;

    // 0493x10i shifted mesoscopic exact-reaction diagnostics.
    unsigned long long mesoReactionBlockCells = 0ull;
    unsigned long long mesoReactionShiftX = 0ull;
    unsigned long long mesoReactionShiftY = 0ull;
    unsigned long long mesoReactionReservoirSlots = 0ull;
    unsigned long long mesoReactionActiveReservoirs = 0ull;
    unsigned long long mesoReactionTrivialReservoirs = 0ull;
    unsigned long long mesoReactionInvalidReservoirs = 0ull;
    unsigned long long mesoReactionNoReceiverReservoirs = 0ull;
    unsigned long long mesoReactionDonorCells = 0ull;
    unsigned long long mesoReactionReceiverCells = 0ull;
    double mesoReactionReceiverMassSum = 0.0;
    double mesoReactionScaleSum = 0.0;
    double mesoReactionScaleAbsFromSpecularSum = 0.0;
    double mesoReactionDeltaUMagnitudeSum = 0.0;
    double mesoReactionCancellationSum = 0.0;
    double mesoReactionFormulaResidualAbsSum = 0.0;
};
''',
'audit mesoscopic fields')

# Reaction object array.
replace_once(
'''    void ensure_kinetic_interface_0493x9x(int numCells, int reactionBlocks = 1) {
        ensure_kinetic_interface_0493x9u(numCells);
        kineticAccum0493x9x.ensure(1u);
        kineticGlobalReaction0493x10f.ensure(1u);
        kineticGlobalReactionPartials0493x10g.ensure(
            static_cast<std::size_t>(std::max(1, reactionBlocks)));
    }
''',
'''    void ensure_kinetic_interface_0493x9x(
        int numCells, int reactionBlocks = 1, int reactionReservoirs = 1) {
        ensure_kinetic_interface_0493x9u(numCells);
        kineticAccum0493x9x.ensure(1u);
        kineticGlobalReaction0493x10f.ensure(
            static_cast<std::size_t>(std::max(1, reactionReservoirs)));
        kineticGlobalReactionPartials0493x10g.ensure(
            static_cast<std::size_t>(std::max(1, reactionBlocks)));
    }
''',
'workspace reaction array')

# Mapping helpers before x10g kernel marker.
marker = '// 0493x10g hierarchical global reduction — PERFORMANCE ONLY.\n'
helpers = r'''// 0493x10i shifted mesoscopic reservoirs.
//
// blockCells is the linear side in cell units (4 or 5 in the first sweep).
// For a shift s in [0,B-1], cells before s belong to edge reservoir 0 and the
// remaining cells are grouped by B. +1 in blocksX/blocksY reserves that edge
// slot without ever wrapping nonperiodic physical boundaries together.
__device__ __forceinline__ int q6_x10i_meso_axis_index(
    int i, int blockCells, int shift) {
    if (i < shift) return 0;
    return 1 + (i - shift) / blockCells;
}

__device__ __forceinline__ int q6_x10i_meso_reservoir_id(
    int cell, int nx, int blockCells, int shiftX, int shiftY, int blocksX) {
    const int i = cell % nx;
    const int j = cell / nx;
    const int bx = q6_x10i_meso_axis_index(i, blockCells, shiftX);
    const int by = q6_x10i_meso_axis_index(j, blockCells, shiftY);
    return by * blocksX + bx;
}

static inline std::uint64_t q6_x10i_mix64_host(std::uint64_t x) {
    x += 0x9e3779b97f4a7c15ull;
    x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ull;
    x = (x ^ (x >> 27)) * 0x94d049bb133111ebull;
    return x ^ (x >> 31);
}

'''
replace_once(marker, helpers + marker, 'insert meso mapping helpers')

# Meso kernels before x10f finalizer.
insert_before = '__global__ void q6_x10f_finalize_global_reaction(\n'
meso_kernels = r'''// 0493x10i: reduce existing per-cell donor/receiver statistics into
// shifted mesoscopic reservoirs. No particle pass is added.
__global__ void q6_x10i_reduce_meso_reactions(
    int numCells,
    int nx,
    int blockCells,
    int shiftX,
    int shiftY,
    int blocksX,
    const double* donorA,
    const double* donorSx,
    const double* donorSy,
    const double* donorH,
    const double* recvM,
    const double* recvPx,
    const double* recvPy,
    KineticGlobalReaction0493x10f* reactions) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;

    for (int c = idx; c < numCells; c += stride) {
        const int rid = q6_x10i_meso_reservoir_id(
            c, nx, blockCells, shiftX, shiftY, blocksX);
        KineticGlobalReaction0493x10f* r = &reactions[rid];

        const double A = donorA[c];
        const double Sx = donorSx[c];
        const double Sy = donorSy[c];
        const double H = donorH[c];
        const double donorRequest = fabs(A) + fabs(Sx) + fabs(Sy) + fabs(H);
        if (donorRequest > 1.0e-30 &&
            isfinite(A) && isfinite(Sx) && isfinite(Sy) && isfinite(H)) {
            atomic_add_double_0400(&r->A, A);
            atomic_add_double_0400(&r->Sx, Sx);
            atomic_add_double_0400(&r->Sy, Sy);
            atomic_add_double_0400(&r->H, H);
            atomic_add_double_0400(
                &r->cellSNormSum, sqrt(Sx * Sx + Sy * Sy));
            atomicAdd(&r->donorCells, 1ull);
        }

        const double mr = recvM[c];
        const double px = recvPx[c];
        const double py = recvPy[c];
        if (mr > 1.0e-14 && isfinite(mr) && isfinite(px) && isfinite(py)) {
            atomic_add_double_0400(&r->receiverM, mr);
            atomic_add_double_0400(&r->receiverPx, px);
            atomic_add_double_0400(&r->receiverPy, py);
            atomicAdd(&r->receiverCells, 1ull);
        }
    }
}

// Exact x10f root independently for every mesoscopic reservoir.
__global__ void q6_x10i_finalize_meso_reactions(
    int numReservoirs,
    int blockCells,
    int shiftX,
    int shiftY,
    KineticGlobalReaction0493x10f* reactions,
    KineticCrossingAccumulator0493x9x* audit) {
    const int rid = blockIdx.x * blockDim.x + threadIdx.x;
    if (rid >= numReservoirs) return;

    KineticGlobalReaction0493x10f* global = &reactions[rid];
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

    if (audit && rid == 0) {
        audit->mesoReactionBlockCells =
            static_cast<unsigned long long>(blockCells);
        audit->mesoReactionShiftX =
            static_cast<unsigned long long>(shiftX);
        audit->mesoReactionShiftY =
            static_cast<unsigned long long>(shiftY);
        audit->mesoReactionReservoirSlots =
            static_cast<unsigned long long>(numReservoirs);
    }

    const double request = fabs(A) + fabs(Sx) + fabs(Sy) + fabs(H);
    if (!(request > 1.0e-30) || !isfinite(request)) return;

    global->active = 1;
    double B = 0.0;
    double uRx = 0.0;
    double uRy = 0.0;
    double numer = 0.0;
    double denom = 0.0;
    double a = 0.0;
    bool valid = true;
    bool noReceiver = false;

    if (!(mr > 1.0e-14) || !isfinite(mr) ||
        !isfinite(global->receiverPx) || !isfinite(global->receiverPy)) {
        valid = false;
        noReceiver = true;
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
    const double duMag =
        sqrt(global->dux * global->dux + global->duy * global->duy);

    if (audit) {
        atomicAdd(&audit->mesoReactionActiveReservoirs, 1ull);
        if (global->trivial)
            atomicAdd(&audit->mesoReactionTrivialReservoirs, 1ull);
        if (global->invalid)
            atomicAdd(&audit->mesoReactionInvalidReservoirs, 1ull);
        if (noReceiver)
            atomicAdd(&audit->mesoReactionNoReceiverReservoirs, 1ull);
        atomicAdd(&audit->mesoReactionDonorCells, global->donorCells);
        atomicAdd(&audit->mesoReactionReceiverCells, global->receiverCells);
        atomic_add_double_0400(
            &audit->mesoReactionReceiverMassSum, mr > 0.0 ? mr : 0.0);
        atomic_add_double_0400(&audit->mesoReactionScaleSum, a);
        atomic_add_double_0400(
            &audit->mesoReactionScaleAbsFromSpecularSum, fabs(a - 2.0));
        atomic_add_double_0400(
            &audit->mesoReactionDeltaUMagnitudeSum, duMag);
        atomic_add_double_0400(
            &audit->mesoReactionCancellationSum, cancellation);
        atomic_add_double_0400(
            &audit->mesoReactionFormulaResidualAbsSum, fabs(residual));

        atomicAdd(&audit->reactionActiveCells, 1ull);
        atomicAdd(&audit->analyticConservativeReactionCells, 1ull);
        if (noReceiver)
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
            &audit->reactionDeltaUMagnitudeSum, duMag);
    }
}

'''
replace_once(insert_before, meso_kernels + insert_before, 'insert meso kernels')

# Apply signature and reservoir selection.
replace_once(
'''    const double* reactionLambda,
    const KineticGlobalReaction0493x10f* globalReaction,
    std::uint32_t phaseAType,
''',
'''    const double* reactionLambda,
    const KineticGlobalReaction0493x10f* mesoReactions,
    int mesoBlockCells,
    int mesoShiftX,
    int mesoShiftY,
    int mesoBlocksX,
    std::uint32_t phaseAType,
''',
'apply meso signature')

replace_once(
'''        const bool globalReactionActive =
            hardR1Reaction && globalReaction && globalReaction->active != 0;
        const bool receiver =
            !d.crossing &&
            (hardR1Reaction ? globalReactionActive
                            : (reactionActive[c] > 0.5));
''',
'''        const int mesoReactionCell =
            donor && d.bathCell >= 0 ? d.bathCell : c;
        const int mesoReactionId =
            hardR1Reaction && mesoReactions && mesoReactionCell >= 0
                ? q6_x10i_meso_reservoir_id(
                      mesoReactionCell, nx, mesoBlockCells,
                      mesoShiftX, mesoShiftY, mesoBlocksX)
                : -1;
        const KineticGlobalReaction0493x10f* mesoReaction =
            mesoReactionId >= 0 ? &mesoReactions[mesoReactionId] : nullptr;
        const bool mesoReactionActive =
            hardR1Reaction && mesoReaction && mesoReaction->active != 0;
        const bool receiver =
            !d.crossing &&
            (hardR1Reaction ? mesoReactionActive
                            : (reactionActive[c] > 0.5));
''',
'apply meso reaction selection')

replace_once(
'''                // x10f: one exact global scale for the whole current phase-A
                // reservoir.  Donors still keep their own local g_i and n_i.
                donorScale =
                    (globalReaction && globalReaction->active != 0)
                        ? globalReaction->a : 0.0;
''',
'''                // x10i: exact scale of the shifted mesoscopic reservoir
                // containing the donor's liquid bath cell.
                donorScale =
                    (mesoReaction && mesoReaction->active != 0)
                        ? mesoReaction->a : 0.0;
''',
'donor meso scale')

replace_once(
'''                // x10f global-reservoir ablation: every non-donor receiver in
                // this current phase-A set gets the same tiny +a*S/M_R shift.
                // This removes the cell-local outward counter-kick suspected
                // of generating the cardinal mass accumulation.
                const double dux = globalReaction ? globalReaction->dux : 0.0;
                const double duy = globalReaction ? globalReaction->duy : 0.0;
''',
'''                // x10i: receiver correction is local to the same shifted
                // mesoscopic reservoir, preserving exact P/E per reservoir.
                const double dux = mesoReaction ? mesoReaction->dux : 0.0;
                const double duy = mesoReaction ? mesoReaction->duy : 0.0;
''',
'receiver meso du')

# Orchestration config.
replace_once(
'''    ws.ensure_kinetic_interface_0493x9x(grid.numCells, cellBlocks);
''',
'''    const int mesoBlockCells =
        std::max(2, std::min(32,
            env_int_0400("MPCD_X10I_REACTION_BLOCK_CELLS", 5)));
    const std::uint64_t mesoHashX = q6_x10i_mix64_host(
        static_cast<std::uint64_t>(step) ^
        (static_cast<std::uint64_t>(params.rngSeed) + 0x10a10493ull));
    const std::uint64_t mesoHashY = q6_x10i_mix64_host(
        mesoHashX ^ 0xd1b54a32d192ed03ull);
    const int mesoShiftX =
        static_cast<int>(mesoHashX % static_cast<std::uint64_t>(mesoBlockCells));
    const int mesoShiftY =
        static_cast<int>(mesoHashY % static_cast<std::uint64_t>(mesoBlockCells));
    const int mesoBlocksX =
        2 + (std::max(1, grid.Nx) - 1) / mesoBlockCells;
    const int mesoBlocksY =
        2 + (std::max(1, grid.Ny) - 1) / mesoBlockCells;
    const int mesoReservoirs = mesoBlocksX * mesoBlocksY;

    ws.ensure_kinetic_interface_0493x9x(
        grid.numCells, cellBlocks, mesoReservoirs);
''',
'orchestration meso config')

old_hard = '''    if (r >= 1.0) {
        check_cuda_0400(
            cudaMemset(ws.kineticGlobalReaction0493x10f.data(), 0,
                       sizeof(KineticGlobalReaction0493x10f)),
            "0493x10f global reaction zero");

        q6_x10g_reduce_global_reaction_blocks<<<cellBlocks, threads>>>(
            grid.numCells,
            ws.kineticRefM0493x9t.data(),
            ws.kineticRefPx0493x9t.data(),
            ws.kineticRefPy0493x9t.data(),
            ws.kineticRefNx0493x9u.data(),
            ws.kineticTxM0493x9t.data(),
            ws.kineticTxPx0493x9t.data(),
            ws.kineticTxPy0493x9t.data(),
            ws.kineticGlobalReactionPartials0493x10g.data());
        check_cuda_0400(
            cudaGetLastError(), "0493x10g global reaction block reduction launch");

        q6_x10g_reduce_global_reaction_partials<<<1, threads>>>(
            cellBlocks,
            ws.kineticGlobalReactionPartials0493x10g.data(),
            ws.kineticGlobalReaction0493x10f.data());
        check_cuda_0400(
            cudaGetLastError(), "0493x10g global reaction partial reduction launch");

        q6_x10f_finalize_global_reaction<<<1, 1>>>(
            ws.kineticGlobalReaction0493x10f.data(), auditDev);
        check_cuda_0400(
            cudaGetLastError(), "0493x10f global reaction finalize launch");
    } else {
'''
new_hard = '''    if (r >= 1.0) {
        check_cuda_0400(
            cudaMemset(
                ws.kineticGlobalReaction0493x10f.data(), 0,
                static_cast<std::size_t>(mesoReservoirs) *
                    sizeof(KineticGlobalReaction0493x10f)),
            "0493x10i mesoscopic reaction array zero");

        q6_x10i_reduce_meso_reactions<<<cellBlocks, threads>>>(
            grid.numCells,
            grid.Nx,
            mesoBlockCells,
            mesoShiftX,
            mesoShiftY,
            mesoBlocksX,
            ws.kineticRefM0493x9t.data(),
            ws.kineticRefPx0493x9t.data(),
            ws.kineticRefPy0493x9t.data(),
            ws.kineticRefNx0493x9u.data(),
            ws.kineticTxM0493x9t.data(),
            ws.kineticTxPx0493x9t.data(),
            ws.kineticTxPy0493x9t.data(),
            ws.kineticGlobalReaction0493x10f.data());
        check_cuda_0400(
            cudaGetLastError(), "0493x10i mesoscopic reaction reduce launch");

        const int mesoFinalizeBlocks =
            (mesoReservoirs + threads - 1) / threads;
        q6_x10i_finalize_meso_reactions<<<mesoFinalizeBlocks, threads>>>(
            mesoReservoirs,
            mesoBlockCells,
            mesoShiftX,
            mesoShiftY,
            ws.kineticGlobalReaction0493x10f.data(),
            auditDev);
        check_cuda_0400(
            cudaGetLastError(), "0493x10i mesoscopic reaction finalize launch");
    } else {
'''
replace_once(old_hard, new_hard, 'replace global hard-r1 reduction')

replace_once(
'''        ws.kineticRefNy0493x9u.data(),
        ws.kineticGlobalReaction0493x10f.data(),
        phaseAType,
''',
'''        ws.kineticRefNy0493x9u.data(),
        ws.kineticGlobalReaction0493x10f.data(),
        mesoBlockCells,
        mesoShiftX,
        mesoShiftY,
        mesoBlocksX,
        phaseAType,
''',
'apply meso args')

# CSV.
replace_once(
'''               "globalReactionDeltaUMagnitude,globalReactionFormulaResidual,"
               "contract\\n";
''',
'''               "globalReactionDeltaUMagnitude,globalReactionFormulaResidual,"
               "mesoReactionBlockCells,mesoReactionShiftX,mesoReactionShiftY,"
               "mesoReactionReservoirSlots,mesoReactionActiveReservoirs,"
               "mesoReactionTrivialReservoirs,mesoReactionInvalidReservoirs,"
               "mesoReactionNoReceiverReservoirs,mesoReactionDonorCells,"
               "mesoReactionReceiverCells,mesoReactionReceiverMassSum,"
               "mesoReactionScaleMean,mesoReactionScaleAbsFromSpecularMean,"
               "mesoReactionDeltaUMagnitudeMean,mesoReactionCancellationMean,"
               "mesoReactionFormulaResidualAbsSum,"
               "contract\\n";
''',
'CSV meso header')

replace_once(
'''    const double meanAnalyticScaleAbsFrom2 = a.analyticPositiveScaleCells > 0ull ?
        a.analyticDonorScaleAbsFromSpecularSum /
            static_cast<double>(a.analyticPositiveScaleCells) : 0.0;
''',
'''    const double meanAnalyticScaleAbsFrom2 = a.analyticPositiveScaleCells > 0ull ?
        a.analyticDonorScaleAbsFromSpecularSum /
            static_cast<double>(a.analyticPositiveScaleCells) : 0.0;
    const double meanMesoScale =
        a.mesoReactionActiveReservoirs > 0ull ?
        a.mesoReactionScaleSum /
            static_cast<double>(a.mesoReactionActiveReservoirs) : 0.0;
    const double meanMesoScaleAbsFrom2 =
        a.mesoReactionActiveReservoirs > 0ull ?
        a.mesoReactionScaleAbsFromSpecularSum /
            static_cast<double>(a.mesoReactionActiveReservoirs) : 0.0;
    const double meanMesoDU =
        a.mesoReactionActiveReservoirs > 0ull ?
        a.mesoReactionDeltaUMagnitudeSum /
            static_cast<double>(a.mesoReactionActiveReservoirs) : 0.0;
    const double meanMesoCancellation =
        a.mesoReactionActiveReservoirs > 0ull ?
        a.mesoReactionCancellationSum /
            static_cast<double>(a.mesoReactionActiveReservoirs) : 0.0;
''',
'CSV meso means')

replace_once(
'''        << a.globalReactionDeltaUMagnitude << ','
        << a.globalReactionFormulaResidual << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'''        << a.globalReactionDeltaUMagnitude << ','
        << a.globalReactionFormulaResidual << ','
        << a.mesoReactionBlockCells << ',' << a.mesoReactionShiftX << ','
        << a.mesoReactionShiftY << ',' << a.mesoReactionReservoirSlots << ','
        << a.mesoReactionActiveReservoirs << ','
        << a.mesoReactionTrivialReservoirs << ','
        << a.mesoReactionInvalidReservoirs << ','
        << a.mesoReactionNoReceiverReservoirs << ','
        << a.mesoReactionDonorCells << ',' << a.mesoReactionReceiverCells << ','
        << a.mesoReactionReceiverMassSum << ',' << meanMesoScale << ','
        << meanMesoScaleAbsFrom2 << ',' << meanMesoDU << ','
        << meanMesoCancellation << ','
        << a.mesoReactionFormulaResidualAbsSum << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'CSV meso row')

replace_once(
'''           "0493x10h-mobile-interface-relative-thermal-retention;"
           "multi-component-not-production;"
''',
'''           "0493x10h-mobile-interface-relative-thermal-retention;"
           "0493x10i-shifted-mesoscopic-reservoirs;"
           "mesoscopic-block-size-runtime-4-or-5;"
           "deterministic-step-shifted-reaction-partition;"
           "multi-component-not-production-no-ccl;"
''',
'CSV x10i tag')

SRC.write_text(text)

# Analyzer.
an = ROOT / 'scripts/analyze_0493x10i_mesoscopic_reservoirs.py'
an.write_text(r'''#!/usr/bin/env python3
import csv
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(
        'usage: analyze_0493x10i_mesoscopic_reservoirs.py '
        '<cuda_phase_kinetic_crossing_0493x9z.csv>')

p = Path(sys.argv[1])
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10i-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)
def weighted_mean(value_key, count_key):
    den=sum(I(r,count_key) for r in rows)
    num=sum(F(r,value_key)*I(r,count_key) for r in rows)
    return num/den if den else 0.0

last=rows[-1]
active=isum('mesoReactionActiveReservoirs')
trivial=isum('mesoReactionTrivialReservoirs')
invalid=isum('mesoReactionInvalidReservoirs')
no_recv=isum('mesoReactionNoReceiverReservoirs')
dp=max(maxabs('deltaPx'),maxabs('deltaPy'))
de=maxabs('deltaKineticEnergy')
formula=max(F(r,'mesoReactionFormulaResidualAbsSum') for r in rows)
deep=max(I(r,'deepOuterParticles') for r in rows)

print('===== 0493x10i SHIFTED MESOSCOPIC RESERVOIRS =====')
print(f'file={p} rows={len(rows)} lastStep={I(last,"step")}')
print(f'blockCells={I(last,"mesoReactionBlockCells")} '
      f'lastShift=({I(last,"mesoReactionShiftX")},{I(last,"mesoReactionShiftY")}) '
      f'reservoirSlots={I(last,"mesoReactionReservoirSlots")}')
print('--- reaction reservoirs ---')
print(f'active={active} trivial={trivial} invalid={invalid} noReceiver={no_recv}')
print(f'trivialFraction={(trivial/active if active else 0):.6%} '
      f'invalidFraction={(invalid/active if active else 0):.6%}')
print(f'meanA={weighted_mean("mesoReactionScaleMean","mesoReactionActiveReservoirs"):.9g} '
      f'mean|a-2|={weighted_mean("mesoReactionScaleAbsFromSpecularMean","mesoReactionActiveReservoirs"):.9g}')
print(f'mean|du|={weighted_mean("mesoReactionDeltaUMagnitudeMean","mesoReactionActiveReservoirs"):.9g} '
      f'meanCancellation={weighted_mean("mesoReactionCancellationMean","mesoReactionActiveReservoirs"):.9g}')
print(f'last donorCells={I(last,"mesoReactionDonorCells")} '
      f'receiverCells={I(last,"mesoReactionReceiverCells")} '
      f'receiverMass={F(last,"mesoReactionReceiverMassSum"):.9g}')
print('--- actual conservation / mobile interface ---')
print(f'max|deltaP|={dp:.12e}')
print(f'max|deltaKE|={de:.12e}')
print(f'maxMesoFormulaResidualAbsSum={formula:.12e}')
print(f'maxDeepOuter={deep}')
print(f'universalHardBarrierChecks={isum("hardFinalEndpointChecks")}')
print(f'interiorDonorFinalOutside={isum("appliedInteriorFinalOutside")} '
      f'shellDonorFinalOutside={isum("shellHardRetentionFinalOutside")}')

cons=(dp < 1e-8 and de < 1e-9 and formula < 1e-8)
mobile=(isum('hardFinalEndpointChecks')==0)
seal=(isum('appliedInteriorFinalOutside')==0 and
      isum('shellHardRetentionFinalOutside')==0)
finite=(invalid==0)
print('conservationContract=' + ('PASS' if cons else 'FAIL'))
print('mobileInterfaceContract=' + ('PASS' if mobile else 'FAIL'))
print('thermalDonorSealContract=' + ('PASS' if seal else 'FAIL'))
print('mesoscopicFiniteContract=' + ('PASS' if finite else 'FAIL'))
print('shapeContract=VISUAL_PENDING')
print('multiComponentContract=NOT_QUALIFIED_NO_CCL')
''')
an.chmod(0o755)

# Static drop runner and sweep.
run = ROOT / 'scripts/run_0493x10i_mesoscopic_drop.sh'
run.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

B="${MPCD_X10I_REACTION_BLOCK_CELLS:-5}"
export MPCD_X10I_REACTION_BLOCK_CELLS="$B"
export TARGET=wall
export RUN_ROOT="${RUN_ROOT:-runs/0493x10i_mesoscopic_drop_b${B}}"
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
  echo "[0493x10i-suite] ERROR qualification intentionally restricted to r=1" >&2
  exit 2
fi

printf '%s\n' \
  "[0493x10i-suite] shifted mesoscopic exact P/E reservoirs, B=${B}x${B}" \
  "[0493x10i-suite] x10h mobile interface + relative thermal donor retention retained" \
  "[0493x10i-suite] deterministic step-shifted partition; no CCL yet" \
  "[0493x10i-suite] small/disconnected liquid components NOT production-qualified" \
  "[0493x10i-suite] kBT=$KBT LiveVis=$LIVE_VIS_ENABLE filteredRecording=$FILTERED_RECORDING_ENABLE"

bash scripts/run_0493x9s_splash.sh

CSV="$RUN_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv"
[[ -f "$CSV" ]] || { echo "[0493x10i-suite] ERROR missing $CSV" >&2; exit 2; }
python3 scripts/analyze_0493x10i_mesoscopic_reservoirs.py "$CSV"
''')
run.chmod(0o755)

sweep = ROOT / 'scripts/run_0493x10i_mesoscopic_drop_sweep_4_5.sh'
sweep.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
mkdir -p logs

for B in 4 5; do
  echo
  echo "===== 0493x10i B=${B}x${B} ====="
  MPCD_X10I_REACTION_BLOCK_CELLS="$B" \
  RUN_ROOT="runs/0493x10i_mesoscopic_drop_b${B}" \
  LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
  LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}" \
  LIVE_VIS_HOLD_ON_EXIT=0 \
  FILTERED_RECORDING_ENABLE=0 \
  STEPS="${STEPS:-800}" \
  SUMMARY_EVERY="${SUMMARY_EVERY:-25}" \
  CLEAN_RUN_ROOT=1 \
  bash scripts/run_0493x10i_mesoscopic_drop.sh \
    2>&1 | tee "logs/0493x10i_mesoscopic_drop_b${B}.log"
done
''')
sweep.chmod(0o755)

# Pure math/partition check.
chk = ROOT / 'scripts/check_0493x10i_mesoscopic_reaction_math.py'
chk.write_text(r'''#!/usr/bin/env python3
import math
import random

rng=random.Random(4931010)

def rid(c,nx,B,sx,sy,nbx):
    i=c%nx; j=c//nx
    bx=0 if i<sx else 1+(i-sx)//B
    by=0 if j<sy else 1+(j-sy)//B
    return by*nbx+bx

def test(B):
    nx,ny=200,120
    sx,sy=(B-1)//2, B//2
    nbx=2+(nx-1)//B
    nby=2+(ny-1)//B
    slots=nbx*nby
    seen=[0]*slots
    for c in range(nx*ny):
        r=rid(c,nx,B,sx,sy,nbx)
        if not (0<=r<slots):
            raise SystemExit(f'FAIL B={B}: invalid reservoir id {r}')
        seen[r]+=1
    if sum(seen)!=nx*ny:
        raise SystemExit(f'FAIL B={B}: partition coverage')

    maxP=maxE=0.0
    active=0
    for _ in range(2000):
        nd=rng.randint(1,8)
        nrx=rng.randint(5,80)
        donors=[]
        A=Sx=Sy=H=0.0
        for _ in range(nd):
            m=rng.uniform(.5,2.0); g=rng.uniform(.01,.8)
            ang=rng.uniform(-math.pi,math.pi)
            nxv,nyv=math.cos(ang),math.sin(ang)
            vx=rng.uniform(-.5,.5); vy=rng.uniform(-.5,.5)
            donors.append((m,g,nxv,nyv,vx,vy))
            A+=m*g*g; Sx+=m*g*nxv; Sy+=m*g*nyv
            H+=m*g*(vx*nxv+vy*nyv)
        receivers=[]; M=Px=Py=0.0
        for _ in range(nrx):
            m=rng.uniform(.5,2.0); vx=rng.uniform(-.5,.5); vy=rng.uniform(-.5,.5)
            receivers.append((m,vx,vy)); M+=m; Px+=m*vx; Py+=m*vy
        ux,uy=Px/M,Py/M
        den=A+(Sx*Sx+Sy*Sy)/M
        num=2*(H-(ux*Sx+uy*Sy))
        a=num/den
        if not (a>0 and math.isfinite(a)):
            continue
        active+=1
        dux=a*Sx/M; duy=a*Sy/M
        dpx=dpy=dE=0.0
        for m,g,nxv,nyv,vx,vy in donors:
            nvx=vx-a*g*nxv; nvy=vy-a*g*nyv
            dpx+=m*(nvx-vx); dpy+=m*(nvy-vy)
            dE+=.5*m*((nvx*nvx+nvy*nvy)-(vx*vx+vy*vy))
        for m,vx,vy in receivers:
            nvx=vx+dux; nvy=vy+duy
            dpx+=m*(nvx-vx); dpy+=m*(nvy-vy)
            dE+=.5*m*((nvx*nvx+nvy*nvy)-(vx*vx+vy*vy))
        maxP=max(maxP,math.hypot(dpx,dpy)); maxE=max(maxE,abs(dE))
    print(f'B={B} slots={slots} usedSlots={sum(v>0 for v in seen)} '
          f'activeSynthetic={active} maxMomentumResidual={maxP:.3e} '
          f'maxEnergyResidual={maxE:.3e}')
    if maxP>1e-10 or maxE>1e-10:
        raise SystemExit(f'FAIL B={B}: conservation residual')

for B in (4,5):
    test(B)
print('status=PASS')
''')
chk.chmod(0o755)

print('[0493x10i-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10i-patch] wrote scripts/analyze_0493x10i_mesoscopic_reservoirs.py')
print('[0493x10i-patch] wrote scripts/run_0493x10i_mesoscopic_drop.sh')
print('[0493x10i-patch] wrote scripts/run_0493x10i_mesoscopic_drop_sweep_4_5.sh')
print('[0493x10i-patch] wrote scripts/check_0493x10i_mesoscopic_reaction_math.py')
print('[0493x10i-patch] x10h mobile-interface semantics retained; no CCL yet')
