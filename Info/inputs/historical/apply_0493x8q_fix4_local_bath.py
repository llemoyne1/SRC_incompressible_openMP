#!/usr/bin/env python3
"""
0493x8q-fix4 — Neumann particle outlet as a local kinetic bath reconstructed
from interior moments.

Apply on top of the compiled x8q-fix3 state.

The fix3 particle-to-particle sampler was shown to be self-exciting in both the
cylinder and straight-channel Q6GF controls. fix4 removes that feedback: the
incoming half-space is generated independently from a local Maxwellian bath
whose density, mean velocity and temperature are reconstructed from the two
interior cell layers adjacent to each Neumann outlet cell.

Important implementation points:
  * moments are accumulated from PRE-STREAM positions x-v*dt, before outlet
    deletion, so the bath is not biased by the absorbing crossing performed
    later in the same boundary kernel;
  * outgoing particles are therefore included in the local state estimate;
  * the moment accumulation is fused into the existing O(N) boundary scan;
  * only particles in the two boundary layers execute atomics;
  * one small O(N_boundary_cells) kernel builds the incoming counts;
  * one small O(N_incoming) kernel samples the flux-weighted half-Maxwellian;
  * no new user parameter and no second O(N) particle scan are introduced;
  * mass/type metadata are sampled locally from one random particle in each bath
    cell, preserving local composition without copying that particle's velocity.

No clean-tree requirement; no git apply.
"""

from pathlib import Path
import re

ROOT = Path.cwd()
CU = ROOT / "src/cuda_classic_src_io_resident_0263.cu"
SIM = ROOT / "include/simulation_params.h"
TAG = "0493x8q-fix4"

for p in (CU, SIM):
    if not p.is_file():
        raise SystemExit(f"[{TAG}] missing {p}")


def function_span(text: str, name: str):
    s = text.find(name)
    if s < 0:
        raise SystemExit(f"[{TAG}] function not found: {name}")
    brace = text.find("{", s)
    if brace < 0:
        raise SystemExit(f"[{TAG}] opening brace not found: {name}")

    depth = 0
    i = brace
    state = "code"
    quote = ""
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""

        if state == "line":
            if c == "\n":
                state = "code"
            i += 1
            continue
        if state == "block":
            if c == "*" and n == "/":
                state = "code"
                i += 2
            else:
                i += 1
            continue
        if state == "string":
            if c == "\\":
                i += 2
                continue
            if c == quote:
                state = "code"
            i += 1
            continue

        if c == "/" and n == "/":
            state = "line"
            i += 2
            continue
        if c == "/" and n == "*":
            state = "block"
            i += 2
            continue
        if c in ('"', "'"):
            state = "string"
            quote = c
            i += 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return s, i + 1
        i += 1

    raise SystemExit(f"[{TAG}] unmatched braces: {name}")


def replace_function(text: str, name: str, replacement: str) -> str:
    s, e = function_span(text, name)
    return text[:s] + replacement.rstrip() + "\n" + text[e:]


cu = CU.read_text(encoding="utf-8")

required = (
    "outletNeumannKinetic0493x8q",
    "CudaNeumannGhostCandidate0493x8q",
    "NeumannGhostWorkspace0493x8q",
    "io_fullface_boundary_particles_kernel_0267",
    "io_neumann_ghost_insert_kernel_0493x8q",
    "ghostCopies0493x8q",
    "outletParticlesInserted",
)
missing = [x for x in required if x not in cu]
if missing:
    raise SystemExit(f"[{TAG}] expected x8q-fix3 state not found: {', '.join(missing)}")


# ---------------------------------------------------------------------------
# A. Candidate and bath structures.
# ---------------------------------------------------------------------------

candidate_pat = re.compile(
    r"struct\s+CudaNeumannGhostCandidate0493x8q\s*\{.*?\n\};",
    re.S,
)
candidate_new = r'''struct CudaNeumannGhostCandidate0493x8q {
    std::uint64_t source = 0ULL; // metadata source used when the bath count was built
    unsigned int bathCell = 0u;
    int face = -1;
    double particleMass = 1.0;
    std::uint32_t particleType = 0u;
};'''
cu, n = candidate_pat.subn(candidate_new, cu, count=1)
if n != 1:
    raise SystemExit(f"[{TAG}] candidate struct not found")

boundary_marker = "__global__ void io_fullface_boundary_particles_kernel_0267("
bath_insert_marker = "__global__ void io_neumann_ghost_insert_kernel_0493x8q("
bp = cu.find(bath_insert_marker)
if bp < 0:
    raise SystemExit(f"[{TAG}] Neumann insertion kernel marker not found")

bath_device = r'''
struct CudaNeumannBathMoments0493x8q {
    unsigned int count = 0u;
    double sumMass = 0.0;
    double sumMomX = 0.0;
    double sumMomY = 0.0;
    double sumMvv = 0.0;
    unsigned long long sourcePacked = 0ULL;

    // After io_neumann_bath_candidates_kernel_0493x8q these four fields are
    // overwritten with derived bath values:
    // sumMass=mbar, sumMomX=ux, sumMomY=uy, sumMvv=kBT.
};

__host__ __device__ inline unsigned int neumann_bath_cell_count_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg)
{
    const unsigned int nx = static_cast<unsigned int>(cfg.Nx > 0 ? cfg.Nx : 1);
    const unsigned int ny = static_cast<unsigned int>(cfg.Ny > 0 ? cfg.Ny : 1);
    return 2u * (nx + ny);
}

__host__ __device__ inline unsigned int neumann_bath_index_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int face,
    int tangentialCell)
{
    const unsigned int nx = static_cast<unsigned int>(cfg.Nx > 0 ? cfg.Nx : 1);
    const unsigned int ny = static_cast<unsigned int>(cfg.Ny > 0 ? cfg.Ny : 1);
    if (face == 0) return static_cast<unsigned int>(tangentialCell);
    if (face == 1) return ny + static_cast<unsigned int>(tangentialCell);
    if (face == 2) return 2u * ny + static_cast<unsigned int>(tangentialCell);
    return 2u * ny + nx + static_cast<unsigned int>(tangentialCell);
}

__host__ __device__ inline bool neumann_bath_decode_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    unsigned int bathCell,
    int& face,
    int& tangentialCell)
{
    const unsigned int nx = static_cast<unsigned int>(cfg.Nx > 0 ? cfg.Nx : 1);
    const unsigned int ny = static_cast<unsigned int>(cfg.Ny > 0 ? cfg.Ny : 1);
    if (bathCell < ny) {
        face = 0; tangentialCell = static_cast<int>(bathCell); return true;
    }
    bathCell -= ny;
    if (bathCell < ny) {
        face = 1; tangentialCell = static_cast<int>(bathCell); return true;
    }
    bathCell -= ny;
    if (bathCell < nx) {
        face = 2; tangentialCell = static_cast<int>(bathCell); return true;
    }
    bathCell -= nx;
    if (bathCell < nx) {
        face = 3; tangentialCell = static_cast<int>(bathCell); return true;
    }
    return false;
}

__device__ inline void accumulate_one_neumann_bath_0493x8q(
    std::uint64_t particleIndex,
    int face,
    int tangentialCell,
    double xp,
    double yp,
    double vxp,
    double vyp,
    double particleMass,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaNeumannBathMoments0493x8q* bath,
    unsigned int bathCellCount)
{
    if (outlet_mode_at_particle_0493x8q(cfg, face, xp, yp) != 2) return;
    const unsigned int bidx =
        neumann_bath_index_0493x8q(cfg, face, tangentialCell);
    if (bidx >= bathCellCount) return;

    CudaNeumannBathMoments0493x8q* b = bath + bidx;
    const double m = isfinite(particleMass) && particleMass > 0.0
        ? particleMass : cfg.refMass;

    atomicAdd(&b->count, 1u);
    atomicAdd(&b->sumMass, m);
    atomicAdd(&b->sumMomX, m * vxp);
    atomicAdd(&b->sumMomY, m * vyp);
    atomicAdd(&b->sumMvv, m * (vxp * vxp + vyp * vyp));

    if (particleIndex <= 0xffffffffULL) {
        const std::uint64_t z = splitmix64_device_0263(
            cfg.rngSeed ^
            (cfg.step * 0x9e3779b97f4a7c15ULL) ^
            (particleIndex * 0xbf58476d1ce4e5b9ULL) ^
            (static_cast<std::uint64_t>(bidx + 1u) * 0x94d049bb133111ebULL));
        const unsigned long long priority =
            static_cast<unsigned long long>(static_cast<unsigned int>(z >> 32));
        const unsigned long long packed =
            ((priority | 1ULL) << 32) |
            static_cast<unsigned long long>(
                static_cast<unsigned int>(particleIndex));
        atomicMax(&b->sourcePacked, packed);
    }
}

__device__ inline void accumulate_neumann_bath_moments_0493x8q(
    std::uint64_t particleIndex,
    double xpre,
    double ypre,
    double vxp,
    double vyp,
    double particleMass,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaNeumannBathMoments0493x8q* bath,
    unsigned int bathCellCount)
{
    if (!cfg.outletNeumannKinetic0493x8q ||
        bath == nullptr || bathCellCount == 0u) return;
    if (!(xpre >= cfg.xMin && xpre <= cfg.xMax &&
          ypre >= cfg.yMin && ypre <= cfg.yMax)) return;

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    if (!(dx > 0.0) || !(dy > 0.0)) return;

    constexpr int layers = 2;
    const bool nearLeft   = xpre <  cfg.xMin + layers * dx;
    const bool nearRight  = xpre >= cfg.xMax - layers * dx;
    const bool nearBottom = ypre <  cfg.yMin + layers * dy;
    const bool nearTop    = ypre >= cfg.yMax - layers * dy;
    if (!(nearLeft || nearRight || nearBottom || nearTop)) return;

    int ix = static_cast<int>(floor((xpre - cfg.xMin) / dx));
    int iy = static_cast<int>(floor((ypre - cfg.yMin) / dy));
    ix = imax_device_0263(0, imin_device_0263(nx - 1, ix));
    iy = imax_device_0263(0, imin_device_0263(ny - 1, iy));

    if (nearLeft) {
        accumulate_one_neumann_bath_0493x8q(
            particleIndex, 0, iy, xpre, ypre, vxp, vyp, particleMass,
            cfg, bath, bathCellCount);
    }
    if (nearRight) {
        accumulate_one_neumann_bath_0493x8q(
            particleIndex, 1, iy, xpre, ypre, vxp, vyp, particleMass,
            cfg, bath, bathCellCount);
    }
    if (nearBottom) {
        accumulate_one_neumann_bath_0493x8q(
            particleIndex, 2, ix, xpre, ypre, vxp, vyp, particleMass,
            cfg, bath, bathCellCount);
    }
    if (nearTop) {
        accumulate_one_neumann_bath_0493x8q(
            particleIndex, 3, ix, xpre, ypre, vxp, vyp, particleMass,
            cfg, bath, bathCellCount);
    }
}

__device__ inline double normal_pdf_0493x8q(double z)
{
    return 0.39894228040143267794 * exp(-0.5 * z * z);
}

__device__ inline double normal_cdf_0493x8q(double z)
{
    return 0.5 * erfc(-0.70710678118654752440 * z);
}

__device__ inline double incoming_normal_moment_0493x8q(double un, double sigma)
{
    if (!(sigma > 0.0) || !isfinite(sigma))
        return fmax(0.0, -un);
    const double a = un / sigma;
    const double m =
        sigma * normal_pdf_0493x8q(a) -
        un * (0.5 * erfc(0.70710678118654752440 * a));
    return isfinite(m) ? fmax(0.0, m) : 0.0;
}

__device__ inline double sample_incoming_normal_velocity_0493x8q(
    double un,
    double sigma,
    double uniform01)
{
    if (!(sigma > 0.0) || !isfinite(sigma))
        return un < 0.0 ? un : -0.0;

    const double zhi = -un / sigma;
    const double total = incoming_normal_moment_0493x8q(un, sigma);
    if (!(total > 0.0)) return -0.0;

    const double target = fmin(fmax(uniform01, 0.0), 1.0) * total;
    double zlo = fmin(-12.0, zhi - 12.0);
    double hi = zhi;

    for (int it = 0; it < 18; ++it) {
        const double z = 0.5 * (zlo + hi);
        const double F =
            sigma * normal_pdf_0493x8q(z) -
            un * normal_cdf_0493x8q(z);
        if (F < target) zlo = z;
        else hi = z;
    }
    return fmin(0.0, un + sigma * 0.5 * (zlo + hi));
}

__device__ inline double uniform_from_u64_0493x8q(std::uint64_t z)
{
    return static_cast<double>(z >> 11) * 0x1.0p-53;
}

__global__ void io_neumann_bath_candidates_kernel_0493x8q(
    std::uint64_t n,
    const double* __restrict__ mass,
    const std::uint32_t* __restrict__ type,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    CudaNeumannBathMoments0493x8q* __restrict__ bath,
    unsigned int bathCellCount,
    CudaNeumannGhostCandidate0493x8q* __restrict__ candidates,
    unsigned int* candidateCount,
    unsigned int candidateCapacity)
{
    const unsigned int bidx = blockIdx.x * blockDim.x + threadIdx.x;
    if (bidx >= bathCellCount) return;

    CudaNeumannBathMoments0493x8q& b = bath[bidx];
    const unsigned int N = b.count;
    if (N < 2u || !(b.sumMass > 0.0) || b.sourcePacked == 0ULL) return;

    int face = -1;
    int tangentialCell = -1;
    if (!neumann_bath_decode_0493x8q(cfg, bidx, face, tangentialCell)) return;

    const double sumM = b.sumMass;
    const double ux = b.sumMomX / sumM;
    const double uy = b.sumMomY / sumM;
    const double rel =
        b.sumMvv - (b.sumMomX * b.sumMomX + b.sumMomY * b.sumMomY) / sumM;

    double kBTlocal = 0.5 * fmax(0.0, rel) / static_cast<double>(N);
    if (!isfinite(kBTlocal) || kBTlocal < 0.0)
        kBTlocal = fmax(0.0, cfg.inletKBT);
    if (!(kBTlocal > 0.0) && cfg.inletKBT > 0.0)
        kBTlocal = cfg.inletKBT;

    const double mbar = sumM / static_cast<double>(N);
    const double sigmaBar =
        (kBTlocal > 0.0 && mbar > 0.0) ? sqrt(kBTlocal / mbar) : 0.0;

    double un = 0.0;
    double normalWidth = 1.0;
    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    constexpr double layers = 2.0;

    if (face == 0) { un = -ux; normalWidth = layers * dx; }
    else if (face == 1) { un = ux; normalWidth = layers * dx; }
    else if (face == 2) { un = -uy; normalWidth = layers * dy; }
    else if (face == 3) { un = uy; normalWidth = layers * dy; }
    else return;

    if (!(normalWidth > 0.0) || !(cfg.dt > 0.0)) return;

    const double oneWay = incoming_normal_moment_0493x8q(un, sigmaBar);
    const double lambda =
        static_cast<double>(N) * (cfg.dt / normalWidth) * oneWay;
    if (!(lambda > 0.0) || !isfinite(lambda)) return;

    const double baseD = floor(lambda);
    if (baseD > static_cast<double>(0xffffffffu - 1u)) return;
    unsigned int copies = static_cast<unsigned int>(baseD);
    const double frac = lambda - baseD;

    std::uint64_t z = splitmix64_device_0263(
        cfg.rngSeed ^
        (cfg.step * 0xd2b74407b1ce6e93ULL) ^
        (static_cast<std::uint64_t>(bidx + 1u) * 0x9e3779b97f4a7c15ULL));
    if (uniform_from_u64_0493x8q(z) < frac) ++copies;

    b.sumMass = mbar;
    b.sumMomX = ux;
    b.sumMomY = uy;
    b.sumMvv = kBTlocal;

    if (copies == 0u) return;

    const std::uint64_t source =
        static_cast<std::uint64_t>(
            static_cast<unsigned int>(b.sourcePacked & 0xffffffffULL));
    if (source >= n) return;

    const double particleMass =
        isfinite(mass[source]) && mass[source] > 0.0 ? mass[source] : mbar;
    const std::uint32_t particleType = type[source];

    const unsigned int first = atomicAdd(candidateCount, copies);
    if (first > candidateCapacity || copies > candidateCapacity - first) return;

    for (unsigned int k = 0u; k < copies; ++k) {
        CudaNeumannGhostCandidate0493x8q& c = candidates[first + k];
        c.source = source;
        c.bathCell = bidx;
        c.face = face;
        c.particleMass = particleMass;
        c.particleType = particleType;
    }
}
'''

cu = cu[:bp] + bath_device + cu[bp:]


# ---------------------------------------------------------------------------
# B. Boundary kernel: accumulate PRE-STREAM moments before any deletion.
# ---------------------------------------------------------------------------

s, e = function_span(cu, boundary_marker)
kernel = cu[s:e]

old = '''    double* __restrict__ vx,
    double* __restrict__ vy,
    unsigned char* __restrict__ role,
'''
new = '''    double* __restrict__ vx,
    double* __restrict__ vy,
    const double* __restrict__ mass,
    unsigned char* __restrict__ role,
'''
if old not in kernel:
    raise SystemExit(f"[{TAG}] boundary mass signature anchor not found")
kernel = kernel.replace(old, new, 1)

old = '''    CudaNeumannGhostCandidate0493x8q* ghostCandidates,
    unsigned int* ghostCandidateCount,
    unsigned int ghostCandidateCapacity)
'''
new = '''    CudaNeumannGhostCandidate0493x8q* ghostCandidates,
    unsigned int* ghostCandidateCount,
    unsigned int ghostCandidateCapacity,
    CudaNeumannBathMoments0493x8q* bathMoments0493x8q,
    unsigned int bathCellCount0493x8q)
'''
if old not in kernel:
    raise SystemExit(f"[{TAG}] boundary workspace signature anchor not found")
kernel = kernel.replace(old, new, 1)

needle = "    bool remove = false;\n"
if needle not in kernel:
    raise SystemExit(f"[{TAG}] boundary remove anchor not found")
acc = '''    const double xpre0493x8q = x[i] - vx[i] * cfg.dt;
    const double ypre0493x8q = y[i] - vy[i] * cfg.dt;
    accumulate_neumann_bath_moments_0493x8q(
        i, xpre0493x8q, ypre0493x8q, vx[i], vy[i], mass[i],
        cfg, bathMoments0493x8q, bathCellCount0493x8q);

'''
kernel = kernel.replace(needle, acc + needle, 1)

fix3_block = '''        unsigned int ghostCopies0493x8q = 0u;
        const int ghostFace0493x8q =
            neumann_ghost_face_for_survivor_0493x8q(
                cfg, i, x[i], y[i], vx[i], vy[i], ghostCopies0493x8q);
        record_neumann_ghost_candidate_0493x8q(
            i, ghostFace0493x8q, ghostCopies0493x8q,
            ghostCandidates, ghostCandidateCount,
            ghostCandidateCapacity, counters);
'''
if fix3_block not in kernel:
    raise SystemExit(f"[{TAG}] fix3 survivor sampler block not found")
kernel = kernel.replace(fix3_block, "", 1)

cu = cu[:s] + kernel + cu[e:]


# ---------------------------------------------------------------------------
# C. Replace insertion by an independent local-bath sampler.
# ---------------------------------------------------------------------------

inserter = r'''
__global__ void io_neumann_ghost_insert_kernel_0493x8q(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    const CudaNeumannGhostCandidate0493x8q* __restrict__ candidates,
    unsigned int candidateCount,
    const CudaNeumannBathMoments0493x8q* __restrict__ bath,
    unsigned int bathCellCount,
    const std::uint64_t* __restrict__ inactiveIndices,
    unsigned int inactiveCount,
    CudaClassicSrcIoCounters0263* counters)
{
    const unsigned int j = blockIdx.x * blockDim.x + threadIdx.x;
    if (j >= candidateCount) return;
    if (j >= inactiveCount) {
        atomicMax(&counters->overflowFlag, 9);
        return;
    }

    const CudaNeumannGhostCandidate0493x8q c = candidates[j];
    if (c.bathCell >= bathCellCount || c.face < 0 || c.face > 3) {
        atomicMax(&counters->failureFlag, 8);
        return;
    }

    const std::uint64_t slot = inactiveIndices[j];
    if (slot >= n || role[slot] != inactiveRole) {
        atomicMax(&counters->overflowFlag, 10);
        return;
    }

    const CudaNeumannBathMoments0493x8q b = bath[c.bathCell];
    const double ux = b.sumMomX;
    const double uy = b.sumMomY;
    const double kBTlocal = fmax(0.0, b.sumMvv);
    const double particleMass =
        c.particleMass > 0.0 ? c.particleMass :
        (b.sumMass > 0.0 ? b.sumMass : cfg.refMass);
    const double sigma =
        (kBTlocal > 0.0 && particleMass > 0.0)
        ? sqrt(kBTlocal / particleMass) : 0.0;

    double un = 0.0;
    double ut = 0.0;
    if (c.face == 0) { un = -ux; ut = uy; }
    else if (c.face == 1) { un = ux; ut = uy; }
    else if (c.face == 2) { un = -uy; ut = ux; }
    else { un = uy; ut = ux; }

    std::uint64_t z1 = splitmix64_device_0263(
        cfg.rngSeed ^
        (cfg.step * 0x94d049bb133111ebULL) ^
        (static_cast<std::uint64_t>(j + 1u) * 0x369dea0f31a53f85ULL) ^
        (static_cast<std::uint64_t>(c.bathCell + 1u) * 0x9e3779b97f4a7c15ULL));
    const std::uint64_t z2 = splitmix64_device_0263(z1 ^ 0x243f6a8885a308d3ULL);
    const std::uint64_t z3 = splitmix64_device_0263(z2 ^ 0x13198a2e03707344ULL);
    const std::uint64_t z4 = splitmix64_device_0263(z3 ^ 0xa4093822299f31d0ULL);
    const std::uint64_t z5 = splitmix64_device_0263(z4 ^ 0x082efa98ec4e6c89ULL);

    const double rFlux = uniform_from_u64_0493x8q(z1);
    const double r1 = fmax(1.0e-15, uniform_from_u64_0493x8q(z2));
    const double r2 = uniform_from_u64_0493x8q(z3);
    const double rNormalPos = uniform_from_u64_0493x8q(z4);
    const double rTangentialPos = uniform_from_u64_0493x8q(z5);

    const double vn =
        sample_incoming_normal_velocity_0493x8q(un, sigma, rFlux);
    const double gaussian =
        sqrt(-2.0 * log(r1)) *
        cos(6.28318530717958647693 * r2);
    const double vt = ut + sigma * gaussian;

    double vxp = 0.0;
    double vyp = 0.0;
    if (c.face == 0) { vxp = -vn; vyp = vt; }
    else if (c.face == 1) { vxp = vn; vyp = vt; }
    else if (c.face == 2) { vxp = vt; vyp = -vn; }
    else { vxp = vt; vyp = vn; }

    int decodedFace = -1;
    int tangentialCell = -1;
    if (!neumann_bath_decode_0493x8q(
            cfg, c.bathCell, decodedFace, tangentialCell) ||
        decodedFace != c.face) {
        atomicMax(&counters->failureFlag, 9);
        return;
    }

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    const double penetration = rNormalPos * fmax(0.0, -vn) * cfg.dt;

    double xp = 0.5 * (cfg.xMin + cfg.xMax);
    double yp = 0.5 * (cfg.yMin + cfg.yMax);

    if (c.face == 0 || c.face == 1) {
        yp = cfg.yMin +
            (static_cast<double>(tangentialCell) + rTangentialPos) * dy;
        xp = c.face == 0 ? cfg.xMin + penetration : cfg.xMax - penetration;
    } else {
        xp = cfg.xMin +
            (static_cast<double>(tangentialCell) + rTangentialPos) * dx;
        yp = c.face == 2 ? cfg.yMin + penetration : cfg.yMax - penetration;
    }

    xp = clamp_strictly_inside_device_0263(xp, cfg.xMin, cfg.xMax);
    yp = clamp_strictly_inside_device_0263(yp, cfg.yMin, cfg.yMax);

    x[slot] = xp;
    y[slot] = yp;
    vx[slot] = vxp;
    vy[slot] = vyp;
    mass[slot] = particleMass;
    type[slot] = c.particleType;
    role[slot] = fluidRole;

    add_counter_ull_0267(&counters->outletParticlesInserted, 1ULL);
    add_counter_ull_0267(&counters->fluidParticles, 1ULL);
}
'''
cu = replace_function(
    cu,
    "__global__ void io_neumann_ghost_insert_kernel_0493x8q(",
    inserter,
)


# ---------------------------------------------------------------------------
# D. Persistent host workspace.
# ---------------------------------------------------------------------------

workspace_pat = re.compile(
    r"struct\s+NeumannGhostWorkspace0493x8q\s*\{.*?\n\};",
    re.S,
)
workspace_new = r'''struct NeumannGhostWorkspace0493x8q {
    CudaNeumannGhostCandidate0493x8q* candidates = nullptr;
    unsigned int* count = nullptr;
    unsigned int capacity = 0u;

    CudaNeumannBathMoments0493x8q* bath = nullptr;
    unsigned int bathCells = 0u;
    unsigned int bathCapacity = 0u;
};'''
cu, n = workspace_pat.subn(workspace_new, cu, count=1)
if n != 1:
    raise SystemExit(f"[{TAG}] host workspace struct not found")

prepare = r'''
NeumannGhostWorkspace0493x8q prepare_neumann_ghost_candidates_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    std::uint64_t nActiveFluid)
{
    static NeumannGhostWorkspace0493x8q cached{};
    if (!cfg.outletNeumannKinetic0493x8q || nActiveFluid == 0ULL)
        return NeumannGhostWorkspace0493x8q{};

    const std::uint64_t boundaryCells =
        static_cast<std::uint64_t>(std::max(cfg.Nx, cfg.Ny));
    const std::uint64_t perCell = static_cast<std::uint64_t>(
        std::max(128, 4 * std::max(1, cfg.inletTargetOccupancy)));
    const std::uint64_t cap64 = std::min<std::uint64_t>(
        nActiveFluid, std::max<std::uint64_t>(1024ULL, boundaryCells * perCell));
    if (cap64 > static_cast<std::uint64_t>(
            std::numeric_limits<unsigned int>::max()))
        throw std::runtime_error(
            "0493x8q Neumann candidate capacity exceeds unsigned int");

    const unsigned int wanted = static_cast<unsigned int>(cap64);
    if (cached.capacity < wanted || cached.candidates == nullptr) {
        if (cached.candidates)
            check_cuda_0263(cudaFree(cached.candidates),
                            "resize 0493x8q Neumann candidates");
        check_cuda_0263(cudaMalloc(
            &cached.candidates,
            sizeof(CudaNeumannGhostCandidate0493x8q) *
                static_cast<std::size_t>(wanted)),
            "allocate 0493x8q Neumann candidates");
        cached.capacity = wanted;
    }
    if (cached.count == nullptr) {
        check_cuda_0263(cudaMalloc(&cached.count, sizeof(unsigned int)),
                        "allocate 0493x8q Neumann count");
    }

    const unsigned int wantedBath = neumann_bath_cell_count_0493x8q(cfg);
    if (cached.bathCapacity < wantedBath || cached.bath == nullptr) {
        if (cached.bath)
            check_cuda_0263(cudaFree(cached.bath),
                            "resize 0493x8q Neumann bath");
        check_cuda_0263(cudaMalloc(
            &cached.bath,
            sizeof(CudaNeumannBathMoments0493x8q) *
                static_cast<std::size_t>(wantedBath)),
            "allocate 0493x8q Neumann bath");
        cached.bathCapacity = wantedBath;
    }
    cached.bathCells = wantedBath;

    check_cuda_0263(cudaMemset(cached.count, 0, sizeof(unsigned int)),
                    "clear 0493x8q Neumann count");
    check_cuda_0263(cudaMemset(
        cached.bath, 0,
        sizeof(CudaNeumannBathMoments0493x8q) *
            static_cast<std::size_t>(cached.bathCells)),
        "clear 0493x8q Neumann bath");

    return cached;
}
'''
cu = replace_function(
    cu,
    "NeumannGhostWorkspace0493x8q prepare_neumann_ghost_candidates_0493x8q(",
    prepare,
)

read_count = r'''
unsigned int read_neumann_ghost_count_0493x8q(
    const NeumannGhostWorkspace0493x8q& w,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaParticleDeviceView view)
{
    if (w.count == nullptr || w.bath == nullptr || w.bathCells == 0u)
        return 0u;

    const int threads = 128;
    const unsigned int blocks =
        (w.bathCells + static_cast<unsigned int>(threads) - 1u) /
        static_cast<unsigned int>(threads);
    io_neumann_bath_candidates_kernel_0493x8q<<<blocks, threads>>>(
        view.n, view.mass, view.type, cfg,
        w.bath, w.bathCells,
        w.candidates, w.count, w.capacity);
    check_cuda_0263(cudaGetLastError(),
                    "io_neumann_bath_candidates_kernel_0493x8q launch");

    unsigned int n = 0u;
    check_cuda_0263(cudaMemcpy(
        &n, w.count, sizeof(unsigned int), cudaMemcpyDeviceToHost),
        "read 0493x8q Neumann bath count");
    if (n > w.capacity)
        throw std::runtime_error(
            "0493x8q Neumann candidate buffer overflow count=" +
            std::to_string(n) +
            " capacity=" + std::to_string(w.capacity));
    return n;
}
'''
cu = replace_function(
    cu,
    "unsigned int read_neumann_ghost_count_0493x8q(",
    read_count,
)

launch_insert = r'''
void launch_neumann_ghost_insert_0493x8q(
    CudaParticleDeviceView view,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    const NeumannGhostWorkspace0493x8q& w,
    unsigned int ghostCount,
    const std::uint64_t* dInactiveIndices,
    unsigned int inactiveCount,
    CudaClassicSrcIoCounters0263* dCounters,
    int threads,
    const char* label)
{
    if (ghostCount == 0u) return;
    if (ghostCount > inactiveCount)
        throw std::runtime_error(
            "0493x8q insufficient inactive slots for Neumann bath");

    const unsigned int blocks =
        (ghostCount + static_cast<unsigned int>(threads) - 1u) /
        static_cast<unsigned int>(threads);
    io_neumann_ghost_insert_kernel_0493x8q<<<blocks, threads>>>(
        view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
        kParticleRoleFluid, kParticleRoleInactive, cfg,
        w.candidates, ghostCount, w.bath, w.bathCells,
        dInactiveIndices, inactiveCount, dCounters);
    check_cuda_0263(cudaGetLastError(), label);
}
'''
cu = replace_function(
    cu,
    "void launch_neumann_ghost_insert_0493x8q(",
    launch_insert,
)


# ---------------------------------------------------------------------------
# E. Host launches.
# ---------------------------------------------------------------------------

search = 0
launches = 0
while True:
    k = cu.find("io_fullface_boundary_particles_kernel_0267<<<", search)
    if k < 0:
        break
    close = cu.find(");", k)
    if close < 0:
        raise SystemExit(f"[{TAG}] unterminated boundary kernel launch")
    reg = cu[k:close + 2]

    old = "view.n, view.x, view.y, view.vx, view.vy, view.role,"
    new = "view.n, view.x, view.y, view.vx, view.vy, view.mass, view.role,"
    if old not in reg:
        raise SystemExit(f"[{TAG}] boundary launch mass anchor not found")
    reg = reg.replace(old, new, 1)

    old = '''ghostWorkspace0493x8q.candidates, ghostWorkspace0493x8q.count,
            ghostWorkspace0493x8q.capacity);'''
    new = '''ghostWorkspace0493x8q.candidates, ghostWorkspace0493x8q.count,
            ghostWorkspace0493x8q.capacity,
            ghostWorkspace0493x8q.bath, ghostWorkspace0493x8q.bathCells);'''
    if old not in reg:
        raise SystemExit(f"[{TAG}] boundary launch workspace anchor not found")
    reg = reg.replace(old, new, 1)

    cu = cu[:k] + reg + cu[close + 2:]
    search = k + len(reg)
    launches += 1

if launches == 0:
    raise SystemExit(f"[{TAG}] no boundary kernel launch patched")

old = "read_neumann_ghost_count_0493x8q(ghostWorkspace0493x8q)"
new = "read_neumann_ghost_count_0493x8q(ghostWorkspace0493x8q, cfg, view)"
n_reads = cu.count(old)
if n_reads == 0:
    raise SystemExit(f"[{TAG}] Neumann count call anchor not found")
cu = cu.replace(old, new)

CU.write_text(cu, encoding="utf-8")


# ---------------------------------------------------------------------------
# F. Documentation.
# ---------------------------------------------------------------------------

sim = SIM.read_text(encoding="utf-8")
for old in (
    "stochastically sampling the adjacent interior distribution",
    "stochastically sampling the adjacent interior particle distribution",
    "mirror-copying the adjacent interior distribution",
):
    sim = sim.replace(
        old,
        "sampling an independent local kinetic bath reconstructed from adjacent interior moments",
    )
SIM.write_text(sim, encoding="utf-8")

print(f"[{TAG}] applied")
print(f"[{TAG}] Neumann bath: rho,u,kBT from two PRE-STREAM interior layers")
print(f"[{TAG}] incoming velocities: independent flux-weighted half-Maxwellian")
print(f"[{TAG}] local mass/type metadata: random interior source per bath cell")
print(f"[{TAG}] no new parameter; no second O(N) particle scan")
print(f"[{TAG}] boundary launches patched: {launches}")
print(f"[{TAG}] read-count calls patched: {n_reads}")
