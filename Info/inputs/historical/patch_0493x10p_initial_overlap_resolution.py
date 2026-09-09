#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(".").resolve()
SRC = ROOT / "src/cuda_q6_resident_0400.cu"

if not SRC.exists():
    raise SystemExit(f"[0493x10p-patch] missing {SRC}")

text = SRC.read_text()

for tag in (
    "0493x10n-q6-continuous-moving-interface",
    "0493x10o-q6-hydrodynamic-thermal-interface",
):
    if tag not in text:
        raise SystemExit(f"[0493x10p-patch] prerequisite not found: {tag}")

if "0493x10p-initial-overlap-resolution" in text:
    raise SystemExit("[0493x10p-patch] x10p already appears applied")

def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(
            f"[0493x10p-patch] {label}: expected 1 anchor, found {n}"
        )
    text = text.replace(old, new, 1)

replace_once(
'''    double q6ThermalHydroAbsVnSum = 0.0;
    double q6ThermalThicknessSum = 0.0;
};
''',
'''    double q6ThermalHydroAbsVnSum = 0.0;
    double q6ThermalThicknessSum = 0.0;

    // 0493x10p: resolve a particle which starts a step already on the
    // vacuum side of the kinetic (thermally shifted) moving interface.
    unsigned long long x10pInitialOutside = 0ull;
    unsigned long long x10pInitialOverlapResolved = 0ull;
    unsigned long long x10pInitialOverlapOutwardReflected = 0ull;
    unsigned long long x10pInitialOverlapInwardReleased = 0ull;
    unsigned long long x10pInitialOutsideTooDeep = 0ull;
    double x10pInitialOverlapPenetrationSum = 0.0;
    double x10pInitialOverlapMaxPenetration = 0.0;
};
''',
"audit overlap fields",
)

replace_once(
'''struct MovingSegmentCollision0493x10n {
    bool hit = false;
    double tau = 0.0;
    double lambda = 0.0;
    double newVx = 0.0, newVy = 0.0;
    double wallVx = 0.0, wallVy = 0.0;
    double nx = 0.0, ny = 0.0;
    double relnBefore = 0.0;
    double impulseWallX = 0.0, impulseWallY = 0.0;
};
''',
'''struct MovingSegmentCollision0493x10n {
    bool hit = false;
    double tau = 0.0;
    double lambda = 0.0;
    double newVx = 0.0, newVy = 0.0;
    double wallVx = 0.0, wallVy = 0.0;
    double nx = 0.0, ny = 0.0;
    double relnBefore = 0.0;
    double impulseWallX = 0.0, impulseWallY = 0.0;

    // x10p generic initial-overlap response. Ordinary swept collisions leave
    // these members at their zero/default values.
    bool initialOverlap = false;
    bool overlapOutwardReflected = false;
    double penetration = 0.0;
    double positionCorrectionX = 0.0;
    double positionCorrectionY = 0.0;
};
''',
"collision result overlap members",
)

anchor = '''__device__ __forceinline__ bool q6_x10n_collide_moving_segment(
'''
if text.count(anchor) != 1:
    raise SystemExit(
        f"[0493x10p-patch] collision helper anchor count={text.count(anchor)}"
    )

helpers = r'''// =============================================================================
// 0493x10p — INITIAL OVERLAP / PENETRATION RESOLUTION
// =============================================================================
// A reconstructed moving boundary can move between two alpha reconstructions.
// A particle may therefore start the next step slightly beyond the kinetic
// wall even though the previous swept collision was valid.
//
// x10p adds the second standard branch of a moving-boundary engine:
//   (1) swept collision during dt;
//   (2) initial-overlap resolution at t=0.
//
// The nearest finite segment is selected before using the sign of the distance.
// This avoids classifying against a non-nearest tangent of a curved interface.

__device__ __forceinline__ void q6_x10p_atomic_max_positive_double(
    double* address, double value) {
    if (!address || !(value > 0.0) || !isfinite(value)) return;
    auto* u = reinterpret_cast<unsigned long long*>(address);
    unsigned long long old = *u;
    while (true) {
        const double oldValue = __longlong_as_double(
            static_cast<long long>(old));
        if (oldValue >= value) return;
        const unsigned long long desired =
            static_cast<unsigned long long>(__double_as_longlong(value));
        const unsigned long long observed = atomicCAS(u, old, desired);
        if (observed == old) return;
        old = observed;
    }
}

struct InitialOverlapNearest0493x10p {
    bool valid = false;
    double distance = 0.0;
    double signedDistance = 0.0;
    double lambda = 0.0;
    double qx = 0.0, qy = 0.0;
    double wallVx = 0.0, wallVy = 0.0;
    double nx = 0.0, ny = 0.0;
    MovingSegment0493x10n seg{};
};

__device__ __forceinline__ bool q6_x10p_closest_current_segment(
    double px, double py,
    double tStart,
    double lx, double ly,
    int periodicX, int periodicY,
    const MovingSegment0493x10n& seg,
    InitialOverlapNearest0493x10p* out) {
    if (!out) return false;

    const double ax = seg.ax + seg.uax * tStart;
    const double ay = seg.ay + seg.uay * tStart;
    const double bx = seg.bx + seg.ubx * tStart;
    const double by = seg.by + seg.uby * tStart;

    const double arx = q6_x10m_minimum_image(ax - px, lx, periodicX);
    const double ary = q6_x10m_minimum_image(ay - py, ly, periodicY);
    const double dax = q6_x10m_minimum_image(bx - ax, lx, periodicX);
    const double day = q6_x10m_minimum_image(by - ay, ly, periodicY);
    const double L2 = dax * dax + day * day;
    if (!(L2 > 1.0e-24) || !isfinite(L2)) return false;

    const double pax = -arx;
    const double pay = -ary;
    double lambda = (pax * dax + pay * day) / L2;
    if (!isfinite(lambda)) return false;
    lambda = fmin(1.0, fmax(0.0, lambda));

    const double qrelx = arx + lambda * dax;
    const double qrely = ary + lambda * day;
    const double dxp = -qrelx;
    const double dyp = -qrely;
    const double distance = sqrt(dxp * dxp + dyp * dyp);

    const double invL = 1.0 / sqrt(L2);
    const double nx = day * invL;
    const double ny = -dax * invL;
    const double signedDistance = dxp * nx + dyp * ny;

    out->valid = isfinite(distance) && isfinite(signedDistance);
    out->distance = distance;
    out->signedDistance = signedDistance;
    out->lambda = lambda;
    out->qx = px + qrelx;
    out->qy = py + qrely;
    out->wallVx = seg.uax + lambda * (seg.ubx - seg.uax);
    out->wallVy = seg.uay + lambda * (seg.uby - seg.uay);
    out->nx = nx;
    out->ny = ny;
    out->seg = seg;
    return out->valid &&
           isfinite(out->wallVx) && isfinite(out->wallVy);
}

__device__ __forceinline__ bool q6_x10p_resolve_initial_overlap(
    double px, double py,
    double vx, double vy,
    double mass,
    double sideTol,
    const InitialOverlapNearest0493x10p& nearest,
    MovingSegmentCollision0493x10n* out) {
    if (!out || !nearest.valid || !(nearest.signedDistance > sideTol))
        return false;

    const double reln =
        (vx - nearest.wallVx) * nearest.nx +
        (vy - nearest.wallVy) * nearest.ny;
    if (!isfinite(reln)) return false;

    const double pushTol = 4.0 * sideTol;

    out->hit = true;
    out->initialOverlap = true;
    out->tau = 0.0;
    out->lambda = nearest.lambda;
    out->wallVx = nearest.wallVx;
    out->wallVy = nearest.wallVy;
    out->nx = nearest.nx;
    out->ny = nearest.ny;
    out->relnBefore = reln;
    out->penetration = nearest.signedDistance;

    out->positionCorrectionX =
        (nearest.qx - px) - pushTol * nearest.nx;
    out->positionCorrectionY =
        (nearest.qy - py) - pushTol * nearest.ny;

    if (reln > 1.0e-13) {
        out->overlapOutwardReflected = true;
        out->newVx = vx - 2.0 * reln * nearest.nx;
        out->newVy = vy - 2.0 * reln * nearest.ny;
        const double impulse = 2.0 * mass * reln;
        out->impulseWallX = impulse * nearest.nx;
        out->impulseWallY = impulse * nearest.ny;
    } else {
        out->overlapOutwardReflected = false;
        out->newVx = vx;
        out->newVy = vy;
        out->impulseWallX = 0.0;
        out->impulseWallY = 0.0;
    }

    return isfinite(out->newVx) && isfinite(out->newVy) &&
           isfinite(out->positionCorrectionX) &&
           isfinite(out->positionCorrectionY);
}

'''
text = text.replace(anchor, helpers + anchor, 1)

replace_once(
'''    if (s0 > sideTol || s0 < -2.5 * h) return false;
''',
'''    // x10p pre-resolves the nearest finite-segment initial overlap.
    if (s0 > sideTol || s0 < -2.5 * h) return false;
''',
"swept s0 guard comment",
)

replace_once(
'''    double lx, double ly, double dt,
    int periodicX, int periodicY,
    KineticCrossingAccumulator0493x9x* audit) {
''',
'''    double lx, double ly, double dt,
    int periodicX, int periodicY,
    int resolveInitialOverlap0493x10p,
    KineticCrossingAccumulator0493x9x* audit) {
''',
"apply kernel overlap flag",
)

replace_once(
'''            MovingSegmentCollision0493x10n best{};
            MovingSegment0493x10n bestSeg{};
            double bestTau = remaining + 1.0;
            int validHits = 0;
            int candidates = 0;
''',
'''            MovingSegmentCollision0493x10n best{};
            MovingSegment0493x10n bestSeg{};
            double bestTau = remaining + 1.0;
            int validHits = 0;
            int candidates = 0;

            InitialOverlapNearest0493x10p nearest{};
            double nearestDistance0493x10p = 1.0e300;
''',
"event nearest-overlap state",
)

replace_once(
'''                        seg.ubx = segUbx[s]; seg.uby = segUby[s];
                        seg.ownerCell = owner;
                        MovingSegmentCollision0493x10n hit{};
                        if (!q6_x10n_collide_moving_segment(
''',
'''                        seg.ubx = segUbx[s]; seg.uby = segUby[s];
                        seg.ownerCell = owner;

                        if (resolveInitialOverlap0493x10p && event == 0) {
                            InitialOverlapNearest0493x10p q{};
                            if (q6_x10p_closest_current_segment(
                                    cx, cy, elapsed, lx, ly,
                                    periodicX, periodicY, seg, &q) &&
                                q.distance < nearestDistance0493x10p) {
                                nearestDistance0493x10p = q.distance;
                                nearest = q;
                            }
                        }

                        MovingSegmentCollision0493x10n hit{};
                        if (!q6_x10n_collide_moving_segment(
''',
"nearest segment collection",
)

anchor_after_search = '''            if (event == 0) firstSearchCandidates = candidates;
            if (candidates > 0) sawAnySegment = true;
            if (!best.hit) {
'''
if text.count(anchor_after_search) != 1:
    raise SystemExit(
        f"[0493x10p-patch] post-search anchor count={text.count(anchor_after_search)}"
    )

replacement_after_search = r'''            if (resolveInitialOverlap0493x10p && event == 0 && nearest.valid) {
                const double h0493x10p = fmin(dx, dy);
                const double sideTol0493x10p =
                    1.0e-8 * fmax(1.0, h0493x10p);
                if (nearest.signedDistance > sideTol0493x10p) {
                    if (audit)
                        atomicAdd(&audit->x10pInitialOutside, 1ull);

                    if (nearest.distance <= 2.5 * h0493x10p) {
                        MovingSegmentCollision0493x10n overlap{};
                        if (q6_x10p_resolve_initial_overlap(
                                cx, cy, cvx, cvy, mass,
                                sideTol0493x10p, nearest, &overlap)) {
                            best = overlap;
                            bestSeg = nearest.seg;
                            bestTau = 0.0;
                            if (audit) {
                                atomicAdd(
                                    &audit->x10pInitialOverlapResolved, 1ull);
                                if (overlap.overlapOutwardReflected)
                                    atomicAdd(
                                        &audit->x10pInitialOverlapOutwardReflected,
                                        1ull);
                                else
                                    atomicAdd(
                                        &audit->x10pInitialOverlapInwardReleased,
                                        1ull);
                                atomic_add_double_0400(
                                    &audit->x10pInitialOverlapPenetrationSum,
                                    overlap.penetration);
                                q6_x10p_atomic_max_positive_double(
                                    &audit->x10pInitialOverlapMaxPenetration,
                                    overlap.penetration);
                            }
                        }
                    } else if (audit) {
                        atomicAdd(&audit->x10pInitialOutsideTooDeep, 1ull);
                    }
                }
            }

            if (event == 0) firstSearchCandidates = candidates;
            if (candidates > 0) sawAnySegment = true;
            if (!best.hit) {
'''
text = text.replace(anchor_after_search, replacement_after_search, 1)

replace_once(
'''            cx += cvx * best.tau;
            cy += cvy * best.tau;
            elapsed += best.tau;
''',
'''            cx += cvx * best.tau + best.positionCorrectionX;
            cy += cvy * best.tau + best.positionCorrectionY;
            elapsed += best.tau;
''',
"apply depenetration correction",
)

replace_once(
'''                const double beforeRelX =
                    (best.newVx + 2.0 * best.relnBefore * best.nx) - best.wallVx;
                const double beforeRelY =
                    (best.newVy + 2.0 * best.relnBefore * best.ny) - best.wallVy;
                const double afterRelX = best.newVx - best.wallVx;
                const double afterRelY = best.newVy - best.wallVy;
''',
'''                double beforeRelX = 0.0;
                double beforeRelY = 0.0;
                if (best.initialOverlap && !best.overlapOutwardReflected) {
                    beforeRelX = best.newVx - best.wallVx;
                    beforeRelY = best.newVy - best.wallVy;
                } else {
                    beforeRelX =
                        (best.newVx + 2.0 * best.relnBefore * best.nx) -
                        best.wallVx;
                    beforeRelY =
                        (best.newVy + 2.0 * best.relnBefore * best.ny) -
                        best.wallVy;
                }
                const double afterRelX = best.newVx - best.wallVx;
                const double afterRelY = best.newVy - best.wallVy;
''',
"relative energy audit for inward depenetration",
)

replace_once(
'''    const bool q6ThermalInterfaceWall0493x10o =
        r >= 1.0 &&
        env_int_0400("MPCD_X10O_Q6_THERMAL_INTERFACE_WALL", 0) != 0;
    const bool continuousInterfaceWall0493x10n =
''',
'''    const bool q6ThermalInterfaceWall0493x10o =
        r >= 1.0 &&
        env_int_0400("MPCD_X10O_Q6_THERMAL_INTERFACE_WALL", 0) != 0;
    const bool initialOverlapResolution0493x10p =
        q6ThermalInterfaceWall0493x10o &&
        env_int_0400("MPCD_X10P_INITIAL_OVERLAP_RESOLUTION", 1) != 0;
    const bool continuousInterfaceWall0493x10n =
''',
"host overlap enable",
)

replace_once(
'''            phaseAType,
            grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt,
            periodicX, periodicY, auditDev);
''',
'''            phaseAType,
            grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt,
            periodicX, periodicY,
            initialOverlapResolution0493x10p ? 1 : 0,
            auditDev);
''',
"apply launch overlap flag",
)

replace_once(
'''               "q6ThermalRmsHydroVn,q6ThermalMeanAbsHydroVn,"
               "q6ThermalMeanThickness,"
               "contract\\n";
''',
'''               "q6ThermalRmsHydroVn,q6ThermalMeanAbsHydroVn,"
               "q6ThermalMeanThickness,"
               "x10pInitialOutside,x10pInitialOverlapResolved,"
               "x10pInitialOverlapOutwardReflected,"
               "x10pInitialOverlapInwardReleased,"
               "x10pInitialOutsideTooDeep,"
               "x10pInitialOverlapPenetrationSum,"
               "x10pInitialOverlapMaxPenetration,"
               "contract\\n";
''',
"CSV overlap header",
)

replace_once(
'''        << q6ThermalMeanAbsHydroVn << ',' << q6ThermalMeanThickness << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'''        << q6ThermalMeanAbsHydroVn << ',' << q6ThermalMeanThickness << ','
        << a.x10pInitialOutside << ','
        << a.x10pInitialOverlapResolved << ','
        << a.x10pInitialOverlapOutwardReflected << ','
        << a.x10pInitialOverlapInwardReleased << ','
        << a.x10pInitialOutsideTooDeep << ','
        << a.x10pInitialOverlapPenetrationSum << ','
        << a.x10pInitialOverlapMaxPenetration << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
"CSV overlap row",
)

replace_once(
'''           "0493x10o-q6-hydrodynamic-thermal-interface;"
           "x10o-q6-projected-face-plus-cell-hydrodynamic-velocity;"
''',
'''           "0493x10o-q6-hydrodynamic-thermal-interface;"
           "0493x10p-initial-overlap-resolution;"
           "x10p-nearest-finite-moving-segment-before-s0-sign;"
           "x10p-outward-overlap-specular-inward-overlap-depenetrate-only;"
           "x10p-no-extra-particle-pass;"
           "x10o-q6-projected-face-plus-cell-hydrodynamic-velocity;"
''',
"contract x10p tags",
)

SRC.write_text(text)

AN = ROOT / "scripts/analyze_0493x10o_q6_thermal_interface.py"
if not AN.exists():
    raise SystemExit(f"[0493x10p-patch] missing analyzer {AN}")
an = AN.read_text()
if "initialOverlapResolutionContract=" not in an:
    anchor = '''print(f'meanThermalThickness={thick:.9g}')
'''
    if an.count(anchor) != 1:
        raise SystemExit(
            f"[0493x10p-patch] analyzer print anchor count={an.count(anchor)}"
        )
    an = an.replace(anchor, anchor + r'''initial_out=isum('x10pInitialOutside')
initial_resolved=isum('x10pInitialOverlapResolved')
initial_reflected=isum('x10pInitialOverlapOutwardReflected')
initial_inward=isum('x10pInitialOverlapInwardReleased')
initial_too_deep=isum('x10pInitialOutsideTooDeep')
penetration_sum=fsum('x10pInitialOverlapPenetrationSum')
penetration_max=maxf('x10pInitialOverlapMaxPenetration')
print('--- x10p initial-overlap resolution ---')
print(f'initialOutside={initial_out} resolved={initial_resolved} '
      f'outwardReflected={initial_reflected} inwardReleased={initial_inward} '
      f'tooDeep={initial_too_deep}')
print(f'meanPenetration={(penetration_sum/initial_resolved if initial_resolved else 0):.9g} '
      f'maxPenetration={penetration_max:.9g}')
''', 1)

    anchor2 = '''print('thermalMovingWallCollisionContract=' + ('PASS' if coll_ok else 'FAIL'))
'''
    if an.count(anchor2) != 1:
        raise SystemExit(
            f"[0493x10p-patch] analyzer contract anchor count={an.count(anchor2)}"
        )
    an = an.replace(anchor2, anchor2 + r'''overlap_ok = (
    initial_resolved == initial_reflected + initial_inward and
    initial_too_deep == 0
)
print('initialOverlapResolutionContract=' + ('PASS' if overlap_ok else 'FAIL'))
''', 1)
    AN.write_text(an)

RUN = ROOT / "scripts/run_0493x10p_initial_overlap_static_5step.sh"
RUN.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
export LIVE_VIS_HOLD_ON_EXIT=0
export LIVE_VIS_RECORD_ENABLE=0

RUN_ROOT="${RUN_ROOT:-runs/0493x10p_initial_overlap_static_5step}" \
STEPS="${STEPS:-5}" \
SUMMARY_EVERY="${SUMMARY_EVERY:-1}" \
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1}" \
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}" \
bash scripts/run_0493x10o_q6_thermal_interface_static_drop.sh
''')
RUN.chmod(0o755)

print("[0493x10p-patch] patched src/cuda_q6_resident_0400.cu")
print("[0493x10p-patch] active on x10o with MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1 (default)")
print("[0493x10p-patch] nearest finite moving segment chosen before deciding s0>0")
print("[0493x10p-patch] outward overlap: depenetrate + moving-frame specular reflection")
print("[0493x10p-patch] inward overlap: depenetrate only, velocity unchanged")
print("[0493x10p-patch] no B8/receiver/seal and no extra particle pass")
print("[0493x10p-patch] updated x10o analyzer and wrote 5-step dump runner")
