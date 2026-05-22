#pragma once

#include <cstdint>
#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

struct ImmersedCircleDiagnostics {
    std::uint64_t hits = 0;
};

bool immersed_circle_enabled(const SimulationParams& params);

void immersed_circle_center(const SimulationParams& params, double time, double& cx, double& cy);

bool point_is_inside_immersed_circle(double x, double y, const SimulationParams& params, double time = 0.0);

double immersed_circle_signed_distance(double x, double y, const SimulationParams& params, double time = 0.0);

ImmersedCircleDiagnostics apply_immersed_circle_reflection(ParticleState& state,
                                                           const SimulationParams& params,
                                                           const FluidDomainBounds& domain,
                                                           double time);

double immersed_circle_solid_fraction_in_cell(int ix,
                                              int iy,
                                              const CellGrid& grid,
                                              const GridShift& shift,
                                              const SimulationParams& params,
                                              const FluidDomainBounds& domain,
                                              double time);

void immersed_circle_wall_velocity(const SimulationParams& params,
                                   double x,
                                   double y,
                                   double time,
                                   double& ux,
                                   double& uy);

} // namespace mpcd
