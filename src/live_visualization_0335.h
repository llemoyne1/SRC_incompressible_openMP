#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace mpcd {

struct ParticleState;
struct SimulationParams;

struct LiveVisualization0335RuntimeControls {
    std::string field;
    std::string colormap = "blue_red";
    double clip = -1.0;
    double gain = 1.0;
    int smoothPasses = 1;
    int quiverNx = 60;
    int quiverNy = 32;
    double quiverScale = -1.0; // <0 disables quiver overlay
    double quiverMinSpeed = 0.0;
    int quiverSmoothPasses = -1; // <0 reuses smoothPasses
};

struct LiveVisualization0335QuiverFrame {
    int nx = 0;
    int ny = 0;
    double scale = -1.0; // pixels per velocity unit; <0 disables overlay
    double minSpeed = 0.0;
    std::vector<float> ux;
    std::vector<float> uy;
};

class LiveVisualization0335 {
public:
    LiveVisualization0335();
    ~LiveVisualization0335();

    LiveVisualization0335(const LiveVisualization0335&) = delete;
    LiveVisualization0335& operator=(const LiveVisualization0335&) = delete;

    void maybe_initialize(const SimulationParams& params);
    bool enabled() const;
    bool should_draw(std::uint64_t step, std::uint64_t finalStep) const;
    void maybe_reload_controls(std::uint64_t step);
    LiveVisualization0335RuntimeControls current_controls() const;
    void update(const ParticleState& state, const SimulationParams& params,
                std::uint64_t step, double time);
    void draw_rgba_frame(const SimulationParams& params,
                         std::uint64_t step,
                         double time,
                         const std::vector<unsigned char>& rgba,
                         int nx,
                         int ny,
                         const std::string& sourceLabel,
                         const LiveVisualization0335QuiverFrame* quiver = nullptr);

    // Optional run-end hold controlled by SRC_LIVE_VIS_HOLD_ON_EXIT=1 or
    // MPCD_LIVE_VIS_HOLD_ON_EXIT=1.  Default behavior remains unchanged.
    void hold_until_closed_on_exit();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace mpcd
