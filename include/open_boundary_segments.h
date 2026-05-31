#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <string>

#include "fluid_domain.h"
#include "simulation_params.h"

namespace mpcd {

constexpr int kOpenBoundaryMaxSegments = 16;

inline bool open_boundary_face_is_x(const std::string& face) {
    return face == "left" || face == "right";
}

inline bool open_boundary_face_is_y(const std::string& face) {
    return face == "bottom" || face == "top";
}

inline bool open_boundary_segment_is_inlet(const OpenBoundarySegment& s) {
    return is_inlet_boundary_mode(s.mode);
}

inline bool open_boundary_segment_is_outlet(const OpenBoundarySegment& s) {
    return is_outlet_boundary_mode(s.mode);
}

inline double open_boundary_segment_coordinate(const std::string& face,
                                               double x,
                                               double y,
                                               const FluidDomainBounds& domain) {
    if (face == "left" || face == "right") {
        const double h = domain.yMax - domain.yMin;
        return h > 0.0 ? (y - domain.yMin) / h : -1.0;
    }
    if (face == "bottom" || face == "top") {
        const double w = domain.xMax - domain.xMin;
        return w > 0.0 ? (x - domain.xMin) / w : -1.0;
    }
    return -1.0;
}

inline double open_boundary_segment_center_s_x_face(int j, int Ny) {
    return (static_cast<double>(j) + 0.5) / static_cast<double>(std::max(1, Ny));
}

inline double open_boundary_segment_center_s_y_face(int i, int Nx) {
    return (static_cast<double>(i) + 0.5) / static_cast<double>(std::max(1, Nx));
}

inline bool open_boundary_s_in_segment(double s, const OpenBoundarySegment& seg) {
    return s >= seg.sMin && s <= seg.sMax;
}

inline const OpenBoundarySegment* open_boundary_segment_at(const SimulationParams& params,
                                                           const std::string& face,
                                                           double s) {
    if (!params.openBoundarySegmentsEnable) return nullptr;
    for (const auto& seg : params.openBoundarySegments) {
        if (seg.face == face && open_boundary_s_in_segment(s, seg)) {
            return &seg;
        }
    }
    return nullptr;
}

inline const OpenBoundarySegment* open_boundary_segment_at_point(const SimulationParams& params,
                                                                 const FluidDomainBounds& domain,
                                                                 const std::string& face,
                                                                 double x,
                                                                 double y) {
    const double s = open_boundary_segment_coordinate(face, x, y, domain);
    return open_boundary_segment_at(params, face, s);
}

inline bool has_open_boundary_segments_on_face(const SimulationParams& params,
                                               const std::string& face) {
    if (!params.openBoundarySegmentsEnable) return false;
    for (const auto& seg : params.openBoundarySegments) {
        if (seg.face == face) return true;
    }
    return false;
}

inline bool has_open_boundary_segments_on_x_axis(const SimulationParams& params) {
    return has_open_boundary_segments_on_face(params, "left") ||
           has_open_boundary_segments_on_face(params, "right");
}

inline bool has_open_boundary_segments_on_y_axis(const SimulationParams& params) {
    return has_open_boundary_segments_on_face(params, "bottom") ||
           has_open_boundary_segments_on_face(params, "top");
}

inline bool has_open_boundary_segments(const SimulationParams& params) {
    return params.openBoundarySegmentsEnable && !params.openBoundarySegments.empty();
}

inline bool has_inlet_open_boundary_segment(const SimulationParams& params) {
    if (!params.openBoundarySegmentsEnable) return false;
    for (const auto& seg : params.openBoundarySegments) {
        if (open_boundary_segment_is_inlet(seg)) return true;
    }
    return false;
}

inline bool has_outlet_open_boundary_segment(const SimulationParams& params) {
    if (!params.openBoundarySegmentsEnable) return false;
    for (const auto& seg : params.openBoundarySegments) {
        if (open_boundary_segment_is_outlet(seg)) return true;
    }
    return false;
}

inline bool face_has_inlet_open_boundary_segment(const SimulationParams& params,
                                                 const std::string& face) {
    if (!params.openBoundarySegmentsEnable) return false;
    for (const auto& seg : params.openBoundarySegments) {
        if (seg.face == face && open_boundary_segment_is_inlet(seg)) return true;
    }
    return false;
}

inline bool face_has_outlet_open_boundary_segment(const SimulationParams& params,
                                                  const std::string& face) {
    if (!params.openBoundarySegmentsEnable) return false;
    for (const auto& seg : params.openBoundarySegments) {
        if (seg.face == face && open_boundary_segment_is_outlet(seg)) return true;
    }
    return false;
}

} // namespace mpcd
