#include "fluid_domain.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace mpcd {
namespace {

double resolve_max_bound(double value0, double fallback) {
    return value0 >= 0.0 ? value0 : fallback;
}

} // namespace

FluidDomainBounds make_fluid_domain_bounds(const SimulationParams& params, double time) {
    FluidDomainBounds d{};
    d.xMin = params.fluidXMin0 + params.fluidXMinVelocity * time;
    d.xMax = resolve_max_bound(params.fluidXMax0, params.Lx) + params.fluidXMaxVelocity * time;
    d.yMin = params.fluidYMin0 + params.fluidYMinVelocity * time;
    d.yMax = resolve_max_bound(params.fluidYMax0, params.Ly) + params.fluidYMaxVelocity * time;

    d.vxMin = params.fluidXMinVelocity;
    d.vxMax = params.fluidXMaxVelocity;
    d.vyMin = params.fluidYMinVelocity;
    d.vyMax = params.fluidYMaxVelocity;

    constexpr double eps = 1.0e-12;
    if (d.xMin < -eps || d.yMin < -eps || d.xMax > params.Lx + eps || d.yMax > params.Ly + eps) {
        throw std::runtime_error("Active fluid domain left the fixed numerical box; check fluid bounds and velocities");
    }
    d.xMin = std::clamp(d.xMin, 0.0, params.Lx);
    d.xMax = std::clamp(d.xMax, 0.0, params.Lx);
    d.yMin = std::clamp(d.yMin, 0.0, params.Ly);
    d.yMax = std::clamp(d.yMax, 0.0, params.Ly);

    if (!(d.xMax > d.xMin) || !(d.yMax > d.yMin)) {
        throw std::runtime_error("Active fluid domain has non-positive area");
    }
    return d;
}

double fluid_domain_width(const FluidDomainBounds& domain) {
    return domain.xMax - domain.xMin;
}

double fluid_domain_height(const FluidDomainBounds& domain) {
    return domain.yMax - domain.yMin;
}

double fluid_domain_area(const FluidDomainBounds& domain) {
    return fluid_domain_width(domain) * fluid_domain_height(domain);
}

bool point_is_inside_fluid_domain(double x, double y, const FluidDomainBounds& domain) {
    return x >= domain.xMin && x <= domain.xMax && y >= domain.yMin && y <= domain.yMax;
}

} // namespace mpcd
