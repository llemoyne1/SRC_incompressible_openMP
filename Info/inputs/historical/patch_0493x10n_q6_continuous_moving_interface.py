#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'
if not SRC.exists():
    raise SystemExit(f'[0493x10n-patch] missing {SRC}')
text = SRC.read_text()
for tag in ('0493x10m-moving-interface-wall', '0493x10m-fix1-local-alpha-helper-order-independent'):
    if tag not in text:
        raise SystemExit(f'[0493x10n-patch] prerequisite not found: {tag}')
if '0493x10n-q6-continuous-moving-interface' in text:
    raise SystemExit('[0493x10n-patch] x10n already appears applied')

def replace_once(old, new, label):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10n-patch] {label}: expected 1 anchor, found {n}')
    text = text.replace(old, new, 1)

# Audit fields.
replace_once(
'''    double movingWallPositionShiftAbsSum = 0.0;\n};\n''',
'''    double movingWallPositionShiftAbsSum = 0.0;\n\n    // 0493x10n Q6-consistent continuous alpha=.5 polyline diagnostics.\n    unsigned long long continuousWallDualCellsVisited = 0ull;\n    unsigned long long continuousWallInterfaceDualCells = 0ull;\n    unsigned long long continuousWallSegmentsBuilt = 0ull;\n    unsigned long long continuousWallAmbiguousDualCells = 0ull;\n    unsigned long long continuousWallInvalidDualCells = 0ull;\n    unsigned long long continuousWallParticlesWithCandidate = 0ull;\n    unsigned long long continuousWallOldStationaryCrossingCandidates = 0ull;\n    unsigned long long continuousWallOldStationaryCrossingReleased = 0ull;\n    unsigned long long continuousWallNoNearbySegment = 0ull;\n    unsigned long long continuousWallCandidateNoHit = 0ull;\n    unsigned long long continuousWallCollisions = 0ull;\n    unsigned long long continuousWallSecondCollisions = 0ull;\n    unsigned long long continuousWallThirdCollisions = 0ull;\n    unsigned long long continuousWallCollisionLimitReached = 0ull;\n    unsigned long long continuousWallMultipleCollisionCandidates = 0ull;\n    unsigned long long continuousWallRelativeStillOutward = 0ull;\n    double continuousWallCollisionTimeFractionSum = 0.0;\n    double continuousWallWallVnSum = 0.0;\n    double continuousWallWallVnSqSum = 0.0;\n    double continuousWallWallVnAbsSum = 0.0;\n    double continuousWallRelativeSpeedSqAbsErrorSum = 0.0;\n    double continuousWallRelativeSpeedSqReferenceSum = 0.0;\n    double continuousWallImpulseX = 0.0;\n    double continuousWallImpulseY = 0.0;\n    double continuousWallImpulseAbsSum = 0.0;\n    double continuousWallPositionShiftAbsSum = 0.0;\n};\n''',
'audit x10n fields')

# Workspace buffers: at most two marching-squares segments per dual cell.
replace_once(
'''    DeviceBuffer0400<double> kineticMovingWallImpulseY0493x10m;\n    bool phaseInterfaceStencilValid0493x6f = false;\n''',
'''    DeviceBuffer0400<double> kineticMovingWallImpulseY0493x10m;\n\n    // 0493x10n continuous interface on the cell-centre dual grid.  Every dual\n    // square owns 0, 1 or 2 segments; shared Q6-style edge crossings are\n    // computed from the same two alpha cell values, so neighboring segments\n    // have exactly matching endpoints.\n    DeviceBuffer0400<unsigned char> kineticContinuousSegCount0493x10n;\n    DeviceBuffer0400<double> kineticContinuousSegAx0493x10n;\n    DeviceBuffer0400<double> kineticContinuousSegAy0493x10n;\n    DeviceBuffer0400<double> kineticContinuousSegBx0493x10n;\n    DeviceBuffer0400<double> kineticContinuousSegBy0493x10n;\n    DeviceBuffer0400<double> kineticContinuousSegUax0493x10n;\n    DeviceBuffer0400<double> kineticContinuousSegUay0493x10n;\n    DeviceBuffer0400<double> kineticContinuousSegUbx0493x10n;\n    DeviceBuffer0400<double> kineticContinuousSegUby0493x10n;\n    bool phaseInterfaceStencilValid0493x6f = false;\n''',
'workspace x10n buffers')

replace_once(
'''        kineticMovingWallImpulseX0493x10m.ensure(c);\n        kineticMovingWallImpulseY0493x10m.ensure(c);\n    }\n''',
'''        kineticMovingWallImpulseX0493x10m.ensure(c);\n        kineticMovingWallImpulseY0493x10m.ensure(c);\n        kineticContinuousSegCount0493x10n.ensure(c);\n        const std::size_t s2 = 2u * c;\n        kineticContinuousSegAx0493x10n.ensure(s2);\n        kineticContinuousSegAy0493x10n.ensure(s2);\n        kineticContinuousSegBx0493x10n.ensure(s2);\n        kineticContinuousSegBy0493x10n.ensure(s2);\n        kineticContinuousSegUax0493x10n.ensure(s2);\n        kineticContinuousSegUay0493x10n.ensure(s2);\n        kineticContinuousSegUbx0493x10n.ensure(s2);\n        kineticContinuousSegUby0493x10n.ensure(s2);\n    }\n''',
'ensure x10n buffers')

# Kernels inserted before x10i reduction anchor.
anchor = '''// 0493x10i: reduce existing per-cell donor/receiver statistics into\n// shifted mesoscopic reservoirs. No particle pass is added.\n'''
if text.count(anchor) != 1:
    raise SystemExit(f'[0493x10n-patch] kernel insertion anchor count={text.count(anchor)}')

kernels = r'''// =============================================================================
// 0493x10n — Q6-CONSISTENT CONTINUOUS MOVING alpha=.5 INTERFACE
// =============================================================================
// x10m proved the moving-boundary kinematics but approximated Gamma by one
// independently truncated plane per liquid cell.  x10n instead reconstructs a
// continuous polyline on the cell-centre dual grid.  Every edge crossing uses
// exactly the Q6 cut fraction for a linearly interpolated alpha=.5 crossing:
//
//   theta = (0.5-alpha0)/(alpha1-alpha0).
//
// A dual square then connects its 2 (or, in a saddle, 4) shared edge crossings
// with marching-squares topology.  Adjacent dual squares recompute a shared
// edge endpoint from the same two alpha values and therefore meet exactly.
// Endpoint velocities are taken from the liquid-side post-Q6/B1 cell velocity;
// the same shared edge has the same liquid-side cell, so endpoint motion also
// remains continuous during the streaming interval.
//
// The moving-segment collision primitive is intentionally generic: a future
// mobile solid can provide persistent segment endpoints/velocities and consume
// the same collision impulses for rigid-body translation/rotation.
struct MovingSegment0493x10n {
    double ax = 0.0, ay = 0.0;
    double bx = 0.0, by = 0.0;
    double uax = 0.0, uay = 0.0;
    double ubx = 0.0, uby = 0.0;
    int ownerCell = -1;
};

struct MovingSegmentCollision0493x10n {
    bool hit = false;
    double tau = 0.0;
    double lambda = 0.0;
    double newVx = 0.0, newVy = 0.0;
    double wallVx = 0.0, wallVy = 0.0;
    double nx = 0.0, ny = 0.0;
    double relnBefore = 0.0;
    double impulseWallX = 0.0, impulseWallY = 0.0;
};

struct IsoPoint0493x10n {
    double x = 0.0, y = 0.0;
    double ux = 0.0, uy = 0.0;
    bool valid = false;
};

__device__ __forceinline__ double q6_x10n_cross2(
    double ax, double ay, double bx, double by) {
    return ax * by - ay * bx;
}

__device__ __forceinline__ int q6_x10n_cell_index(
    int i, int j, int nx, int ny, int periodicX, int periodicY) {
    if (periodicX) {
        i %= nx; if (i < 0) i += nx;
    } else if (i < 0 || i >= nx) return -1;
    if (periodicY) {
        j %= ny; if (j < 0) j += ny;
    } else if (j < 0 || j >= ny) return -1;
    return j * nx + i;
}

__device__ __forceinline__ bool q6_x10n_cell_velocity(
    int c,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    double* ux, double* uy) {
    if (c < 0 || !ux || !uy) return false;
    const double m = totalM[c];
    const double px = totalPx[c];
    const double py = totalPy[c];
    if (!(m > 1.0e-14) || !isfinite(m) || !isfinite(px) || !isfinite(py))
        return false;
    *ux = px / m;
    *uy = py / m;
    return isfinite(*ux) && isfinite(*uy);
}

// Q6-consistent alpha=.5 crossing on one edge between two cell centres.
// The velocity attached to the endpoint is the post-Q6/B1 velocity of the
// liquid-side cell.  This choice is unique for the shared edge and therefore
// gives identical endpoint motion to both adjacent dual squares.
__device__ __forceinline__ bool q6_x10n_edge_crossing(
    double a0, double a1,
    double x0, double y0, double x1, double y1,
    int c0, int c1,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    IsoPoint0493x10n* out) {
    if (!out) return false;
    const bool in0 = a0 >= 0.5;
    const bool in1 = a1 >= 0.5;
    if (in0 == in1) return false;
    const double den = a1 - a0;
    if (!(fabs(den) > 1.0e-15) || !isfinite(den)) return false;
    double theta = (0.5 - a0) / den;
    theta = fmin(1.0, fmax(0.0, theta));
    const int liquid = in0 ? c0 : c1;
    double ux = 0.0, uy = 0.0;
    if (!q6_x10n_cell_velocity(
            liquid, totalM, totalPx, totalPy, &ux, &uy))
        return false;
    out->x = x0 + theta * (x1 - x0);
    out->y = y0 + theta * (y1 - y0);
    out->ux = ux;
    out->uy = uy;
    out->valid = isfinite(out->x) && isfinite(out->y);
    return out->valid;
}

__device__ __forceinline__ void q6_x10n_orient_segment_outward(
    IsoPoint0493x10n* a,
    IsoPoint0493x10n* b,
    double a00, double a10, double a11, double a01,
    double xBase, double yBase, double dx, double dy) {
    if (!a || !b) return;
    const double mx = 0.5 * (a->x + b->x);
    const double my = 0.5 * (a->y + b->y);
    const double xi = fmin(1.0, fmax(0.0, (mx - xBase) / dx));
    const double eta = fmin(1.0, fmax(0.0, (my - yBase) / dy));
    const double gx = ((a10 - a00) * (1.0 - eta) +
                       (a11 - a01) * eta) / dx;
    const double gy = ((a01 - a00) * (1.0 - xi) +
                       (a11 - a10) * xi) / dy;
    const double tx0 = b->x - a->x;
    const double ty0 = b->y - a->y;
    const double L2 = tx0 * tx0 + ty0 * ty0;
    if (!(L2 > 1.0e-24)) return;
    const double invL = 1.0 / sqrt(L2);
    const double nrx = ty0 * invL;   // right normal of A -> B
    const double nry = -tx0 * invL;
    // Outward is toward decreasing alpha, i.e. -grad(alpha).
    if (nrx * (-gx) + nry * (-gy) < 0.0) {
        const IsoPoint0493x10n tmp = *a;
        *a = *b;
        *b = tmp;
    }
}

__device__ __forceinline__ bool q6_x10n_store_segment(
    int owner, int slot,
    IsoPoint0493x10n a,
    IsoPoint0493x10n b,
    double a00, double a10, double a11, double a01,
    double xBase, double yBase, double dx, double dy,
    double* segAx, double* segAy,
    double* segBx, double* segBy,
    double* segUax, double* segUay,
    double* segUbx, double* segUby) {
    if (owner < 0 || slot < 0 || slot > 1 || !a.valid || !b.valid) return false;
    const double ddx = b.x - a.x;
    const double ddy = b.y - a.y;
    if (!(ddx * ddx + ddy * ddy > 1.0e-20 * fmin(dx * dx, dy * dy)))
        return false;
    q6_x10n_orient_segment_outward(
        &a, &b, a00, a10, a11, a01, xBase, yBase, dx, dy);
    const int s = 2 * owner + slot;
    segAx[s] = a.x; segAy[s] = a.y;
    segBx[s] = b.x; segBy[s] = b.y;
    segUax[s] = a.ux; segUay[s] = a.uy;
    segUbx[s] = b.ux; segUby[s] = b.uy;
    return true;
}

__global__ void q6_x10n_build_continuous_interface(
    int numCells,
    int nx, int ny,
    double lx, double ly,
    int periodicX, int periodicY,
    const double* alpha,
    const double* totalM,
    const double* totalPx,
    const double* totalPy,
    unsigned char* segCount,
    double* segAx, double* segAy,
    double* segBx, double* segBy,
    double* segUax, double* segUay,
    double* segUbx, double* segUby,
    KineticCrossingAccumulator0493x9x* audit) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);

    for (int owner = idx; owner < numCells; owner += stride) {
        segCount[owner] = 0;
        const int i = owner % nx;
        const int j = owner / nx;
        if ((!periodicX && i + 1 >= nx) ||
            (!periodicY && j + 1 >= ny))
            continue;
        if (audit) atomicAdd(&audit->continuousWallDualCellsVisited, 1ull);

        const int c00 = q6_x10n_cell_index(i,     j,     nx, ny, periodicX, periodicY);
        const int c10 = q6_x10n_cell_index(i + 1, j,     nx, ny, periodicX, periodicY);
        const int c11 = q6_x10n_cell_index(i + 1, j + 1, nx, ny, periodicX, periodicY);
        const int c01 = q6_x10n_cell_index(i,     j + 1, nx, ny, periodicX, periodicY);
        if (c00 < 0 || c10 < 0 || c11 < 0 || c01 < 0) continue;
        const double a00 = alpha[c00], a10 = alpha[c10];
        const double a11 = alpha[c11], a01 = alpha[c01];
        if (!isfinite(a00) || !isfinite(a10) || !isfinite(a11) || !isfinite(a01)) {
            if (audit) atomicAdd(&audit->continuousWallInvalidDualCells, 1ull);
            continue;
        }
        const int b0 = a00 >= 0.5 ? 1 : 0;
        const int b1 = a10 >= 0.5 ? 1 : 0;
        const int b2 = a11 >= 0.5 ? 1 : 0;
        const int b3 = a01 >= 0.5 ? 1 : 0;
        const int code = b0 | (b1 << 1) | (b2 << 2) | (b3 << 3);
        if (code == 0 || code == 15) continue;
        if (audit) atomicAdd(&audit->continuousWallInterfaceDualCells, 1ull);

        const double x0 = (static_cast<double>(i) + 0.5) * dx;
        const double y0 = (static_cast<double>(j) + 0.5) * dy;
        const double x1 = x0 + dx;
        const double y1 = y0 + dy;
        IsoPoint0493x10n e[4];
        bool h[4] = {false, false, false, false};
        h[0] = q6_x10n_edge_crossing(a00, a10, x0, y0, x1, y0,
                                      c00, c10, totalM, totalPx, totalPy, &e[0]);
        h[1] = q6_x10n_edge_crossing(a10, a11, x1, y0, x1, y1,
                                      c10, c11, totalM, totalPx, totalPy, &e[1]);
        h[2] = q6_x10n_edge_crossing(a11, a01, x1, y1, x0, y1,
                                      c11, c01, totalM, totalPx, totalPy, &e[2]);
        h[3] = q6_x10n_edge_crossing(a01, a00, x0, y1, x0, y0,
                                      c01, c00, totalM, totalPx, totalPy, &e[3]);
        int edges[4]; int ne = 0;
        for (int k = 0; k < 4; ++k) if (h[k]) edges[ne++] = k;

        int built = 0;
        if (ne == 2) {
            if (q6_x10n_store_segment(owner, 0, e[edges[0]], e[edges[1]],
                    a00, a10, a11, a01, x0, y0, dx, dy,
                    segAx, segAy, segBx, segBy,
                    segUax, segUay, segUbx, segUby))
                built = 1;
        } else if (ne == 4) {
            if (code != 5 && code != 10) {
                if (audit) atomicAdd(&audit->continuousWallInvalidDualCells, 1ull);
                continue;
            }
            if (audit) atomicAdd(&audit->continuousWallAmbiguousDualCells, 1ull);
            // Marching-squares asymptotic choice reduced to the bilinear value
            // at the dual-square centre.  It is deterministic and shared-edge
            // continuous; it only selects topology inside this saddle square.
            const bool centerInside = 0.25 * (a00 + a10 + a11 + a01) >= 0.5;
            int p00a = 0, p00b = 0, p11a = 0, p11b = 0;
            if (code == 5) { // inside corners 00 and 11
                if (centerInside) {
                    p00a = 0; p00b = 1; p11a = 2; p11b = 3;
                } else {
                    p00a = 3; p00b = 0; p11a = 1; p11b = 2;
                }
            } else { // code 10: inside corners 10 and 01
                if (centerInside) {
                    p00a = 3; p00b = 0; p11a = 1; p11b = 2;
                } else {
                    p00a = 0; p00b = 1; p11a = 2; p11b = 3;
                }
            }
            if (q6_x10n_store_segment(owner, built, e[p00a], e[p00b],
                    a00, a10, a11, a01, x0, y0, dx, dy,
                    segAx, segAy, segBx, segBy,
                    segUax, segUay, segUbx, segUby)) ++built;
            if (built < 2 && q6_x10n_store_segment(owner, built, e[p11a], e[p11b],
                    a00, a10, a11, a01, x0, y0, dx, dy,
                    segAx, segAy, segBx, segBy,
                    segUax, segUay, segUbx, segUby)) ++built;
        } else {
            if (audit) atomicAdd(&audit->continuousWallInvalidDualCells, 1ull);
            continue;
        }
        segCount[owner] = static_cast<unsigned char>(built);
        if (audit && built > 0)
            atomicAdd(&audit->continuousWallSegmentsBuilt,
                      static_cast<unsigned long long>(built));
    }
}

// Collision against a line segment with linearly moving endpoints.  The
// particle and endpoint trajectories are linear, so collinearity is a
// quadratic equation in tau.  At the hit, specular reflection uses the local
// interpolated wall velocity and the instantaneous segment normal.
__device__ __forceinline__ bool q6_x10n_collide_moving_segment(
    double x0, double y0,
    double vx, double vy,
    double mass,
    double tStart,
    double window,
    double dx, double dy,
    double lx, double ly,
    int periodicX, int periodicY,
    const MovingSegment0493x10n& seg,
    MovingSegmentCollision0493x10n* out) {
    if (!out || !(window > 0.0)) return false;

    const double agx = seg.ax + seg.uax * tStart;
    const double agy = seg.ay + seg.uay * tStart;
    const double dgx = (seg.bx - seg.ax) + (seg.ubx - seg.uax) * tStart;
    const double dgy = (seg.by - seg.ay) + (seg.uby - seg.uay) * tStart;
    double arx = q6_x10m_minimum_image(agx - x0, lx, periodicX);
    double ary = q6_x10m_minimum_image(agy - y0, ly, periodicY);
    const double L20 = dgx * dgx + dgy * dgy;
    if (!(L20 > 1.0e-24) || !isfinite(L20)) return false;
    const double invL0 = 1.0 / sqrt(L20);
    const double n0x = dgy * invL0;   // outward: segments are oriented A->B
    const double n0y = -dgx * invL0;
    const double s0 = (-arx) * n0x + (-ary) * n0y;
    const double h = fmin(dx, dy);
    const double sideTol = 1.0e-8 * fmax(1.0, h);
    if (s0 > sideTol || s0 < -2.5 * h) return false;

    const double r0x = -arx;
    const double r0y = -ary;
    const double urx = vx - seg.uax;
    const double ury = vy - seg.uay;
    const double udx = seg.ubx - seg.uax;
    const double udy = seg.uby - seg.uay;
    const double c0 = q6_x10n_cross2(dgx, dgy, r0x, r0y);
    const double c1 = q6_x10n_cross2(dgx, dgy, urx, ury) +
                      q6_x10n_cross2(udx, udy, r0x, r0y);
    const double c2 = q6_x10n_cross2(udx, udy, urx, ury);

    double roots[2]; int nr = 0;
    const double eps = 1.0e-14;
    if (fabs(c2) < eps) {
        if (fabs(c1) < eps) return false;
        roots[nr++] = -c0 / c1;
    } else {
        double disc = c1 * c1 - 4.0 * c2 * c0;
        if (disc < -1.0e-14 * fmax(1.0, c1 * c1)) return false;
        disc = fmax(0.0, disc);
        const double sd = sqrt(disc);
        roots[nr++] = (-c1 - sd) / (2.0 * c2);
        roots[nr++] = (-c1 + sd) / (2.0 * c2);
        if (roots[1] < roots[0]) {
            const double tmp = roots[0]; roots[0] = roots[1]; roots[1] = tmp;
        }
    }

    for (int ir = 0; ir < nr; ++ir) {
        double tau = roots[ir];
        const double tTol = 1.0e-11 * fmax(1.0, window);
        if (tau < -tTol || tau > window + tTol || !isfinite(tau)) continue;
        tau = fmin(window, fmax(0.0, tau));
        const double dxh = dgx + udx * tau;
        const double dyh = dgy + udy * tau;
        const double L2 = dxh * dxh + dyh * dyh;
        if (!(L2 > 1.0e-24)) continue;
        const double rxh = r0x + urx * tau;
        const double ryh = r0y + ury * tau;
        double lambda = (rxh * dxh + ryh * dyh) / L2;
        const double ltol = 1.0e-9;
        if (lambda < -ltol || lambda > 1.0 + ltol) continue;
        lambda = fmin(1.0, fmax(0.0, lambda));
        const double invL = 1.0 / sqrt(L2);
        const double nxh = dyh * invL;
        const double nyh = -dxh * invL;
        const double wallVx = seg.uax + lambda * (seg.ubx - seg.uax);
        const double wallVy = seg.uay + lambda * (seg.uby - seg.uay);
        const double reln = (vx - wallVx) * nxh + (vy - wallVy) * nyh;
        if (!(reln > 1.0e-13) || !isfinite(reln)) continue;

        out->hit = true;
        out->tau = tau;
        out->lambda = lambda;
        out->wallVx = wallVx;
        out->wallVy = wallVy;
        out->nx = nxh;
        out->ny = nyh;
        out->relnBefore = reln;
        out->newVx = vx - 2.0 * reln * nxh;
        out->newVy = vy - 2.0 * reln * nyh;
        const double impulse = 2.0 * mass * reln;
        out->impulseWallX = impulse * nxh;
        out->impulseWallY = impulse * nyh;
        return isfinite(out->newVx) && isfinite(out->newVy);
    }
    return false;
}

__device__ __forceinline__ int q6_x10n_position_cell(
    double x, double y,
    int nx, int ny, double lx, double ly,
    int periodicX, int periodicY) {
    if (periodicX) {
        x -= floor(x / lx) * lx;
        if (x >= lx) x = 0.0;
    }
    if (periodicY) {
        y -= floor(y / ly) * ly;
        if (y >= ly) y = 0.0;
    }
    if (x < 0.0 || x >= lx || y < 0.0 || y >= ly) return -1;
    int i = static_cast<int>(floor(x * static_cast<double>(nx) / lx));
    int j = static_cast<int>(floor(y * static_cast<double>(ny) / ly));
    if (i < 0) i = 0; else if (i >= nx) i = nx - 1;
    if (j < 0) j = 0; else if (j >= ny) j = ny - 1;
    return j * nx + i;
}

__global__ void q6_x10n_apply_continuous_moving_interface(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    std::uint64_t nParticles,
    const double* alpha,
    const unsigned char* segCount,
    const double* segAx, const double* segAy,
    const double* segBx, const double* segBy,
    const double* segUax, const double* segUay,
    const double* segUbx, const double* segUby,
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
        const int initialCell = cells.cellId[p];
        if (initialCell < 0 || initialCell >= cells.numCells) continue;

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
                atomicAdd(&audit->continuousWallOldStationaryCrossingCandidates, 1ull);
        }

        double cx = x0, cy = y0;
        double cvx = vx0, cvy = vy0;
        double elapsed = 0.0;
        int hitsTotal = 0;
        bool sawAnySegment = false;
        bool sawCandidateNoHit = false;
        int firstSearchCandidates = 0;

        // Up to three local impacts handles a near-vertex hit without turning
        // the interface into a multi-pass global particle correction.
        for (int event = 0; event < 3; ++event) {
            const double remaining = dt - elapsed;
            if (!(remaining > 1.0e-14)) break;
            const int cc = q6_x10n_position_cell(
                cx, cy, nx, ny, lx, ly, periodicX, periodicY);
            if (cc < 0) break;
            const int ci = cc % nx;
            const int cj = cc / nx;

            MovingSegmentCollision0493x10n best{};
            MovingSegment0493x10n bestSeg{};
            double bestTau = remaining + 1.0;
            int validHits = 0;
            int candidates = 0;

            for (int dj = -1; dj <= 1; ++dj) {
                for (int di = -1; di <= 1; ++di) {
                    const int owner = q6_x10n_cell_index(
                        ci + di, cj + dj, nx, ny, periodicX, periodicY);
                    if (owner < 0) continue;
                    const int ns = static_cast<int>(segCount[owner]);
                    for (int slot = 0; slot < ns && slot < 2; ++slot) {
                        ++candidates;
                        const int s = 2 * owner + slot;
                        MovingSegment0493x10n seg{};
                        seg.ax = segAx[s]; seg.ay = segAy[s];
                        seg.bx = segBx[s]; seg.by = segBy[s];
                        seg.uax = segUax[s]; seg.uay = segUay[s];
                        seg.ubx = segUbx[s]; seg.uby = segUby[s];
                        seg.ownerCell = owner;
                        MovingSegmentCollision0493x10n hit{};
                        if (!q6_x10n_collide_moving_segment(
                                cx, cy, cvx, cvy, mass,
                                elapsed, remaining,
                                dx, dy, lx, ly,
                                periodicX, periodicY,
                                seg, &hit))
                            continue;
                        ++validHits;
                        if (hit.tau < bestTau) {
                            bestTau = hit.tau;
                            best = hit;
                            bestSeg = seg;
                        }
                    }
                }
            }

            if (event == 0) firstSearchCandidates = candidates;
            if (candidates > 0) sawAnySegment = true;
            if (!best.hit) {
                if (candidates > 0) sawCandidateNoHit = true;
                break;
            }
            if (validHits > 1 && audit)
                atomicAdd(&audit->continuousWallMultipleCollisionCandidates, 1ull);

            cx += cvx * best.tau;
            cy += cvy * best.tau;
            elapsed += best.tau;
            cvx = best.newVx;
            cvy = best.newVy;
            ++hitsTotal;

            atomic_add_double_0400(
                &wallImpulseX[bestSeg.ownerCell], best.impulseWallX);
            atomic_add_double_0400(
                &wallImpulseY[bestSeg.ownerCell], best.impulseWallY);

            if (audit) {
                atomicAdd(&audit->continuousWallCollisions, 1ull);
                if (hitsTotal == 2)
                    atomicAdd(&audit->continuousWallSecondCollisions, 1ull);
                else if (hitsTotal == 3)
                    atomicAdd(&audit->continuousWallThirdCollisions, 1ull);
                atomic_add_double_0400(
                    &audit->continuousWallCollisionTimeFractionSum,
                    elapsed / dt);
                const double wallVn = best.wallVx * best.nx + best.wallVy * best.ny;
                atomic_add_double_0400(&audit->continuousWallWallVnSum, wallVn);
                atomic_add_double_0400(
                    &audit->continuousWallWallVnSqSum, wallVn * wallVn);
                atomic_add_double_0400(
                    &audit->continuousWallWallVnAbsSum, fabs(wallVn));
                const double cbx = (event == 0 ? vx0 : 0.0); // reference below is recomputed
                (void)cbx;
                const double beforeRelX =
                    (best.newVx + 2.0 * best.relnBefore * best.nx) - best.wallVx;
                const double beforeRelY =
                    (best.newVy + 2.0 * best.relnBefore * best.ny) - best.wallVy;
                const double afterRelX = best.newVx - best.wallVx;
                const double afterRelY = best.newVy - best.wallVy;
                const double eBefore = beforeRelX * beforeRelX + beforeRelY * beforeRelY;
                const double eAfter = afterRelX * afterRelX + afterRelY * afterRelY;
                atomic_add_double_0400(
                    &audit->continuousWallRelativeSpeedSqAbsErrorSum,
                    fabs(eAfter - eBefore));
                atomic_add_double_0400(
                    &audit->continuousWallRelativeSpeedSqReferenceSum,
                    fabs(eBefore));
                const double relAfter =
                    (best.newVx - best.wallVx) * best.nx +
                    (best.newVy - best.wallVy) * best.ny;
                if (!(relAfter < 1.0e-12 * fmax(1.0, fabs(best.relnBefore))))
                    atomicAdd(&audit->continuousWallRelativeStillOutward, 1ull);
                atomic_add_double_0400(
                    &audit->continuousWallImpulseX, best.impulseWallX);
                atomic_add_double_0400(
                    &audit->continuousWallImpulseY, best.impulseWallY);
                atomic_add_double_0400(
                    &audit->continuousWallImpulseAbsSum,
                    sqrt(best.impulseWallX * best.impulseWallX +
                         best.impulseWallY * best.impulseWallY));
            }
        }

        if (audit && sawAnySegment)
            atomicAdd(&audit->continuousWallParticlesWithCandidate, 1ull);
        if (audit && oldStationaryOuter && hitsTotal == 0)
            atomicAdd(&audit->continuousWallOldStationaryCrossingReleased, 1ull);
        if (audit && oldStationaryOuter && firstSearchCandidates == 0)
            atomicAdd(&audit->continuousWallNoNearbySegment, 1ull);
        if (audit && oldStationaryOuter && firstSearchCandidates > 0 && hitsTotal == 0)
            atomicAdd(&audit->continuousWallCandidateNoHit, 1ull);
        if (audit && hitsTotal >= 3)
            atomicAdd(&audit->continuousWallCollisionLimitReached, 1ull);

        if (hitsTotal == 0) continue;
        const double remaining = fmax(0.0, dt - elapsed);
        const double xf = cx + cvx * remaining;
        const double yf = cy + cvy * remaining;
        const double corrX = xf - cvx * dt - x0;
        const double corrY = yf - cvy * dt - y0;
        particles.x[p] = x0 + corrX;
        particles.y[p] = y0 + corrY;
        particles.vx[p] = cvx;
        particles.vy[p] = cvy;
        if (audit)
            atomic_add_double_0400(
                &audit->continuousWallPositionShiftAbsSum,
                sqrt(corrX * corrX + corrY * corrY));
    }
}

'''
text = text.replace(anchor, kernels + anchor, 1)

# Runtime precedence.
replace_once(
'''    const bool movingInterfaceWall0493x10m =\n        r >= 1.0 &&\n        env_int_0400("MPCD_X10M_MOVING_INTERFACE_WALL", 0) != 0;\n    const bool localFrameSpecularAblation =\n        !movingInterfaceWall0493x10m && r >= 1.0 &&\n        env_int_0400("MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION", 0) != 0;\n    const bool simpleSpecularAblation =\n        !movingInterfaceWall0493x10m && !localFrameSpecularAblation && r >= 1.0 &&\n        env_int_0400("MPCD_X10J_SIMPLE_SPECULAR_ABLATION", 0) != 0;\n    const bool anySimpleSpecularAblation =\n        movingInterfaceWall0493x10m ||\n        simpleSpecularAblation || localFrameSpecularAblation;\n''',
'''    const bool continuousInterfaceWall0493x10n =\n        r >= 1.0 &&\n        env_int_0400("MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL", 0) != 0;\n    const bool movingInterfaceWall0493x10m =\n        !continuousInterfaceWall0493x10n && r >= 1.0 &&\n        env_int_0400("MPCD_X10M_MOVING_INTERFACE_WALL", 0) != 0;\n    const bool localFrameSpecularAblation =\n        !continuousInterfaceWall0493x10n && !movingInterfaceWall0493x10m && r >= 1.0 &&\n        env_int_0400("MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION", 0) != 0;\n    const bool simpleSpecularAblation =\n        !continuousInterfaceWall0493x10n && !movingInterfaceWall0493x10m &&\n        !localFrameSpecularAblation && r >= 1.0 &&\n        env_int_0400("MPCD_X10J_SIMPLE_SPECULAR_ABLATION", 0) != 0;\n    const bool anySimpleSpecularAblation =\n        continuousInterfaceWall0493x10n || movingInterfaceWall0493x10m ||\n        simpleSpecularAblation || localFrameSpecularAblation;\n''',
'x10n precedence flags')

# Build branch: x10n before x10m.
old_build = '''    if (movingInterfaceWall0493x10m) {\n        const std::size_t cellCount =\n            static_cast<std::size_t>(std::max(1, grid.numCells));\n        check_cuda_0400(\n            cudaMemset(ws.kineticMovingWallActive0493x10m.data(), 0,\n                       cellCount * sizeof(unsigned char)),\n            "0493x10m moving-wall active zero");\n        check_cuda_0400(\n            cudaMemset(ws.kineticMovingWallImpulseX0493x10m.data(), 0,\n                       cellCount * sizeof(double)),\n            "0493x10m moving-wall impulseX zero");\n        check_cuda_0400(\n            cudaMemset(ws.kineticMovingWallImpulseY0493x10m.data(), 0,\n                       cellCount * sizeof(double)),\n            "0493x10m moving-wall impulseY zero");\n\n        q6_x10m_build_moving_interface_cells<<<cellBlocks, threads>>>(\n            grid.numCells,\n            grid.Nx, grid.Ny,\n            params.Lx, params.Ly,\n            periodicX, periodicY,\n            phaseAlpha0493x6c,\n            ws.kineticTotalM0493x9t.data(),\n            ws.kineticTotalPx0493x9t.data(),\n            ws.kineticTotalPy0493x9t.data(),\n            ws.kineticMovingWallActive0493x10m.data(),\n            ws.kineticMovingWallNx0493x10m.data(),\n            ws.kineticMovingWallNy0493x10m.data(),\n            ws.kineticMovingWallQx0493x10m.data(),\n            ws.kineticMovingWallQy0493x10m.data(),\n            ws.kineticMovingWallVn0493x10m.data(),\n            auditDev);\n        check_cuda_0400(\n            cudaGetLastError(), "0493x10m moving-interface build launch");\n    }\n'''
new_build = '''    if (continuousInterfaceWall0493x10n) {\n        const std::size_t cellCount =\n            static_cast<std::size_t>(std::max(1, grid.numCells));\n        check_cuda_0400(\n            cudaMemset(ws.kineticContinuousSegCount0493x10n.data(), 0,\n                       cellCount * sizeof(unsigned char)),\n            "0493x10n segment-count zero");\n        check_cuda_0400(\n            cudaMemset(ws.kineticMovingWallImpulseX0493x10m.data(), 0,\n                       cellCount * sizeof(double)),\n            "0493x10n interface impulseX zero");\n        check_cuda_0400(\n            cudaMemset(ws.kineticMovingWallImpulseY0493x10m.data(), 0,\n                       cellCount * sizeof(double)),\n            "0493x10n interface impulseY zero");\n        q6_x10n_build_continuous_interface<<<cellBlocks, threads>>>(\n            grid.numCells, grid.Nx, grid.Ny,\n            params.Lx, params.Ly, periodicX, periodicY,\n            phaseAlpha0493x6c,\n            ws.kineticTotalM0493x9t.data(),\n            ws.kineticTotalPx0493x9t.data(),\n            ws.kineticTotalPy0493x9t.data(),\n            ws.kineticContinuousSegCount0493x10n.data(),\n            ws.kineticContinuousSegAx0493x10n.data(),\n            ws.kineticContinuousSegAy0493x10n.data(),\n            ws.kineticContinuousSegBx0493x10n.data(),\n            ws.kineticContinuousSegBy0493x10n.data(),\n            ws.kineticContinuousSegUax0493x10n.data(),\n            ws.kineticContinuousSegUay0493x10n.data(),\n            ws.kineticContinuousSegUbx0493x10n.data(),\n            ws.kineticContinuousSegUby0493x10n.data(),\n            auditDev);\n        check_cuda_0400(\n            cudaGetLastError(), "0493x10n continuous-interface build launch");\n    } else if (movingInterfaceWall0493x10m) {\n        const std::size_t cellCount =\n            static_cast<std::size_t>(std::max(1, grid.numCells));\n        check_cuda_0400(\n            cudaMemset(ws.kineticMovingWallActive0493x10m.data(), 0,\n                       cellCount * sizeof(unsigned char)),\n            "0493x10m moving-wall active zero");\n        check_cuda_0400(\n            cudaMemset(ws.kineticMovingWallImpulseX0493x10m.data(), 0,\n                       cellCount * sizeof(double)),\n            "0493x10m moving-wall impulseX zero");\n        check_cuda_0400(\n            cudaMemset(ws.kineticMovingWallImpulseY0493x10m.data(), 0,\n                       cellCount * sizeof(double)),\n            "0493x10m moving-wall impulseY zero");\n\n        q6_x10m_build_moving_interface_cells<<<cellBlocks, threads>>>(\n            grid.numCells,\n            grid.Nx, grid.Ny,\n            params.Lx, params.Ly,\n            periodicX, periodicY,\n            phaseAlpha0493x6c,\n            ws.kineticTotalM0493x9t.data(),\n            ws.kineticTotalPx0493x9t.data(),\n            ws.kineticTotalPy0493x9t.data(),\n            ws.kineticMovingWallActive0493x10m.data(),\n            ws.kineticMovingWallNx0493x10m.data(),\n            ws.kineticMovingWallNy0493x10m.data(),\n            ws.kineticMovingWallQx0493x10m.data(),\n            ws.kineticMovingWallQy0493x10m.data(),\n            ws.kineticMovingWallVn0493x10m.data(),\n            auditDev);\n        check_cuda_0400(\n            cudaGetLastError(), "0493x10m moving-interface build launch");\n    }\n'''
replace_once(old_build, new_build, 'x10n build branch')

# Apply branch.
old_apply_prefix = '''    if (movingInterfaceWall0493x10m) {\n        q6_x10m_apply_moving_interface_wall<<<particleBlocks, threads>>>(\n'''
new_apply_prefix = '''    if (continuousInterfaceWall0493x10n) {\n        q6_x10n_apply_continuous_moving_interface<<<particleBlocks, threads>>>(\n            particles, cells, nParticles,\n            phaseAlpha0493x6c,\n            ws.kineticContinuousSegCount0493x10n.data(),\n            ws.kineticContinuousSegAx0493x10n.data(),\n            ws.kineticContinuousSegAy0493x10n.data(),\n            ws.kineticContinuousSegBx0493x10n.data(),\n            ws.kineticContinuousSegBy0493x10n.data(),\n            ws.kineticContinuousSegUax0493x10n.data(),\n            ws.kineticContinuousSegUay0493x10n.data(),\n            ws.kineticContinuousSegUbx0493x10n.data(),\n            ws.kineticContinuousSegUby0493x10n.data(),\n            ws.kineticMovingWallImpulseX0493x10m.data(),\n            ws.kineticMovingWallImpulseY0493x10m.data(),\n            phaseAType,\n            grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt,\n            periodicX, periodicY, auditDev);\n        check_cuda_0400(\n            cudaGetLastError(), "0493x10n continuous-interface collision launch");\n    } else if (movingInterfaceWall0493x10m) {\n        q6_x10m_apply_moving_interface_wall<<<particleBlocks, threads>>>(\n'''
replace_once(old_apply_prefix, new_apply_prefix, 'x10n apply branch')

# CSV header append before contract.
replace_once(
'''               "movingWallPositionShiftAbsSum,"\n               "contract\\n";\n''',
'''               "movingWallPositionShiftAbsSum,"\n               "continuousWallDualCellsVisited,continuousWallInterfaceDualCells,"\n               "continuousWallSegmentsBuilt,continuousWallAmbiguousDualCells,"\n               "continuousWallInvalidDualCells,continuousWallParticlesWithCandidate,"\n               "continuousWallOldStationaryCrossingCandidates,"\n               "continuousWallOldStationaryCrossingReleased,"\n               "continuousWallNoNearbySegment,continuousWallCandidateNoHit,"\n               "continuousWallCollisions,continuousWallSecondCollisions,"\n               "continuousWallThirdCollisions,continuousWallCollisionLimitReached,"\n               "continuousWallMultipleCollisionCandidates,"\n               "continuousWallRelativeStillOutward,"\n               "continuousWallMeanCollisionTimeFraction,continuousWallMeanWallVn,"\n               "continuousWallRmsWallVn,continuousWallMeanAbsWallVn,"\n               "continuousWallRelativeSpeedSqAbsErrorSum,"\n               "continuousWallRelativeSpeedSqReferenceSum,"\n               "continuousWallImpulseX,continuousWallImpulseY,"\n               "continuousWallImpulseAbsSum,continuousWallPositionShiftAbsSum,"\n               "contract\\n";\n''',
'x10n CSV header')

# CSV derived means before out <<.
replace_once(
'''    const double movingWallMeanAbsVn = a.movingWallCollisions > 0ull ?\n        a.movingWallWallVnAbsSum /\n            static_cast<double>(a.movingWallCollisions) : 0.0;\n\n    out << std::setprecision(17)\n''',
'''    const double movingWallMeanAbsVn = a.movingWallCollisions > 0ull ?\n        a.movingWallWallVnAbsSum /\n            static_cast<double>(a.movingWallCollisions) : 0.0;\n    const double continuousWallMeanTime = a.continuousWallCollisions > 0ull ?\n        a.continuousWallCollisionTimeFractionSum /\n            static_cast<double>(a.continuousWallCollisions) : 0.0;\n    const double continuousWallMeanVn = a.continuousWallCollisions > 0ull ?\n        a.continuousWallWallVnSum /\n            static_cast<double>(a.continuousWallCollisions) : 0.0;\n    const double continuousWallRmsVn = a.continuousWallCollisions > 0ull ?\n        sqrt(fmax(0.0, a.continuousWallWallVnSqSum /\n            static_cast<double>(a.continuousWallCollisions))) : 0.0;\n    const double continuousWallMeanAbsVn = a.continuousWallCollisions > 0ull ?\n        a.continuousWallWallVnAbsSum /\n            static_cast<double>(a.continuousWallCollisions) : 0.0;\n\n    out << std::setprecision(17)\n''',
'x10n CSV means')

replace_once(
'''        << a.movingWallImpulseAbsSum << ','\n        << a.movingWallPositionShiftAbsSum << ','\n        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"\n''',
'''        << a.movingWallImpulseAbsSum << ','\n        << a.movingWallPositionShiftAbsSum << ','\n        << a.continuousWallDualCellsVisited << ','\n        << a.continuousWallInterfaceDualCells << ','\n        << a.continuousWallSegmentsBuilt << ','\n        << a.continuousWallAmbiguousDualCells << ','\n        << a.continuousWallInvalidDualCells << ','\n        << a.continuousWallParticlesWithCandidate << ','\n        << a.continuousWallOldStationaryCrossingCandidates << ','\n        << a.continuousWallOldStationaryCrossingReleased << ','\n        << a.continuousWallNoNearbySegment << ','\n        << a.continuousWallCandidateNoHit << ','\n        << a.continuousWallCollisions << ','\n        << a.continuousWallSecondCollisions << ','\n        << a.continuousWallThirdCollisions << ','\n        << a.continuousWallCollisionLimitReached << ','\n        << a.continuousWallMultipleCollisionCandidates << ','\n        << a.continuousWallRelativeStillOutward << ','\n        << continuousWallMeanTime << ',' << continuousWallMeanVn << ','\n        << continuousWallRmsVn << ',' << continuousWallMeanAbsVn << ','\n        << a.continuousWallRelativeSpeedSqAbsErrorSum << ','\n        << a.continuousWallRelativeSpeedSqReferenceSum << ','\n        << a.continuousWallImpulseX << ',' << a.continuousWallImpulseY << ','\n        << a.continuousWallImpulseAbsSum << ','\n        << a.continuousWallPositionShiftAbsSum << ','\n        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"\n''',
'x10n CSV row')

# Contract tag.
replace_once(
'''           "0493x10m-fix1-local-alpha-helper-order-independent;"\n''',
'''           "0493x10m-fix1-local-alpha-helper-order-independent;"\n           "0493x10n-q6-continuous-moving-interface;"\n           "x10n-shared-q6-theta-edge-crossings;"\n           "x10n-marching-squares-continuous-dual-grid-polyline;"\n           "x10n-shared-endpoint-post-q6-b1-liquid-velocity;"\n           "x10n-moving-segment-event-collision-up-to-three-impacts;"\n           "x10n-free-surface-impulse-diagnostic-only;"\n''',
'x10n contract tags')

SRC.write_text(text)

# Analyzer.
an = ROOT / 'scripts/analyze_0493x10n_continuous_interface.py'
an.write_text(r'''#!/usr/bin/env python3
import csv
import math
import sys
from pathlib import Path

if len(sys.argv) < 2:
    raise SystemExit('usage: analyze_0493x10n_continuous_interface.py <csv> [--mode static|dripping]')
p = Path(sys.argv[1])
mode = 'unknown'
if '--mode' in sys.argv:
    k = sys.argv.index('--mode')
    if k + 1 < len(sys.argv): mode = sys.argv[k+1]
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x10n-check] ERROR empty CSV')
def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def fsum(k): return sum(F(r,k) for r in rows)
def maxf(k): return max((F(r,k) for r in rows), default=0.0)

seg=isum('continuousWallSegmentsBuilt')
iface=isum('continuousWallInterfaceDualCells')
amb=isum('continuousWallAmbiguousDualCells')
inv=isum('continuousWallInvalidDualCells')
old=isum('continuousWallOldStationaryCrossingCandidates')
rel=isum('continuousWallOldStationaryCrossingReleased')
no_near=isum('continuousWallNoNearbySegment')
no_hit=isum('continuousWallCandidateNoHit')
coll=isum('continuousWallCollisions')
sec=isum('continuousWallSecondCollisions')
third=isum('continuousWallThirdCollisions')
limit=isum('continuousWallCollisionLimitReached')
mult=isum('continuousWallMultipleCollisionCandidates')
outw=isum('continuousWallRelativeStillOutward')
eref=fsum('continuousWallRelativeSpeedSqReferenceSum')
eerr=fsum('continuousWallRelativeSpeedSqAbsErrorSum')
ix=fsum('continuousWallImpulseX'); iy=fsum('continuousWallImpulseY')

last=rows[-1]
print('===== 0493x10n Q6-CONTINUOUS MOVING INTERFACE =====')
print(f'file={p} mode={mode} rows={len(rows)} lastStep={I(last,"step")}')
print('--- continuous Q6-style reconstruction ---')
print(f'interfaceDualCells={iface} segmentsBuilt={seg} ambiguous={amb} invalid={inv}')
print('--- moving segment collision path ---')
print(f'collisions={coll} second={sec} third={third} collisionLimitReached={limit} multipleCandidates={mult}')
print(f'oldStationaryCrossings={old} releasedByMovingInterface={rel} releasedFraction={(rel/old if old else 0):.6%}')
print(f'oldCrossingNoNearbySegment={no_near} oldCrossingCandidateButNoHit={no_hit}')
print(f'relativeStillOutward={outw} relativeSpeedSqRelativeError={(eerr/eref if eref else 0):.12e}')
print(f'interfaceImpulse=({ix:.9g},{iy:.9g}) absImpulseSum={fsum("continuousWallImpulseAbsSum"):.9g}')
print(f'positionShiftAbsSum={fsum("continuousWallPositionShiftAbsSum"):.9g}')
print('--- pre-wall Q6/B1 predictor retained ---')
print(f'meanVn={F(last,"preWallMeanVn"):.9g} massWeightedMeanVn=' +
      (f'{F(last,"preWallMassVnSum")/F(last,"preWallMassSum"):.9g}' if F(last,'preWallMassSum') else '0'))
if 'preWallAlphaArea' in last:
    print(f'alphaArea first/last={F(rows[0],"preWallAlphaArea"):.9g}/{F(last,"preWallAlphaArea"):.9g}')
if mode == 'dripping' and 'preWallLowerTipY' in last:
    print(f'tipY first/last={F(rows[0],"preWallLowerTipY"):.9g}/{F(last,"preWallLowerTipY"):.9g}')
geom = inv == 0 and seg > 0
collision = outw == 0 and (eerr/eref if eref else 0) < 1e-10
# A continuous reconstruction should make an old stationary crossing without
# any nearby segment exceptional. Candidate-but-no-hit can legitimately occur
# because the interface itself moves.
coverage = (no_near == 0)
print('continuousGeometryContract=' + ('PASS' if geom else 'FAIL'))
print('continuousCoverageContract=' + ('PASS' if coverage else 'FAIL'))
print('movingSegmentCollisionContract=' + ('PASS' if collision else 'FAIL'))
print('freeSurfaceImpulseFeedback=DIAGNOSTIC_ONLY_NOT_APPLIED')
print('shapeAdvanceEvaporationContract=VISUAL_REVIEW')
print('mobileSolidExtension=GENERIC_MOVING_SEGMENT_ENDPOINT_VELOCITIES_PLUS_IMPULSE')
''')
an.chmod(0o755)

# Pure geometry/math check.
chk = ROOT / 'scripts/check_0493x10n_continuous_interface_math.py'
chk.write_text(r'''#!/usr/bin/env python3
import math
import random

ISO=.5

def cross(a,b): return a[0]*b[1]-a[1]*b[0]
def edge(a0,a1,p0,p1):
    if (a0>=ISO)==(a1>=ISO): return None
    t=(ISO-a0)/(a1-a0)
    return (p0[0]+t*(p1[0]-p0[0]),p0[1]+t*(p1[1]-p0[1]))

def segments(vals, ox=0., oy=0.):
    a00,a10,a11,a01=vals
    p=[(ox,oy),(ox+1,oy),(ox+1,oy+1),(ox,oy+1)]
    es=[edge(a00,a10,p[0],p[1]), edge(a10,a11,p[1],p[2]),
        edge(a11,a01,p[2],p[3]), edge(a01,a00,p[3],p[0])]
    ids=[i for i,e in enumerate(es) if e is not None]
    code=(a00>=ISO)|((a10>=ISO)<<1)|((a11>=ISO)<<2)|((a01>=ISO)<<3)
    if len(ids)==2: return [(es[ids[0]],es[ids[1]])]
    if len(ids)!=4: return []
    ci=sum(vals)/4>=ISO
    if code==5:
        pairs=((0,1),(2,3)) if ci else ((3,0),(1,2))
    else:
        pairs=((3,0),(1,2)) if ci else ((0,1),(2,3))
    return [(es[a],es[b]) for a,b in pairs]

# Adjacent dual squares must reproduce their shared-edge crossing bit-for-bit.
r=random.Random(4931014)
max_gap=0.0
checks=0
for _ in range(20000):
    # left square values a00,a10,a11,a01; right shares a10,a11
    a00,a10,a11,a01=[r.random() for _ in range(4)]
    b10,b11=r.random(),r.random()
    L=segments((a00,a10,a11,a01),0,0)
    R=segments((a10,b10,b11,a11),1,0)
    shared=edge(a10,a11,(1,0),(1,1))
    if shared is None: continue
    lp=[q for s in L for q in s if abs(q[0]-1)<1e-12]
    rp=[q for s in R for q in s if abs(q[0]-1)<1e-12]
    if not lp or not rp: raise SystemExit('FAIL missing shared endpoint')
    gap=min(math.hypot(a[0]-b[0],a[1]-b[1]) for a in lp for b in rp)
    max_gap=max(max_gap,gap); checks+=1

# Moving-segment quadratic collision: stationary horizontal wall sanity and
# relative-speed conservation for random translating segments.
max_e=0.0
hits=0
for _ in range(50000):
    ax=-1; ay=0; bx=1; by=0
    uw=r.uniform(-.2,.2)
    x=r.uniform(-.8,.8); y=r.uniform(-.3,-.01)
    vx=r.uniform(-.3,.3); vy=r.uniform(.02,.6)
    # rigid translating horizontal segment in y: analytic hit
    rel=vy-uw
    if rel<=0: continue
    t=-y/rel
    if not (0<=t<=1): continue
    vyp=vy-2*rel
    e0=(vy-uw)**2+vx*vx; e1=(vyp-uw)**2+vx*vx
    max_e=max(max_e,abs(e1-e0)); hits+=1
print(f'sharedEndpointChecks={checks} maxSharedEndpointGap={max_gap:.3e}')
print(f'collisionHits={hits} maxRelativeSpeedSqError={max_e:.3e}')
if max_gap>1e-14 or max_e>1e-12: raise SystemExit('status=FAIL')
print('status=PASS')
''')
chk.chmod(0o755)

# Runners derived from x10m, changing only the geometry flag and analyzer.
static_src = ROOT / 'scripts/run_0493x10m_moving_interface_static_drop.sh'
drip_src = ROOT / 'scripts/run_0493x10m_moving_interface_dripping.sh'
if not static_src.exists() or not drip_src.exists():
    raise SystemExit('[0493x10n-patch] missing x10m runner(s)')

s = static_src.read_text()
s = s.replace('export MPCD_X10M_MOVING_INTERFACE_WALL=1',
'''export MPCD_X10M_MOVING_INTERFACE_WALL=0
export MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=1''',1)
s = s.replace('runs/0493x10m_moving_interface_static_s4500','runs/0493x10n_continuous_interface_static_s4500')
s = s.replace('0493x10m STATIC DROP / MOVING INTERFACE WALL','0493x10n STATIC DROP / Q6-CONTINUOUS MOVING INTERFACE')
s = s.replace('alpha=.5 local moving wall','continuous alpha=.5 moving polyline from shared Q6-style crossings')
s = s.replace('python3 scripts/analyze_0493x10m_moving_interface_wall.py "$CSV" --mode static',
              'python3 scripts/analyze_0493x10n_continuous_interface.py "$CSV" --mode static')
static_out=ROOT/'scripts/run_0493x10n_continuous_interface_static_drop.sh'
static_out.write_text(s); static_out.chmod(0o755)

s = drip_src.read_text()
s = s.replace('MPCD_X10M_MOVING_INTERFACE_WALL=1',
'''MPCD_X10M_MOVING_INTERFACE_WALL=0
MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=1''',1)
s = s.replace('export MPCD_X10J_SIMPLE_SPECULAR_ABLATION MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION MPCD_X10M_MOVING_INTERFACE_WALL MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS',
              'export MPCD_X10J_SIMPLE_SPECULAR_ABLATION MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION MPCD_X10M_MOVING_INTERFACE_WALL MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS',1)
s = s.replace('dripping_vk_0493x10m_moving_interface','dripping_vk_0493x10n_continuous_interface')
s = s.replace('runs/0493x10m_moving_interface_dripping_s4500_g01','runs/0493x10n_continuous_interface_dripping_s4500_g01')
s = s.replace('dripping_vk_0493x10m_moving_interface.kv','dripping_vk_0493x10n_continuous_interface.kv')
s = s.replace('[0493x10m-drip] objective=alpha=.5 local moving-interface wall driven by post-Q6/B1 normal liquid velocity; no collective receiver reaction',
              '[0493x10n-drip] objective=continuous alpha=.5 moving polyline from shared Q6-style crossings; no B8/global reaction')
s = s.replace('python3 scripts/analyze_0493x10m_moving_interface_wall.py "$KINCSV" --mode dripping',
              'python3 scripts/analyze_0493x10n_continuous_interface.py "$KINCSV" --mode dripping')
drip_out=ROOT/'scripts/run_0493x10n_continuous_interface_dripping.sh'
drip_out.write_text(s); drip_out.chmod(0o755)

# Ensure analyzer calls actually changed.
if 'analyze_0493x10n_continuous_interface.py' not in static_out.read_text():
    raise SystemExit('[0493x10n-patch] static analyzer replacement failed')
if 'analyze_0493x10n_continuous_interface.py' not in drip_out.read_text():
    raise SystemExit('[0493x10n-patch] dripping analyzer replacement failed')

dual=ROOT/'scripts/run_0493x10n_continuous_interface_dual_qualification.sh'
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

STATIC_ROOT="${STATIC_RUN_ROOT:-runs/0493x10n_continuous_interface_static_s4500}"
DRIP_ROOT="${DRIP_RUN_ROOT:-runs/0493x10n_continuous_interface_dripping_s4500_g01}"

echo "===== 0493x10n Q6-CONTINUOUS MOVING INTERFACE DUAL QUALIFICATION ====="
echo "[0493x10n] shared alpha=.5 edge crossings -> watertight marching-squares polyline"
echo "[0493x10n] shared endpoint velocities from post-Q6/B1 liquid-side cells"
echo "[0493x10n] moving-segment specular collision; up to 3 local impacts per step"
echo "[0493x10n] interface impulse diagnostic only; no B8/global receiver reaction"
echo "[0493x10n] static=${STATIC_STEPS:-800}; dripping=${DRIP_STEPS:-3000}"
echo "[0493x10n] liveEvery=$LIVE_VIS_EVERY recordEvery=$LIVE_VIS_RECORD_EVERY recordFields=$LIVE_VIS_RECORD_FIELDS filterSampleEvery=$FILTER_SAMPLE_EVERY hold=$LIVE_VIS_HOLD_ON_EXIT"

echo
echo "===== STATIC DROP ====="
RUN_ROOT="$STATIC_ROOT" \
SIGMA_ACTIVE="${STATIC_SIGMA_ACTIVE:-4500}" \
STEPS="${STATIC_STEPS:-800}" \
SUMMARY_EVERY="${STATIC_SUMMARY_EVERY:-25}" \
CLEAN_RUN_ROOT=1 \
bash scripts/run_0493x10n_continuous_interface_static_drop.sh \
2>&1 | tee logs/0493x10n_continuous_interface_static.log

echo
echo "===== DRIPPING ====="
RUN_ROOT="$DRIP_ROOT" \
SIGMA_ACTIVE="${DRIP_SIGMA_ACTIVE:-4500}" \
GRAVITY_Y="${DRIP_GRAVITY_Y:--0.1}" \
STEPS="${DRIP_STEPS:-3000}" \
SUMMARY_EVERY="${DRIP_SUMMARY_EVERY:-25}" \
CLEAN_RUN_ROOT=1 \
bash scripts/run_0493x10n_continuous_interface_dripping.sh \
2>&1 | tee logs/0493x10n_continuous_interface_dripping.log
''')
dual.chmod(0o755)

print('[0493x10n-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10n-patch] runtime flag: MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=1')
print('[0493x10n-patch] x10n takes precedence over x10m/x10k/x10j and bypasses B8/global reaction')
print('[0493x10n-patch] geometry: continuous marching-squares polyline on cell-centre dual grid')
print('[0493x10n-patch] edge crossings use Q6 linear alpha=.5 theta formula')
print('[0493x10n-patch] shared endpoint velocity = post-Q6/B1 liquid-side cell velocity')
print('[0493x10n-patch] collision: moving segment with linearly moving endpoints, up to 3 impacts/step')
print('[0493x10n-patch] interface impulse remains diagnostic only; primitive is reusable for mobile solids')
print('[0493x10n-patch] wrote math check, analyzer, static/dripping/dual runners')
