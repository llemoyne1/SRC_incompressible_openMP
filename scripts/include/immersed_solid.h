#pragma once

#include <cstdint>
#include <vector>
#include "cell_grid.h"
#include "elliptic_projection.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

struct ImmersedSolidDiagnostics {
    std::uint64_t hits = 0;
};

struct ImmersedSolidProjectionMask {
    std::vector<std::uint8_t> activeCell;
    PeriodicFaceField faceOpen;
    std::vector<double> fluidFraction;
    std::uint64_t fluidCells = 0;
    std::uint64_t solidCells = 0;
    std::uint64_t closedXFaces = 0;
    std::uint64_t closedYFaces = 0;
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

ImmersedSolidProjectionMask build_immersed_solid_projection_mask(const SimulationParams& params,
                                                                  const CellGrid& grid,
                                                                  const FluidDomainBounds& domain,
                                                                  double time,
                                                                  double fluidFractionThreshold);

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
