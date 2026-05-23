#pragma once

#include <cstdint>
#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

struct ImmersedSolidDiagnostics {
    std::uint64_t hits = 0;
};

enum class ImmersedSolidShape {
    None,
    Circle,
    Rectangle
};

ImmersedSolidShape immersed_solid_shape(const SimulationParams& params);

bool immersed_solid_enabled(const SimulationParams& params);

void immersed_solid_circle_center(const SimulationParams& params, double time, double& cx, double& cy);

void immersed_solid_rectangle_bounds(const SimulationParams& params,
                                     double time,
                                     double& xMin,
                                     double& xMax,
                                     double& yMin,
                                     double& yMax);

bool point_is_inside_immersed_solid(double x, double y, const SimulationParams& params, double time = 0.0);

double immersed_solid_signed_distance(double x, double y, const SimulationParams& params, double time = 0.0);

ImmersedSolidDiagnostics apply_immersed_solid_reflection(ParticleState& state,
                                                        const SimulationParams& params,
                                                        const FluidDomainBounds& domain,
                                                        double time);

double immersed_solid_fraction_in_cell(int ix,
                                       int iy,
                                       const CellGrid& grid,
                                       const GridShift& shift,
                                       const SimulationParams& params,
                                       const FluidDomainBounds& domain,
                                       double time);

void immersed_solid_wall_velocity(const SimulationParams& params,
                                  double x,
                                  double y,
                                  double time,
                                  double& ux,
                                  double& uy);

} // namespace mpcd
