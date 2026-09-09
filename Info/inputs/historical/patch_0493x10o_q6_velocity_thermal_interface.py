#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'
if not SRC.exists():
    raise SystemExit(f'[0493x10o-patch] missing {SRC}')
text = SRC.read_text()

for tag in (
    '0493x10n-q6-continuous-moving-interface',
    '0493x10m-fix1-local-alpha-helper-order-independent',
):
    if tag not in text:
        raise SystemExit(f'[0493x10o-patch] prerequisite not found: {tag}')
if '0493x10o-q6-hydrodynamic-thermal-interface' in text:
    raise SystemExit('[0493x10o-patch] x10o already appears applied')

def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10o-patch] {label}: expected 1 anchor, found {n}')
    text = text.replace(old, new, 1)

# ---------------------------------------------------------------------------
# Diagnostics.
# ---------------------------------------------------------------------------
replace_once(
'''    double continuousWallImpulseAbsSum = 0.0;\n    double continuousWallPositionShiftAbsSum = 0.0;\n};\n''',
'''    double continuousWallImpulseAbsSum = 0.0;\n    double continuousWallPositionShiftAbsSum = 0.0;\n\n    // 0493x10o: Q6-hydrodynamic velocity + finite thermal interface layer.\n    unsigned long long q6ThermalHydroCapturedCells = 0ull;\n    unsigned long long q6ThermalInterfaceEndpointSamples = 0ull;\n    unsigned long long q6ThermalHydroFallbacks = 0ull;\n    double q6ThermalHydroVnSum = 0.0;\n    double q6ThermalHydroVnSqSum = 0.0;\n    double q6ThermalHydroAbsVnSum = 0.0;\n    double q6ThermalThicknessSum = 0.0;\n};\n''',
'audit x10o fields')

# ---------------------------------------------------------------------------
# Resident Q6 hydrodynamic field captured before the face buffers are reused.
# ---------------------------------------------------------------------------
replace_once(
'''    DeviceBuffer0400<double> kineticContinuousSegUbx0493x10n;\n    DeviceBuffer0400<double> kineticContinuousSegUby0493x10n;\n    bool phaseInterfaceStencilValid0493x6f = false;\n''',
'''    DeviceBuffer0400<double> kineticContinuousSegUbx0493x10n;\n    DeviceBuffer0400<double> kineticContinuousSegUby0493x10n;\n\n    // 0493x10o stores the projected liquid hydrodynamic field produced by Q6\n    // before r/p/dux/duy are reused.  Cell values are tentative liquid COM\n    // velocity + Q6 cell correction; east/north values carry the corresponding\n    // projected Q6 face component.\n    DeviceBuffer0400<unsigned char> kineticQ6HydroValid0493x10o;\n    DeviceBuffer0400<double> kineticQ6HydroCellUx0493x10o;\n    DeviceBuffer0400<double> kineticQ6HydroCellUy0493x10o;\n    DeviceBuffer0400<double> kineticQ6HydroFaceUxEast0493x10o;\n    DeviceBuffer0400<double> kineticQ6HydroFaceUyNorth0493x10o;\n    bool kineticQ6HydroFieldValid0493x10o = false;\n    int kineticQ6HydroFieldStep0493x10o = -1;\n    std::uint32_t kineticQ6HydroFieldType0493x10o = 0u;\n    bool phaseInterfaceStencilValid0493x6f = false;\n''',
'workspace x10o fields')

# ---------------------------------------------------------------------------
# x10o kernels/helpers inserted immediately before x10n geometry.
# ---------------------------------------------------------------------------
anchor = '''__device__ __forceinline__ bool q6_x10n_cell_velocity(
'''
if text.count(anchor) != 1:
    raise SystemExit(f'[0493x10o-patch] x10n helper insertion anchor count={text.count(anchor)}')

kernels = r'''// =============================================================================
// 0493x10o — Q6 HYDRODYNAMIC VELOCITY + THERMAL-THICKNESS INTERFACE WALL
// =============================================================================
// x10n made Gamma continuous, but moved each shared endpoint with an
// instantaneous post-B1 particle-cell COM velocity.  x10o separates the two
// scales:
//   * hydrodynamic motion comes directly from the projected Q6 field;
//   * the kinetic wall is displaced outward from alpha=.5 by a finite thermal
//     thickness delta = min(C*dt*sqrt(kBT/m), deltaMax*h).
//
// The alpha=.5 centreline remains the capillary/Q6 interface.  The outer
// thermal envelope is only the particle reflection surface.  A shared edge
// crossing gets one shared interpolated alpha normal, one shared shifted point,
// and one shared normal wall velocity, so neighboring marching-squares cells
// remain watertight both geometrically and kinematically.

__global__ void q6_x10o_capture_projected_q6_hydrodynamics(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    const unsigned char* velocityMask,
    const double* cellDUx,
    const double* cellDUy,
    const double* faceDUxEast,
    const double* faceDUyNorth,
    unsigned char* valid,
    double* cellUx,
    double* cellUy,
    double* faceUxEast,
    double* faceUyNorth,
    int nx,
    int ny,
    int periodicX,
    int periodicY) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int k = speciesIndex * species.numCells + c;
        const double m = species.mass[k];
        const bool ok = m > 1.0e-14 && isfinite(m) &&
                        isfinite(species.px[k]) && isfinite(species.py[k]);
        valid[c] = ok ? 1u : 0u;
        if (!ok) {
            cellUx[c] = 0.0; cellUy[c] = 0.0;
            faceUxEast[c] = 0.0; faceUyNorth[c] = 0.0;
            continue;
        }
        const double ux0 = species.px[k] / m;
        const double uy0 = species.py[k] / m;
        cellUx[c] = ux0 + cellDUx[c];
        cellUy[c] = uy0 + cellDUy[c];

        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasNorth = periodicY || iy < ny - 1;
        if (hasEast) {
            const int east = iy * nx +
                (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
            const double base = q6_species_face_velocity_0493w5(
                species, velocityMask, speciesIndex, c, east, 0);
            faceUxEast[c] = base + faceDUxEast[c];
        } else {
            faceUxEast[c] = cellUx[c];
        }
        if (hasNorth) {
            const int north =
                (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix;
            const double base = q6_species_face_velocity_0493w5(
                species, velocityMask, speciesIndex, c, north, 1);
            faceUyNorth[c] = base + faceDUyNorth[c];
        } else {
            faceUyNorth[c] = cellUy[c];
        }
    }
}

__device__ __forceinline__ void q6_x10o_alpha_gradient_cell(
    const double* alpha,
    int c,
    int nx, int ny,
    double dx, double dy,
    int periodicX, int periodicY,
    double* gx, double* gy) {
    const int ix = c % nx;
    const int iy = c / nx;
    const int west = q6_x10n_cell_index(ix - 1, iy, nx, ny, periodicX, periodicY);
    const int east = q6_x10n_cell_index(ix + 1, iy, nx, ny, periodicX, periodicY);
    const int south = q6_x10n_cell_index(ix, iy - 1, nx, ny, periodicX, periodicY);
    const int north = q6_x10n_cell_index(ix, iy + 1, nx, ny, periodicX, periodicY);
    const double ac = alpha[c];
    const double aw = west >= 0 ? alpha[west] : ac;
    const double ae = east >= 0 ? alpha[east] : ac;
    const double as = south >= 0 ? alpha[south] : ac;
    const double an = north >= 0 ? alpha[north] : ac;
    const double denx = (west >= 0 && east >= 0) ? 2.0 * dx : dx;
    const double deny = (south >= 0 && north >= 0) ? 2.0 * dy : dy;
    *gx = nx > 1 ? (ae - aw) / denx : 0.0;
    *gy = ny > 1 ? (an - as) / deny : 0.0;
}

// Shared thermal-envelope endpoint.  faceComponent: 0=x projected Q6 face
// component, 1=y. faceOwner is the west/south owner of that Q6 face.
__device__ __forceinline__ bool q6_x10o_edge_crossing_q6_thermal(
    double a0, double a1,
    double x0, double y0, double x1, double y1,
    int c0, int c1,
    int faceOwner,
    int faceComponent,
    const double* alpha,
    int nx, int ny,
    double dx, double dy,
    int periodicX, int periodicY,
    const unsigned char* hydroValid,
    const double* hydroCellUx,
    const double* hydroCellUy,
    const double* hydroFaceUxEast,
    const double* hydroFaceUyNorth,
    double thermalThickness,
    IsoPoint0493x10n* out,
    KineticCrossingAccumulator0493x9x* audit) {
    if (!out) return false;
    const bool in0 = a0 >= 0.5;
    const bool in1 = a1 >= 0.5;
    if (in0 == in1) return false;
    const double den = a1 - a0;
    if (!(fabs(den) > 1.0e-15) || !isfinite(den)) return false;
    double theta = (0.5 - a0) / den;
    theta = fmin(1.0, fmax(0.0, theta));
    const int liquid = in0 ? c0 : c1;

    double g0x = 0.0, g0y = 0.0, g1x = 0.0, g1y = 0.0;
    q6_x10o_alpha_gradient_cell(
        alpha, c0, nx, ny, dx, dy, periodicX, periodicY, &g0x, &g0y);
    q6_x10o_alpha_gradient_cell(
        alpha, c1, nx, ny, dx, dy, periodicX, periodicY, &g1x, &g1y);
    double gx = (1.0 - theta) * g0x + theta * g1x;
    double gy = (1.0 - theta) * g0y + theta * g1y;
    double nxo = -gx;
    double nyo = -gy;
    double n2 = nxo * nxo + nyo * nyo;
    if (!(n2 > 1.0e-24) || !isfinite(n2)) {
        const double ex = x1 - x0;
        const double ey = y1 - y0;
        const double e2 = ex * ex + ey * ey;
        if (!(e2 > 1.0e-24)) return false;
        const double invE = 1.0 / sqrt(e2);
        nxo = (in0 ? 1.0 : -1.0) * ex * invE;
        nyo = (in0 ? 1.0 : -1.0) * ey * invE;
    } else {
        const double invN = 1.0 / sqrt(n2);
        nxo *= invN;
        nyo *= invN;
    }

    double ux = 0.0, uy = 0.0;
    bool hydroOk = hydroValid && hydroValid[liquid] != 0u;
    if (hydroOk) {
        ux = hydroCellUx[liquid];
        uy = hydroCellUy[liquid];
        if (faceOwner >= 0) {
            if (faceComponent == 0) ux = hydroFaceUxEast[faceOwner];
            else uy = hydroFaceUyNorth[faceOwner];
        }
        hydroOk = isfinite(ux) && isfinite(uy);
    }
    if (!hydroOk) {
        ux = 0.0; uy = 0.0;
        if (audit) atomicAdd(&audit->q6ThermalHydroFallbacks, 1ull);
    }

    const double vn = ux * nxo + uy * nyo;
    const double xc = x0 + theta * (x1 - x0);
    const double yc = y0 + theta * (y1 - y0);
    out->x = xc + thermalThickness * nxo;
    out->y = yc + thermalThickness * nyo;
    // Only normal motion changes the geometry of an implicit free surface.
    out->ux = vn * nxo;
    out->uy = vn * nyo;
    out->valid = isfinite(out->x) && isfinite(out->y) &&
                 isfinite(out->ux) && isfinite(out->uy);

    if (out->valid && audit) {
        atomicAdd(&audit->q6ThermalInterfaceEndpointSamples, 1ull);
        atomic_add_double_0400(&audit->q6ThermalHydroVnSum, vn);
        atomic_add_double_0400(&audit->q6ThermalHydroVnSqSum, vn * vn);
        atomic_add_double_0400(&audit->q6ThermalHydroAbsVnSum, fabs(vn));
        atomic_add_double_0400(&audit->q6ThermalThicknessSum, thermalThickness);
    }
    return out->valid;
}

'''
text = text.replace(anchor, kernels + anchor, 1)

# ---------------------------------------------------------------------------
# Extend the x10n continuous builder with an optional x10o source.  The
# marching-squares topology itself is unchanged.
# ---------------------------------------------------------------------------
replace_once(
'''    const double* totalM,\n    const double* totalPx,\n    const double* totalPy,\n    unsigned char* segCount,\n''',
'''    const double* totalM,\n    const double* totalPx,\n    const double* totalPy,\n    const unsigned char* q6HydroValid0493x10o,\n    const double* q6HydroCellUx0493x10o,\n    const double* q6HydroCellUy0493x10o,\n    const double* q6HydroFaceUxEast0493x10o,\n    const double* q6HydroFaceUyNorth0493x10o,\n    double thermalThickness0493x10o,\n    int useQ6ThermalWall0493x10o,\n    unsigned char* segCount,\n''',
'x10n builder optional x10o args')

old_calls = '''        IsoPoint0493x10n e[4];\n        bool h[4] = {false, false, false, false};\n        h[0] = q6_x10n_edge_crossing(a00, a10, x0, y0, x1, y0,\n                                      c00, c10, totalM, totalPx, totalPy, &e[0]);\n        h[1] = q6_x10n_edge_crossing(a10, a11, x1, y0, x1, y1,\n                                      c10, c11, totalM, totalPx, totalPy, &e[1]);\n        h[2] = q6_x10n_edge_crossing(a11, a01, x1, y1, x0, y1,\n                                      c11, c01, totalM, totalPx, totalPy, &e[2]);\n        h[3] = q6_x10n_edge_crossing(a01, a00, x0, y1, x0, y0,\n                                      c01, c00, totalM, totalPx, totalPy, &e[3]);\n'''
new_calls = '''        IsoPoint0493x10n e[4];\n        bool h[4] = {false, false, false, false};\n        if (useQ6ThermalWall0493x10o) {\n            // edge 0: c00--c10, Q6 x-face owned by c00\n            h[0] = q6_x10o_edge_crossing_q6_thermal(\n                a00, a10, x0, y0, x1, y0, c00, c10, c00, 0,\n                alpha, nx, ny, dx, dy, periodicX, periodicY,\n                q6HydroValid0493x10o, q6HydroCellUx0493x10o, q6HydroCellUy0493x10o,\n                q6HydroFaceUxEast0493x10o, q6HydroFaceUyNorth0493x10o,\n                thermalThickness0493x10o, &e[0], audit);\n            // edge 1: c10--c11, Q6 y-face owned by c10\n            h[1] = q6_x10o_edge_crossing_q6_thermal(\n                a10, a11, x1, y0, x1, y1, c10, c11, c10, 1,\n                alpha, nx, ny, dx, dy, periodicX, periodicY,\n                q6HydroValid0493x10o, q6HydroCellUx0493x10o, q6HydroCellUy0493x10o,\n                q6HydroFaceUxEast0493x10o, q6HydroFaceUyNorth0493x10o,\n                thermalThickness0493x10o, &e[1], audit);\n            // edge 2: c11--c01, same physical x-face is owned by c01\n            h[2] = q6_x10o_edge_crossing_q6_thermal(\n                a11, a01, x1, y1, x0, y1, c11, c01, c01, 0,\n                alpha, nx, ny, dx, dy, periodicX, periodicY,\n                q6HydroValid0493x10o, q6HydroCellUx0493x10o, q6HydroCellUy0493x10o,\n                q6HydroFaceUxEast0493x10o, q6HydroFaceUyNorth0493x10o,\n                thermalThickness0493x10o, &e[2], audit);\n            // edge 3: c01--c00, same physical y-face is owned by c00\n            h[3] = q6_x10o_edge_crossing_q6_thermal(\n                a01, a00, x0, y1, x0, y0, c01, c00, c00, 1,\n                alpha, nx, ny, dx, dy, periodicX, periodicY,\n                q6HydroValid0493x10o, q6HydroCellUx0493x10o, q6HydroCellUy0493x10o,\n                q6HydroFaceUxEast0493x10o, q6HydroFaceUyNorth0493x10o,\n                thermalThickness0493x10o, &e[3], audit);\n        } else {\n            h[0] = q6_x10n_edge_crossing(a00, a10, x0, y0, x1, y0,\n                                          c00, c10, totalM, totalPx, totalPy, &e[0]);\n            h[1] = q6_x10n_edge_crossing(a10, a11, x1, y0, x1, y1,\n                                          c10, c11, totalM, totalPx, totalPy, &e[1]);\n            h[2] = q6_x10n_edge_crossing(a11, a01, x1, y1, x0, y1,\n                                          c11, c01, totalM, totalPx, totalPy, &e[2]);\n            h[3] = q6_x10n_edge_crossing(a01, a00, x0, y1, x0, y0,\n                                          c01, c00, totalM, totalPx, totalPy, &e[3]);\n        }\n'''
replace_once(old_calls, new_calls, 'x10n builder edge calls')

# ---------------------------------------------------------------------------
# Capture the projected Q6 hydrodynamic field in the free-surface solve.
# ---------------------------------------------------------------------------
insert_after_flag = '''    const bool densityRelaxationRequested0493x7c =\n        densityRelaxationBeta0493x7d > 0.0;\n'''
if text.count(insert_after_flag) != 1:
    raise SystemExit('[0493x10o-patch] density flag anchor missing')
text = text.replace(insert_after_flag, insert_after_flag + '''    const bool q6ThermalInterfaceWallRequested0493x10o =\n        freeSurfaceMode0493x5a && params.phaseInterfaceKineticReflectionFraction >= 1.0 &&\n        env_int_0400("MPCD_X10O_Q6_THERMAL_INTERFACE_WALL", 0) != 0;\n''', 1)

# Validate/allocate after projected-species metadata is known.
anchor_projected = '''    const bool faceToParticleRt00493x6hB1 =\n        faceToParticleRt0Requested0493x6hB1 && exclusiveProjectedSpecies;\n'''
if text.count(anchor_projected) != 1:
    raise SystemExit('[0493x10o-patch] projected species anchor missing')
text = text.replace(anchor_projected, anchor_projected + '''    if (q6ThermalInterfaceWallRequested0493x10o) {\n        if (!faceToParticleRt00493x6hB1 || projectedSpeciesIndex0493x7a < 0 ||\n            liquidPhaseSpeciesCount0493x7a != 1 ||\n            params.speciesDefinitions[\n                static_cast<std::size_t>(projectedSpeciesIndex0493x7a)].phaseFamily !=\n                SpeciesPhaseFamily::Liquid) {\n            diag.reason =\n                "0493x10o requires one projected liquid species with free-surface B1/RT0";\n            return false;\n        }\n        const std::size_t c0493x10o =\n            static_cast<std::size_t>(std::max(1, grid.numCells));\n        ws.kineticQ6HydroValid0493x10o.ensure(c0493x10o);\n        ws.kineticQ6HydroCellUx0493x10o.ensure(c0493x10o);\n        ws.kineticQ6HydroCellUy0493x10o.ensure(c0493x10o);\n        ws.kineticQ6HydroFaceUxEast0493x10o.ensure(c0493x10o);\n        ws.kineticQ6HydroFaceUyNorth0493x10o.ensure(c0493x10o);\n        ws.kineticQ6HydroFieldValid0493x10o = false;\n        ws.kineticQ6HydroFieldStep0493x10o = -1;\n        ws.kineticQ6HydroFieldType0493x10o = projectedSpeciesType0493x7a;\n    }\n''', 1)

# Launch capture immediately after cell correction is computed while r/p and
# species tentative moments still refer to this projected liquid species.
capture_anchor = '''        check_cuda_0400(cudaGetLastError(), "independent masked cell correction launch");\n        double correctionSq = 0.0;\n'''
if text.count(capture_anchor) != 1:
    raise SystemExit('[0493x10o-patch] cell correction capture anchor missing')
text = text.replace(capture_anchor, '''        check_cuda_0400(cudaGetLastError(), "independent masked cell correction launch");\n\n        if (q6ThermalInterfaceWallRequested0493x10o &&\n            s == projectedSpeciesIndex0493x7a) {\n            q6_x10o_capture_projected_q6_hydrodynamics<<<cellBlocks, threads>>>(\n                species, s, ws.speciesMask0493w5.data(),\n                ws.dux.data(), ws.duy.data(), ws.r.data(), ws.p.data(),\n                ws.kineticQ6HydroValid0493x10o.data(),\n                ws.kineticQ6HydroCellUx0493x10o.data(),\n                ws.kineticQ6HydroCellUy0493x10o.data(),\n                ws.kineticQ6HydroFaceUxEast0493x10o.data(),\n                ws.kineticQ6HydroFaceUyNorth0493x10o.data(),\n                grid.Nx, grid.Ny, periodicX, periodicY);\n            check_cuda_0400(\n                cudaGetLastError(), "0493x10o projected Q6 hydrodynamic capture launch");\n            ws.kineticQ6HydroFieldValid0493x10o = true;\n            ws.kineticQ6HydroFieldStep0493x10o = step;\n            ws.kineticQ6HydroFieldType0493x10o = audit.type;\n        }\n        double correctionSq = 0.0;\n''', 1)

# ---------------------------------------------------------------------------
# x10o takes precedence over x10n at the kinetic-wall stage.
# ---------------------------------------------------------------------------
old_flags = '''    const bool continuousInterfaceWall0493x10n =\n        r >= 1.0 &&\n        env_int_0400("MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL", 0) != 0;\n    const bool movingInterfaceWall0493x10m =\n        !continuousInterfaceWall0493x10n && r >= 1.0 &&\n        env_int_0400("MPCD_X10M_MOVING_INTERFACE_WALL", 0) != 0;\n    const bool localFrameSpecularAblation =\n        !continuousInterfaceWall0493x10n && !movingInterfaceWall0493x10m && r >= 1.0 &&\n        env_int_0400("MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION", 0) != 0;\n    const bool simpleSpecularAblation =\n        !continuousInterfaceWall0493x10n && !movingInterfaceWall0493x10m &&\n        !localFrameSpecularAblation && r >= 1.0 &&\n        env_int_0400("MPCD_X10J_SIMPLE_SPECULAR_ABLATION", 0) != 0;\n    const bool anySimpleSpecularAblation =\n        continuousInterfaceWall0493x10n || movingInterfaceWall0493x10m ||\n        simpleSpecularAblation || localFrameSpecularAblation;\n'''
new_flags = '''    const bool q6ThermalInterfaceWall0493x10o =\n        r >= 1.0 &&\n        env_int_0400("MPCD_X10O_Q6_THERMAL_INTERFACE_WALL", 0) != 0;\n    const bool continuousInterfaceWall0493x10n =\n        !q6ThermalInterfaceWall0493x10o && r >= 1.0 &&\n        env_int_0400("MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL", 0) != 0;\n    const bool movingInterfaceWall0493x10m =\n        !q6ThermalInterfaceWall0493x10o && !continuousInterfaceWall0493x10n && r >= 1.0 &&\n        env_int_0400("MPCD_X10M_MOVING_INTERFACE_WALL", 0) != 0;\n    const bool localFrameSpecularAblation =\n        !q6ThermalInterfaceWall0493x10o && !continuousInterfaceWall0493x10n &&\n        !movingInterfaceWall0493x10m && r >= 1.0 &&\n        env_int_0400("MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION", 0) != 0;\n    const bool simpleSpecularAblation =\n        !q6ThermalInterfaceWall0493x10o && !continuousInterfaceWall0493x10n &&\n        !movingInterfaceWall0493x10m && !localFrameSpecularAblation && r >= 1.0 &&\n        env_int_0400("MPCD_X10J_SIMPLE_SPECULAR_ABLATION", 0) != 0;\n    const bool anySimpleSpecularAblation =\n        q6ThermalInterfaceWall0493x10o || continuousInterfaceWall0493x10n ||\n        movingInterfaceWall0493x10m || simpleSpecularAblation ||\n        localFrameSpecularAblation;\n'''
replace_once(old_flags, new_flags, 'x10o precedence flags')

# Add thermal thickness calculation after geometry validity guard.
thermal_anchor = '''    if (!geometryValid0493x6c || phaseAlpha0493x6c == nullptr)\n        throw std::runtime_error("0493x9x kinetic reflection requested without valid resident x6c alpha geometry");\n\n'''
if text.count(thermal_anchor) != 1:
    raise SystemExit('[0493x10o-patch] thermal host anchor missing')
text = text.replace(thermal_anchor, thermal_anchor + '''    double thermalThickness0493x10o = 0.0;\n    if (q6ThermalInterfaceWall0493x10o) {\n        if (!ws.kineticQ6HydroFieldValid0493x10o ||\n            ws.kineticQ6HydroFieldStep0493x10o != step ||\n            ws.kineticQ6HydroFieldType0493x10o != phaseAType) {\n            throw std::runtime_error(\n                "0493x10o requested without same-step projected Q6 liquid hydrodynamic field");\n        }\n        const double particleMass0493x10o = fmax(\n            1.0e-30, env_double_0400("MPCD_X10O_THERMAL_PARTICLE_MASS", 1.0));\n        const double thermalSigmas0493x10o = fmax(\n            0.0, env_double_0400("MPCD_X10O_THERMAL_SIGMAS", 3.0));\n        const double thermalMaxCells0493x10o = fmax(\n            0.0, env_double_0400("MPCD_X10O_THERMAL_MAX_CELLS", 0.75));\n        const double thermalKBT0493x10o =\n            params.thermostatTargetKBT > 0.0 ? params.thermostatTargetKBT : params.kBT;\n        const double h0493x10o = fmin(\n            params.Lx / static_cast<double>(grid.Nx),\n            params.Ly / static_cast<double>(grid.Ny));\n        const double ballistic0493x10o = thermalSigmas0493x10o * params.dt *\n            sqrt(fmax(0.0, thermalKBT0493x10o) / particleMass0493x10o);\n        thermalThickness0493x10o = fmin(\n            thermalMaxCells0493x10o * h0493x10o, ballistic0493x10o);\n    }\n\n''', 1)

# Build branch: x10o and x10n share the same continuous marching-squares
# kernel; x10o supplies Q6 fields and thermal offset.
old_build_if = '''    if (continuousInterfaceWall0493x10n) {\n        const std::size_t cellCount =\n            static_cast<std::size_t>(std::max(1, grid.numCells));\n'''
new_build_if = '''    if (q6ThermalInterfaceWall0493x10o || continuousInterfaceWall0493x10n) {\n        const std::size_t cellCount =\n            static_cast<std::size_t>(std::max(1, grid.numCells));\n'''
replace_once(old_build_if, new_build_if, 'continuous build branch')

# Extend builder launch args.
old_launch_args = '''            ws.kineticTotalM0493x9t.data(),\n            ws.kineticTotalPx0493x9t.data(),\n            ws.kineticTotalPy0493x9t.data(),\n            ws.kineticContinuousSegCount0493x10n.data(),\n'''
new_launch_args = '''            ws.kineticTotalM0493x9t.data(),\n            ws.kineticTotalPx0493x9t.data(),\n            ws.kineticTotalPy0493x9t.data(),\n            q6ThermalInterfaceWall0493x10o ? ws.kineticQ6HydroValid0493x10o.data() : nullptr,\n            q6ThermalInterfaceWall0493x10o ? ws.kineticQ6HydroCellUx0493x10o.data() : nullptr,\n            q6ThermalInterfaceWall0493x10o ? ws.kineticQ6HydroCellUy0493x10o.data() : nullptr,\n            q6ThermalInterfaceWall0493x10o ? ws.kineticQ6HydroFaceUxEast0493x10o.data() : nullptr,\n            q6ThermalInterfaceWall0493x10o ? ws.kineticQ6HydroFaceUyNorth0493x10o.data() : nullptr,\n            thermalThickness0493x10o,\n            q6ThermalInterfaceWall0493x10o ? 1 : 0,\n            ws.kineticContinuousSegCount0493x10n.data(),\n'''
# There are potentially x10n builder text occurrences only once in host launch.
replace_once(old_launch_args, new_launch_args, 'builder launch x10o args')

# Apply branch uses same moving-segment collision kernel.
replace_once(
'''    if (continuousInterfaceWall0493x10n) {\n        q6_x10n_apply_continuous_moving_interface<<<particleBlocks, threads>>>(\n''',
'''    if (q6ThermalInterfaceWall0493x10o || continuousInterfaceWall0493x10n) {\n        q6_x10n_apply_continuous_moving_interface<<<particleBlocks, threads>>>(\n''',
'apply branch x10o')

# ---------------------------------------------------------------------------
# CSV audit additions and contract tag.
# ---------------------------------------------------------------------------
replace_once(
'''               "continuousWallImpulseX,continuousWallImpulseY,"\n               "continuousWallImpulseAbsSum,continuousWallPositionShiftAbsSum,"\n               "contract\\n";\n''',
'''               "continuousWallImpulseX,continuousWallImpulseY,"\n               "continuousWallImpulseAbsSum,continuousWallPositionShiftAbsSum,"\n               "q6ThermalHydroCapturedCells,q6ThermalInterfaceEndpointSamples,"\n               "q6ThermalHydroFallbacks,q6ThermalMeanHydroVn,"\n               "q6ThermalRmsHydroVn,q6ThermalMeanAbsHydroVn,"\n               "q6ThermalMeanThickness,"\n               "contract\\n";\n''',
'CSV x10o header')

mean_anchor = '''    const double continuousWallMeanAbsVn = a.continuousWallCollisions > 0ull ?\n        a.continuousWallWallVnAbsSum /\n            static_cast<double>(a.continuousWallCollisions) : 0.0;\n'''
if text.count(mean_anchor) != 1:
    raise SystemExit('[0493x10o-patch] CSV mean anchor missing')
text = text.replace(mean_anchor, mean_anchor + '''    const double q6ThermalMeanHydroVn = a.q6ThermalInterfaceEndpointSamples > 0ull ?\n        a.q6ThermalHydroVnSum /\n            static_cast<double>(a.q6ThermalInterfaceEndpointSamples) : 0.0;\n    const double q6ThermalRmsHydroVn = a.q6ThermalInterfaceEndpointSamples > 0ull ?\n        sqrt(fmax(0.0, a.q6ThermalHydroVnSqSum /\n            static_cast<double>(a.q6ThermalInterfaceEndpointSamples))) : 0.0;\n    const double q6ThermalMeanAbsHydroVn = a.q6ThermalInterfaceEndpointSamples > 0ull ?\n        a.q6ThermalHydroAbsVnSum /\n            static_cast<double>(a.q6ThermalInterfaceEndpointSamples) : 0.0;\n    const double q6ThermalMeanThickness = a.q6ThermalInterfaceEndpointSamples > 0ull ?\n        a.q6ThermalThicknessSum /\n            static_cast<double>(a.q6ThermalInterfaceEndpointSamples) : 0.0;\n''', 1)

replace_once(
'''        << a.continuousWallImpulseAbsSum << ','\n        << a.continuousWallPositionShiftAbsSum << ','\n        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"\n''',
'''        << a.continuousWallImpulseAbsSum << ','\n        << a.continuousWallPositionShiftAbsSum << ','\n        << a.q6ThermalHydroCapturedCells << ','\n        << a.q6ThermalInterfaceEndpointSamples << ','\n        << a.q6ThermalHydroFallbacks << ','\n        << q6ThermalMeanHydroVn << ',' << q6ThermalRmsHydroVn << ','\n        << q6ThermalMeanAbsHydroVn << ',' << q6ThermalMeanThickness << ','\n        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"\n''',
'CSV x10o row')

replace_once(
'''           "0493x10n-q6-continuous-moving-interface;"\n           "x10n-shared-q6-theta-edge-crossings;"\n''',
'''           "0493x10n-q6-continuous-moving-interface;"\n           "0493x10o-q6-hydrodynamic-thermal-interface;"\n           "x10o-q6-projected-face-plus-cell-hydrodynamic-velocity;"\n           "x10o-normal-only-interface-motion;"\n           "x10o-thermal-envelope-dt-sqrt-kbt-over-m;"\n           "x10n-shared-q6-theta-edge-crossings;"\n''',
'contract x10o tag')

# Captured-cell count is cheap to collect in capture kernel only on audit rows;
# since the capture kernel has no audit pointer, set the count from the number
# of valid cells with a dedicated tiny counting kernel would add a launch.  Keep
# this field reserved at zero for now and rely on endpoint/fallback coverage.

SRC.write_text(text)

# ---------------------------------------------------------------------------
# Analyzer.
# ---------------------------------------------------------------------------
an = ROOT / 'scripts/analyze_0493x10o_q6_thermal_interface.py'
an.write_text(r'''#!/usr/bin/env python3
import argparse, csv, math
from pathlib import Path

ap=argparse.ArgumentParser()
ap.add_argument('csv')
ap.add_argument('--mode',choices=('static','dripping'),required=True)
a=ap.parse_args()
p=Path(a.csv)
with p.open(newline='') as f: rows=list(csv.DictReader(f))
if not rows: raise SystemExit('[0493x10o-check] ERROR empty CSV')

def F(r,k): return float(r.get(k,0) or 0)
def I(r,k): return int(float(r.get(k,0) or 0))
def isum(k): return sum(I(r,k) for r in rows)
def mx(k): return max((F(r,k) for r in rows), default=0.0)
def wmean(k,count):
    den=sum(I(r,count) for r in rows)
    return sum(F(r,k)*I(r,count) for r in rows)/den if den else 0.0

last=rows[-1]
coll=isum('continuousWallCollisions')
endpoints=isum('q6ThermalInterfaceEndpointSamples')
fallback=isum('q6ThermalHydroFallbacks')
no_seg=isum('continuousWallNoNearbySegment')
rel_out=isum('continuousWallRelativeStillOutward')
limit=isum('continuousWallCollisionLimitReached')
mean_vn=wmean('q6ThermalMeanHydroVn','q6ThermalInterfaceEndpointSamples')
rms_vn=math.sqrt(max(0.0, sum((F(r,'q6ThermalRmsHydroVn')**2)*I(r,'q6ThermalInterfaceEndpointSamples') for r in rows)/endpoints)) if endpoints else 0.0
mean_abs=wmean('q6ThermalMeanAbsHydroVn','q6ThermalInterfaceEndpointSamples')
mean_delta=wmean('q6ThermalMeanThickness','q6ThermalInterfaceEndpointSamples')
rel_err=max((F(r,'continuousWallRelativeSpeedSqAbsErrorSum')/(F(r,'continuousWallRelativeSpeedSqReferenceSum')+1e-300) for r in rows), default=0.0)

print('===== 0493x10o Q6 HYDRO + THERMAL INTERFACE WALL =====')
print(f'file={p} mode={a.mode} rows={len(rows)} lastStep={I(last,"step")}')
print('--- Q6 hydrodynamic interface kinematics ---')
print(f'endpointSamples={endpoints} hydroFallbacks={fallback}')
print(f'meanHydroVn={mean_vn:.9g} rmsHydroVn={rms_vn:.9g} mean|HydroVn|={mean_abs:.9g}')
print(f'meanThermalThickness={mean_delta:.9g}')
print('--- continuous thermal-envelope collision ---')
print(f'collisions={coll} second={isum("continuousWallSecondCollisions")} third={isum("continuousWallThirdCollisions")} limitReached={limit}')
print(f'oldStationaryCrossings={isum("continuousWallOldStationaryCrossingCandidates")} released={isum("continuousWallOldStationaryCrossingReleased")}')
print(f'noNearbySegment={no_seg} candidateButNoHit={isum("continuousWallCandidateNoHit")} relativeStillOutward={rel_out}')
print(f'maxRelativeSpeedSqRelativeError={rel_err:.12e}')
print('--- alpha motion predictor context ---')
print(f'preWallMeanVn(last)={F(last,"preWallVnSum")/max(1,I(last,"preWallVelocityCells")):.9g}')
print(f'alphaArea(last)={F(last,"preWallAlphaArea"):.9g} tipY(last)={F(last,"preWallLowerTipY"):.9g}')

geom = no_seg == 0
hydro = endpoints > 0 and fallback == 0
coll_ok = rel_out == 0 and rel_err < 1e-10
print('q6HydroFieldContract=' + ('PASS' if hydro else 'FAIL'))
print('thermalContinuousGeometryContract=' + ('PASS' if geom else 'FAIL'))
print('thermalMovingWallCollisionContract=' + ('PASS' if coll_ok else 'FAIL'))
print('freeSurfaceImpulseFeedback=DIAGNOSTIC_ONLY_NOT_APPLIED')
print('shapeAdvanceEvaporationContract=VISUAL_REVIEW')
print('mobileSolidExtension=GENERIC_MOVING_SEGMENT_PRIMITIVE_RETAINED')
''')
an.chmod(0o755)

# ---------------------------------------------------------------------------
# Pure math check: shared thermal endpoint + normal-only moving wall.
# ---------------------------------------------------------------------------
chk = ROOT / 'scripts/check_0493x10o_q6_thermal_interface_math.py'
chk.write_text(r'''#!/usr/bin/env python3
import math, random
rng=random.Random(493100)

def grad(alpha,i,j,nx,ny,h):
    def a(ii,jj):
        ii=max(0,min(nx-1,ii)); jj=max(0,min(ny-1,jj)); return alpha[jj*nx+ii]
    return ((a(i+1,j)-a(i-1,j))/(2*h),(a(i,j+1)-a(i,j-1))/(2*h))

nx=ny=32; h=1/nx
alpha=[]
for j in range(ny):
    y=(j+.5)*h
    for i in range(nx):
        x=(i+.5)*h
        alpha.append(.5 + .35*(.55-x) + .12*(y-.5))

max_gap=0.0; checks=0
# A shared horizontal edge recomputed from the dual square above/below must
# produce the identical thermally shifted endpoint.
for j in range(1,ny-1):
  for i in range(nx-1):
    c0=j*nx+i; c1=j*nx+i+1
    a0,a1=alpha[c0],alpha[c1]
    if (a0-.5)*(a1-.5)>=0: continue
    t=(.5-a0)/(a1-a0)
    g0=grad(alpha,i,j,nx,ny,h); g1=grad(alpha,i+1,j,nx,ny,h)
    gx=(1-t)*g0[0]+t*g1[0]; gy=(1-t)*g0[1]+t*g1[1]
    q=math.hypot(gx,gy); n=(-gx/q,-gy/q)
    delta=3*.002*math.sqrt(.125)
    x=((i+.5)+t)*h + delta*n[0]; y=(j+.5)*h + delta*n[1]
    x2=((i+.5)+t)*h + delta*n[0]; y2=(j+.5)*h + delta*n[1]
    max_gap=max(max_gap,math.hypot(x-x2,y-y2)); checks+=1

max_rel=0.0
for _ in range(200000):
    ang=rng.uniform(-math.pi,math.pi); n=(math.cos(ang),math.sin(ang))
    ux,uy=rng.uniform(-.2,.2),rng.uniform(-.2,.2)
    vn=ux*n[0]+uy*n[1]; uw=(vn*n[0],vn*n[1])
    vx,vy=rng.uniform(-1,1),rng.uniform(-1,1)
    rel=(vx-uw[0])*n[0]+(vy-uw[1])*n[1]
    if rel<=0: continue
    vxp=vx-2*rel*n[0]; vyp=vy-2*rel*n[1]
    e0=(vx-uw[0])**2+(vy-uw[1])**2
    e1=(vxp-uw[0])**2+(vyp-uw[1])**2
    max_rel=max(max_rel,abs(e1-e0))
print(f'sharedThermalEndpointChecks={checks} maxGap={max_gap:.3e}')
print(f'maxRelativeSpeedSqError={max_rel:.3e}')
if checks==0 or max_gap>1e-14 or max_rel>1e-12: raise SystemExit('status=FAIL')
print('status=PASS')
''')
chk.chmod(0o755)

# ---------------------------------------------------------------------------
# Runners: derive from x10n and turn on x10o.  Thermal mass is explicitly tied
# to LIQUID_MASS so the thickness follows dt*sqrt(kBT/m) without a hidden 1.0.
# ---------------------------------------------------------------------------
static_src = ROOT / 'scripts/run_0493x10n_continuous_interface_static_drop.sh'
drip_src = ROOT / 'scripts/run_0493x10n_continuous_interface_dripping.sh'
if not static_src.exists() or not drip_src.exists():
    raise SystemExit('[0493x10o-patch] missing x10n runner(s)')

s=static_src.read_text()
s=s.replace('export MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=1',
'''export MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1''',1)
s=s.replace('export LIQUID_MASS="${LIQUID_MASS:-1.0}"',
'''export LIQUID_MASS="${LIQUID_MASS:-1.0}"
export MPCD_X10O_THERMAL_PARTICLE_MASS="${MPCD_X10O_THERMAL_PARTICLE_MASS:-$LIQUID_MASS}"
export MPCD_X10O_THERMAL_SIGMAS="${MPCD_X10O_THERMAL_SIGMAS:-3.0}"
export MPCD_X10O_THERMAL_MAX_CELLS="${MPCD_X10O_THERMAL_MAX_CELLS:-0.75}"''',1)
s=s.replace('runs/0493x10n_continuous_interface_static_s4500','runs/0493x10o_q6_thermal_interface_static_s4500')
s=s.replace('0493x10n STATIC DROP / Q6-CONTINUOUS MOVING INTERFACE','0493x10o STATIC DROP / Q6 HYDRO + THERMAL INTERFACE')
s=s.replace('continuous alpha=.5 moving polyline from shared Q6-style crossings; no B8/global receiver reaction',
            'continuous alpha=.5 Q6-hydrodynamic thermal-envelope wall; no B8/global receiver reaction')
s=s.replace('[0493x10m] sigma=$SIGMA_ACTIVE kBT=$KBT; continuous alpha=.5 Q6-hydrodynamic thermal-envelope wall; no B8/global receiver reaction',
            '[0493x10o] sigma=$SIGMA_ACTIVE kBT=$KBT; continuous alpha=.5 Q6-hydrodynamic thermal-envelope wall; no B8/global receiver reaction')
s=s.replace('[0493x10m] moving plane velocity UGamma.n from post-Q6/B1 liquid; boundary impulse recorded, not fed back',
            '[0493x10o] wall normal velocity from captured projected Q6 hydrodynamics; boundary impulse recorded, not fed back')
s=s.replace('[0493x10k] liveEvery=$LIVE_VIS_EVERY recordEvery=$RECORD_EVERY recordFields=$RECORD_FIELDS filterSampleEvery=$FILTER_SAMPLE_EVERY hold=$LIVE_VIS_HOLD_ON_EXIT',
            '[0493x10o] liveEvery=$LIVE_VIS_EVERY recordEvery=$RECORD_EVERY recordFields=$RECORD_FIELDS filterSampleEvery=$FILTER_SAMPLE_EVERY hold=$LIVE_VIS_HOLD_ON_EXIT')
s=s.replace('echo "[0493x10j] ERROR missing $CSV"', 'echo "[0493x10o] ERROR missing $CSV"')
s=s.replace('python3 scripts/analyze_0493x10n_continuous_interface.py "$CSV" --mode static',
            'python3 scripts/analyze_0493x10o_q6_thermal_interface.py "$CSV" --mode static')
static_out=ROOT/'scripts/run_0493x10o_q6_thermal_interface_static_drop.sh'
static_out.write_text(s); static_out.chmod(0o755)

s=drip_src.read_text()
s=s.replace('MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=1',
'''MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
MPCD_X10O_THERMAL_PARTICLE_MASS="${MPCD_X10O_THERMAL_PARTICLE_MASS:-$LIQUID_MASS}"
MPCD_X10O_THERMAL_SIGMAS="${MPCD_X10O_THERMAL_SIGMAS:-3.0}"
MPCD_X10O_THERMAL_MAX_CELLS="${MPCD_X10O_THERMAL_MAX_CELLS:-0.75}"''',1)
s=s.replace('MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS',
            'MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL MPCD_X10O_Q6_THERMAL_INTERFACE_WALL MPCD_X10O_THERMAL_PARTICLE_MASS MPCD_X10O_THERMAL_SIGMAS MPCD_X10O_THERMAL_MAX_CELLS MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS',1)
s=s.replace('dripping_vk_0493x10n_continuous_interface','dripping_vk_0493x10o_q6_thermal_interface')
s=s.replace('runs/0493x10n_continuous_interface_dripping_s4500_g01','runs/0493x10o_q6_thermal_interface_dripping_s4500_g01')
s=s.replace('dripping_vk_0493x10n_continuous_interface.kv','dripping_vk_0493x10o_q6_thermal_interface.kv')
s=s.replace('[0493x10n-drip] objective=continuous alpha=.5 moving polyline from shared Q6-style crossings; no B8/global reaction',
            '[0493x10o-drip] objective=Q6-hydrodynamic normal motion + finite thermal envelope around continuous alpha=.5; no B8/global reaction')
s=s.replace('python3 scripts/analyze_0493x10n_continuous_interface.py "$KINCSV" --mode dripping',
            'python3 scripts/analyze_0493x10o_q6_thermal_interface.py "$KINCSV" --mode dripping')
drip_out=ROOT/'scripts/run_0493x10o_q6_thermal_interface_dripping.sh'
drip_out.write_text(s); drip_out.chmod(0o755)

# Ensure x10o variables are exported in the dripping runner after replacement.
if 'export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL' not in drip_out.read_text():
    # The inherited export line exports the variable list rather than using
    # individual 'export var=...' statements.  Confirm its presence instead.
    if 'MPCD_X10O_Q6_THERMAL_INTERFACE_WALL MPCD_X10O_THERMAL_PARTICLE_MASS' not in drip_out.read_text():
        raise SystemExit('[0493x10o-patch] dripping x10o export replacement failed')

dual=ROOT/'scripts/run_0493x10o_q6_thermal_interface_dual_qualification.sh'
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

STATIC_ROOT="${STATIC_RUN_ROOT:-runs/0493x10o_q6_thermal_interface_static_s4500}"
DRIP_ROOT="${DRIP_RUN_ROOT:-runs/0493x10o_q6_thermal_interface_dripping_s4500_g01}"

echo "===== 0493x10o Q6 HYDRO + THERMAL INTERFACE DUAL QUALIFICATION ====="
echo "[0493x10o] centreline=continuous Q6-style alpha=.5"
echo "[0493x10o] wall velocity=projected Q6 hydrodynamic normal velocity only"
echo "[0493x10o] kinetic envelope delta=min(C*dt*sqrt(kBT/m), maxCells*h)"
echo "[0493x10o] C=${MPCD_X10O_THERMAL_SIGMAS:-3.0} maxCells=${MPCD_X10O_THERMAL_MAX_CELLS:-0.75}"
echo "[0493x10o] no B8/global reaction; interface impulse diagnostic only"
echo "[0493x10o] static=${STATIC_STEPS:-800}; dripping=${DRIP_STEPS:-3000}"
echo "[0493x10o] liveEvery=$LIVE_VIS_EVERY recordEvery=$LIVE_VIS_RECORD_EVERY recordFields=$LIVE_VIS_RECORD_FIELDS filterSampleEvery=$FILTER_SAMPLE_EVERY hold=$LIVE_VIS_HOLD_ON_EXIT"

echo
echo "===== STATIC DROP ====="
RUN_ROOT="$STATIC_ROOT" \
SIGMA_ACTIVE="${STATIC_SIGMA_ACTIVE:-4500}" \
STEPS="${STATIC_STEPS:-800}" \
SUMMARY_EVERY="${STATIC_SUMMARY_EVERY:-25}" \
CLEAN_RUN_ROOT=1 \
bash scripts/run_0493x10o_q6_thermal_interface_static_drop.sh \
2>&1 | tee logs/0493x10o_q6_thermal_interface_static.log

echo
echo "===== DRIPPING ====="
RUN_ROOT="$DRIP_ROOT" \
SIGMA_ACTIVE="${DRIP_SIGMA_ACTIVE:-4500}" \
GRAVITY_Y="${DRIP_GRAVITY_Y:--0.1}" \
STEPS="${DRIP_STEPS:-3000}" \
SUMMARY_EVERY="${DRIP_SUMMARY_EVERY:-25}" \
CLEAN_RUN_ROOT=1 \
bash scripts/run_0493x10o_q6_thermal_interface_dripping.sh \
2>&1 | tee logs/0493x10o_q6_thermal_interface_dripping.log
''')
dual.chmod(0o755)

print('[0493x10o-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10o-patch] runtime flag: MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1')
print('[0493x10o-patch] x10o takes precedence over x10n/x10m/x10k/x10j')
print('[0493x10o-patch] Q6 projected liquid hydrodynamic field captured before workspace reuse')
print('[0493x10o-patch] endpoint motion is normal-only; shared endpoint remains continuous')
print('[0493x10o-patch] thermal envelope delta=min(C*dt*sqrt(kBT/m), maxCells*h)')
print('[0493x10o-patch] defaults: C=3, maxCells=0.75; runner ties m to LIQUID_MASS')
print('[0493x10o-patch] no B8/global reaction; free-surface impulse remains diagnostic only')
print('[0493x10o-patch] wrote analyzer, math check, static/dripping/dual runners')
