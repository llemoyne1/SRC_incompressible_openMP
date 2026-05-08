#include "visualization.h"

#include <algorithm>

namespace mpcd {

bool Visualizer::init(const Params& params) {
    enabled_ = params.visualEnable;
    every_ = std::max(1, params.visualEvery);
    close_ = false;
    return true;
}

bool Visualizer::enabled() const {
    return enabled_;
}

bool Visualizer::should_draw(int step) const {
    return enabled_ && step >= 0 && (step % every_ == 0);
}

bool Visualizer::should_close() const {
    return close_;
}

void Visualizer::update(
    int,
    double,
    const Params&,
    const State&,
    const CellFields&
) {
    // No-op backend.
    // The real GLFW/OpenGL renderer will be added in the next commit.
}

void Visualizer::shutdown() {
    enabled_ = false;
    close_ = false;
}

} // namespace mpcd
