#pragma once

#include "types.h"

#include <cstdint>
#include <vector>

namespace mpcd {

struct ObstacleHit {
    bool inside = false;
    double signedDistance = 0.0; // positive outside, negative inside
    double nx = 1.0;
    double ny = 0.0;
};

// True when the current Params describe an active cylindrical obstacle.
bool obstacle_is_active_cylinder(const Params& p);

// Signed distance to the cylinder surface.
// Positive outside, zero on the surface, negative inside.
// If no active cylinder is present, returns +infinity.
double cylinder_signed_distance(const Params& p, double x, double y);

// Returns inside flag, signed distance and outward normal.
// If the point is exactly at the cylinder centre, normal defaults to +x.
ObstacleHit cylinder_query(const Params& p, double x, double y);

// Convenience predicate.
bool point_in_obstacle(const Params& p, double x, double y);

// Cell-centre solid mask, size Nx*Ny, using index c = ix + Nx*iy.
std::vector<std::uint8_t> build_solid_mask(const Params& p);

struct FluidFractionMaskSummary {
    int nCells = 0;
    int nSolidCells = 0;
    int nPartialCells = 0;
    int nFullFluidCells = 0;
    double sumFluidFraction = 0.0;
    double gammaFluidObstacle = 0.0;
};

// Cell-centered fluid fraction mask for rectangle minus obstacle.
// phi[c] = fraction of cell c that is fluid.
// c = iy + params.Ny * ix, consistently with common_grid.cpp.
// nSub is the number of quadrature samples per direction in each cell.
// shiftX, shiftY allow using the same routine for the base and shifted grids.
std::vector<double> build_fluid_fraction_mask(const Params& params,
                                              int nSub,
                                              double shiftX,
                                              double shiftY);

FluidFractionMaskSummary summarize_fluid_fraction_mask(const Params& params,
                                                       const std::vector<double>& phi,
                                                       double phiSolidTol = 1e-12,
                                                       double phiFullTol = 1e-12);

} // namespace mpcd
