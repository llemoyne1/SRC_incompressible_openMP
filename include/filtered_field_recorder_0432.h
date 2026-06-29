#pragma once

#include <cstdint>
#include <memory>
#include <string>

namespace mpcd {

struct ParticleState;
struct SimulationParams;
struct LiveVisualization0335RuntimeControls;

// 0432a: livevis-control driven, observation-only filtered field recorder.
// The recorder never mutates particles, solver fields, roles, masses or types.
// When disabled it must leave the validated strict code path unchanged.
class FilteredFieldRecorder0432 {
public:
    FilteredFieldRecorder0432();
    ~FilteredFieldRecorder0432();

    FilteredFieldRecorder0432(const FilteredFieldRecorder0432&) = delete;
    FilteredFieldRecorder0432& operator=(const FilteredFieldRecorder0432&) = delete;

    void maybe_initialize(const SimulationParams& params);
    bool enabled() const;

    void poll_controls(std::uint64_t step,
                       double time,
                       const LiveVisualization0335RuntimeControls& liveControls);
    bool needs_host_state(std::uint64_t step) const;
    void sample_and_maybe_write(const ParticleState& state,
                                const SimulationParams& params,
                                std::uint64_t step,
                                double time);
    void finalize(std::uint64_t step, double time);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace mpcd
