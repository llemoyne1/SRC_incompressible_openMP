#include "boundary_conditions.h"
#include "obstacles.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <random>
#include <stdexcept>
#include <string>

namespace mpcd {

namespace {

std::string lowercase_ascii(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return s;
}

std::string canonical_obstacle_boundary_mode(const Params& params) {
    std::string mode = lowercase_ascii(params.obstacleBoundaryMode);

    if (mode.empty() || mode == "specular") {
        return "specular";
    }

    if (mode == "bounceback" ||
        mode == "bounce_back" ||
        mode == "bounce-back" ||
        mode == "noslip" ||
        mode == "no-slip" ||
        mode == "no_slip") {
        return "bounceback";
    }

    throw std::runtime_error(
        "Unsupported obstacleBoundaryMode: " + params.obstacleBoundaryMode +
        " (supported: specular, bounceback)"
    );
}

void reflect_velocity_at_cylinder(double& vx,
                                  double& vy,
                                  double nx,
                                  double ny,
                                  const std::string& mode) {
    const double vn = vx * nx + vy * ny;

    if (vn >= 0.0) {
        return;
    }

    if (mode == "specular") {
        vx -= 2.0 * vn * nx;
        vy -= 2.0 * vn * ny;
    } else if (mode == "bounceback") {
        // Deterministic no-slip-like reflection for a fixed wall:
        // both the normal and tangential components of the relative velocity
        // are reversed.
        vx = -vx;
        vy = -vy;
    } else {
        throw std::runtime_error("Internal error: unsupported cylinder reflection mode: " + mode);
    }
}

void reflect_remaining_displacement_at_cylinder(double remx,
                                                double remy,
                                                double nx,
                                                double ny,
                                                const std::string& mode,
                                                double& outx,
                                                double& outy) {
    outx = remx;
    outy = remy;

    const double remn = remx * nx + remy * ny;

    if (remn >= 0.0) {
        return;
    }

    if (mode == "specular") {
        outx -= 2.0 * remn * nx;
        outy -= 2.0 * remn * ny;
    } else if (mode == "bounceback") {
        // Same local wall law applied to the remaining displacement during
        // the current streaming step. This makes the position update
        // consistent with the no-slip-like velocity reflection.
        outx = -remx;
        outy = -remy;
    } else {
        throw std::runtime_error("Internal error: unsupported cylinder displacement mode: " + mode);
    }
}

} // namespace

bool is_periodic_pair(const Params& params, const std::string& axis_name) {
    if (axis_name == "x") {
        return params.boundary_left == "periodic" && params.boundary_right == "periodic";
    }
    if (axis_name == "y") {
        return params.boundary_bottom == "periodic" && params.boundary_top == "periodic";
    }
    throw std::runtime_error("Unknown axis in is_periodic_pair: " + axis_name);
}



void apply_cylinder_position_bc(std::vector<double>& x,
                                std::vector<double>& v,
                                const Params& params) {
  if (!obstacle_is_active_cylinder(params)) {
    return;
  }

  const std::string mode = canonical_obstacle_boundary_mode(params);
  const double R = params.obstacleRadius;

  double scale = 1.0;
  scale = std::max(scale, params.Lx);
  scale = std::max(scale, params.Ly);
  scale = std::max(scale, R);
  const double eps = 1e-10 * scale;

  for (int i = 0; i < params.n; ++i) {
    double& xi = x[2 * i];
    double& yi = x[2 * i + 1];
    double& vxi = v[2 * i];
    double& vyi = v[2 * i + 1];

    const ObstacleHit hit = cylinder_query(params, xi, yi);
    if (!hit.inside) {
      continue;
    }

    xi = params.obstacleCx + (R + eps) * hit.nx;
    yi = params.obstacleCy + (R + eps) * hit.ny;

    reflect_velocity_at_cylinder(vxi, vyi, hit.nx, hit.ny, mode);
  }
}


void apply_cylinder_swept_bc(std::vector<double>& x,
                             std::vector<double>& v,
                             const std::vector<double>& xOld,
                             const Params& params) {
  if (!obstacle_is_active_cylinder(params)) {
    return;
  }

  if (static_cast<int>(xOld.size()) < 2 * params.n) {
    throw std::runtime_error("apply_cylinder_swept_bc: xOld has inconsistent size");
  }

  const std::string mode = canonical_obstacle_boundary_mode(params);
  const double cx = params.obstacleCx;
  const double cy = params.obstacleCy;
  const double R = params.obstacleRadius;

  double scale = 1.0;
  scale = std::max(scale, params.Lx);
  scale = std::max(scale, params.Ly);
  scale = std::max(scale, R);
  const double eps = 1e-10 * scale;
  const double discTol = 1e-14 * scale * scale * scale * scale;

  for (int i = 0; i < params.n; ++i) {
    const double x0 = xOld[2 * i];
    const double y0 = xOld[2 * i + 1];

    double& x1 = x[2 * i];
    double& y1 = x[2 * i + 1];
    double& vx = v[2 * i];
    double& vy = v[2 * i + 1];

    const double dx = x1 - x0;
    const double dy = y1 - y0;
    const double a = dx * dx + dy * dy;

    if (a <= 1e-30) {
      continue;
    }

    const double ox = x0 - cx;
    const double oy = y0 - cy;

    const double b = 2.0 * (ox * dx + oy * dy);
    const double c = ox * ox + oy * oy - R * R;

    // If the particle already starts inside the cylinder, this swept test
    // has no well-defined first exterior impact. Use the position fallback.
    if (c <= 0.0) {
      continue;
    }

    const double disc = b * b - 4.0 * a * c;
    if (disc < -discTol) {
      continue;
    }

    const double sqrtDisc = std::sqrt(std::max(0.0, disc));
    const double inv2a = 0.5 / a;

    const double sA = (-b - sqrtDisc) * inv2a;
    const double sB = (-b + sqrtDisc) * inv2a;

    double sHit = 2.0;
    if (sA >= 0.0 && sA <= 1.0) {
      sHit = sA;
    } else if (sB >= 0.0 && sB <= 1.0) {
      sHit = sB;
    }

    if (sHit > 1.0) {
      continue;
    }

    const double xHit = x0 + sHit * dx;
    const double yHit = y0 + sHit * dy;

    double nx = xHit - cx;
    double ny = yHit - cy;
    const double nr = std::sqrt(nx * nx + ny * ny);

    if (nr > 1e-30) {
      nx /= nr;
      ny /= nr;
    } else {
      nx = 1.0;
      ny = 0.0;
    }

    // Reflect remaining displacement for the fraction of the time step
    // after impact, using the selected local cylinder wall law.
    const double remx = (1.0 - sHit) * dx;
    const double remy = (1.0 - sHit) * dy;

    double remrx = remx;
    double remry = remy;
    reflect_remaining_displacement_at_cylinder(remx, remy, nx, ny, mode, remrx, remry);

    // Reflect incoming velocity component(s) using the selected local wall law.
    reflect_velocity_at_cylinder(vx, vy, nx, ny, mode);

    x1 = xHit + remrx + eps * nx;
    y1 = yHit + remry + eps * ny;
  }

  // Final projection fallback: catches particles that started inside, or rare
  // cases with very large displacements.
  apply_cylinder_position_bc(x, v, params);
}

void apply_cylinder_specular_position_bc(std::vector<double>& x,
                                         std::vector<double>& v,
                                         const Params& params) {
  apply_cylinder_position_bc(x, v, params);
}

void apply_cylinder_specular_swept_bc(std::vector<double>& x,
                                      std::vector<double>& v,
                                      const std::vector<double>& xOld,
                                      const Params& params) {
  apply_cylinder_swept_bc(x, v, xOld, params);
}

void apply_bc_general(std::vector<double>& x,
                      std::vector<double>& v,
                      const Params& params,
                      WallInfo& info,
                      std::uint64_t rng_seed) {
    std::mt19937_64 rng(rng_seed);
    std::normal_distribution<double> normal(0.0, 1.0);

    const double Lx = params.Lx;
    const double Ly = params.Ly;
    const auto& leftMode = params.boundary_left;
    const auto& rightMode = params.boundary_right;
    const auto& bottomMode = params.boundary_bottom;
    const auto& topMode = params.boundary_top;
    const double Utop = params.Utop;
    const double Ubottom = params.Ubottom;
    const double wallSigma = params.wallSigma;

    for (int k = 0; k < 4; ++k) {
        for (int i = 0; i < params.n; ++i) {
            double& xi = x[2 * i];
            double& yi = x[2 * i + 1];
            double& vxi = v[2 * i];
            double& vyi = v[2 * i + 1];

            if (xi < 0.0) {
                const double voldx = vxi;
                const double voldy = vyi;
                if (leftMode == "periodic") {
                    xi += Lx;
                } else if (leftMode == "thermalize" || leftMode == "bounceback" || leftMode == "specular") {
                    xi = -xi;
                    if (leftMode == "thermalize") {
                        vxi = std::abs(wallSigma * normal(rng));
                        vyi = wallSigma * normal(rng);
                    } else if (leftMode == "bounceback") {
                        vxi = std::abs(vxi);
                        vyi = -vyi;
                    } else {
                        vxi = std::abs(vxi);
                    }
                    const double dvx = vxi - voldx;
                    const double dvy = vyi - voldy;
                    info.nLeft += 1;
                    info.dEwall += 0.5 * ((vxi * vxi + vyi * vyi) - (voldx * voldx + voldy * voldy));
                    info.dPxLeft += std::abs(dvx);
                    info.dPyLeft += dvy;
                } else {
                    throw std::runtime_error("Unsupported boundary_left mode: " + leftMode);
                }
            }

            if (xi > Lx) {
                const double voldx = vxi;
                const double voldy = vyi;
                if (rightMode == "periodic") {
                    xi -= Lx;
                } else if (rightMode == "thermalize" || rightMode == "bounceback" || rightMode == "specular") {
                    xi = 2.0 * Lx - xi;
                    if (rightMode == "thermalize") {
                        vxi = -std::abs(wallSigma * normal(rng));
                        vyi = wallSigma * normal(rng);
                    } else if (rightMode == "bounceback") {
                        vxi = -std::abs(vxi);
                        vyi = -vyi;
                    } else {
                        vxi = -std::abs(vxi);
                    }
                    const double dvx = vxi - voldx;
                    const double dvy = vyi - voldy;
                    info.nRight += 1;
                    info.dEwall += 0.5 * ((vxi * vxi + vyi * vyi) - (voldx * voldx + voldy * voldy));
                    info.dPxRight += std::abs(dvx);
                    info.dPyRight += dvy;
                } else {
                    throw std::runtime_error("Unsupported boundary_right mode: " + rightMode);
                }
            }

            if (yi < 0.0) {
                const double voldx = vxi;
                const double voldy = vyi;
                if (bottomMode == "periodic") {
                    yi += Ly;
                } else if (bottomMode == "thermalize") {
                    yi = -yi;
                    vxi = Ubottom + wallSigma * normal(rng);
                    vyi = std::abs(wallSigma * normal(rng));
                    const double dvx = vxi - voldx;
                    const double dvy = vyi - voldy;
                    info.nBot += 1;
                    info.dEwall += 0.5 * ((vxi * vxi + vyi * vyi) - (voldx * voldx + voldy * voldy));
                    info.dPxBot += dvx;
                    info.dPyBot += std::abs(dvy);
                } else if (bottomMode == "bounceback") {
                    yi = -yi;
                    vxi = 2.0 * Ubottom - vxi;
                    vyi = std::abs(vyi);
                    const double dvx = vxi - voldx;
                    const double dvy = vyi - voldy;
                    info.nBot += 1;
                    info.dEwall += 0.5 * ((vxi * vxi + vyi * vyi) - (voldx * voldx + voldy * voldy));
                    info.dPxBot += dvx;
                    info.dPyBot += std::abs(dvy);
                } else if (bottomMode == "specular") {
                    yi = -yi;
                    vyi = std::abs(vyi);
                    const double dvx = vxi - voldx;
                    const double dvy = vyi - voldy;
                    info.nBot += 1;
                    info.dEwall += 0.5 * ((vxi * vxi + vyi * vyi) - (voldx * voldx + voldy * voldy));
                    info.dPxBot += dvx;
                    info.dPyBot += std::abs(dvy);
                } else {
                    throw std::runtime_error("Unsupported boundary_bottom mode: " + bottomMode);
                }
            }

            if (yi > Ly) {
                const double voldx = vxi;
                const double voldy = vyi;
                if (topMode == "periodic") {
                    yi -= Ly;
                } else if (topMode == "thermalize") {
                    yi = 2.0 * Ly - yi;
                    vxi = Utop + wallSigma * normal(rng);
                    vyi = -std::abs(wallSigma * normal(rng));
                    const double dvx = vxi - voldx;
                    const double dvy = vyi - voldy;
                    info.nTop += 1;
                    info.dEwall += 0.5 * ((vxi * vxi + vyi * vyi) - (voldx * voldx + voldy * voldy));
                    info.dPxTop += dvx;
                    info.dPyTop += std::abs(dvy);
                } else if (topMode == "bounceback") {
                    yi = 2.0 * Ly - yi;
                    vxi = 2.0 * Utop - vxi;
                    vyi = -std::abs(vyi);
                    const double dvx = vxi - voldx;
                    const double dvy = vyi - voldy;
                    info.nTop += 1;
                    info.dEwall += 0.5 * ((vxi * vxi + vyi * vyi) - (voldx * voldx + voldy * voldy));
                    info.dPxTop += dvx;
                    info.dPyTop += std::abs(dvy);
                } else if (topMode == "specular") {
                    yi = 2.0 * Ly - yi;
                    vyi = -std::abs(vyi);
                    const double dvx = vxi - voldx;
                    const double dvy = vyi - voldy;
                    info.nTop += 1;
                    info.dEwall += 0.5 * ((vxi * vxi + vyi * vyi) - (voldx * voldx + voldy * voldy));
                    info.dPxTop += dvx;
                    info.dPyTop += std::abs(dvy);
                } else {
                    throw std::runtime_error("Unsupported boundary_top mode: " + topMode);
                }
            }
        }
    }

    if (is_periodic_pair(params, "x")) {
        for (int i = 0; i < params.n; ++i) {
            double& xi = x[2 * i];
            xi = xi - std::floor(xi / params.Lx) * params.Lx;
        }
    } else {
        for (int i = 0; i < params.n; ++i) {
            double& xi = x[2 * i];
            if (xi < 0.0) xi = 0.0;
            if (xi > params.Lx) xi = params.Lx;
        }
    }

    if (is_periodic_pair(params, "y")) {
        for (int i = 0; i < params.n; ++i) {
            double& yi = x[2 * i + 1];
            yi = yi - std::floor(yi / params.Ly) * params.Ly;
        }
    } else {
        for (int i = 0; i < params.n; ++i) {
            double& yi = x[2 * i + 1];
            if (yi < 0.0) yi = 0.0;
            if (yi > params.Ly) yi = params.Ly;
        }
    }
  apply_cylinder_position_bc(x, v, params);
}

} // namespace mpcd
