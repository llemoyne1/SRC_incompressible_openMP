#pragma once

#include "types.h"

namespace mpcd {

class Visualizer {
public:
    bool init(const Params& params);

    bool enabled() const;
    bool should_draw(int step) const;
    bool should_close() const;

    void update(
        int step,
        double time,
        const Params& params,
        const State& state,
        const CellFields& fields
    );

    void shutdown();

private:
    bool enabled_ = false;
    bool close_ = false;
    int every_ = 1;

#ifdef ENABLE_VISUALIZATION
    void* window_ = nullptr;
#endif
};

} // namespace mpcd
