#!/usr/bin/env python3
"""
0493x8q — complete openBoundaryOutletMode=neumann with a kinetic
zero-normal-gradient continuation on the resident CUDA inlet/outlet path.

The Q6/Q6-G-F Neumann face already extrapolates the local interior normal
velocity (0493x8l).  x8q fixes the particle counterpart: outward crossings
remain natural deletions, while the missing inward half-space flux is restored
by mirror-copying the adjacent interior particle distribution.

Performance rule: candidate detection is fused into the existing O(N) boundary
kernel.  The added work is one compact candidate buffer, one scalar count copy,
and one tiny kernel over O(boundary flux) particles; no extra O(N) particle
scan is introduced.

This script performs targeted semantic edits and intentionally does not require
a clean Git tree.
"""

from pathlib import Path
import re

ROOT = Path.cwd()
CU = ROOT / "src/cuda_classic_src_io_resident_0263.cu"
SIM = ROOT / "include/simulation_params.h"
BOUNDARY = ROOT / "include/boundary_base.h"
RSUM_H = ROOT / "include/runtime_summary.h"
RSUM_CPP = ROOT / "src/runtime_summary.cpp"
TAG = "0493x8q"

for p in (CU, SIM, BOUNDARY, RSUM_H, RSUM_CPP):
    if not p.is_file():
        raise SystemExit(f"[{TAG}] missing {p}")


def one(text, old, new, label):
    if old not in text:
        raise SystemExit(f"[{TAG}] anchor not found: {label}")
    return text.replace(old, new, 1)


def all_required(text, old, new, label):
    if old not in text:
        raise SystemExit(f"[{TAG}] anchor not found: {label}")
    return text.replace(old, new)


# ---------------------------------------------------------------------------
# Documentation and public diagnostics.
# ---------------------------------------------------------------------------
sim = SIM.read_text(encoding="utf-8")
old = (
    "    //   neumann          : passive outlet; only particles that actually cross\n"
    "    //                      the outlet boundary are deleted.\n"
)
new = (
    "    //   neumann          : zero-normal-gradient open boundary. Particles that\n"
    "    //                      cross outward are deleted, while the resident CUDA\n"
    "    //                      path supplies the inward kinetic half-space flux by\n"
    "    //                      mirror-copying the adjacent interior distribution.\n"
    "    //                      This is the particle counterpart of the local Q6/Q6-G-F\n"
    "    //                      Neumann face extrapolation, not an absorbing vacuum.\n"
)
if old in sim:
    sim = sim.replace(old, new, 1)
elif "mirror-copying the adjacent interior distribution" not in sim:
    raise SystemExit(f"[{TAG}] simulation_params Neumann comment anchor not found")
SIM.write_text(sim, encoding="utf-8")

for p in (BOUNDARY, RSUM_H):
    text = p.read_text(encoding="utf-8")
    if "outletParticlesInserted" not in text:
        text = one(
            text,
            "    std::uint64_t outletParticlesDeleted = 0;\n"
            "    std::uint64_t inletParticlesInserted = 0;\n",
            "    std::uint64_t outletParticlesDeleted = 0;\n"
            "    std::uint64_t outletParticlesInserted = 0;\n"
            "    std::uint64_t inletParticlesInserted = 0;\n",
            f"{p.name} outlet insertion diagnostic",
        )
    p.write_text(text, encoding="utf-8")

rs = RSUM_CPP.read_text(encoding="utf-8")
if "s.outletParticlesInserted = boundary->outletParticlesInserted;" not in rs:
    rs = one(
        rs,
        "        s.outletParticlesDeleted = boundary->outletParticlesDeleted;\n"
        "        s.inletParticlesInserted = boundary->inletParticlesInserted;\n",
        "        s.outletParticlesDeleted = boundary->outletParticlesDeleted;\n"
        "        s.outletParticlesInserted = boundary->outletParticlesInserted;\n"
        "        s.inletParticlesInserted = boundary->inletParticlesInserted;\n",
        "runtime summary boundary mapping",
    )

rs = rs.replace(
    "inletBackflowDeleted,outletParticlesDeleted,inletParticlesInserted,inletNetParticleDelta",
    "inletBackflowDeleted,outletParticlesDeleted,outletParticlesInserted,inletParticlesInserted,inletNetParticleDelta",
)

if "<< s.outletParticlesInserted << ','" not in rs:
    m = re.search(
        r"(<<\s*s\.outletParticlesDeleted\s*<<\s*','\s*)"
        r"(<<\s*s\.inletParticlesInserted\s*<<\s*','\s*)",
        rs,
    )
    if not m:
        raise SystemExit(f"[{TAG}] runtime summary CSV row anchor not found")
    rs = rs[:m.start()] + m.group(1) + "<< s.outletParticlesInserted << ',' " + m.group(2) + rs[m.end():]
RSUM_CPP.write_text(rs, encoding="utf-8")


# ---------------------------------------------------------------------------
# CUDA implementation.
# ---------------------------------------------------------------------------
cu = CU.read_text(encoding="utf-8")

if "outletNeumannKinetic0493x8q" not in cu:
    cu = one(
        cu,
        "    int outletRegimeCode = 0; // 0 passive/neumann, 1 equilibrium_flux, 2 forced_flux\n",
        "    int outletRegimeCode = 0; // 0 natural crossing, 1 equilibrium_flux, 2 forced_flux\n"
        "    int outletNeumannKinetic0493x8q = 0; // mirror exterior kinetic continuation\n",
        "config outlet regime",
    )

if "unsigned long long outletParticlesInserted" not in cu:
    cu = one(
        cu,
        "    unsigned long long outletParticlesDeleted = 0ULL;\n",
        "    unsigned long long outletParticlesDeleted = 0ULL;\n"
        "    unsigned long long outletParticlesInserted = 0ULL;\n",
        "CUDA counters outlet insertion",
    )

if "cfg.outletNeumannKinetic0493x8q" not in cu:
    cu = one(
        cu,
        "    cfg.outletRegimeCode = outlet_regime_code_0291(params);\n",
        "    cfg.outletRegimeCode = outlet_regime_code_0291(params);\n"
        "    {\n"
        "        std::string mode0493x8q = params.openBoundaryOutletMode;\n"
        "        std::replace(mode0493x8q.begin(), mode0493x8q.end(), '-', '_');\n"
        "        cfg.outletNeumannKinetic0493x8q = mode0493x8q == \"neumann\" ? 1 : 0;\n"
        "    }\n",
        "make_config Neumann flag",
    )

# Candidate/clone implementation before the existing parallel boundary kernel.
marker = "__global__ void io_fullface_boundary_particles_kernel_0267("
if "struct CudaNeumannGhostCandidate0493x8q" not in cu:
    pos = cu.find(marker)
    if pos < 0:
        raise SystemExit(f"[{TAG}] boundary kernel marker not found")
    helper = r'''
struct CudaNeumannGhostCandidate0493x8q {
    std::uint64_t source = 0ULL;
    int face = -1;
};

__device__ inline int outlet_mode_at_particle_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int face,
    double xp,
    double yp)
{
    int mode = 0;
    if (face == 0) mode = cfg.leftMode;
    else if (face == 1) mode = cfg.rightMode;
    else if (face == 2) mode = cfg.bottomMode;
    else if (face == 3) mode = cfg.topMode;
    if (cfg.segmentedEnable) {
        const double s = segment_s_device_0263(face, xp, yp, cfg);
        mode = segment_mode_at_device_0263(cfg, face, s);
    }
    return mode;
}

// A surviving interior particle is a source for one exterior mirror particle
// iff the mirror crosses the outlet inward during this same dt.  This extends
// the local distribution f with zero normal gradient without fitting moments.
__device__ inline int neumann_ghost_face_for_survivor_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    double xp,
    double yp,
    double vxp,
    double vyp)
{
    if (!cfg.outletNeumannKinetic0493x8q || !(cfg.dt > 0.0)) return -1;
    const double xpre = xp - vxp * cfg.dt;
    const double ypre = yp - vyp * cfg.dt;

    if (vxp > 0.0 && xpre >= cfg.xMin && xpre <= cfg.xMax &&
        xpre - cfg.xMin < vxp * cfg.dt &&
        outlet_mode_at_particle_0493x8q(cfg, 0, xp, yp) == 2) return 0;
    if (vxp < 0.0 && xpre >= cfg.xMin && xpre <= cfg.xMax &&
        cfg.xMax - xpre < -vxp * cfg.dt &&
        outlet_mode_at_particle_0493x8q(cfg, 1, xp, yp) == 2) return 1;
    if (vyp > 0.0 && ypre >= cfg.yMin && ypre <= cfg.yMax &&
        ypre - cfg.yMin < vyp * cfg.dt &&
        outlet_mode_at_particle_0493x8q(cfg, 2, xp, yp) == 2) return 2;
    if (vyp < 0.0 && ypre >= cfg.yMin && ypre <= cfg.yMax &&
        cfg.yMax - ypre < -vyp * cfg.dt &&
        outlet_mode_at_particle_0493x8q(cfg, 3, xp, yp) == 2) return 3;
    return -1;
}

__device__ inline void record_neumann_ghost_candidate_0493x8q(
    std::uint64_t source,
    int face,
    CudaNeumannGhostCandidate0493x8q* candidates,
    unsigned int* candidateCount,
    unsigned int candidateCapacity,
    CudaClassicSrcIoCounters0263* counters)
{
    if (face < 0 || candidates == nullptr || candidateCount == nullptr) return;
    const unsigned int ordinal = atomicAdd(candidateCount, 1u);
    if (ordinal < candidateCapacity) {
        candidates[ordinal].source = source;
        candidates[ordinal].face = face;
    } else {
        atomicMax(&counters->overflowFlag, 8);
    }
}

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
    if (c.source >= n || role[c.source] != fluidRole) {
        atomicMax(&counters->failureFlag, 8);
        return;
    }
    const std::uint64_t slot = inactiveIndices[j];
    if (slot >= n || role[slot] != inactiveRole) {
        atomicMax(&counters->overflowFlag, 10);
        return;
    }

    const double xs = x[c.source];
    const double ys = y[c.source];
    const double vxs = vx[c.source];
    const double vys = vy[c.source];
    double xg = xs;
    double yg = ys;

    // Mirror the pre-stream state, then advance with the same velocity.
    if (c.face == 0) xg = 2.0 * cfg.xMin - xs + 2.0 * vxs * cfg.dt;
    else if (c.face == 1) xg = 2.0 * cfg.xMax - xs + 2.0 * vxs * cfg.dt;
    else if (c.face == 2) yg = 2.0 * cfg.yMin - ys + 2.0 * vys * cfg.dt;
    else if (c.face == 3) yg = 2.0 * cfg.yMax - ys + 2.0 * vys * cfg.dt;
    else {
        atomicMax(&counters->failureFlag, 9);
        return;
    }

    xg = clamp_strictly_inside_device_0263(xg, cfg.xMin, cfg.xMax);
    yg = clamp_strictly_inside_device_0263(yg, cfg.yMin, cfg.yMax);
    x[slot] = xg;
    y[slot] = yg;
    vx[slot] = vxs;
    vy[slot] = vys;
    mass[slot] = mass[c.source];
    type[slot] = type[c.source];
    role[slot] = fluidRole;
    add_counter_ull_0267(&counters->outletParticlesInserted, 1ULL);
    add_counter_ull_0267(&counters->fluidParticles, 1ULL);
}

'''
    cu = cu[:pos] + helper + cu[pos:]

old_sig = '''__global__ void io_fullface_boundary_particles_kernel_0267(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    CudaClassicSrcIoCounters0263* counters)
'''
new_sig = '''__global__ void io_fullface_boundary_particles_kernel_0267(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    CudaClassicSrcIoCounters0263* counters,
    CudaNeumannGhostCandidate0493x8q* ghostCandidates,
    unsigned int* ghostCandidateCount,
    unsigned int ghostCandidateCapacity)
'''
if old_sig in cu:
    cu = cu.replace(old_sig, new_sig, 1)
elif "CudaNeumannGhostCandidate0493x8q* ghostCandidates" not in cu:
    raise SystemExit(f"[{TAG}] boundary kernel signature anchor not found")

old = '''    } else {
        local.fluidParticles += 1ULL;
    }

    local.maxYReflections = maxY;
'''
new = '''    } else {
        local.fluidParticles += 1ULL;
        const int ghostFace0493x8q =
            neumann_ghost_face_for_survivor_0493x8q(cfg, x[i], y[i], vx[i], vy[i]);
        record_neumann_ghost_candidate_0493x8q(
            i, ghostFace0493x8q, ghostCandidates, ghostCandidateCount,
            ghostCandidateCapacity, counters);
    }

    local.maxYReflections = maxY;
'''
if old in cu:
    cu = cu.replace(old, new, 1)
elif "ghostFace0493x8q" not in cu:
    raise SystemExit(f"[{TAG}] survivor branch anchor not found")

# Pool offset: Neumann ghost clones consume [0, ghostCount); inlet refill starts
# at ghostCount.  This reuses the pool already built by the resident inlet path.
if "poolBaseOffset0493x8q" not in cu:
    cu = one(
        cu,
        "    const std::uint64_t* __restrict__ inactiveIndices,\n"
        "    unsigned int inactiveCount,\n"
        "    const CudaClassicSrcIoFullfaceConfig0263& cfg,\n",
        "    const std::uint64_t* __restrict__ inactiveIndices,\n"
        "    unsigned int inactiveCount,\n"
        "    std::uint64_t poolBaseOffset0493x8q,\n"
        "    const CudaClassicSrcIoFullfaceConfig0263& cfg,\n",
        "reservoir pool helper signature",
    )
    cu = one(
        cu,
        "    const std::uint64_t baseSlot = cellOrdinal * static_cast<std::uint64_t>(targetN);\n",
        "    const std::uint64_t baseSlot = poolBaseOffset0493x8q +\n"
        "        cellOrdinal * static_cast<std::uint64_t>(targetN);\n",
        "reservoir pool base slot",
    )

    def patch_pool_kernel(text, name, end_marker):
        s = text.find(name)
        e = text.find(end_marker, s)
        if s < 0 or e < 0:
            raise SystemExit(f"[{TAG}] pool kernel region not found: {name}")
        reg = text[s:e]
        reg = one(
            reg,
            "    const std::uint64_t* __restrict__ inactiveIndices,\n"
            "    unsigned int inactiveCount,\n"
            "    CudaClassicSrcIoCounters0263* counters)",
            "    const std::uint64_t* __restrict__ inactiveIndices,\n"
            "    unsigned int inactiveCount,\n"
            "    std::uint64_t poolBaseOffset0493x8q,\n"
            "    CudaClassicSrcIoCounters0263* counters)",
            name + " signature",
        )
        reg = one(
            reg,
            "                                           inactiveIndices, inactiveCount,\n"
            "                                           cfg,",
            "                                           inactiveIndices, inactiveCount,\n"
            "                                           poolBaseOffset0493x8q,\n"
            "                                           cfg,",
            name + " helper call",
        )
        return text[:s] + reg + text[e:]

    cu = patch_pool_kernel(
        cu,
        "__global__ void io_fullface_hard_reservoir_insert_pool_kernel_0268(",
        "std::uint64_t fullface_reservoir_cell_count_host_0268",
    )
    cu = patch_pool_kernel(
        cu,
        "__global__ void io_segmented_hard_reservoir_insert_pool_kernel_0269(",
        "CudaParticleState& shared_state_0263()",
    )

# Host workspace helpers before the fullface boundary driver.
anchor = "CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_fullface_boundary_0263("
if "struct NeumannGhostWorkspace0493x8q" not in cu:
    pos = cu.find(anchor)
    if pos < 0:
        raise SystemExit(f"[{TAG}] fullface boundary driver anchor not found")
    helper = r'''
struct NeumannGhostWorkspace0493x8q {
    CudaNeumannGhostCandidate0493x8q* candidates = nullptr;
    unsigned int* count = nullptr;
    unsigned int capacity = 0u;
};

NeumannGhostWorkspace0493x8q prepare_neumann_ghost_candidates_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    std::uint64_t nActiveFluid)
{
    // Persistent tiny workspace: allocate only on first use / capacity growth.
    // This keeps Neumann suitable as a production-default outlet and avoids
    // adding cudaMalloc/cudaFree traffic to every timestep.
    static NeumannGhostWorkspace0493x8q cached{};
    if (!cfg.outletNeumannKinetic0493x8q || nActiveFluid == 0ULL)
        return NeumannGhostWorkspace0493x8q{};
    const std::uint64_t boundaryCells =
        static_cast<std::uint64_t>(std::max(cfg.Nx, cfg.Ny));
    const std::uint64_t perCell = static_cast<std::uint64_t>(
        std::max(128, 4 * std::max(1, cfg.inletTargetOccupancy)));
    const std::uint64_t cap64 = std::min<std::uint64_t>(
        nActiveFluid, std::max<std::uint64_t>(1024ULL, boundaryCells * perCell));
    if (cap64 > static_cast<std::uint64_t>(std::numeric_limits<unsigned int>::max()))
        throw std::runtime_error("0493x8q Neumann candidate capacity exceeds unsigned int");
    const unsigned int wanted = static_cast<unsigned int>(cap64);
    if (cached.capacity < wanted || cached.candidates == nullptr) {
        if (cached.candidates) check_cuda_0263(cudaFree(cached.candidates), "resize 0493x8q Neumann candidates");
        check_cuda_0263(cudaMalloc(&cached.candidates,
            sizeof(CudaNeumannGhostCandidate0493x8q) * static_cast<std::size_t>(wanted)),
            "allocate 0493x8q Neumann candidates");
        cached.capacity = wanted;
    }
    if (cached.count == nullptr) {
        check_cuda_0263(cudaMalloc(&cached.count, sizeof(unsigned int)),
            "allocate 0493x8q Neumann count");
    }
    check_cuda_0263(cudaMemset(cached.count, 0, sizeof(unsigned int)),
        "clear 0493x8q Neumann count");
    return cached;
}

unsigned int read_neumann_ghost_count_0493x8q(const NeumannGhostWorkspace0493x8q& w)
{
    if (w.count == nullptr) return 0u;
    unsigned int n = 0u;
    check_cuda_0263(cudaMemcpy(&n, w.count, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                    "read 0493x8q Neumann count");
    if (n > w.capacity)
        throw std::runtime_error("0493x8q Neumann candidate buffer overflow count=" +
                                 std::to_string(n) + " capacity=" + std::to_string(w.capacity));
    return n;
}

void free_neumann_ghost_workspace_0493x8q(NeumannGhostWorkspace0493x8q& w)
{
    // Workspace is process-persistent and reused on the next timestep.
    // Only clear the local non-owning view.
    w = NeumannGhostWorkspace0493x8q{};
}

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
        throw std::runtime_error("0493x8q insufficient inactive slots for Neumann ghosts");
    const unsigned int blocks =
        (ghostCount + static_cast<unsigned int>(threads) - 1u) /
        static_cast<unsigned int>(threads);
    io_neumann_ghost_insert_kernel_0493x8q<<<blocks, threads>>>(
        view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
        kParticleRoleFluid, kParticleRoleInactive, cfg,
        w.candidates, ghostCount, dInactiveIndices, inactiveCount, dCounters);
    check_cuda_0263(cudaGetLastError(), label);
}

'''
    cu = cu[:pos] + helper + cu[pos:]

# Both boundary drivers: force parallel scan for Neumann because candidate
# collection is fused there.  The serial switch is diagnostic only.
old = '    const bool serialBoundary0267 = env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_SERIAL_BOUNDARY");\n'
new = (
    '    const bool serialBoundary0267 =\n'
    '        env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_SERIAL_BOUNDARY") &&\n'
    '        !cfg.outletNeumannKinetic0493x8q;\n'
    '    NeumannGhostWorkspace0493x8q ghostWorkspace0493x8q =\n'
    '        prepare_neumann_ghost_candidates_0493x8q(cfg, nActiveFluid);\n'
)
if old in cu:
    cu = all_required(cu, old, new, "serial boundary declarations")
elif "prepare_neumann_ghost_candidates_0493x8q(cfg, nActiveFluid)" not in cu:
    raise SystemExit(f"[{TAG}] serial boundary anchors not found")

# Add candidate buffers to every parallel boundary launch.
search = 0
while True:
    k = cu.find("io_fullface_boundary_particles_kernel_0267<<<", search)
    if k < 0:
        break
    close = cu.find(");", k)
    if close < 0:
        raise SystemExit(f"[{TAG}] boundary launch not terminated")
    reg = cu[k:close+2]
    if "ghostWorkspace0493x8q.candidates" not in reg:
        oldtail = "            kParticleRoleFluid, kParticleRoleInactive, cfg, dCounters);"
        if oldtail not in reg:
            raise SystemExit(f"[{TAG}] boundary launch tail anchor not found")
        reg = reg.replace(
            oldtail,
            "            kParticleRoleFluid, kParticleRoleInactive, cfg, dCounters,\n"
            "            ghostWorkspace0493x8q.candidates, ghostWorkspace0493x8q.count,\n"
            "            ghostWorkspace0493x8q.capacity);",
            1,
        )
        cu = cu[:k] + reg + cu[close+2:]
        search = k + len(reg)
    else:
        search = close + 2


def patch_driver(text, start_marker, end_marker, segmented):
    s = text.find(start_marker)
    e = text.find(end_marker, s + 1)
    if s < 0 or e < 0:
        raise SystemExit(f"[{TAG}] driver region not found: {start_marker}")
    reg = text[s:e]

    if "const unsigned int ghostCount0493x8q" not in reg:
        m = re.search(
            r'(\s*check_cuda_0263\(cudaDeviceSynchronize\(\),\s*"io_[^"]*pre_insert_outlet_extraction_kernel_0293 synchronize"\);\n)',
            reg,
        )
        if not m:
            raise SystemExit(f"[{TAG}] pre-insert synchronize anchor not found")
        at = m.end()
        reg = reg[:at] + (
            "        const unsigned int ghostCount0493x8q =\n"
            "            read_neumann_ghost_count_0493x8q(ghostWorkspace0493x8q);\n"
        ) + reg[at:]

    oldneed = (
        "            const std::uint64_t neededInactive = std::max<std::uint64_t>(\n"
        "                reservoirCells * static_cast<std::uint64_t>(std::max(0, cfg.inletTargetOccupancy)),\n"
        "                static_cast<std::uint64_t>(equilibriumPredictedInsertions0293));\n"
    )
    newneed = (
        "            const std::uint64_t reservoirPoolNeed0493x8q = std::max<std::uint64_t>(\n"
        "                reservoirCells * static_cast<std::uint64_t>(std::max(0, cfg.inletTargetOccupancy)),\n"
        "                static_cast<std::uint64_t>(equilibriumPredictedInsertions0293));\n"
        "            const std::uint64_t neededInactive =\n"
        "                static_cast<std::uint64_t>(ghostCount0493x8q) + reservoirPoolNeed0493x8q;\n"
    )
    if oldneed in reg:
        reg = reg.replace(oldneed, newneed, 1)
    elif "reservoirPoolNeed0493x8q" not in reg:
        raise SystemExit(f"[{TAG}] neededInactive anchor not found")

    kernel = (
        "io_segmented_hard_reservoir_insert_pool_kernel_0269"
        if segmented else "io_fullface_hard_reservoir_insert_pool_kernel_0268"
    )
    kp = reg.find(kernel + "<<<")
    if kp < 0:
        raise SystemExit(f"[{TAG}] pool kernel launch not found: {kernel}")

    if "launch_neumann_ghost_insert_0493x8q(" not in reg:
        ip = reg.rfind("            if (reservoirCells", 0, kp)
        if ip < 0:
            raise SystemExit(f"[{TAG}] reservoirCells if anchor not found")
        label = "segmented" if segmented else "fullface"
        launch = (
            "            launch_neumann_ghost_insert_0493x8q(\n"
            "                view, cfg, ghostWorkspace0493x8q, ghostCount0493x8q,\n"
            "                dInactiveIndices, inactiveCount, dCounters, poolThreads,\n"
            f'                "io_{label}_neumann_ghost_insert_0493x8q launch");\n'
        )
        reg = reg[:ip] + launch + reg[ip:]

    kp = reg.find(kernel + "<<<")
    close = reg.find(");", kp)
    launch = reg[kp:close+2]
    if "static_cast<std::uint64_t>(ghostCount0493x8q)" not in launch:
        launch2, n = re.subn(
            r"dInactiveIndices\s*,\s*inactiveCount\s*,\s*dCounters",
            "dInactiveIndices, inactiveCount,\n"
            "                    static_cast<std::uint64_t>(ghostCount0493x8q), dCounters",
            launch,
            count=1,
        )
        if n != 1:
            raise SystemExit(f"[{TAG}] pool launch args anchor not found")
        reg = reg[:kp] + launch2 + reg[close+2:]

    if "free_neumann_ghost_workspace_0493x8q(ghostWorkspace0493x8q);" not in reg:
        m = re.search(
            r'(\s*CudaClassicSrcIoCounters0263 h\{\};\s*\n\s*check_cuda_0263\(cudaMemcpy\(&h,\s*dCounters)',
            reg,
        )
        if not m:
            raise SystemExit(f"[{TAG}] host counter copy anchor not found")
        reg = reg[:m.start()] + (
            "    free_neumann_ghost_workspace_0493x8q(ghostWorkspace0493x8q);\n"
        ) + reg[m.start():]

    return text[:s] + reg + text[e:]

full_start = "CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_fullface_boundary_0263("
seg_start = "CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_segmented_boundary_0264("
cu = patch_driver(cu, full_start, seg_start, False)

# Segmented boundary ends at the next public resident function.
s = cu.find(seg_start)
end_candidates = []
for mark in (
    "CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_fullface_stream_0263(",
    "CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_segmented_stream_0264(",
    "#endif",
):
    q = cu.find(mark, s + len(seg_start))
    if q >= 0:
        end_candidates.append((q, mark))
if not end_candidates:
    raise SystemExit(f"[{TAG}] segmented driver end marker not found")
q, mark = min(end_candidates)
sentinel = "__X8Q_SEGMENTED_END__"
cu = cu[:q] + sentinel + cu[q:]
cu = patch_driver(cu, seg_start, sentinel, True)
cu = cu.replace(sentinel, "", 1)

# BoundaryDiagnostics propagation.
if "b.outletParticlesInserted" not in cu:
    cu = all_required(
        cu,
        "    b.outletParticlesDeleted = static_cast<std::uint64_t>(h.outletParticlesDeleted);\n",
        "    b.outletParticlesDeleted = static_cast<std::uint64_t>(h.outletParticlesDeleted);\n"
        "    b.outletParticlesInserted = static_cast<std::uint64_t>(h.outletParticlesInserted);\n",
        "host outlet insertion propagation",
    )

# Exact total boundary population delta.  Keep legacy field name for compatibility.
old = "    const std::int64_t inserted = static_cast<std::int64_t>(b.inletParticlesInserted);\n"
new = (
    "    const std::int64_t inserted =\n"
    "        static_cast<std::int64_t>(b.inletParticlesInserted) +\n"
    "        static_cast<std::int64_t>(b.outletParticlesInserted);\n"
)
if old in cu:
    cu = all_required(cu, old, new, "boundary net inserted accounting")
elif "static_cast<std::int64_t>(b.outletParticlesInserted)" not in cu:
    raise SystemExit(f"[{TAG}] boundary net accounting anchor not found")

# Active-prefix bookkeeping: wherever the resident path treats inlet insertion
# as the sole source of newly active particles, include Neumann outlet insertion.
cu = cu.replace(
    "static_cast<std::uint64_t>(h.inletParticlesInserted)",
    "static_cast<std::uint64_t>(h.inletParticlesInserted + h.outletParticlesInserted)",
)

# Any remaining direct call to the modified device helper (outside the two pool
# kernels) gets zero offset.
pat = re.compile(
    r"(insert_reservoir_cell_pool_device_0268\([\s\S]{0,700}?"
    r"inactiveIndices,\s*inactiveCount,\s*)(cfg,)",
    re.MULTILINE,
)
def add_zero(m):
    if "poolBaseOffset0493x8q" in m.group(0):
        return m.group(0)
    return m.group(1) + "0ULL,\n                                           " + m.group(2)
cu = pat.sub(add_zero, cu)

CU.write_text(cu, encoding="utf-8")

print(f"[{TAG}] patched Neumann semantics and diagnostics")
print(f"[{TAG}] no additional O(N) scan: candidate detection is fused into boundary kernel")
for p in (CU, SIM, BOUNDARY, RSUM_H, RSUM_CPP):
    print(" ", p)
