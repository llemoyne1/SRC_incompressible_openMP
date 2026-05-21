#pragma once

#include "simulation_params.h"

namespace mpcd {

struct FluidDomainBounds {
    // Fixed numerical box remains [0,Lx] x [0,Ly]. These bounds describe the
    // active fluid sub-domain inside that box at a given time.
    double xMin = 0.0;
    double xMax = 1.0;
    double yMin = 0.0;
    double yMax = 1.0;

    // Normal velocities of the four active-domain boundaries. They are zero
    // for static domains and become non-zero for later piston/domain-motion tests.
    double vxMin = 0.0;
    double vxMax = 0.0;
    double vyMin = 0.0;
    double vyMax = 0.0;
};

FluidDomainBounds make_fluid_domain_bounds(const SimulationParams& params, double time);

double fluid_domain_width(const FluidDomainBounds& domain);
double fluid_domain_height(const FluidDomainBounds& domain);
double fluid_domain_area(const FluidDomainBounds& domain);

bool point_is_inside_fluid_domain(double x, double y, const FluidDomainBounds& domain);

} // namespace mpcd
