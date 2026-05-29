#include "immersed_solid.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <string>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace mpcd {
namespace {

constexpr double kTiny = 1.0e-14;

inline double wrap_periodic(double x, double L) {
    x = std::fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

inline std::string lower_ascii(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return s;
}

inline double clamp(double x, double a, double b) {
    return std::max(a, std::min(b, x));
}

inline bool inside_circle(double x, double y, const SimulationParams& p, double time) {
    double cx = 0.0, cy = 0.0;
    immersed_solid_circle_center(p, time, cx, cy);
    const double dx = x - cx;
    const double dy = y - cy;
    return dx * dx + dy * dy < p.immersedSolidR * p.immersedSolidR;
}

inline bool inside_rectangle(double x, double y, const SimulationParams& p, double time) {
    double xMin = 0.0, xMax = 0.0, yMin = 0.0, yMax = 0.0;
    immersed_solid_rectangle_bounds(p, time, xMin, xMax, yMin, yMax);
    return x >= xMin && x <= xMax && y >= yMin && y <= yMax;
}

inline double circle_signed_distance(double x, double y, const SimulationParams& p, double time) {
    double cx = 0.0, cy = 0.0;
    immersed_solid_circle_center(p, time, cx, cy);
    const double dx = x - cx;
    const double dy = y - cy;
    return std::sqrt(dx * dx + dy * dy) - p.immersedSolidR;
}

inline double rectangle_signed_distance(double x, double y, const SimulationParams& p, double time) {
    double xMin = 0.0, xMax = 0.0, yMin = 0.0, yMax = 0.0;
    immersed_solid_rectangle_bounds(p, time, xMin, xMax, yMin, yMax);

    const double cx = 0.5 * (xMin + xMax);
    const double cy = 0.5 * (yMin + yMax);
    const double hx = 0.5 * (xMax - xMin);
    const double hy = 0.5 * (yMax - yMin);
    const double qx = std::abs(x - cx) - hx;
    const double qy = std::abs(y - cy) - hy;
    const double ox = std::max(qx, 0.0);
    const double oy = std::max(qy, 0.0);
    const double outside = std::sqrt(ox * ox + oy * oy);
    const double inside = std::min(std::max(qx, qy), 0.0);
    return outside + inside;
}

struct FaceHit {
    bool valid = false;
    double t = 2.0;
    double x = 0.0;
    double y = 0.0;
    double nx = 1.0;
    double ny = 0.0;
};

inline void consider_face(FaceHit& best,
                          bool enabled,
                          double t,
                          double xHit,
                          double yHit,
                          double nx,
                          double ny,
                          double xMin,
                          double xMax,
                          double yMin,
                          double yMax) {
    if (!enabled) return;
    if (!(t >= -1.0e-12 && t <= 1.0 + 1.0e-12)) return;
    if (xHit < xMin - 1.0e-12 || xHit > xMax + 1.0e-12) return;
    if (yHit < yMin - 1.0e-12 || yHit > yMax + 1.0e-12) return;
    if (!best.valid || t < best.t) {
        best.valid = true;
        best.t = clamp(t, 0.0, 1.0);
        best.x = clamp(xHit, xMin, xMax);
        best.y = clamp(yHit, yMin, yMax);
        best.nx = nx;
        best.ny = ny;
    }
}

inline FaceHit rectangle_entry_face(double xPrev,
                                    double yPrev,
                                    double xNow,
                                    double yNow,
                                    double xMin,
                                    double xMax,
                                    double yMin,
                                    double yMax,
                                    bool exposeLeft,
                                    bool exposeRight,
                                    bool exposeBottom,
                                    bool exposeTop) {
    FaceHit best{};
    const double dx = xNow - xPrev;
    const double dy = yNow - yPrev;

    if (std::abs(dx) > kTiny) {
        if (dx > 0.0) {
            const double t = (xMin - xPrev) / dx;
            consider_face(best, exposeLeft, t, xMin, yPrev + t * dy, -1.0, 0.0,
                          xMin, xMax, yMin, yMax);
        } else {
            const double t = (xMax - xPrev) / dx;
            consider_face(best, exposeRight, t, xMax, yPrev + t * dy, 1.0, 0.0,
                          xMin, xMax, yMin, yMax);
        }
    }
    if (std::abs(dy) > kTiny) {
        if (dy > 0.0) {
            const double t = (yMin - yPrev) / dy;
            consider_face(best, exposeBottom, t, xPrev + t * dx, yMin, 0.0, -1.0,
                          xMin, xMax, yMin, yMax);
        } else {
            const double t = (yMax - yPrev) / dy;
            consider_face(best, exposeTop, t, xPrev + t * dx, yMax, 0.0, 1.0,
                          xMin, xMax, yMin, yMax);
        }
    }
    return best;
}

inline FaceHit nearest_rectangle_face(double x,
                                      double y,
                                      double xMin,
                                      double xMax,
                                      double yMin,
                                      double yMax,
                                      bool exposeLeft,
                                      bool exposeRight,
                                      bool exposeBottom,
                                      bool exposeTop) {
    FaceHit out{};
    auto choose = [&](bool enabled, double dist, double xHit, double yHit, double nx, double ny) {
        if (!enabled) return;
        if (!out.valid || dist < out.t) {
            out.valid = true;
            out.t = dist;
            out.x = xHit;
            out.y = yHit;
            out.nx = nx;
            out.ny = ny;
        }
    };
    choose(exposeLeft, std::abs(x - xMin), xMin, clamp(y, yMin, yMax), -1.0, 0.0);
    choose(exposeRight, std::abs(xMax - x), xMax, clamp(y, yMin, yMax), 1.0, 0.0);
    choose(exposeBottom, std::abs(y - yMin), clamp(x, xMin, xMax), yMin, 0.0, -1.0);
    choose(exposeTop, std::abs(yMax - y), clamp(x, xMin, xMax), yMax, 0.0, 1.0);
    return out;
}


inline bool segment_intersects_circle(double x0,
                                      double y0,
                                      double x1,
                                      double y1,
                                      const SimulationParams& p,
                                      double time) {
    double cx = 0.0, cy = 0.0;
    immersed_solid_circle_center(p, time, cx, cy);
    const double dx = x1 - x0;
    const double dy = y1 - y0;
    const double len2 = dx * dx + dy * dy;
    double t = 0.0;
    if (len2 > kTiny) {
        t = ((cx - x0) * dx + (cy - y0) * dy) / len2;
        t = clamp(t, 0.0, 1.0);
    }
    const double px = x0 + t * dx;
    const double py = y0 + t * dy;
    const double rx = px - cx;
    const double ry = py - cy;
    return rx * rx + ry * ry <= p.immersedSolidR * p.immersedSolidR;
}

inline bool segment_intersects_rectangle(double x0,
                                         double y0,
                                         double x1,
                                         double y1,
                                         const SimulationParams& p,
                                         double time) {
    double xMin = 0.0, xMax = 0.0, yMin = 0.0, yMax = 0.0;
    immersed_solid_rectangle_bounds(p, time, xMin, xMax, yMin, yMax);
    if (x0 >= xMin && x0 <= xMax && y0 >= yMin && y0 <= yMax) return true;
    if (x1 >= xMin && x1 <= xMax && y1 >= yMin && y1 <= yMax) return true;

    const double dx = x1 - x0;
    const double dy = y1 - y0;
    double t0 = 0.0;
    double t1 = 1.0;
    auto clip = [&](double pEdge, double qEdge) {
        if (std::abs(pEdge) <= kTiny) return qEdge >= 0.0;
        const double r = qEdge / pEdge;
        if (pEdge < 0.0) {
            if (r > t1) return false;
            if (r > t0) t0 = r;
        } else {
            if (r < t0) return false;
            if (r < t1) t1 = r;
        }
        return true;
    };
    return clip(-dx, x0 - xMin) && clip(dx, xMax - x0) &&
           clip(-dy, y0 - yMin) && clip(dy, yMax - y0) && t0 <= t1;
}

inline bool segment_intersects_immersed_solid(double x0,
                                              double y0,
                                              double x1,
                                              double y1,
                                              const SimulationParams& p,
                                              double time) {
    if (!immersed_solid_enabled(p)) return false;
    switch (immersed_solid_shape(p)) {
        case ImmersedSolidShape::Circle:
            return segment_intersects_circle(x0, y0, x1, y1, p, time);
        case ImmersedSolidShape::Rectangle:
            return segment_intersects_rectangle(x0, y0, x1, y1, p, time);
        case ImmersedSolidShape::None:
            return false;
    }
    return false;
}

inline bool face_segment_cuts_solid(bool xFace,
                                    int i,
                                    int j,
                                    const CellGrid& grid,
                                    const SimulationParams& p,
                                    double time) {
    if (!p.projectionImmersedSolidCloseCutFaces) return false;
    if (xFace) {
        double x = static_cast<double>(i + 1) * grid.dx;
        if (x >= grid.Lx) x -= grid.Lx;
        const double y0 = static_cast<double>(j) * grid.dy;
        const double y1 = static_cast<double>(j + 1) * grid.dy;
        return segment_intersects_immersed_solid(x, y0, x, y1, p, time);
    }
    double y = static_cast<double>(j + 1) * grid.dy;
    if (y >= grid.Ly) y -= grid.Ly;
    const double x0 = static_cast<double>(i) * grid.dx;
    const double x1 = static_cast<double>(i + 1) * grid.dx;
    return segment_intersects_immersed_solid(x0, y, x1, y, p, time);
}

} // namespace

ImmersedSolidShape immersed_solid_shape(const SimulationParams& params) {
    const std::string s = lower_ascii(params.immersedSolidShape);
    if (s == "none" || s == "off" || s == "false") return ImmersedSolidShape::None;
    if (s == "circle" || s == "disk" || s == "disc") return ImmersedSolidShape::Circle;
    if (s == "rectangle" || s == "rect" || s == "box" || s == "step") return ImmersedSolidShape::Rectangle;
    return ImmersedSolidShape::None;
}

bool immersed_solid_enabled(const SimulationParams& params) {
    if (!params.immersedSolidEnable) return false;
    const ImmersedSolidShape shape = immersed_solid_shape(params);
    if (shape == ImmersedSolidShape::Circle) {
        return params.immersedSolidR > 0.0;
    }
    if (shape == ImmersedSolidShape::Rectangle) {
        return params.immersedSolidXMax > params.immersedSolidXMin &&
               params.immersedSolidYMax > params.immersedSolidYMin;
    }
    return false;
}

void immersed_solid_circle_center(const SimulationParams& params, double time, double& cx, double& cy) {
    cx = params.immersedSolidCx + params.immersedSolidVx * time;
    cy = params.immersedSolidCy + params.immersedSolidVy * time;
}

void immersed_solid_rectangle_bounds(const SimulationParams& params,
                                     double time,
                                     double& xMin,
                                     double& xMax,
                                     double& yMin,
                                     double& yMax) {
    const double dx = params.immersedSolidVx * time;
    const double dy = params.immersedSolidVy * time;
    xMin = params.immersedSolidXMin + dx;
    xMax = params.immersedSolidXMax + dx;
    yMin = params.immersedSolidYMin + dy;
    yMax = params.immersedSolidYMax + dy;
}

bool point_is_inside_immersed_solid(double x, double y, const SimulationParams& params, double time) {
    if (!immersed_solid_enabled(params)) return false;
    switch (immersed_solid_shape(params)) {
        case ImmersedSolidShape::Circle:
            return inside_circle(x, y, params, time);
        case ImmersedSolidShape::Rectangle:
            return inside_rectangle(x, y, params, time);
        case ImmersedSolidShape::None:
            return false;
    }
    return false;
}

double immersed_solid_signed_distance(double x, double y, const SimulationParams& params, double time) {
    if (!immersed_solid_enabled(params)) return 1.0e300;
    switch (immersed_solid_shape(params)) {
        case ImmersedSolidShape::Circle:
            return circle_signed_distance(x, y, params, time);
        case ImmersedSolidShape::Rectangle:
            return rectangle_signed_distance(x, y, params, time);
        case ImmersedSolidShape::None:
            return 1.0e300;
    }
    return 1.0e300;
}

ImmersedSolidDiagnostics apply_immersed_solid_reflection(ParticleState& state,
                                                        const SimulationParams& params,
                                                        const FluidDomainBounds& domain,
                                                        double time) {
    ImmersedSolidDiagnostics diag{};
    if (!immersed_solid_enabled(params)) {
        return diag;
    }

    validate_particle_state(state, "apply_immersed_solid_reflection");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const double epsBase = 1.0e-12 * std::max({1.0, domain.xMax - domain.xMin, domain.yMax - domain.yMin});

    std::uint64_t hits = 0;
    const ImmersedSolidShape shape = immersed_solid_shape(params);

    if (shape == ImmersedSolidShape::Circle) {
        double cx = 0.0, cy = 0.0;
        immersed_solid_circle_center(params, time, cx, cy);
        const double R = params.immersedSolidR;
        const double R2 = R * R;
        const double eps = 1.0e-12 * std::max(1.0, R);

#pragma omp parallel for reduction(+:hits) if(n > 10000)
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            if (!is_fluid_particle(state, i)) {
                continue;
            }
            const double dx = state.x[i] - cx;
            const double dy = state.y[i] - cy;
            const double r2 = dx * dx + dy * dy;
            if (!(r2 < R2)) continue;

            double r = std::sqrt(std::max(r2, 0.0));
            double nx = 1.0;
            double ny = 0.0;
            if (r > kTiny) {
                nx = dx / r;
                ny = dy / r;
            } else {
                r = 0.0;
            }

            const double rMirror = std::max(R + eps, 2.0 * R - r + eps);
            state.x[i] = cx + rMirror * nx;
            state.y[i] = cy + rMirror * ny;

            double wallUx = 0.0, wallUy = 0.0;
            immersed_solid_wall_velocity(params, state.x[i], state.y[i], time, wallUx, wallUy);
            const double vrx = state.vx[i] - wallUx;
            const double vry = state.vy[i] - wallUy;
            const double vn = vrx * nx + vry * ny;
            state.vx[i] = wallUx + vrx - 2.0 * vn * nx;
            state.vy[i] = wallUy + vry - 2.0 * vn * ny;
            hits += 1u;
        }
    } else if (shape == ImmersedSolidShape::Rectangle) {
        double xMin = 0.0, xMax = 0.0, yMin = 0.0, yMax = 0.0;
        immersed_solid_rectangle_bounds(params, time, xMin, xMax, yMin, yMax);
        const bool exposeLeft = xMin > domain.xMin + 1.0e-12;
        const bool exposeRight = xMax < domain.xMax - 1.0e-12;
        const bool exposeBottom = yMin > domain.yMin + 1.0e-12;
        const bool exposeTop = yMax < domain.yMax - 1.0e-12;
        const double eps = epsBase;

#pragma omp parallel for reduction(+:hits) if(n > 10000)
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            if (!is_fluid_particle(state, i)) {
                continue;
            }
            const double xNow = state.x[i];
            const double yNow = state.y[i];
            if (!(xNow >= xMin && xNow <= xMax && yNow >= yMin && yNow <= yMax)) continue;

            const double xPrev = xNow - state.vx[i] * params.dt;
            const double yPrev = yNow - state.vy[i] * params.dt;
            FaceHit face = rectangle_entry_face(xPrev, yPrev, xNow, yNow,
                                                xMin, xMax, yMin, yMax,
                                                exposeLeft, exposeRight, exposeBottom, exposeTop);
            if (!face.valid) {
                face = nearest_rectangle_face(xNow, yNow, xMin, xMax, yMin, yMax,
                                              exposeLeft, exposeRight, exposeBottom, exposeTop);
            }
            if (!face.valid) {
                // Fully enclosed/degenerated exposed-face configuration: leave the
                // particle untouched rather than creating an arbitrary kick.
                continue;
            }

            const double dxSeg = xNow - xPrev;
            const double dySeg = yNow - yPrev;
            const double remainX = (1.0 - face.t) * dxSeg;
            const double remainY = (1.0 - face.t) * dySeg;
            const double remainN = remainX * face.nx + remainY * face.ny;
            state.x[i] = face.x + remainX - 2.0 * remainN * face.nx + eps * face.nx;
            state.y[i] = face.y + remainY - 2.0 * remainN * face.ny + eps * face.ny;

            double wallUx = 0.0, wallUy = 0.0;
            immersed_solid_wall_velocity(params, face.x, face.y, time, wallUx, wallUy);
            const double vrx = state.vx[i] - wallUx;
            const double vry = state.vy[i] - wallUy;
            const double vn = vrx * face.nx + vry * face.ny;
            state.vx[i] = wallUx + vrx - 2.0 * vn * face.nx;
            state.vy[i] = wallUy + vry - 2.0 * vn * face.ny;
            hits += 1u;
        }
    }

    diag.hits = hits;
    return diag;
}


ImmersedSolidProjectionMask build_immersed_solid_projection_mask(const SimulationParams& params,
                                                                  const CellGrid& grid,
                                                                  const FluidDomainBounds& domain,
                                                                  double time,
                                                                  double fluidFractionThreshold) {
    ImmersedSolidProjectionMask mask{};
    const int nc = grid.numCells;
    mask.activeCell.assign(static_cast<std::size_t>(nc), 1u);
    mask.fluidFraction.assign(static_cast<std::size_t>(nc), 1.0);
    mask.cutCell.assign(static_cast<std::size_t>(nc), 0u);
    mask.activeSolidAdjacentCell.assign(static_cast<std::size_t>(nc), 0u);
    resize_periodic_face_field(mask.faceOpen, nc);
    std::fill(mask.faceOpen.x.begin(), mask.faceOpen.x.end(), 1.0);
    std::fill(mask.faceOpen.y.begin(), mask.faceOpen.y.end(), 1.0);
    mask.faceClosedByCellX.assign(static_cast<std::size_t>(nc), 0u);
    mask.faceClosedByCellY.assign(static_cast<std::size_t>(nc), 0u);
    mask.faceClosedByCutX.assign(static_cast<std::size_t>(nc), 0u);
    mask.faceClosedByCutY.assign(static_cast<std::size_t>(nc), 0u);

    if (!immersed_solid_enabled(params)) {
        mask.fluidCells = static_cast<std::uint64_t>(std::max(0, nc));
        mask.solidCells = 0u;
        return mask;
    }

    const double thr = clamp(fluidFractionThreshold, 0.0, 1.0);
    std::uint64_t fluidCells = 0u;
    std::uint64_t solidCells = 0u;
    std::uint64_t cutCells = 0u;
    std::uint64_t activeCutCells = 0u;
#pragma omp parallel for reduction(+:fluidCells,solidCells,cutCells,activeCutCells) if(nc > 1024)
    for (int j = 0; j < grid.Ny; ++j) {
        for (int i = 0; i < grid.Nx; ++i) {
            const int c = i + grid.Nx * j;
            const std::size_t k = static_cast<std::size_t>(c);
            const double solidFraction = immersed_solid_fraction_in_cell(i, j, grid, GridShift{}, params, domain, time);
            const double fluidFraction = clamp(1.0 - solidFraction, 0.0, 1.0);
            mask.fluidFraction[k] = fluidFraction;
            const bool active = fluidFraction >= thr;
            const bool cut = solidFraction > 0.0 && fluidFraction > 0.0;
            mask.activeCell[k] = active ? 1u : 0u;
            mask.cutCell[k] = cut ? 1u : 0u;
            if (active) ++fluidCells;
            else ++solidCells;
            if (cut) ++cutCells;
            if (cut && active) ++activeCutCells;
        }
    }
    mask.fluidCells = fluidCells;
    mask.solidCells = solidCells;
    mask.cutCells = cutCells;
    mask.activeCutCells = activeCutCells;

    const bool periodicX = is_x_periodic(params);
    const bool periodicY = is_y_periodic(params);
    std::uint64_t closedX = 0u;
    std::uint64_t closedY = 0u;
    std::uint64_t cellClosedX = 0u;
    std::uint64_t cellClosedY = 0u;
    std::uint64_t cutClosedX = 0u;
    std::uint64_t cutClosedY = 0u;
#pragma omp parallel for reduction(+:closedX,closedY,cellClosedX,cellClosedY,cutClosedX,cutClosedY) if(nc > 1024)
    for (int j = 0; j < grid.Ny; ++j) {
        for (int i = 0; i < grid.Nx; ++i) {
            const int c = i + grid.Nx * j;
            const std::size_t k = static_cast<std::size_t>(c);
            const bool a = mask.activeCell[k] != 0u;

            bool openX = false;
            bool closedByCellX = false;
            bool closedByCutX = false;
            if (periodicX || i < grid.Nx - 1) {
                const int ip = periodicX ? ((i + 1) % grid.Nx) : (i + 1);
                const int e = ip + grid.Nx * j;
                openX = a && (mask.activeCell[static_cast<std::size_t>(e)] != 0u);
                closedByCellX = !openX;
                if (openX && face_segment_cuts_solid(true, i, j, grid, params, time)) {
                    openX = false;
                    closedByCellX = false;
                    closedByCutX = true;
                }
            } else {
                closedByCellX = true;
            }
            mask.faceOpen.x[k] = openX ? 1.0 : 0.0;
            mask.faceClosedByCellX[k] = closedByCellX ? 1u : 0u;
            mask.faceClosedByCutX[k] = closedByCutX ? 1u : 0u;
            if (!openX) ++closedX;
            if (closedByCellX) ++cellClosedX;
            if (closedByCutX) ++cutClosedX;

            bool openY = false;
            bool closedByCellY = false;
            bool closedByCutY = false;
            if (periodicY || j < grid.Ny - 1) {
                const int jp = periodicY ? ((j + 1) % grid.Ny) : (j + 1);
                const int n = i + grid.Nx * jp;
                openY = a && (mask.activeCell[static_cast<std::size_t>(n)] != 0u);
                closedByCellY = !openY;
                if (openY && face_segment_cuts_solid(false, i, j, grid, params, time)) {
                    openY = false;
                    closedByCellY = false;
                    closedByCutY = true;
                }
            } else {
                closedByCellY = true;
            }
            mask.faceOpen.y[k] = openY ? 1.0 : 0.0;
            mask.faceClosedByCellY[k] = closedByCellY ? 1u : 0u;
            mask.faceClosedByCutY[k] = closedByCutY ? 1u : 0u;
            if (!openY) ++closedY;
            if (closedByCellY) ++cellClosedY;
            if (closedByCutY) ++cutClosedY;
        }
    }
    mask.closedXFaces = closedX;
    mask.closedYFaces = closedY;
    mask.cellClosedXFaces = cellClosedX;
    mask.cellClosedYFaces = cellClosedY;
    mask.cutClosedXFaces = cutClosedX;
    mask.cutClosedYFaces = cutClosedY;

    std::uint64_t activeAdjacent = 0u;
#pragma omp parallel for reduction(+:activeAdjacent) if(nc > 1024)
    for (int j = 0; j < grid.Ny; ++j) {
        for (int i = 0; i < grid.Nx; ++i) {
            const int c = i + grid.Nx * j;
            const std::size_t k = static_cast<std::size_t>(c);
            if (mask.activeCell[k] == 0u) {
                continue;
            }

            bool touchesSolid = false;
            if (periodicX || i < grid.Nx - 1) {
                const int ip = periodicX ? ((i + 1) % grid.Nx) : (i + 1);
                const int e = ip + grid.Nx * j;
                const std::size_t ek = static_cast<std::size_t>(e);
                if (mask.activeCell[ek] == 0u || mask.faceClosedByCutX[k] != 0u) touchesSolid = true;
            }
            if (periodicX || i > 0) {
                const int im = periodicX ? ((i + grid.Nx - 1) % grid.Nx) : (i - 1);
                const int w = im + grid.Nx * j;
                const std::size_t wk = static_cast<std::size_t>(w);
                if (mask.activeCell[wk] == 0u || mask.faceClosedByCutX[wk] != 0u) touchesSolid = true;
            }
            if (periodicY || j < grid.Ny - 1) {
                const int jp = periodicY ? ((j + 1) % grid.Ny) : (j + 1);
                const int n = i + grid.Nx * jp;
                const std::size_t nk = static_cast<std::size_t>(n);
                if (mask.activeCell[nk] == 0u || mask.faceClosedByCutY[k] != 0u) touchesSolid = true;
            }
            if (periodicY || j > 0) {
                const int jm = periodicY ? ((j + grid.Ny - 1) % grid.Ny) : (j - 1);
                const int s = i + grid.Nx * jm;
                const std::size_t sk = static_cast<std::size_t>(s);
                if (mask.activeCell[sk] == 0u || mask.faceClosedByCutY[sk] != 0u) touchesSolid = true;
            }

            if (touchesSolid) {
                mask.activeSolidAdjacentCell[k] = 1u;
                ++activeAdjacent;
            }
        }
    }
    mask.activeSolidAdjacentCells = activeAdjacent;
    return mask;
}

double immersed_solid_fraction_in_cell(int ix,
                                       int iy,
                                       const CellGrid& grid,
                                       const GridShift& shift,
                                       const SimulationParams& params,
                                       const FluidDomainBounds& domain,
                                       double time) {
    if (!immersed_solid_enabled(params)) {
        return 0.0;
    }
    const int ns = std::max(1, params.immersedSolidFractionSamples);
    const double x0 = static_cast<double>(ix) * grid.dx - shift.sx;
    const double y0 = static_cast<double>(iy) * grid.dy - shift.sy;

    int inside = 0;
    int fluidSamples = 0;
    const int total = ns * ns;
    for (int sy = 0; sy < ns; ++sy) {
        const double yRaw = y0 + (static_cast<double>(sy) + 0.5) * grid.dy / static_cast<double>(ns);
        double y = yRaw;
        if (is_y_periodic(params)) {
            y = wrap_periodic(y, grid.Ly);
        }
        for (int sx = 0; sx < ns; ++sx) {
            const double xRaw = x0 + (static_cast<double>(sx) + 0.5) * grid.dx / static_cast<double>(ns);
            double x = xRaw;
            if (is_x_periodic(params)) {
                x = wrap_periodic(x, grid.Lx);
            }
            if (!point_is_inside_fluid_domain(x, y, domain)) {
                continue;
            }
            fluidSamples += 1;
            if (point_is_inside_immersed_solid(x, y, params, time)) {
                inside += 1;
            }
        }
    }
    const int denom = fluidSamples > 0 ? fluidSamples : total;
    return static_cast<double>(inside) / static_cast<double>(denom);
}

void immersed_solid_wall_velocity(const SimulationParams& params,
                                  double x,
                                  double y,
                                  double time,
                                  double& ux,
                                  double& uy) {
    const ImmersedSolidShape shape = immersed_solid_shape(params);
    if (shape == ImmersedSolidShape::Circle) {
        double cx = 0.0, cy = 0.0;
        immersed_solid_circle_center(params, time, cx, cy);
        const double dx = x - cx;
        const double dy = y - cy;
        ux = params.immersedSolidVx + params.immersedSolidWallUx - params.immersedSolidOmega * dy;
        uy = params.immersedSolidVy + params.immersedSolidWallUy + params.immersedSolidOmega * dx;
    } else {
        (void)x;
        (void)y;
        (void)time;
        ux = params.immersedSolidVx + params.immersedSolidWallUx;
        uy = params.immersedSolidVy + params.immersedSolidWallUy;
    }
}

} // namespace mpcd
