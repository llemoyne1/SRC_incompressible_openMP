#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'
if not SRC.exists():
    raise SystemExit(f'[0493x10g-patch] missing {SRC}')

text = SRC.read_text()
if 'r1-global-single-component-reservoir-ablation' not in text:
    raise SystemExit('[0493x10g-patch] x10f prerequisite not found')
if '0493x10g hierarchical global reduction' in text:
    raise SystemExit('[0493x10g-patch] x10g already appears applied')


def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10g-patch] {label}: expected 1 anchor, found {n}')
    text = text.replace(old, new, 1)

# ---------------------------------------------------------------------------
# One compact partial record per CUDA block.  The final physics object remains
# KineticGlobalReaction0493x10f unchanged.
# ---------------------------------------------------------------------------
replace_once(
'''struct ResidentWorkspace0400 {\n''',
'''struct KineticGlobalReactionPartial0493x10g {\n    double A = 0.0;\n    double Sx = 0.0;\n    double Sy = 0.0;\n    double H = 0.0;\n    double receiverM = 0.0;\n    double receiverPx = 0.0;\n    double receiverPy = 0.0;\n    double cellSNormSum = 0.0;\n    unsigned long long donorCells = 0ull;\n    unsigned long long receiverCells = 0ull;\n};\n\nstruct ResidentWorkspace0400 {\n''',
'partial struct')

replace_once(
'''    DeviceBuffer0400<KineticGlobalReaction0493x10f> kineticGlobalReaction0493x10f;\n''',
'''    DeviceBuffer0400<KineticGlobalReaction0493x10f> kineticGlobalReaction0493x10f;\n    // 0493x10g performance-only: one atomics-free reduction record per cell block.\n    DeviceBuffer0400<KineticGlobalReactionPartial0493x10g> kineticGlobalReactionPartials0493x10g;\n''',
'workspace partial buffer')

replace_once(
'''    void ensure_kinetic_interface_0493x9x(int numCells) {\n        ensure_kinetic_interface_0493x9u(numCells);\n        kineticAccum0493x9x.ensure(1u);\n        kineticGlobalReaction0493x10f.ensure(1u);\n    }\n''',
'''    void ensure_kinetic_interface_0493x9x(int numCells, int reactionBlocks = 1) {\n        ensure_kinetic_interface_0493x9u(numCells);\n        kineticAccum0493x9x.ensure(1u);\n        kineticGlobalReaction0493x10f.ensure(1u);\n        kineticGlobalReactionPartials0493x10g.ensure(\n            static_cast<std::size_t>(std::max(1, reactionBlocks)));\n    }\n''',
'workspace ensure partials')

# ---------------------------------------------------------------------------
# Replace the contended global-atomic cell reduction with a hierarchical GPU
# reduction.  Each thread grid-strides across cells, each block reduces in
# registers/shared memory, and only one partial record is written per block.
# A second single-block kernel reduces <=1024 partial records into the exact
# same x10f global object.  The existing x10f finalizer is intentionally reused.
# ---------------------------------------------------------------------------
old_kernel_start = text.find('__global__ void q6_x10f_reduce_global_reaction(')
old_kernel_end = text.find('__global__ void q6_x10f_finalize_global_reaction(', old_kernel_start)
if old_kernel_start < 0 or old_kernel_end < 0:
    raise SystemExit('[0493x10g-patch] x10f reduction kernel range not found')
old_kernel = text[old_kernel_start:old_kernel_end]

new_kernel = r'''// 0493x10g hierarchical global reduction — PERFORMANCE ONLY.
//
// x10f physics is unchanged.  The x10f reducer used multiple atomicAdd(double)
// operations from every active receiver cell into the same handful of global
// scalars.  On the 800x400 single-drop qualification this produced heavy
// contention.  x10g computes the identical sums hierarchically:
//   cells -> one partial per CUDA block -> one final block -> x10f finalizer.
// No particle pass, reaction equation, donor/receiver membership, a, du,
// endpoint barrier, or surface-tension path is changed.
__global__ void q6_x10g_reduce_global_reaction_blocks(
    int numCells,
    const double* donorA,
    const double* donorSx,
    const double* donorSy,
    const double* donorH,
    const double* recvM,
    const double* recvPx,
    const double* recvPy,
    KineticGlobalReactionPartial0493x10g* partials) {
    double A = 0.0, Sx = 0.0, Sy = 0.0, H = 0.0;
    double receiverM = 0.0, receiverPx = 0.0, receiverPy = 0.0;
    double cellSNormSum = 0.0;
    unsigned long long donorCells = 0ull, receiverCells = 0ull;

    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < numCells; c += stride) {
        const double a = donorA[c];
        const double sx = donorSx[c];
        const double sy = donorSy[c];
        const double h = donorH[c];
        const double donorRequest = fabs(a) + fabs(sx) + fabs(sy) + fabs(h);
        if (donorRequest > 1.0e-30 &&
            isfinite(a) && isfinite(sx) && isfinite(sy) && isfinite(h)) {
            A += a;
            Sx += sx;
            Sy += sy;
            H += h;
            cellSNormSum += sqrt(sx * sx + sy * sy);
            ++donorCells;
        }

        const double mr = recvM[c];
        const double px = recvPx[c];
        const double py = recvPy[c];
        if (mr > 1.0e-14 && isfinite(mr) && isfinite(px) && isfinite(py)) {
            receiverM += mr;
            receiverPx += px;
            receiverPy += py;
            ++receiverCells;
        }
    }

    const unsigned mask = __activemask();
    for (int off = 16; off > 0; off >>= 1) {
        A += __shfl_down_sync(mask, A, off);
        Sx += __shfl_down_sync(mask, Sx, off);
        Sy += __shfl_down_sync(mask, Sy, off);
        H += __shfl_down_sync(mask, H, off);
        receiverM += __shfl_down_sync(mask, receiverM, off);
        receiverPx += __shfl_down_sync(mask, receiverPx, off);
        receiverPy += __shfl_down_sync(mask, receiverPy, off);
        cellSNormSum += __shfl_down_sync(mask, cellSNormSum, off);
        donorCells += __shfl_down_sync(mask, donorCells, off);
        receiverCells += __shfl_down_sync(mask, receiverCells, off);
    }

    __shared__ double sA[32], sSx[32], sSy[32], sH[32];
    __shared__ double sM[32], sPx[32], sPy[32], sNorm[32];
    __shared__ unsigned long long sDonor[32], sReceiver[32];
    const int lane = threadIdx.x & 31;
    const int warp = threadIdx.x >> 5;
    const int nWarps = (blockDim.x + 31) >> 5;
    if (lane == 0) {
        sA[warp] = A; sSx[warp] = Sx; sSy[warp] = Sy; sH[warp] = H;
        sM[warp] = receiverM; sPx[warp] = receiverPx; sPy[warp] = receiverPy;
        sNorm[warp] = cellSNormSum;
        sDonor[warp] = donorCells; sReceiver[warp] = receiverCells;
    }
    __syncthreads();

    if (warp == 0) {
        A = lane < nWarps ? sA[lane] : 0.0;
        Sx = lane < nWarps ? sSx[lane] : 0.0;
        Sy = lane < nWarps ? sSy[lane] : 0.0;
        H = lane < nWarps ? sH[lane] : 0.0;
        receiverM = lane < nWarps ? sM[lane] : 0.0;
        receiverPx = lane < nWarps ? sPx[lane] : 0.0;
        receiverPy = lane < nWarps ? sPy[lane] : 0.0;
        cellSNormSum = lane < nWarps ? sNorm[lane] : 0.0;
        donorCells = lane < nWarps ? sDonor[lane] : 0ull;
        receiverCells = lane < nWarps ? sReceiver[lane] : 0ull;
        for (int off = 16; off > 0; off >>= 1) {
            A += __shfl_down_sync(mask, A, off);
            Sx += __shfl_down_sync(mask, Sx, off);
            Sy += __shfl_down_sync(mask, Sy, off);
            H += __shfl_down_sync(mask, H, off);
            receiverM += __shfl_down_sync(mask, receiverM, off);
            receiverPx += __shfl_down_sync(mask, receiverPx, off);
            receiverPy += __shfl_down_sync(mask, receiverPy, off);
            cellSNormSum += __shfl_down_sync(mask, cellSNormSum, off);
            donorCells += __shfl_down_sync(mask, donorCells, off);
            receiverCells += __shfl_down_sync(mask, receiverCells, off);
        }
        if (lane == 0) {
            KineticGlobalReactionPartial0493x10g& p = partials[blockIdx.x];
            p.A = A; p.Sx = Sx; p.Sy = Sy; p.H = H;
            p.receiverM = receiverM; p.receiverPx = receiverPx; p.receiverPy = receiverPy;
            p.cellSNormSum = cellSNormSum;
            p.donorCells = donorCells; p.receiverCells = receiverCells;
        }
    }
}

__global__ void q6_x10g_reduce_global_reaction_partials(
    int numPartials,
    const KineticGlobalReactionPartial0493x10g* partials,
    KineticGlobalReaction0493x10f* global) {
    double A = 0.0, Sx = 0.0, Sy = 0.0, H = 0.0;
    double receiverM = 0.0, receiverPx = 0.0, receiverPy = 0.0;
    double cellSNormSum = 0.0;
    unsigned long long donorCells = 0ull, receiverCells = 0ull;

    for (int pidx = threadIdx.x; pidx < numPartials; pidx += blockDim.x) {
        const KineticGlobalReactionPartial0493x10g p = partials[pidx];
        A += p.A; Sx += p.Sx; Sy += p.Sy; H += p.H;
        receiverM += p.receiverM; receiverPx += p.receiverPx; receiverPy += p.receiverPy;
        cellSNormSum += p.cellSNormSum;
        donorCells += p.donorCells; receiverCells += p.receiverCells;
    }

    const unsigned mask = __activemask();
    for (int off = 16; off > 0; off >>= 1) {
        A += __shfl_down_sync(mask, A, off);
        Sx += __shfl_down_sync(mask, Sx, off);
        Sy += __shfl_down_sync(mask, Sy, off);
        H += __shfl_down_sync(mask, H, off);
        receiverM += __shfl_down_sync(mask, receiverM, off);
        receiverPx += __shfl_down_sync(mask, receiverPx, off);
        receiverPy += __shfl_down_sync(mask, receiverPy, off);
        cellSNormSum += __shfl_down_sync(mask, cellSNormSum, off);
        donorCells += __shfl_down_sync(mask, donorCells, off);
        receiverCells += __shfl_down_sync(mask, receiverCells, off);
    }

    __shared__ double sA[32], sSx[32], sSy[32], sH[32];
    __shared__ double sM[32], sPx[32], sPy[32], sNorm[32];
    __shared__ unsigned long long sDonor[32], sReceiver[32];
    const int lane = threadIdx.x & 31;
    const int warp = threadIdx.x >> 5;
    const int nWarps = (blockDim.x + 31) >> 5;
    if (lane == 0) {
        sA[warp] = A; sSx[warp] = Sx; sSy[warp] = Sy; sH[warp] = H;
        sM[warp] = receiverM; sPx[warp] = receiverPx; sPy[warp] = receiverPy;
        sNorm[warp] = cellSNormSum;
        sDonor[warp] = donorCells; sReceiver[warp] = receiverCells;
    }
    __syncthreads();

    if (warp == 0) {
        A = lane < nWarps ? sA[lane] : 0.0;
        Sx = lane < nWarps ? sSx[lane] : 0.0;
        Sy = lane < nWarps ? sSy[lane] : 0.0;
        H = lane < nWarps ? sH[lane] : 0.0;
        receiverM = lane < nWarps ? sM[lane] : 0.0;
        receiverPx = lane < nWarps ? sPx[lane] : 0.0;
        receiverPy = lane < nWarps ? sPy[lane] : 0.0;
        cellSNormSum = lane < nWarps ? sNorm[lane] : 0.0;
        donorCells = lane < nWarps ? sDonor[lane] : 0ull;
        receiverCells = lane < nWarps ? sReceiver[lane] : 0ull;
        for (int off = 16; off > 0; off >>= 1) {
            A += __shfl_down_sync(mask, A, off);
            Sx += __shfl_down_sync(mask, Sx, off);
            Sy += __shfl_down_sync(mask, Sy, off);
            H += __shfl_down_sync(mask, H, off);
            receiverM += __shfl_down_sync(mask, receiverM, off);
            receiverPx += __shfl_down_sync(mask, receiverPx, off);
            receiverPy += __shfl_down_sync(mask, receiverPy, off);
            cellSNormSum += __shfl_down_sync(mask, cellSNormSum, off);
            donorCells += __shfl_down_sync(mask, donorCells, off);
            receiverCells += __shfl_down_sync(mask, receiverCells, off);
        }
        if (lane == 0) {
            global->A = A; global->Sx = Sx; global->Sy = Sy; global->H = H;
            global->receiverM = receiverM;
            global->receiverPx = receiverPx; global->receiverPy = receiverPy;
            global->cellSNormSum = cellSNormSum;
            global->donorCells = donorCells; global->receiverCells = receiverCells;
        }
    }
}

'''
text = text[:old_kernel_start] + new_kernel + text[old_kernel_end:]

replace_once(
'''    ws.ensure_kinetic_interface_0493x9x(grid.numCells);\n''',
'''    ws.ensure_kinetic_interface_0493x9x(grid.numCells, cellBlocks);\n''',
'ensure x10g partial count')

replace_once(
'''        q6_x10f_reduce_global_reaction<<<cellBlocks, threads>>>(\n            grid.numCells,\n            ws.kineticRefM0493x9t.data(),\n            ws.kineticRefPx0493x9t.data(),\n            ws.kineticRefPy0493x9t.data(),\n            ws.kineticRefNx0493x9u.data(),\n            ws.kineticTxM0493x9t.data(),\n            ws.kineticTxPx0493x9t.data(),\n            ws.kineticTxPy0493x9t.data(),\n            ws.kineticGlobalReaction0493x10f.data());\n        check_cuda_0400(\n            cudaGetLastError(), "0493x10f global reaction reduce launch");\n\n        q6_x10f_finalize_global_reaction<<<1, 1>>>(\n''',
'''        q6_x10g_reduce_global_reaction_blocks<<<cellBlocks, threads>>>(\n            grid.numCells,\n            ws.kineticRefM0493x9t.data(),\n            ws.kineticRefPx0493x9t.data(),\n            ws.kineticRefPy0493x9t.data(),\n            ws.kineticRefNx0493x9u.data(),\n            ws.kineticTxM0493x9t.data(),\n            ws.kineticTxPx0493x9t.data(),\n            ws.kineticTxPy0493x9t.data(),\n            ws.kineticGlobalReactionPartials0493x10g.data());\n        check_cuda_0400(\n            cudaGetLastError(), "0493x10g global reaction block reduction launch");\n\n        q6_x10g_reduce_global_reaction_partials<<<1, threads>>>(\n            cellBlocks,\n            ws.kineticGlobalReactionPartials0493x10g.data(),\n            ws.kineticGlobalReaction0493x10f.data());\n        check_cuda_0400(\n            cudaGetLastError(), "0493x10g global reaction partial reduction launch");\n\n        q6_x10f_finalize_global_reaction<<<1, 1>>>(\n''',
'launch hierarchical reduction')

replace_once(
'''           "r1-global-single-component-reservoir-ablation;"\n           "multi-component-not-production;"\n''',
'''           "r1-global-single-component-reservoir-ablation;"\n           "0493x10g-hierarchical-global-reduction-performance-only;"\n           "multi-component-not-production;"\n''',
'CSV x10g contract tag')

SRC.write_text(text)

# ---------------------------------------------------------------------------
# Performance qualification runner.  Exact x10f physics; new RUN_ROOT only.
# ---------------------------------------------------------------------------
run = ROOT / 'scripts/run_0493x10g_global_reduction_perf.sh'
run.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export RUN_ROOT="${RUN_ROOT:-runs/0493x10g_global_reduction_perf}"
export STEPS="${STEPS:-800}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-25}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
export CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

printf '%s\n' \
  "[0493x10g-suite] PERFORMANCE ONLY: x10f global reaction equations/particle paths unchanged" \
  "[0493x10g-suite] reduction=cell-block partials -> one GPU block -> existing x10f finalizer" \
  "[0493x10g-suite] no new particle pass; no host reduction; no physics/configuration change" \
  "[0493x10g-suite] baseline x10f observed by user: 800 steps elapsed=146.04 s" \
  "[0493x10g-suite] kBT=0.125 r=1 LiveVis=$LIVE_VIS_ENABLE filteredRecording=$FILTERED_RECORDING_ENABLE"

bash scripts/run_0493x10f_global_reservoir_ablation.sh
''')
run.chmod(0o755)

# ---------------------------------------------------------------------------
# Pure numerical reduction check: direct and hierarchical grouping produce the
# same global invariants to floating-point summation tolerance, then the exact
# x10f root closes P/E.
# ---------------------------------------------------------------------------
chk = ROOT / 'scripts/check_0493x10g_global_reduction_math.py'
chk.write_text(r'''#!/usr/bin/env python3
import math
import random

rng = random.Random(4931007)
n = 320000
block_threads = 256
blocks = 1024
stride = block_threads * blocks

# Sparse donor cells + O(5000) receiver cells, matching the x10f regime.
donor = {}
for _ in range(220):
    c = rng.randrange(n)
    A = 10.0 ** rng.uniform(-5.0, -1.0)
    ang = rng.uniform(-math.pi, math.pi)
    smag = math.sqrt(A) * rng.uniform(0.1, 1.0)
    donor[c] = (A, smag*math.cos(ang), smag*math.sin(ang),
                rng.uniform(-1.0, 1.0)*math.sqrt(A))
recv = {}
for _ in range(5200):
    c = rng.randrange(n)
    m = rng.uniform(1.0, 40.0)
    ux = rng.uniform(-0.2, 0.2)
    uy = rng.uniform(-0.2, 0.2)
    recv[c] = (m, m*ux, m*uy)

def direct():
    A=Sx=Sy=H=M=Px=Py=sn=0.0; dc=rc=0
    for c,(a,sx,sy,h) in donor.items():
        A+=a; Sx+=sx; Sy+=sy; H+=h; sn+=math.hypot(sx,sy); dc+=1
    for c,(m,px,py) in recv.items():
        M+=m; Px+=px; Py+=py; rc+=1
    return (A,Sx,Sy,H,M,Px,Py,sn,dc,rc)

# Emulate x10g grouping order at a coarse level: one partial per CUDA block
# after the same grid-stride assignment, then sum partials.
def hierarchical():
    p = [[0.0]*8 + [0,0] for _ in range(blocks)]
    for c,(a,sx,sy,h) in donor.items():
        tid = c % stride
        b = tid // block_threads
        q=p[b]; q[0]+=a; q[1]+=sx; q[2]+=sy; q[3]+=h; q[7]+=math.hypot(sx,sy); q[8]+=1
    for c,(m,px,py) in recv.items():
        tid = c % stride
        b = tid // block_threads
        q=p[b]; q[4]+=m; q[5]+=px; q[6]+=py; q[9]+=1
    out=[0.0]*8+[0,0]
    for q in p:
        for j in range(8): out[j]+=q[j]
        out[8]+=q[8]; out[9]+=q[9]
    return tuple(out)

d=direct(); h=hierarchical()
scale=max(1.0, *(abs(x) for x in d[:8]))
maxdiff=max(abs(d[i]-h[i]) for i in range(8))
if d[8:] != h[8:]: raise SystemExit('FAIL integer counts differ')
if maxdiff > 5e-12*scale:
    raise SystemExit(f'FAIL reduction difference {maxdiff:.3e} scale={scale:.3e}')

A,Sx,Sy,H,M,Px,Py,*_ = h
ux,uy=Px/M,Py/M
B=(Sx*Sx+Sy*Sy)/M
a=2.0*(H-(ux*Sx+uy*Sy))/(A+B)
res=a*((ux*Sx+uy*Sy)-H)+0.5*a*a*(A+B)
print(f'maxDirectHierarchicalDifference={maxdiff:.3e}')
print(f'analyticRootResidual={abs(res):.3e}')
print(f'partialBlocks={blocks}')
print('status=PASS')
''')
chk.chmod(0o755)

print('[0493x10g-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10g-patch] wrote scripts/run_0493x10g_global_reduction_perf.sh')
print('[0493x10g-patch] wrote scripts/check_0493x10g_global_reduction_math.py')
