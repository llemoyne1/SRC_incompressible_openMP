#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'
if not SRC.exists():
    raise SystemExit(f'[0493x10m-patch] missing {SRC}')

text = SRC.read_text()
for tag in (
    '0493x10k-local-frame-specular-ablation',
    '0493x10l-prewall-interface-diagnostics',
):
    if tag not in text:
        raise SystemExit(f'[0493x10m-patch] prerequisite not found: {tag}')
if '0493x10m-moving-interface-wall' in text:
    raise SystemExit('[0493x10m-patch] x10m already appears applied')


def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10m-patch] {label}: expected 1 anchor, found {n}')
    text = text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Audit: x10m promotes the already-existing implicit alpha=.5 geometry into a
# one-step local moving-boundary object.  The interface is NOT made persistent:
# it is reconstructed every step from alpha, assigned a local normal velocity
# from the post-Q6/B1 liquid field, used for particle collisions during dt, and
# then discarded.  This keeps topology changes implicit.
# ---------------------------------------------------------------------------
replace_once(
'''    double preWallLowerTipMassVnSum = 0.0;
};
''',
'''    double preWallLowerTipMassVnSum = 0.0;

    // 0493x10m local moving-interface-wall diagnostics.
    unsigned long long movingWallInterfaceCellsBuilt = 0ull;
    unsigned long long movingWallInterfaceVelocityFallbacks = 0ull;
    unsigned long long movingWallInvalidInterfaceCells = 0ull;
    unsigned long long movingWallParticlesWithCandidate = 0ull;
    unsigned long long movingWallOldStationaryCrossingCandidates = 0ull;
    unsigned long long movingWallOldStationaryCrossingReleased = 0ull;
    unsigned long long movingWallCollisions = 0ull;
    unsigned long long movingWallAdvanceCollisions = 0ull;
    unsigned long long movingWallRecedeCollisions = 0ull;
    unsigned long long movingWallStationaryCollisions = 0ull;
    unsigned long long movingWallMultipleCollisionCandidates = 0ull;
    unsigned long long movingWallRelativeStillOutward = 0ull;
    unsigned long long movingWallFinalRelativeOutside = 0ull;
    double movingWallCollisionTimeFractionSum = 0.0;
    double movingWallWallVnSum = 0.0;
    double movingWallWallVnSqSum = 0.0;
    double movingWallWallVnAbsSum = 0.0;
    double movingWallRelativeSpeedSqAbsErrorSum = 0.0;
    double movingWallRelativeSpeedSqReferenceSum = 0.0;
    double movingWallImpulseX = 0.0;
    double movingWallImpulseY = 0.0;
    double movingWallImpulseAbsSum = 0.0;
    double movingWallPositionShiftAbsSum = 0.0;
};
''',
'audit x10m fields')


# ---------------------------------------------------------------------------
# Workspace.  These fields are the local implicit-interface object in SoA form:
# one plane only in liquid-side interface cells.  impulseX/Y are deliberately
# retained even though the free-surface ablation does not feed them back; a
# future rigid/mobile solid can reduce exactly these collision impulses onto
# body linear/angular momentum.
# ---------------------------------------------------------------------------
replace_once(
'''    DeviceBuffer0400<KineticGlobalReactionPartial0493x10g> kineticGlobalReactionPartials0493x10g;
    bool phaseInterfaceStencilValid0493x6f = false;
''',
'''    DeviceBuffer0400<KineticGlobalReactionPartial0493x10g> kineticGlobalReactionPartials0493x10g;

    // 0493x10m one-step local moving interface. Geometry comes from alpha=.5;
    // wallVn comes from the post-Q6/B1 phase-A velocity field.
    DeviceBuffer0400<unsigned char> kineticMovingWallActive0493x10m;
    DeviceBuffer0400<double> kineticMovingWallNx0493x10m;
    DeviceBuffer0400<double> kineticMovingWallNy0493x10m;
    DeviceBuffer0400<double> kineticMovingWallQx0493x10m;
    DeviceBuffer0400<double> kineticMovingWallQy0493x10m;
    DeviceBuffer0400<double> kineticMovingWallVn0493x10m;
    DeviceBuffer0400<double> kineticMovingWallImpulseX0493x10m;
    DeviceBuffer0400<double> kineticMovingWallImpulseY0493x10m;
    bool phaseInterfaceStencilValid0493x6f = false;
''',
'workspace x10m buffers')

replace_once(
'''        kineticGlobalReactionPartials0493x10g.ensure(
            static_cast<std::size_t>(std::max(1, reactionBlocks)));
    }
''',
'''        kineticGlobalReactionPartials0493x10g.ensure(
            static_cast<std::size_t>(std::max(1, reactionBlocks)));
        const std::size_t c = static_cast<std::size_t>(std::max(1, numCells));
        kineticMovingWallActive0493x10m.ensure(c);
        kineticMovingWallNx0493x10m.ensure(c);
        kineticMovingWallNy0493x10m.ensure(c);
        kineticMovingWallQx0493x10m.ensure(c);
        kineticMovingWallQy0493x10m.ensure(c);
        kineticMovingWallVn0493x10m.ensure(c);
        kineticMovingWallImpulseX0493x10m.ensure(c);
        kineticMovingWallImpulseY0493x10m.ensure(c);
    }
''',
'ensure x10m buffers')


# ---------------------------------------------------------------------------
# Generic moving-plane primitive + alpha=.5 local interface builder + one-pass
# particle collision.  The primitive is intentionally geometry/kinematics
# oriented so it can later be reused by a mobile rigid solid: a rigid body only
# needs to supply q,n and wallVn=(V + omega x r).n, then consume impulseOnWall.
# ---------------------------------------------------------------------------
anchor = '''// 0493x10i: reduce existing per-cell donor/receiver statistics into
// shifted mesoscopic reservoirs. No particle pass is added.
'''
if text.count(anchor) != 1:
    raise SystemExit('[0493x10m-patch] x10i kernel anchor not unique')

kernels = r'''// =============================================================================
// 0493x10m — implicit alpha=.5 as a LOCAL MOVING BOUNDARY
// =============================================================================
// The interface is reconstructed each step and lives only during the current
// streaming interval.  This is deliberately NOT a persistent surface mesh.
// Topology (pinch-off/coalescence) therefore remains entirely alpha-driven.
//
// The collision primitive below is generic enough for a future moving solid:
// provide a local plane point q, outward normal n and normal wall velocity.
// It returns the particle velocity after an elastic specular collision in the
// wall frame plus the opposite impulse received by the boundary.
struct LocalMovingPlane0493x10m {
    double qx = 0.0;
    double qy = 0.0;
    double nx = 0.0;
    double ny = 0.0;
    double wallVn = 0.0;
    int ownerCell = -1;
};

struct LocalMovingPlaneCollision0493x10m {
    bool hit = false;
    double tHit = 0.0;
    double newVx = 0.0;
    double newVy = 0.0;
    double impulseWallX = 0.0;
    double impulseWallY = 0.0;
    double relativeNormalBefore = 0.0;
};

__device__ __forceinline__ double q6_x10m_minimum_image(
    double d, double L, int periodic) {
    if (periodic && L > 0.0) d -= nearbyint(d / L) * L;
    return d;
}

__device__ __forceinline__ bool q6_x10m_collide_local_moving_plane(
    double x0, double y0,
    double vx, double vy,
    double mass,
    double dt,
    double dx, double dy,
    double lx, double ly,
    int periodicX, int periodicY,
    const LocalMovingPlane0493x10m& wall,
    LocalMovingPlaneCollision0493x10m* out) {
    if (!out || !(dt > 0.0)) return false;
    const double h = fmin(dx, dy);
    double rx0 = q6_x10m_minimum_image(x0 - wall.qx, lx, periodicX);
    double ry0 = q6_x10m_minimum_image(y0 - wall.qy, ly, periodicY);
    double s0 = rx0 * wall.nx + ry0 * wall.ny; // outside is positive

    // Only liquid-side particles collide.  Tiny positive tolerance covers only
    // floating point / plane-linearization noise; already-outer shell particles
    // are not forcibly recalled by x10m.
    const double sideTol = 1.0e-8 * fmax(1.0, h);
    if (s0 > sideTol || s0 < -2.25 * h) return false;
    if (s0 > 0.0) s0 = 0.0;

    const double reln = vx * wall.nx + vy * wall.ny - wall.wallVn;
    if (!(reln > 1.0e-14) || !isfinite(reln)) return false;

    const double t = -s0 / reln;
    if (!(t >= 0.0 && t <= dt) || !isfinite(t)) return false;

    // Restrict the infinite plane to the local interface segment carried by
    // its owner cell.  The projected half-width is the cell-box extent along
    // the tangent, with a small geometric margin for the linearized alpha plane.
    const double qtx = wall.qx + wall.wallVn * wall.nx * t;
    const double qty = wall.qy + wall.wallVn * wall.ny * t;
    const double xh = x0 + vx * t;
    const double yh = y0 + vy * t;
    const double rhx = q6_x10m_minimum_image(xh - qtx, lx, periodicX);
    const double rhy = q6_x10m_minimum_image(yh - qty, ly, periodicY);
    const double tangential = rhx * (-wall.ny) + rhy * wall.nx;
    const double halfSegment =
        0.5 * (fabs(wall.ny) * dx + fabs(wall.nx) * dy) + 0.35 * h;
    if (fabs(tangential) > halfSegment) return false;

    out->hit = true;
    out->tHit = t;
    out->relativeNormalBefore = reln;
    out->newVx = vx - 2.0 * reln * wall.nx;
    out->newVy = vy - 2.0 * reln * wall.ny;
    const double impulse = 2.0 * mass * reln;
    out->impulseWallX = impulse * wall.nx;
    out->impulseWallY = impulse * wall.ny;
    return isfinite(out->newVx) && isfinite(out->newVy);
}

__global__ void q6_x10m_build_moving_interface_cells(
    int numCells,
    int nx, int ny,
    double lx, double ly,
    int periodicX, int periodicY,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    unsigned char* active,
    double* wallNx,
    double* wallNy,
    double* wallQx,
    double* wallQy,
    double* wallVn,
    KineticCrossingAccumulator0493x9x* audit) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);
    const double maxOffset = 1.25 * sqrt(dx * dx + dy * dy);

    for (int c = idx; c < numCells; c += stride) {
        active[c] = 0;
        wallNx[c] = wallNy[c] = 0.0;
        wallQx[c] = wallQy[c] = 0.0;
        wallVn[c] = 0.0;

        const int i = c % nx;
        const int j = c / nx;
        const double ac = q6_x10l_alpha_cell(
            alpha, i, j, nx, ny, periodicX, periodicY);
        // One interface plane is owned by the LIQUID-SIDE cell only.  This
        // prevents duplicate planes on both sides of the same alpha=.5 sheet.
        if (!(ac >= 0.5)) continue;

        const double al = q6_x10l_alpha_cell(
            alpha, i - 1, j, nx, ny, periodicX, periodicY);
        const double ar = q6_x10l_alpha_cell(
            alpha, i + 1, j, nx, ny, periodicX, periodicY);
        const double ab = q6_x10l_alpha_cell(
            alpha, i, j - 1, nx, ny, periodicX, periodicY);
        const double at = q6_x10l_alpha_cell(
            alpha, i, j + 1, nx, ny, periodicX, periodicY);
        const double amin = fmin(fmin(al, ar), fmin(ab, at));
        if (!(amin < 0.5)) continue;

        const double gx = (ar - al) / (2.0 * dx);
        const double gy = (at - ab) / (2.0 * dy);
        const double g2 = gx * gx + gy * gy;
        if (!(g2 > 1.0e-24) || !isfinite(g2)) {
            if (audit) atomicAdd(&audit->movingWallInvalidInterfaceCells, 1ull);
            continue;
        }
        const double gmag = sqrt(g2);
        const double nxo = -gx / gmag;
        const double nyo = -gy / gmag;

        double offset = (ac - 0.5) / gmag; // center -> alpha=.5, outward
        if (!isfinite(offset)) {
            if (audit) atomicAdd(&audit->movingWallInvalidInterfaceCells, 1ull);
            continue;
        }
        offset = fmin(fmax(offset, -maxOffset), maxOffset);
        const double cx = (static_cast<double>(i) + 0.5) * dx;
        const double cy = (static_cast<double>(j) + 0.5) * dy;
        const double qx = cx + offset * nxo;
        const double qy = cy + offset * nyo;

        int bath = c;
        bool fallback = false;
        double m = totalM[c];
        if (!(m > 1.0e-14) || !isfinite(m)) {
            if (!q6_x9x_choose_direct_bulk_bath(
                    alpha, totalM, c, nxo, nyo,
                    nx, ny, periodicX, periodicY, &bath)) {
                if (audit) atomicAdd(&audit->movingWallInvalidInterfaceCells, 1ull);
                continue;
            }
            fallback = true;
            m = totalM[bath];
        }
        const double px = totalPx[bath];
        const double py = totalPy[bath];
        if (!(m > 1.0e-14) || !isfinite(m) || !isfinite(px) || !isfinite(py)) {
            if (audit) atomicAdd(&audit->movingWallInvalidInterfaceCells, 1ull);
            continue;
        }
        const double ubx = px / m;
        const double uby = py / m;
        const double vn = ubx * nxo + uby * nyo;
        if (!isfinite(vn)) {
            if (audit) atomicAdd(&audit->movingWallInvalidInterfaceCells, 1ull);
            continue;
        }

        wallNx[c] = nxo;
        wallNy[c] = nyo;
        wallQx[c] = qx;
        wallQy[c] = qy;
        wallVn[c] = vn;
        active[c] = 1;
        if (audit) {
            atomicAdd(&audit->movingWallInterfaceCellsBuilt, 1ull);
            if (fallback)
                atomicAdd(&audit->movingWallInterfaceVelocityFallbacks, 1ull);
        }
    }
}

__global__ void q6_x10m_apply_moving_interface_wall(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    std::uint64_t nParticles,
    const double* alpha,
    const unsigned char* active,
    const double* wallNx,
    const double* wallNy,
    const double* wallQx,
    const double* wallQy,
    const double* wallVn,
    double* wallImpulseX,
    double* wallImpulseY,
    std::uint32_t phaseAType,
    int nx, int ny,
    double lx, double ly, double dt,
    int periodicX, int periodicY,
    KineticCrossingAccumulator0493x9x* audit) {
    const std::uint64_t idx =
        static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    const std::uint64_t stride =
        static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);

    for (std::uint64_t p = idx; p < nParticles; p += stride) {
        if (particles.role && particles.role[p] != kParticleRoleFluid) continue;
        if (!particles.type || particles.type[p] != phaseAType) continue;
        const int c0 = cells.cellId[p];
        if (c0 < 0 || c0 >= cells.numCells) continue;

        const double x0 = particles.x[p];
        const double y0 = particles.y[p];
        const double vx0 = particles.vx[p];
        const double vy0 = particles.vy[p];
        const double mass = particles.mass ? particles.mass[p] : 1.0;

        bool oldStationaryOuter = false;
        if (audit) {
            double a0 = 0.0, a1 = 0.0;
            const bool ok0 = q6_x9t_sample_alpha(
                alpha, x0, y0, nx, ny, lx, ly, periodicX, periodicY, &a0);
            const bool ok1 = q6_x9t_sample_alpha(
                alpha, x0 + vx0 * dt, y0 + vy0 * dt,
                nx, ny, lx, ly, periodicX, periodicY, &a1);
            oldStationaryOuter = ok0 && ok1 && a0 >= 0.5 && a1 < 0.5;
            if (oldStationaryOuter)
                atomicAdd(&audit->movingWallOldStationaryCrossingCandidates, 1ull);
        }

        LocalMovingPlane0493x10m bestWall{};
        LocalMovingPlaneCollision0493x10m bestHit{};
        double bestT = dt + 1.0;
        int validHits = 0;
        int candidatePlanes = 0;

        for (int dj = -1; dj <= 1; ++dj) {
            for (int di = -1; di <= 1; ++di) {
                int wc = -1;
                if (!q6_x9u_offset_cell(
                        c0, di, dj, nx, ny,
                        periodicX, periodicY, &wc))
                    continue;
                if (wc < 0 || wc >= cells.numCells || !active[wc]) continue;
                ++candidatePlanes;

                LocalMovingPlane0493x10m wall{};
                wall.qx = wallQx[wc];
                wall.qy = wallQy[wc];
                wall.nx = wallNx[wc];
                wall.ny = wallNy[wc];
                wall.wallVn = wallVn[wc];
                wall.ownerCell = wc;
                LocalMovingPlaneCollision0493x10m hit{};
                if (!q6_x10m_collide_local_moving_plane(
                        x0, y0, vx0, vy0, mass, dt,
                        dx, dy, lx, ly, periodicX, periodicY,
                        wall, &hit))
                    continue;
                ++validHits;
                if (hit.tHit < bestT) {
                    bestT = hit.tHit;
                    bestWall = wall;
                    bestHit = hit;
                }
            }
        }

        if (audit && candidatePlanes > 0)
            atomicAdd(&audit->movingWallParticlesWithCandidate, 1ull);
        if (!bestHit.hit) {
            if (audit && oldStationaryOuter)
                atomicAdd(&audit->movingWallOldStationaryCrossingReleased, 1ull);
            continue;
        }
        if (audit && validHits > 1)
            atomicAdd(&audit->movingWallMultipleCollisionCandidates, 1ull);

        // Standard event-driven streaming split: old velocity until collision,
        // reflected velocity for the remaining interval.  Since the production
        // streamer still advances v_new for the full dt, shift the pre-stream
        // position by (v_old-v_new)*tHit so its final endpoint is identical.
        const double newVx = bestHit.newVx;
        const double newVy = bestHit.newVy;
        const double corrX = (vx0 - newVx) * bestHit.tHit;
        const double corrY = (vy0 - newVy) * bestHit.tHit;
        particles.x[p] = x0 + corrX;
        particles.y[p] = y0 + corrY;
        particles.vx[p] = newVx;
        particles.vy[p] = newVy;

        atomic_add_double_0400(
            &wallImpulseX[bestWall.ownerCell], bestHit.impulseWallX);
        atomic_add_double_0400(
            &wallImpulseY[bestWall.ownerCell], bestHit.impulseWallY);

        if (audit) {
            atomicAdd(&audit->movingWallCollisions, 1ull);
            const double vnTol = 1.0e-12;
            if (bestWall.wallVn > vnTol)
                atomicAdd(&audit->movingWallAdvanceCollisions, 1ull);
            else if (bestWall.wallVn < -vnTol)
                atomicAdd(&audit->movingWallRecedeCollisions, 1ull);
            else
                atomicAdd(&audit->movingWallStationaryCollisions, 1ull);
            atomic_add_double_0400(
                &audit->movingWallCollisionTimeFractionSum,
                bestHit.tHit / dt);
            atomic_add_double_0400(
                &audit->movingWallWallVnSum, bestWall.wallVn);
            atomic_add_double_0400(
                &audit->movingWallWallVnSqSum,
                bestWall.wallVn * bestWall.wallVn);
            atomic_add_double_0400(
                &audit->movingWallWallVnAbsSum, fabs(bestWall.wallVn));

            const double wallVx = bestWall.wallVn * bestWall.nx;
            const double wallVy = bestWall.wallVn * bestWall.ny;
            const double cbx = vx0 - wallVx;
            const double cby = vy0 - wallVy;
            const double cax = newVx - wallVx;
            const double cay = newVy - wallVy;
            const double eBefore = cbx * cbx + cby * cby;
            const double eAfter = cax * cax + cay * cay;
            atomic_add_double_0400(
                &audit->movingWallRelativeSpeedSqAbsErrorSum,
                fabs(eAfter - eBefore));
            atomic_add_double_0400(
                &audit->movingWallRelativeSpeedSqReferenceSum,
                fabs(eBefore));
            const double relAfter =
                newVx * bestWall.nx + newVy * bestWall.ny - bestWall.wallVn;
            if (!(relAfter < 1.0e-12 * fmax(1.0, fabs(bestHit.relativeNormalBefore))))
                atomicAdd(&audit->movingWallRelativeStillOutward, 1ull);

            const double xf = x0 + vx0 * bestHit.tHit +
                              newVx * (dt - bestHit.tHit);
            const double yf = y0 + vy0 * bestHit.tHit +
                              newVy * (dt - bestHit.tHit);
            const double qfx = bestWall.qx +
                               bestWall.wallVn * bestWall.nx * dt;
            const double qfy = bestWall.qy +
                               bestWall.wallVn * bestWall.ny * dt;
            const double rfx = q6_x10m_minimum_image(
                xf - qfx, lx, periodicX);
            const double rfy = q6_x10m_minimum_image(
                yf - qfy, ly, periodicY);
            const double sFinal = rfx * bestWall.nx + rfy * bestWall.ny;
            if (sFinal > 1.0e-10 * fmax(1.0, fmin(dx, dy)))
                atomicAdd(&audit->movingWallFinalRelativeOutside, 1ull);

            atomic_add_double_0400(
                &audit->movingWallImpulseX, bestHit.impulseWallX);
            atomic_add_double_0400(
                &audit->movingWallImpulseY, bestHit.impulseWallY);
            atomic_add_double_0400(
                &audit->movingWallImpulseAbsSum,
                sqrt(bestHit.impulseWallX * bestHit.impulseWallX +
                     bestHit.impulseWallY * bestHit.impulseWallY));
            atomic_add_double_0400(
                &audit->movingWallPositionShiftAbsSum,
                sqrt(corrX * corrX + corrY * corrY));
        }
    }
}

'''
text = text.replace(anchor, kernels + anchor, 1)


# ---------------------------------------------------------------------------
# Runtime precedence/orchestration.  x10m bypasses x10j/x10k and all B8/global
# receiver machinery, but keeps the total-A moment deposit and optional x10l
# passive diagnostic exactly where they already are.
# ---------------------------------------------------------------------------
replace_once(
'''    const double r = params.phaseInterfaceKineticReflectionFraction;
    if (!(r > 0.0)) return false;
    const bool localFrameSpecularAblation =
        r >= 1.0 &&
        env_int_0400("MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION", 0) != 0;
    const bool simpleSpecularAblation =
        !localFrameSpecularAblation && r >= 1.0 &&
        env_int_0400("MPCD_X10J_SIMPLE_SPECULAR_ABLATION", 0) != 0;
    const bool anySimpleSpecularAblation =
        simpleSpecularAblation || localFrameSpecularAblation;
''',
'''    const double r = params.phaseInterfaceKineticReflectionFraction;
    if (!(r > 0.0)) return false;
    const bool movingInterfaceWall0493x10m =
        r >= 1.0 &&
        env_int_0400("MPCD_X10M_MOVING_INTERFACE_WALL", 0) != 0;
    const bool localFrameSpecularAblation =
        !movingInterfaceWall0493x10m && r >= 1.0 &&
        env_int_0400("MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION", 0) != 0;
    const bool simpleSpecularAblation =
        !movingInterfaceWall0493x10m && !localFrameSpecularAblation && r >= 1.0 &&
        env_int_0400("MPCD_X10J_SIMPLE_SPECULAR_ABLATION", 0) != 0;
    const bool anySimpleSpecularAblation =
        movingInterfaceWall0493x10m ||
        simpleSpecularAblation || localFrameSpecularAblation;
''',
'flags x10m precedence')

replace_once(
'''    q6_x9t_deposit_total_a_moments<<<particleBlocks, threads>>>(
        particles, cells, nParticles, phaseAType,
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data());
    check_cuda_0400(cudaGetLastError(), "0493x9x total-A deposit launch");

    if (preWallInterfaceDiagnostics0493x10l && auditDev) {
''',
'''    q6_x9t_deposit_total_a_moments<<<particleBlocks, threads>>>(
        particles, cells, nParticles, phaseAType,
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data());
    check_cuda_0400(cudaGetLastError(), "0493x9x total-A deposit launch");

    if (movingInterfaceWall0493x10m) {
        const std::size_t cellCount =
            static_cast<std::size_t>(std::max(1, grid.numCells));
        check_cuda_0400(
            cudaMemset(ws.kineticMovingWallActive0493x10m.data(), 0,
                       cellCount * sizeof(unsigned char)),
            "0493x10m moving-wall active zero");
        check_cuda_0400(
            cudaMemset(ws.kineticMovingWallImpulseX0493x10m.data(), 0,
                       cellCount * sizeof(double)),
            "0493x10m moving-wall impulseX zero");
        check_cuda_0400(
            cudaMemset(ws.kineticMovingWallImpulseY0493x10m.data(), 0,
                       cellCount * sizeof(double)),
            "0493x10m moving-wall impulseY zero");

        q6_x10m_build_moving_interface_cells<<<cellBlocks, threads>>>(
            grid.numCells,
            grid.Nx, grid.Ny,
            params.Lx, params.Ly,
            periodicX, periodicY,
            phaseAlpha0493x6c,
            ws.kineticTotalM0493x9t.data(),
            ws.kineticTotalPx0493x9t.data(),
            ws.kineticTotalPy0493x9t.data(),
            ws.kineticMovingWallActive0493x10m.data(),
            ws.kineticMovingWallNx0493x10m.data(),
            ws.kineticMovingWallNy0493x10m.data(),
            ws.kineticMovingWallQx0493x10m.data(),
            ws.kineticMovingWallQy0493x10m.data(),
            ws.kineticMovingWallVn0493x10m.data(),
            auditDev);
        check_cuda_0400(
            cudaGetLastError(), "0493x10m moving-interface build launch");
    }

    if (preWallInterfaceDiagnostics0493x10l && auditDev) {
''',
'build x10m interface')

# Replace unconditional old apply with x10m branch.
old_apply = '''    q6_x9z_apply_individual_reflections<<<particleBlocks, threads>>>(
        particles, cells, nParticles, phaseAlpha0493x6c,
        ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data(),
        ws.kineticRefM0493x9t.data(), ws.kineticRefPx0493x9t.data(), ws.kineticRefPy0493x9t.data(),
        ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(), ws.kineticTxPy0493x9t.data(),
        ws.kineticRefNy0493x9u.data(),
        ws.kineticGlobalReaction0493x10f.data(),
        mesoBlockCells,
        mesoShiftX,
        mesoShiftY,
        mesoBlocksX,
        simpleSpecularAblation ? 1 : 0,
        localFrameSpecularAblation ? 1 : 0,
        phaseAType,
        params.phaseInterfaceEvaporationTargetType,
        grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt, periodicX, periodicY, r,
        static_cast<unsigned long long>(step), static_cast<unsigned long long>(params.rngSeed), auditDev);
    check_cuda_0400(cudaGetLastError(), "0493x9x crossing reflection launch");
'''
new_apply = '''    if (movingInterfaceWall0493x10m) {
        q6_x10m_apply_moving_interface_wall<<<particleBlocks, threads>>>(
            particles, cells, nParticles,
            phaseAlpha0493x6c,
            ws.kineticMovingWallActive0493x10m.data(),
            ws.kineticMovingWallNx0493x10m.data(),
            ws.kineticMovingWallNy0493x10m.data(),
            ws.kineticMovingWallQx0493x10m.data(),
            ws.kineticMovingWallQy0493x10m.data(),
            ws.kineticMovingWallVn0493x10m.data(),
            ws.kineticMovingWallImpulseX0493x10m.data(),
            ws.kineticMovingWallImpulseY0493x10m.data(),
            phaseAType,
            grid.Nx, grid.Ny,
            params.Lx, params.Ly, params.dt,
            periodicX, periodicY,
            auditDev);
        check_cuda_0400(
            cudaGetLastError(), "0493x10m moving-interface collision launch");
    } else {
        q6_x9z_apply_individual_reflections<<<particleBlocks, threads>>>(
            particles, cells, nParticles, phaseAlpha0493x6c,
            ws.kineticTotalM0493x9t.data(), ws.kineticTotalPx0493x9t.data(), ws.kineticTotalPy0493x9t.data(),
            ws.kineticRefM0493x9t.data(), ws.kineticRefPx0493x9t.data(), ws.kineticRefPy0493x9t.data(),
            ws.kineticTxM0493x9t.data(), ws.kineticTxPx0493x9t.data(), ws.kineticTxPy0493x9t.data(),
            ws.kineticRefNy0493x9u.data(),
            ws.kineticGlobalReaction0493x10f.data(),
            mesoBlockCells,
            mesoShiftX,
            mesoShiftY,
            mesoBlocksX,
            simpleSpecularAblation ? 1 : 0,
            localFrameSpecularAblation ? 1 : 0,
            phaseAType,
            params.phaseInterfaceEvaporationTargetType,
            grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt, periodicX, periodicY, r,
            static_cast<unsigned long long>(step), static_cast<unsigned long long>(params.rngSeed), auditDev);
        check_cuda_0400(cudaGetLastError(), "0493x9x crossing reflection launch");
    }
'''
replace_once(old_apply, new_apply, 'x10m apply branch')


# ---------------------------------------------------------------------------
# CSV diagnostics.
# ---------------------------------------------------------------------------
replace_once(
'''               "preWallLowerTipMassSum,preWallLowerTipMassVnSum,"
               "contract\\n";
''',
'''               "preWallLowerTipMassSum,preWallLowerTipMassVnSum,"
               "movingWallInterfaceCellsBuilt,movingWallInterfaceVelocityFallbacks,"
               "movingWallInvalidInterfaceCells,movingWallParticlesWithCandidate,"
               "movingWallOldStationaryCrossingCandidates,"
               "movingWallOldStationaryCrossingReleased,movingWallCollisions,"
               "movingWallAdvanceCollisions,movingWallRecedeCollisions,"
               "movingWallStationaryCollisions,movingWallMultipleCollisionCandidates,"
               "movingWallRelativeStillOutward,movingWallFinalRelativeOutside,"
               "movingWallMeanCollisionTimeFraction,movingWallMeanWallVn,"
               "movingWallRmsWallVn,movingWallMeanAbsWallVn,"
               "movingWallRelativeSpeedSqAbsErrorSum,"
               "movingWallRelativeSpeedSqReferenceSum,"
               "movingWallImpulseX,movingWallImpulseY,movingWallImpulseAbsSum,"
               "movingWallPositionShiftAbsSum,"
               "contract\\n";
''',
'CSV x10m header')

replace_once(
'''    const double meanMesoCancellation =
        a.mesoReactionActiveReservoirs > 0ull ?
        a.mesoReactionCancellationSum /
            static_cast<double>(a.mesoReactionActiveReservoirs) : 0.0;

    out << std::setprecision(17)
''',
'''    const double meanMesoCancellation =
        a.mesoReactionActiveReservoirs > 0ull ?
        a.mesoReactionCancellationSum /
            static_cast<double>(a.mesoReactionActiveReservoirs) : 0.0;
    const double movingWallMeanTime = a.movingWallCollisions > 0ull ?
        a.movingWallCollisionTimeFractionSum /
            static_cast<double>(a.movingWallCollisions) : 0.0;
    const double movingWallMeanVn = a.movingWallCollisions > 0ull ?
        a.movingWallWallVnSum /
            static_cast<double>(a.movingWallCollisions) : 0.0;
    const double movingWallRmsVn = a.movingWallCollisions > 0ull ?
        sqrt(fmax(0.0, a.movingWallWallVnSqSum /
            static_cast<double>(a.movingWallCollisions))) : 0.0;
    const double movingWallMeanAbsVn = a.movingWallCollisions > 0ull ?
        a.movingWallWallVnAbsSum /
            static_cast<double>(a.movingWallCollisions) : 0.0;

    out << std::setprecision(17)
''',
'CSV x10m means')

replace_once(
'''        << a.preWallLowerTipAbsVnSum << ',' << a.preWallLowerTipMassSum << ','
        << a.preWallLowerTipMassVnSum << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'''        << a.preWallLowerTipAbsVnSum << ',' << a.preWallLowerTipMassSum << ','
        << a.preWallLowerTipMassVnSum << ','
        << a.movingWallInterfaceCellsBuilt << ','
        << a.movingWallInterfaceVelocityFallbacks << ','
        << a.movingWallInvalidInterfaceCells << ','
        << a.movingWallParticlesWithCandidate << ','
        << a.movingWallOldStationaryCrossingCandidates << ','
        << a.movingWallOldStationaryCrossingReleased << ','
        << a.movingWallCollisions << ','
        << a.movingWallAdvanceCollisions << ','
        << a.movingWallRecedeCollisions << ','
        << a.movingWallStationaryCollisions << ','
        << a.movingWallMultipleCollisionCandidates << ','
        << a.movingWallRelativeStillOutward << ','
        << a.movingWallFinalRelativeOutside << ','
        << movingWallMeanTime << ',' << movingWallMeanVn << ','
        << movingWallRmsVn << ',' << movingWallMeanAbsVn << ','
        << a.movingWallRelativeSpeedSqAbsErrorSum << ','
        << a.movingWallRelativeSpeedSqReferenceSum << ','
        << a.movingWallImpulseX << ',' << a.movingWallImpulseY << ','
        << a.movingWallImpulseAbsSum << ','
        << a.movingWallPositionShiftAbsSum << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'CSV x10m row')

replace_once(
'''           "0493x10l-prewall-interface-diagnostics;"
           "x10l-passive-after-q6-b1-before-kinetic-wall;"
''',
'''           "0493x10l-prewall-interface-diagnostics;"
           "0493x10m-moving-interface-wall;"
           "x10m-alpha0.5-one-step-local-moving-boundary;"
           "x10m-wall-vn-from-post-q6-b1-liquid-cell-velocity;"
           "x10m-event-driven-moving-plane-specular-collision;"
           "x10m-boundary-impulse-recorded-not-fed-back-for-free-surface;"
           "x10m-local-plane-primitive-prepares-mobile-solid-collision-path;"
           "x10l-passive-after-q6-b1-before-kinetic-wall;"
''',
'contract x10m tag')

SRC.write_text(text)


# ---------------------------------------------------------------------------
# Math check: moving plane collision kinematics and relative energy invariant.
# ---------------------------------------------------------------------------
chk = ROOT / 'scripts/check_0493x10m_moving_interface_wall_math.py'
chk.write_text(r'''#!/usr/bin/env python3
import math
import random

rng = random.Random(4931013)
max_rel_e = 0.0
max_final_side = 0.0
max_impulse = 0.0
released = 0
hits = 0
for _ in range(200000):
    ang = rng.uniform(-math.pi, math.pi)
    nx, ny = math.cos(ang), math.sin(ang)
    wall_vn = rng.uniform(-0.3, 0.3)
    # Particle starts on liquid side at signed distance d<0.
    s0 = -rng.uniform(0.0, 0.004)
    tang = rng.uniform(-0.002, 0.002)
    tx, ty = -ny, nx
    x0 = s0*nx + tang*tx
    y0 = s0*ny + tang*ty
    vn = wall_vn + rng.uniform(-0.2, 0.8)
    vt = rng.uniform(-0.5, 0.5)
    vx, vy = vn*nx + vt*tx, vn*ny + vt*ty
    dt = 0.002
    rel = vn-wall_vn
    if rel <= 0:
        continue
    thit = -s0/rel
    stationary_hit = vn > 0 and (-s0/vn) <= dt
    if not (0 <= thit <= dt):
        if stationary_hit:
            released += 1
        continue
    hits += 1
    nvx = vx - 2*rel*nx
    nvy = vy - 2*rel*ny
    wvx, wvy = wall_vn*nx, wall_vn*ny
    eb = (vx-wvx)**2 + (vy-wvy)**2
    ea = (nvx-wvx)**2 + (nvy-wvy)**2
    max_rel_e = max(max_rel_e, abs(ea-eb))
    xf = x0 + vx*thit + nvx*(dt-thit)
    yf = y0 + vy*thit + nvy*(dt-thit)
    qfx, qfy = wall_vn*nx*dt, wall_vn*ny*dt
    sf = (xf-qfx)*nx + (yf-qfy)*ny
    max_final_side = max(max_final_side, sf)
    m = rng.uniform(.5, 2.0)
    jx, jy = 2*m*rel*nx, 2*m*rel*ny
    # Particle momentum change + wall impulse must cancel identically.
    rx = m*(nvx-vx) + jx
    ry = m*(nvy-vy) + jy
    max_impulse = max(max_impulse, math.hypot(rx,ry))

print(f'hits={hits} stationaryOldCrossingsReleasedByMovingWall={released}')
print(f'maxRelativeSpeedSqError={max_rel_e:.12e}')
print(f'maxFinalRelativeOutside={max_final_side:.12e}')
print(f'maxParticlePlusWallImpulseResidual={max_impulse:.12e}')
if max_rel_e > 1e-12 or max_final_side > 1e-12 or max_impulse > 1e-12:
    raise SystemExit('status=FAIL')
print('status=PASS')
''')
chk.chmod(0o755)


# ---------------------------------------------------------------------------
# Analyzer.
# ---------------------------------------------------------------------------
an = ROOT / 'scripts/analyze_0493x10m_moving_interface_wall.py'
an.write_text(r'''#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path

ap=argparse.ArgumentParser()
ap.add_argument('csv')
ap.add_argument('--mode', choices=('static','dripping'), default='static')
a=ap.parse_args()
p=Path(a.csv)
with p.open(newline='') as f:
    rows=list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10m-check] ERROR empty CSV')

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def fsum(k): return sum(F(r,k) for r in rows)
def mx(k): return max((F(r,k) for r in rows), default=0.0)
def wmean(k,count='movingWallCollisions'):
    den=isum(count)
    return sum(F(r,k)*I(r,count) for r in rows)/den if den else 0.0

last=rows[-1]
coll=isum('movingWallCollisions')
old=isum('movingWallOldStationaryCrossingCandidates')
released=isum('movingWallOldStationaryCrossingReleased')
relerr=fsum('movingWallRelativeSpeedSqAbsErrorSum')
relref=fsum('movingWallRelativeSpeedSqReferenceSum')
relative_error=relerr/max(relref,1e-300)

print('===== 0493x10m MOVING INTERFACE WALL =====')
print(f'file={p} mode={a.mode} rows={len(rows)} lastStep={I(last,"step")}')
print('--- implicit interface object ---')
print(f'planesBuilt={isum("movingWallInterfaceCellsBuilt")} '
      f'velocityFallbacks={isum("movingWallInterfaceVelocityFallbacks")} '
      f'invalidPlanes={isum("movingWallInvalidInterfaceCells")}')
print('--- moving-wall collision path ---')
print(f'particlesWithCandidate={isum("movingWallParticlesWithCandidate")} '
      f'collisions={coll} multipleCandidates={isum("movingWallMultipleCollisionCandidates")}')
print(f'oldStationaryCrossings={old} releasedByMovingWall={released} '
      f'releasedFraction={(released/old if old else 0):.6%}')
print(f'advance/recede/stationary={isum("movingWallAdvanceCollisions")}/'
      f'{isum("movingWallRecedeCollisions")}/'
      f'{isum("movingWallStationaryCollisions")}')
print(f'meanHitFraction={wmean("movingWallMeanCollisionTimeFraction"):.9g} '
      f'meanWallVn={wmean("movingWallMeanWallVn"):.9g} '
      f'rmsWallVn={wmean("movingWallRmsWallVn"):.9g} '
      f'mean|wallVn|={wmean("movingWallMeanAbsWallVn"):.9g}')
print(f'relativeStillOutward={isum("movingWallRelativeStillOutward")} '
      f'finalRelativeOutside={isum("movingWallFinalRelativeOutside")}')
print(f'relativeSpeedSqRelativeError={relative_error:.12e}')
print(f'interfaceImpulse=({fsum("movingWallImpulseX"):.9g},'
      f'{fsum("movingWallImpulseY"):.9g}) '
      f'absImpulseSum={fsum("movingWallImpulseAbsSum"):.9g}')
print(f'positionShiftAbsSum={fsum("movingWallPositionShiftAbsSum"):.9g}')
print('--- halo context ---')
deep=[I(r,'deepOuterParticles') for r in rows]
shell=[I(r,'shellParticles') for r in rows]
outer=[I(r,'phaseAOuterCellParticles') for r in rows]
print(f'outer first/max/last={outer[0]}/{max(outer)}/{outer[-1]}')
print(f'shell first/max/last={shell[0]}/{max(shell)}/{shell[-1]}')
print(f'deepOuter first/max/last={deep[0]}/{max(deep)}/{deep[-1]}')

# x10l remains useful: compare what Q6/B1 predicts to what alpha actually did.
if 'preWallVnSum' in last:
    nvel=sum(I(r,'preWallVelocityCells') for r in rows)
    mean_vn=fsum('preWallVnSum')/nvel if nvel else 0.0
    mt=fsum('preWallVelocityMassSum')
    mw=fsum('preWallMassVnSum')/mt if mt else 0.0
    print('--- pre-wall Q6/B1 predictor retained ---')
    print(f'meanVn={mean_vn:.9g} massWeightedMeanVn={mw:.9g}')
    print(f'alphaArea first/last={F(rows[0],"preWallAlphaArea"):.9g}/'
          f'{F(last,"preWallAlphaArea"):.9g}')
    if a.mode=='dripping':
        print(f'tipY first/last={F(rows[0],"preWallLowerTipY"):.9g}/'
              f'{F(last,"preWallLowerTipY"):.9g}')

path_ok=(isum('receiverCorrectedParticles')==0 and
         isum('reactionActiveCells')==0 and
         isum('mesoReactionActiveReservoirs')==0)
geom_ok=(isum('movingWallInvalidInterfaceCells')==0)
collision_ok=(isum('movingWallRelativeStillOutward')==0 and
              isum('movingWallFinalRelativeOutside')==0 and
              relative_error < 1e-10)
print('movingWallPathContract=' + ('PASS' if path_ok else 'FAIL'))
print('movingWallGeometryContract=' + ('PASS' if geom_ok else 'REVIEW'))
print('movingWallCollisionContract=' + ('PASS' if collision_ok else 'FAIL'))
print('freeSurfaceImpulseFeedback=DIAGNOSTIC_ONLY_NOT_APPLIED')
print('shapeAndAdvanceContract=VISUAL_AND_ALPHA_MOTION_REVIEW')
print('mobileSolidExtension=PRIMITIVE_READY_PLANE_VELOCITY_PLUS_IMPULSE')
''')
an.chmod(0o755)


# ---------------------------------------------------------------------------
# Runners.  Reuse the already-qualified x10k cases but make x10m take
# precedence and keep x10l passive diagnostics active.  Defaults match the
# requested LiveVis/recording policy.
# ---------------------------------------------------------------------------
static_src = ROOT / 'scripts/run_0493x10k_local_frame_specular_static_drop.sh'
drip_src = ROOT / 'scripts/run_0493x10k_local_frame_specular_dripping.sh'
if not static_src.exists() or not drip_src.exists():
    raise SystemExit('[0493x10m-patch] missing x10k qualification runner(s)')

s = static_src.read_text()
s = s.replace('export MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=1',
'''export MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0
export MPCD_X10M_MOVING_INTERFACE_WALL=1
export MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS=1''', 1)
s = s.replace('RUN_ROOT="${RUN_ROOT:-runs/0493x10k_local_frame_specular_static_s4500}"',
              'RUN_ROOT="${RUN_ROOT:-runs/0493x10m_moving_interface_static_s4500}"', 1)
s = s.replace('===== 0493x10k STATIC DROP / LOCAL-FRAME SPECULAR =====',
              '===== 0493x10m STATIC DROP / MOVING INTERFACE WALL =====', 1)
s = s.replace('[0493x10k] sigma=$SIGMA_ACTIVE kBT=$KBT; no B8/global receiver reaction',
              '[0493x10m] sigma=$SIGMA_ACTIVE kBT=$KBT; alpha=.5 local moving wall; no B8/global receiver reaction', 1)
s = s.replace("[0493x10k] v' = v - 2[(v-u_b).n]n; interface counter-impulse intentionally ignored",
              "[0493x10m] moving plane velocity UGamma.n from post-Q6/B1 liquid; boundary impulse recorded, not fed back", 1)
s = s.replace('python3 scripts/analyze_0493x10k_local_frame_specular.py "$CSV"',
              'python3 scripts/analyze_0493x10m_moving_interface_wall.py "$CSV" --mode static', 1)
static_out = ROOT / 'scripts/run_0493x10m_moving_interface_static_drop.sh'
static_out.write_text(s)
static_out.chmod(0o755)

s = drip_src.read_text()
s = s.replace('CASE_LABEL="dripping_vk_0493x10k_local_frame_specular"',
              'CASE_LABEL="dripping_vk_0493x10m_moving_interface"', 1)
s = s.replace('RUN_ROOT="${RUN_ROOT:-runs/0493x10k_local_frame_specular_dripping_s4500_g01}"',
              'RUN_ROOT="${RUN_ROOT:-runs/0493x10m_moving_interface_dripping_s4500_g01}"', 1)
s = s.replace('MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=1',
'''MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0
MPCD_X10M_MOVING_INTERFACE_WALL=1
MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS=1''', 1)
s = s.replace('export MPCD_X10J_SIMPLE_SPECULAR_ABLATION MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION',
              'export MPCD_X10J_SIMPLE_SPECULAR_ABLATION MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION MPCD_X10M_MOVING_INTERFACE_WALL MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS', 1)
s = s.replace('[0493x10k-drip] objective=local-liquid-frame specular interface ablation; no collective receiver reaction; retain jet/neck/pinch-off/drop/impact',
              '[0493x10m-drip] objective=alpha=.5 local moving-interface wall driven by post-Q6/B1 normal liquid velocity; no collective receiver reaction', 1)
s = s.replace('dripping_vk_0493x10k_local_frame_specular.kv',
              'dripping_vk_0493x10m_moving_interface.kv')
# Existing x10k analyzer call near the end, if present.
s = s.replace('python3 scripts/analyze_0493x10k_local_frame_specular.py "$KINCSV"',
              'python3 scripts/analyze_0493x10m_moving_interface_wall.py "$KINCSV" --mode dripping')
drip_out = ROOT / 'scripts/run_0493x10m_moving_interface_dripping.sh'
drip_out.write_text(s)
drip_out.chmod(0o755)

# Ensure our x10m analyzer is called even if the inherited runner only invokes
# the older generic x10g audit.
if 'analyze_0493x10m_moving_interface_wall.py' not in s:
    raise SystemExit('[0493x10m-patch] failed to install x10m dripping analyzer call')

dual = ROOT / 'scripts/run_0493x10m_moving_interface_dual_qualification.sh'
dual.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
mkdir -p logs

export LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}"
export LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}"
export LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}"
export LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
export FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"

STATIC_ROOT="${STATIC_RUN_ROOT:-runs/0493x10m_moving_interface_static_s4500}"
DRIP_ROOT="${DRIP_RUN_ROOT:-runs/0493x10m_moving_interface_dripping_s4500_g01}"

echo "===== 0493x10m MOVING INTERFACE DUAL QUALIFICATION ====="
echo "[0493x10m] alpha=.5 geometry promoted to one-step local moving wall"
echo "[0493x10m] UGamma.n from post-Q6/B1 liquid; specular in moving-wall frame"
echo "[0493x10m] boundary impulse is recorded per interface cell, not fed back"
echo "[0493x10m] static=${STATIC_STEPS:-800}; dripping=${DRIP_STEPS:-3000}"
echo "[0493x10m] liveEvery=$LIVE_VIS_EVERY recordEvery=$LIVE_VIS_RECORD_EVERY recordFields=$LIVE_VIS_RECORD_FIELDS filterSampleEvery=$FILTER_SAMPLE_EVERY hold=$LIVE_VIS_HOLD_ON_EXIT"

echo
echo "===== STATIC DROP ====="
RUN_ROOT="$STATIC_ROOT" \
SIGMA_ACTIVE="${STATIC_SIGMA_ACTIVE:-4500}" \
STEPS="${STATIC_STEPS:-800}" \
SUMMARY_EVERY="${STATIC_SUMMARY_EVERY:-25}" \
CLEAN_RUN_ROOT=1 \
bash scripts/run_0493x10m_moving_interface_static_drop.sh \
2>&1 | tee logs/0493x10m_moving_interface_static.log

echo
echo "===== DRIPPING ====="
RUN_ROOT="$DRIP_ROOT" \
SIGMA_ACTIVE="${DRIP_SIGMA_ACTIVE:-4500}" \
GRAVITY_Y="${DRIP_GRAVITY_Y:--0.1}" \
STEPS="${DRIP_STEPS:-3000}" \
SUMMARY_EVERY="${DRIP_SUMMARY_EVERY:-25}" \
CLEAN_RUN_ROOT=1 \
bash scripts/run_0493x10m_moving_interface_dripping.sh \
2>&1 | tee logs/0493x10m_moving_interface_dripping.log
''')
dual.chmod(0o755)

print('[0493x10m-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10m-patch] runtime flag: MPCD_X10M_MOVING_INTERFACE_WALL=1')
print('[0493x10m-patch] x10m takes precedence over x10j/x10k and bypasses B8/global receiver reaction')
print('[0493x10m-patch] interface = alpha=.5 local plane, reconstructed every step')
print('[0493x10m-patch] wall normal velocity = post-Q6/B1 local phase-A velocity projected on n')
print('[0493x10m-patch] event-driven collision with moving plane; no endpoint seal')
print('[0493x10m-patch] boundary impulse recorded per interface cell; free-surface feedback intentionally off')
print('[0493x10m-patch] generic moving-plane primitive is reusable for future moving solids')
print('[0493x10m-patch] wrote math check, analyzer, static/dripping/dual runners')
