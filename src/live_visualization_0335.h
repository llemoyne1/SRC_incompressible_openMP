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
                         const std::string& sourceLabel);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace mpcd
